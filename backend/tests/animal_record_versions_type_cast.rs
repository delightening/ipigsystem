//! 回歸測試：`AnimalService::get_record_versions`（`services/animal/core/query.rs`）
//! 曾把 `record_type: &str` 直接綁定比較 native enum `version_record_type`
//! （`WHERE r.record_type = $1`，無 cast），Postgres 對 `version_record_type = text`
//! 無對應運算子（42883）而 500。此為 `handlers/animal/observation.rs`、
//! `handlers/animal/surgery.rs` 實際呼叫的路徑（非 `AnimalMedicalService` 那份已修正版本）。

use sqlx::PgPool;
use uuid::Uuid;

use erp_backend::services::AnimalService;

async fn setup_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let url = std::env::var("TEST_DATABASE_URL")
        .or_else(|_| std::env::var("DATABASE_URL"))
        .expect("TEST_DATABASE_URL or DATABASE_URL must be set for integration tests");
    let pool = PgPool::connect(&url).await.expect("connect test db");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations on test db");
    pool
}

async fn seed_record_version(pool: &PgPool, record_type: &str, record_id: Uuid) {
    sqlx::query(
        r#"INSERT INTO record_versions (record_type, record_id, version_no, snapshot)
           VALUES ($1::version_record_type, $2, 1, '{}'::jsonb)"#,
    )
    .bind(record_type)
    .bind(record_id)
    .execute(pool)
    .await
    .expect("seed record version");
}

#[tokio::test]
async fn get_record_versions_does_not_500_on_native_enum_column() {
    let pool = setup_pool().await;
    let record_id = Uuid::new_v4();
    seed_record_version(&pool, "observation", record_id).await;

    let result = AnimalService::get_record_versions(&pool, "observation", record_id).await;

    let response = result.expect("record_type cast regression (42883) should not occur");
    assert_eq!(response.versions.len(), 1);
    assert_eq!(response.record_type, "observation");
}
