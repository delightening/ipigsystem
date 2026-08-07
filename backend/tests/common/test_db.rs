#![allow(dead_code)]

//! 整合測試的資料庫隔離護欄（fail-closed）。
//!
//! # 為什麼「要求 `TEST_DATABASE_URL` 存在」還不夠
//!
//! 本分支先前的修正把 fallback 到 `DATABASE_URL` 拿掉了，解決的是「忘記指定」——
//! 開發機（這台同時是 prod）的 `DATABASE_URL` 指向正式庫，沒有 fallback 就不會誤入。
//!
//! 但它只檢查「有沒有這個變數」，**不檢查變數指向哪裡**。而在這台機器上最順手的
//! 寫法恰好是把 `DATABASE_URL` 的值抄過去（`TEST_DATABASE_URL=$DATABASE_URL`），
//! 抄了就繞過整道防線：整合測試會對正式庫跑 `sqlx::migrate!`、寫入 fixture，
//! 而且**沒有 teardown**，污染正式表與稽核鏈（CodeRabbit #37 兩則 Major）。
//!
//! # 判斷依據是資料庫本身，不是它的名字
//!
//! 刻意**不做任何名稱判斷**（不看 DSN 是否含 `test`、也不比對資料庫名）。名稱是
//! 猜測：正式庫改名或多出一個正式庫，靠名字的防線就靜默失效。這裡改看實際狀態：
//!
//! 1. 資料庫有[`MARKER_TABLE`]標記表 → 曾被本護欄認定為丟棄用，放行。
//! 2. 沒有標記，且[`PROBE_TABLES`]任一張已有資料 → **中止**，不連不寫。
//! 3. 沒有標記且探測表全空（或還不存在＝全新空庫）→ 蓋上標記後放行。
//!
//! 第 3 步是 bootstrap：CI 的 `backend-test` job 在 `cargo test` 之前就先跑過
//! `sqlx migrate run`，所以測試開始時資料庫已經有全部結構、卻還沒有標記。用
//! 「業務資料是否為空」而非「有沒有表」來判斷，CI 才不需要額外的蓋章步驟
//! （2026-08-07 與使用者確認採此變體，理由是少一個「CI 與護欄必須同步、忘了加
//! 就整支紅」的耦合點）。
//!
//! # 殘留風險（明說，不假裝沒有）
//!
//! 若把 `TEST_DATABASE_URL` 指向一個「已有完整結構、但三張探測表恰好全空」的
//! 正式庫（例如剛建好還沒進豬的新 prod），它會被當成丟棄庫蓋章。這種庫沒有資料
//! 可損失，接受此風險。

use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

/// 蓋在「可丟棄的測試資料庫」上的標記表。
///
/// 命名帶雙下底線前綴，明確表示非業務結構；`sqlx migrate` 只追蹤
/// `_sqlx_migrations`，多這張表不影響 migration。
const MARKER_TABLE: &str = "__ipig_disposable_test_db";

/// 探測表：核心業務表，**任何 migration 都不會 seed**。
///
/// 2026-08-07 實測依據：跑完全部 142 支 migration 的全新庫三者皆為 0；
/// prod 為 `animals=163` / `audit_logs=244` / `protocols=38`。
///
/// 刻意**不含 `users`**——它被 migration seed 了 1 筆，會讓每個新建的測試庫
/// 都被誤判成正式庫。同理排除 `roles` / `permissions` / `pens` 等 27 張被 seed
/// 的參考表（改用反向白名單要維護那 27 筆，只要有新 migration seed 新參考表
/// 就誤擋，維護成本高得多）。
///
/// 將來若真有 migration seed 到這三張其中之一，CI 會**當場紅掉**而不是靜默
/// 放行——這是刻意選的失敗方向。
const PROBE_TABLES: [&str; 3] = ["animals", "audit_logs", "protocols"];

/// 讀 `TEST_DATABASE_URL`；未設定即中止。
///
/// **不 fallback 到 `DATABASE_URL`**：開發機那條指向 prod，見 CLAUDE.md
/// 「禁止在 prod 跑 backend 整合測試」。
pub fn require_test_database_url() -> String {
    dotenvy::dotenv().ok();
    std::env::var("TEST_DATABASE_URL").expect(
        "需設定 TEST_DATABASE_URL 指向獨立的丟棄用測試 DB；禁止 fallback 到 DATABASE_URL（開發機那條指向 prod，見 CLAUDE.md）",
    )
}

