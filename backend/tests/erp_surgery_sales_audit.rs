//! 整合測試：手術缺銷貨單據稽核 → 通知該計畫 SD。
//!
//! 對應 feat：NotificationService::notify_surgery_missing_sales（scheduler 每日 job）。

use chrono::{Duration, Utc};
use serial_test::serial;
use sqlx::PgPool;
use uuid::Uuid;

use erp_backend::services::NotificationService;
use erp_backend::SYSTEM_USER_ID;

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

/// 建 protocol(SD=SYSTEM) + animal(同 iacuc) + 手術(days_ago 天前)。
/// with_sales=true 時加一張時間窗內已核准 DO。回傳 protocol_id。
async fn seed_protocol_with_surgery(
    pool: &PgPool,
    with_sales: bool,
    days_ago: i64,
) -> (Uuid, Uuid) {
    let suffix = Uuid::new_v4().simple().to_string();
    let proto_id = Uuid::new_v4();
    let animal_id = Uuid::new_v4();
    let sd_id = Uuid::new_v4();
    let iacuc = format!("IACUC-{}", &suffix[..8]);
    let surgery_date = (Utc::now() - Duration::days(days_ago)).date_naive();

    // SD 必須為 active 使用者（稽核已濾停用者；SYSTEM_USER_ID 為 is_active=false）
    sqlx::query(
        "INSERT INTO users (id, email, password_hash, display_name) VALUES ($1, $2, 'x', '測試SD')",
    )
    .bind(sd_id)
    .bind(format!("sd-{}@test.local", &suffix[..8]))
    .execute(pool)
    .await
    .expect("seed SD user");

    sqlx::query(
        "INSERT INTO protocols (id, protocol_no, title, pi_user_id, study_director_user_id, iacuc_no, created_by) \
         VALUES ($1, $2, '測試計畫', $3, $5, $4, $3)",
    )
    .bind(proto_id)
    .bind(format!("P-T-{}", &suffix[..10]))
    .bind(SYSTEM_USER_ID)
    .bind(&iacuc)
    .bind(sd_id)
    .execute(pool)
    .await
    .expect("seed protocol");

    sqlx::query(
        "INSERT INTO animals (id, ear_tag, breed, gender, entry_date, iacuc_no) \
         VALUES ($1, $2, 'other', 'male', CURRENT_DATE, $3)",
    )
    .bind(animal_id)
    .bind(format!("E{}", &suffix[..8]))
    .bind(&iacuc)
    .execute(pool)
    .await
    .expect("seed animal");

    sqlx::query(
        "INSERT INTO animal_surgeries (animal_id, surgery_date, surgery_site) \
         VALUES ($1, $2, '測試手術')",
    )
    .bind(animal_id)
    .bind(surgery_date)
    .execute(pool)
    .await
    .expect("seed surgery");

    if with_sales {
        sqlx::query(
            "INSERT INTO documents (id, doc_type, doc_no, status, protocol_id, doc_date, created_by) \
             VALUES ($1, 'SO', $2, 'approved', $3, $4, $5)",
        )
        .bind(Uuid::new_v4())
        .bind(format!("SO-T-{}", &suffix[..10]))
        .bind(proto_id)
        .bind(surgery_date)
        .bind(SYSTEM_USER_ID)
        .execute(pool)
        .await
        .expect("seed sales SO");
    }

    (proto_id, sd_id)
}

#[tokio::test]
#[serial]
async fn surgery_without_sales_notifies_sd() {
    let pool = setup_pool().await;
    // 30 天前手術、無銷貨單 → 已過 ±7 窗、在 60 天回溯內 → 應通知
    let (proto_id, sd_id) = seed_protocol_with_surgery(&pool, false, 30).await;

    let service = NotificationService::new(pool.clone());
    service
        .notify_surgery_missing_sales()
        .await
        .expect("稽核應成功");

    let n: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notifications \
         WHERE user_id = $1 AND related_entity_type = 'protocol' \
           AND related_entity_id = $2 AND title LIKE '%手術缺銷貨單據%'",
    )
    .bind(sd_id)
    .bind(proto_id)
    .fetch_one(&pool)
    .await
    .expect("count notifications");
    assert!(n >= 1, "SD 應收到手術缺銷貨單據通知");
}

#[tokio::test]
#[serial]
async fn surgery_with_sales_no_notification() {
    let pool = setup_pool().await;
    // 30 天前手術、有時間窗內已核准 DO → 不應通知
    let (proto_id, _sd_id) = seed_protocol_with_surgery(&pool, true, 30).await;

    let service = NotificationService::new(pool.clone());
    service
        .notify_surgery_missing_sales()
        .await
        .expect("稽核應成功");

    let n: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notifications \
         WHERE related_entity_id = $1 AND title LIKE '%手術缺銷貨單據%'",
    )
    .bind(proto_id)
    .fetch_one(&pool)
    .await
    .expect("count notifications");
    assert_eq!(n, 0, "有對應銷貨單據不應產生通知");
}
