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

/// **只認 `TEST_DATABASE_URL`，缺了就 panic —— 絕不 fallback 到 `DATABASE_URL`。**
///
/// 本檔的測試會跑 non-dry-run 對帳，也就是真的 `UPDATE notifications`，
/// 而且還會先跑 migration。若 fallback 到 `DATABASE_URL`（在這台機器上指向 prod），
/// 跑一次測試就會把正式環境的待辦降級、並對正式 schema 動手。
/// 少一個環境變數的代價是測試跑不起來；fallback 的代價是污染 prod。
async fn setup_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let url = std::env::var("TEST_DATABASE_URL").expect(
        "TEST_DATABASE_URL 未設定。本測試會寫入資料庫，禁止 fallback 到 DATABASE_URL（prod）。\
         請指向獨立可丟棄的測試 DB。",
    );
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
    seed_patrol_report_with_follower(pool, vet_id, status, deleted, None).await
}

/// 同上，但可指定 `follow_up_user_id`（撤回情境需要它明確為 NULL）。
async fn seed_patrol_report_with_follower(
    pool: &PgPool,
    vet_id: Uuid,
    status: &str,
    deleted: bool,
    follow_up_user_id: Option<Uuid>,
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO vet_patrol_reports
             (id, patrol_date, status, created_by, follow_up_user_id, deleted_at)
           VALUES ($1, CURRENT_DATE, $2, $3, $4,
                   CASE WHEN $5 THEN NOW() ELSE NULL END)"#,
    )
    .bind(id)
    .bind(status)
    .bind(vet_id)
    .bind(follow_up_user_id)
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

/// 撤回留下 `status='draft'` + `follow_up_user_id IS NULL`。
///
/// 置頂待辦只在 `submit_for_followup` 建立（該處必定同時設 `awaiting_acknowledgement`
/// 與 `follow_up_user_id`），所以這個組合唯一的來源就是撤回。撤回正是 2026-08-07
/// 事故的觸發路徑 —— 若 service 內的解除將來回歸，安全網必須接得住。
#[tokio::test]
#[serial]
async fn reconcile_downgrades_pin_whose_report_was_retracted() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    let report = seed_patrol_report_with_follower(&pool, vet, "draft", false, None).await;
    let notif = seed_pinned_notification(&pool, follower, report).await;

    let svc = NotificationService::new(pool.clone());
    let report_out = svc
        .reconcile_pinned_notifications(false)
        .await
        .expect("reconcile");

    let hit = report_out.resolved.iter().find(|r| r.id == notif);
    assert!(
        hit.is_some(),
        "報告已撤回（draft 且無指派追蹤者），其置頂待辦應被降級"
    );
    assert!(
        hit.expect("hit").reason.contains("撤回"),
        "降級理由應明確指出是撤回，維運者才知道哪條路徑漏接"
    );
    assert_eq!(priority_of(&pool, notif).await, 0);
}

/// 對照組：`draft` 但**仍有**指派追蹤者 —— 這不是撤回造成的狀態，不得誤降。
/// 沒有這一例的話，上一個測試可以靠「只要是 draft 就降級」這種過寬的條件通過。
#[tokio::test]
#[serial]
async fn reconcile_leaves_draft_with_assigned_follower_untouched() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    let report = seed_patrol_report_with_follower(&pool, vet, "draft", false, Some(follower)).await;
    let notif = seed_pinned_notification(&pool, follower, report).await;

    let svc = NotificationService::new(pool.clone());
    let report_out = svc
        .reconcile_pinned_notifications(false)
        .await
        .expect("reconcile");

    assert!(
        !report_out.resolved.iter().any(|r| r.id == notif),
        "draft 但仍有指派追蹤者 ≠ 撤回，不得降級"
    );
    assert_eq!(priority_of(&pool, notif).await, 1);
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