/// 建立連線池，並在回傳前確認目標資料庫可以安全地被測試破壞。
///
/// `max_connections` 由呼叫端指定以保留各測試原本的池大小
/// （`PgPool::connect` 的 sqlx 預設是 10）。
pub async fn connect_disposable(max_connections: u32) -> PgPool {
    let url = require_test_database_url();
    let pool = PgPoolOptions::new()
        .max_connections(max_connections)
        .connect(&url)
        .await
        .expect("connect test db");
    assert_disposable(&pool).await;
    pool
}

/// 確認 `pool` 指向的資料庫是丟棄用測試庫；不是就 panic。
///
/// 必須在 `sqlx::migrate!` 與任何寫入**之前**呼叫。
pub async fn assert_disposable(pool: &PgPool) {
    if has_marker(pool).await {
        return;
    }

    // 三張探測表尚未全部存在 = 結構還沒建完的全新空庫。正式庫不可能只有一部分
    // 核心表，故視為可丟棄並在 migration 之前先蓋章。
    if !probe_tables_all_exist(pool).await {
        stamp_marker(pool).await;
        return;
    }

    let populated = populated_probe_tables(pool).await;
    if !populated.is_empty() {
        let db_name: String = sqlx::query_scalar("SELECT current_database()")
            .fetch_one(pool)
            .await
            .expect("query current_database");
        // 只印資料庫名與筆數，不印完整 DSN——後者含密碼，會進 CI log。
        panic!(
            "拒絕在資料庫 `{db_name}` 執行整合測試：它沒有測試庫標記（{MARKER_TABLE}），\
             且核心業務表已有資料（{}）。整合測試會跑 migration 並寫入 fixture 且不清理，\
             這看起來是正式資料庫。請把 TEST_DATABASE_URL 指向獨立的丟棄用 DB。",
            populated.join(", ")
        );
    }

    stamp_marker(pool).await;
}

async fn has_marker(pool: &PgPool) -> bool {
    let oid: Option<String> = sqlx::query_scalar("SELECT to_regclass($1)::text")
        .bind(format!("public.{MARKER_TABLE}"))
        .fetch_one(pool)
        .await
        .expect("probe marker table");
    oid.is_some()
}

async fn probe_tables_all_exist(pool: &PgPool) -> bool {
    for table in PROBE_TABLES {
        let oid: Option<String> = sqlx::query_scalar("SELECT to_regclass($1)::text")
            .bind(format!("public.{table}"))
            .fetch_one(pool)
            .await
            .expect("probe business table existence");
        if oid.is_none() {
            return false;
        }
    }
    true
}

/// 回傳「有資料」的探測表描述（例：`animals=163`）；全空時為空 vec。
///
/// 三條查詢刻意寫死、不用 `format!` 組 SQL：表名雖來自本檔常數（非外部輸入），
/// 但靜態 SQL 更好稽核，也不會誤觸 SQL 注入的靜態掃描。
async fn populated_probe_tables(pool: &PgPool) -> Vec<String> {
    let counts: (i64, i64, i64) = sqlx::query_as(
        "SELECT (SELECT count(*) FROM public.animals), \
                (SELECT count(*) FROM public.audit_logs), \
                (SELECT count(*) FROM public.protocols)",
    )
    .fetch_one(pool)
    .await
    .expect("count probe tables");

    let mut populated = Vec::new();
    for (name, n) in PROBE_TABLES.iter().zip([counts.0, counts.1, counts.2]) {
        if n > 0 {
            populated.push(format!("{name}={n}"));
        }
    }
    populated
}

/// 蓋上「這是可丟棄的測試資料庫」標記。
///
/// `IF NOT EXISTS` / `WHERE NOT EXISTS`：多個測試 binary 循序跑，但同 binary 內
/// 平行測試仍可能同時進到這裡，靠它們避免競態。
///
/// 表存在即代表已蓋章（[`has_marker`] 只看存在性），`stamped_at` 那一列純粹是給人
/// 除錯用的「這顆庫何時被認定為丟棄庫」。**必須真的寫進去**——只建表不插列會讓欄位
/// 永遠是空的，看的人得不到任何資訊（2026-08-07 實測抓到）。
async fn stamp_marker(pool: &PgPool) {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS public.__ipig_disposable_test_db (\
             stamped_at timestamptz NOT NULL DEFAULT now()\
         )",
    )
    .execute(pool)
    .await
    .expect("create disposable test db marker");

    sqlx::query(
        "INSERT INTO public.__ipig_disposable_test_db (stamped_at) \
         SELECT now() WHERE NOT EXISTS (SELECT 1 FROM public.__ipig_disposable_test_db)",
    )
    .execute(pool)
    .await
    .expect("record disposable test db stamp time");
}
