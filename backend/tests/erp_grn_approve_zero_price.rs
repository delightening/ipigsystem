//! Regression：採購入庫單（GRN）核准。
//!
//! Bug：GRN 明細未填單價（unit_price NULL）時，會計過帳算出金額 0，
//! `journal_entry_lines` 的 `chk_debit_credit` 約束（借貸需恰有一方 > 0）
//! 被違反 → 該錯誤雖被會計層吞掉，但同一 PostgreSQL tx 已進入 aborted
//! 狀態，後續核准的 document UPDATE 失敗（25P02）→ 使用者看到通用的
//! 「資料庫操作失敗」。
//!
//! 修復：(A) 會計過帳剔除零金額分錄、零總額不建傳票；(B) 會計過帳改以
//! SAVEPOINT 隔離，失敗只回滾 savepoint 不毒化外層 tx。

use rust_decimal::Decimal;
use sqlx::PgPool;
use uuid::Uuid;

use erp_backend::middleware::CurrentUser;
use erp_backend::services::DocumentService;
use erp_backend::{ActorContext, SYSTEM_USER_ID};

async fn setup_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let url = std::env::var("TEST_DATABASE_URL")
        .expect("需設定 TEST_DATABASE_URL 指向獨立的丟棄用測試 DB；禁止 fallback 到 DATABASE_URL（開發機那條指向 prod，見 CLAUDE.md）");
    let pool = PgPool::connect(&url).await.expect("connect test db");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations on test db");
    pool
}

/// 倉庫管理員 actor（核准 GRN 用）。借用 migration 033 建立的 SYSTEM user
/// 作為 FK 目標，免去額外 seed user。
fn wm_actor() -> ActorContext {
    ActorContext::User(CurrentUser {
        id: SYSTEM_USER_ID,
        email: "test-wm@example.com".into(),
        roles: vec!["WAREHOUSE_MANAGER".into()],
        permissions: vec![],
        jti: "test".into(),
        exp: 0,
        impersonated_by: None,
    })
}

/// 建立一張「已提交」狀態的 GRN（含單行明細），回傳 document id。
/// `unit_price = None` 即重現未填單價的情境。
async fn seed_submitted_grn(pool: &PgPool, unit_price: Option<Decimal>) -> Uuid {
    let suffix = Uuid::new_v4().simple().to_string();
    let wh_id = Uuid::new_v4();
    let prod_id = Uuid::new_v4();
    let doc_id = Uuid::new_v4();

    sqlx::query("INSERT INTO warehouses (id, code, name) VALUES ($1, $2, $3)")
        .bind(wh_id)
        .bind(format!("WH-{}", &suffix[..8]))
        .bind("測試倉")
        .execute(pool)
        .await
        .expect("seed warehouse");

    sqlx::query("INSERT INTO products (id, sku, name) VALUES ($1, $2, $3)")
        .bind(prod_id)
        .bind(format!("SKU-{}", &suffix[..8]))
        .bind("測試品項")
        .execute(pool)
        .await
        .expect("seed product");

    sqlx::query(
        "INSERT INTO documents (id, doc_type, doc_no, status, warehouse_id, doc_date, created_by) \
         VALUES ($1, 'GRN', $2, 'submitted', $3, CURRENT_DATE, $4)",
    )
    .bind(doc_id)
    .bind(format!("GRN-T-{}", &suffix[..10]))
    .bind(wh_id)
    .bind(SYSTEM_USER_ID)
    .execute(pool)
    .await
    .expect("seed document");

    sqlx::query(
        "INSERT INTO document_lines (id, document_id, line_no, product_id, qty, uom, unit_price) \
         VALUES ($1, $2, 1, $3, 5, 'pcs', $4)",
    )
    .bind(Uuid::new_v4())
    .bind(doc_id)
    .bind(prod_id)
    .bind(unit_price)
    .execute(pool)
    .await
    .expect("seed document line");

    doc_id
}

#[tokio::test]
async fn grn_approve_with_null_unit_price_succeeds() {
    let pool = setup_pool().await;
    let doc_id = seed_submitted_grn(&pool, None).await;

    // 修復前：此呼叫會回傳 AppError::Database（25P02）→ expect 失敗（RED）
    DocumentService::approve(&pool, &wm_actor(), doc_id)
        .await
        .expect("零單價 GRN 核准不應失敗");

    let status: String = sqlx::query_scalar("SELECT status::text FROM documents WHERE id = $1")
        .bind(doc_id)
        .fetch_one(&pool)
        .await
        .expect("query document status");
    assert_eq!(status, "approved", "核准後狀態應為 approved");

    // 零總額 → 不建立空傳票
    let je_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM journal_entries WHERE source_entity_id = $1")
            .bind(doc_id)
            .fetch_one(&pool)
            .await
            .expect("count journal entries");
    assert_eq!(je_count, 0, "零單價 GRN 不應產生空傳票");

    // 核准的主要效果：庫存流水已寫入
    let ledger_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM stock_ledger WHERE doc_id = $1")
            .bind(doc_id)
            .fetch_one(&pool)
            .await
            .expect("count stock ledger");
    assert_eq!(ledger_count, 1, "GRN 核准應寫入庫存流水");
}

#[tokio::test]
async fn grn_approve_with_unit_price_posts_balanced_entry() {
    let pool = setup_pool().await;
    let doc_id = seed_submitted_grn(&pool, Some(Decimal::new(100, 0))).await;

    DocumentService::approve(&pool, &wm_actor(), doc_id)
        .await
        .expect("有單價 GRN 核准應成功");

    // 應建立一張平衡傳票：借存貨 = 貸應付 = qty(5) * price(100) = 500
    let (debit, credit): (Decimal, Decimal) = sqlx::query_as(
        "SELECT COALESCE(SUM(jel.debit_amount), 0), COALESCE(SUM(jel.credit_amount), 0) \
         FROM journal_entry_lines jel \
         JOIN journal_entries je ON je.id = jel.journal_entry_id \
         WHERE je.source_entity_id = $1",
    )
    .bind(doc_id)
    .fetch_one(&pool)
    .await
    .expect("sum journal entry lines");
    assert_eq!(debit, Decimal::new(500, 0), "借方總額應為 500");
    assert_eq!(credit, Decimal::new(500, 0), "貸方總額應為 500");
}
