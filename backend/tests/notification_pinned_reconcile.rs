//! 回歸測試：置頂待辦（`priority > 0`）的孤兒對帳。
//!
//! 2026-08-07 事故：巡場報告的 `retract_to_draft` / `delete`（軟刪）兩條路徑沒有呼叫
//! `resolve_pinned_notifications`，導致置頂通知綁在一份已軟刪的報告上永久卡死——
//! 而待辦依設計不可手動已讀，使用者完全無法自救。
//!
//! 本測試鎖住對帳作業的兩個對稱契約：
//! 1. 關聯實體已刪 / 已完成 / 不存在 → **必須**降級
//! 2. 關聯實體仍在途（等使用者動作）→ **絕不可**降級
//!
//! 第 2 點比第 1 點重要：誤清真正待處理的事項，比留下一筆多餘待辦嚴重得多。

use serial_test::serial;
use sqlx::PgPool;
use uuid::Uuid;

use erp_backend::services::NotificationService;

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

async fn seed_user(pool: &PgPool) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO users (id, email, password_hash, display_name, is_active, must_change_password)
           VALUES ($1, $2, 'fake', 'pinned reconcile test', true, false)"#,
    )
    .bind(id)
    .bind(format!("pinned-reconcile-{}@test.local", &id.to_string()[..8]))
    .execute(pool)
    .await
    .expect("seed user");
    id
}

/// 建一份巡場報告。`deleted` 為 true 時同時軟刪。
async fn seed_patrol_report(pool: &PgPool, vet_id: Uuid, status: &str, deleted: bool) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO vet_patrol_reports (id, patrol_date, status, created_by, deleted_at)
           VALUES ($1, CURRENT_DATE, $2, $3, CASE WHEN $4 THEN NOW() ELSE NULL END)"#,
    )
    .bind(id)
    .bind(status)
    .bind(vet_id)
    .bind(deleted)
    .execute(pool)
    .await
    .expect("seed patrol report");
    id
}

/// 建一則置頂待辦（`priority = 1`）。
async fn seed_pinned_notification(pool: &PgPool, user_id: Uuid, report_id: Uuid) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO notifications
             (id, user_id, type, title, related_entity_type, related_entity_id, priority)
           VALUES ($1, $2, 'vet_recommendation'::notification_type, '需您填寫追蹤改善',
                   'vet_patrol_reports', $3, 1)"#,
    )
    .bind(id)
    .bind(user_id)
    .bind(report_id)
    .execute(pool)
    .await
    .expect("seed pinned notification");
    id
}

async fn priority_of(pool: &PgPool, notification_id: Uuid) -> i16 {
    sqlx::query_scalar("SELECT priority FROM notifications WHERE id = $1")
        .bind(notification_id)
        .fetch_one(pool)
        .await
        .expect("read priority")
}

// 本檔全部測試都對「整張 notifications 表」跑對帳＝共享狀態，必須序列化：
// 併發下另一支測試的非 dry-run 對帳會把本測試的列一起降級，dry-run 那支尤其會偽紅。
#[tokio::test]
#[serial]
async fn reconcile_downgrades_pin_whose_report_was_soft_deleted() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    // 事故重現：報告在待追蹤狀態被撤回並軟刪，置頂通知留了下來
    let report = seed_patrol_report(&pool, vet, "draft", true).await;
    let notif = seed_pinned_notification(&pool, follower, report).await;

    let svc = NotificationService::new(pool.clone());
    let report_out = svc
        .reconcile_pinned_notifications(false)
        .await
        .expect("reconcile");

    assert!(
        report_out.resolved.iter().any(|r| r.id == notif),
        "報告已軟刪，其置頂待辦應被對帳作業降級"
    );
    assert_eq!(
        priority_of(&pool, notif).await,
        0,
        "降級後 priority 應為 0，否則仍會出現在待處理清單"
    );
}

#[tokio::test]
#[serial]
async fn reconcile_downgrades_pin_whose_report_is_completed() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    let report = seed_patrol_report(&pool, vet, "completed", false).await;
    let notif = seed_pinned_notification(&pool, follower, report).await;

    let svc = NotificationService::new(pool.clone());
    svc.reconcile_pinned_notifications(false)
        .await
        .expect("reconcile");

    assert_eq!(
        priority_of(&pool, notif).await,
        0,
        "報告已完成，追蹤者已無事可做，置頂待辦應降級"
    );
}

#[tokio::test]
#[serial]
async fn reconcile_leaves_in_flight_todo_untouched() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    // 仍在途：指派給追蹤者、等他確認收到
    let report = seed_patrol_report(&pool, vet, "awaiting_acknowledgement", false).await;
    let notif = seed_pinned_notification(&pool, follower, report).await;

    let svc = NotificationService::new(pool.clone());
    let report_out = svc
        .reconcile_pinned_notifications(false)
        .await
        .expect("reconcile");

    assert!(
        !report_out.resolved.iter().any(|r| r.id == notif),
        "在途待辦不得被對帳作業降級——誤清真正待處理的事項比留下多餘待辦嚴重得多"
    );
    assert_eq!(
        priority_of(&pool, notif).await,
        1,
        "在途待辦的 priority 必須維持 1"
    );
}

#[tokio::test]
#[serial]
async fn reconcile_dry_run_reports_without_writing() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    let report = seed_patrol_report(&pool, vet, "draft", true).await;
    let notif = seed_pinned_notification(&pool, follower, report).await;

    let svc = NotificationService::new(pool.clone());
    let report_out = svc
        .reconcile_pinned_notifications(true)
        .await
        .expect("reconcile dry-run");

    assert!(
        report_out.resolved.iter().any(|r| r.id == notif),
        "dry-run 仍應回報將被降級的列，供上 prod 前核對筆數"
    );
    assert_eq!(
        priority_of(&pool, notif).await,
        1,
        "dry-run 不得寫入——這是上 prod 前唯一的核對機會"
    );
}
