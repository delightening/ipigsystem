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

/// 取測試 DB 連線字串，**拒絕連上疑似正式環境的資料庫**。
///
/// 本檔的測試會跑 non-dry-run 對帳（真的 `UPDATE notifications`）並跑 migration，
/// 所以「連錯 DB」的代價是污染正式資料，不是測試失敗而已。
///
/// 規則：優先 `TEST_DATABASE_URL`，未設時才看 `DATABASE_URL`；
/// **不論來自哪一個變數，都必須通過同一道「database 名稱含 `test`」檢查**。
///
/// 為什麼檢查要套用在兩個來源上：`TEST_DATABASE_URL` 這個名字本身不保證任何事，
/// 有人把它指向 prod 一樣會中。守衛該守的是「連到哪個 DB」，不是「用了哪個變數名」。
///
/// 為什麼保留 `DATABASE_URL` fallback（而非硬性只認 `TEST_DATABASE_URL`）：
/// CI 只設 `DATABASE_URL`（指向 runner 自己的丟棄庫 `ipig_db_test`），
/// 硬性要求會讓 CI 全紅 —— 這不是推測，是本 PR 前一個 commit 的實測結果（6 個測試
/// 全 panic 於 `NotPresent`）。要在 CI 補環境變數得改 `.github/workflows/*`，
/// 那是需使用者授權的項目，不能在本 PR 順手改。
///
/// 名稱檢查對兩個來源都生效之後，fallback 並不會弱化防護：
/// prod 的 `ipig_db` 不含 `test` → 兩條路徑都擋得下來。
fn test_database_url() -> String {
    let (url, source) = match std::env::var("TEST_DATABASE_URL") {
        Ok(url) => (url, "TEST_DATABASE_URL"),
        Err(_) => (
            std::env::var("DATABASE_URL").expect(
                "TEST_DATABASE_URL 與 DATABASE_URL 皆未設定。本測試會寫入資料庫，\
                 請指向獨立可丟棄的測試 DB。",
            ),
            "DATABASE_URL",
        ),
    };
    let db_name = url
        .rsplit('/')
        .next()
        .and_then(|tail| tail.split(['?', '#']).next())
        .unwrap_or_default();
    assert!(
        db_name.contains("test"),
        "{source} 指向的資料庫 `{db_name}` 不像測試庫（名稱不含 test）。\
         本測試會 UPDATE notifications 並跑 migration，拒絕在可能是 prod 的連線上執行。\
         請指向獨立可丟棄的測試 DB。"
    );
    url
}

async fn setup_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let url = test_database_url();
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
//
// ⚠️ `#[serial]` 只在**同一測試 binary 內**生效。目前這是安全的，因為
// `reconcile_pinned_notifications` 只有本檔呼叫 —— 其他 test binary 不會動到
// 別人的置頂列。**若日後有第二個 test binary 呼叫對帳（非 dry-run），這個前提就破了**，
// 屆時需改用跨行程機制（各自獨立的 test database，或 advisory lock），
// 而不是再加 `#[serial]`（那擋不住跨 binary 的併發）。
#[tokio::test]
#[serial]
async fn reconcile_downgrades_pin_whose_report_was_soft_deleted() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    // fixture 必須**只**滿足「軟刪」這一個 disjunct，否則測不出軟刪規則：
    // 若用 draft + follow_up_user_id=NULL，會同時命中「已撤回」那條，
    // 把 SQL 裡的 `deleted_at IS NOT NULL` 整條拿掉、測試仍然會綠。
    // 故用「在途狀態 + 有指派追蹤者 + 已軟刪」—— 這也正是 2026-08-07 事故的真實狀態。
    let report = seed_patrol_report_with_follower(
        &pool,
        vet,
        "awaiting_acknowledgement",
        true,
        Some(follower),
    )
    .await;
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

    // completed 報告必定帶指派的追蹤者（complete_followup 只能由他本人執行）。
    // fixture 要符合正式流程產得出來的狀態，否則保護的是不可能存在的資料。
    let report =
        seed_patrol_report_with_follower(&pool, vet, "completed", false, Some(follower)).await;
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

/// `related_entity_id IS NULL` ＝ **無從判斷**，不是「實體不存在」。
///
/// 初版 SQL 沒有這個條件，於是 `NOT EXISTS (... WHERE d.id = NULL)` 恆為真、
/// `LEFT JOIN` 的 `r.id IS NULL` 也恆成立 → 這類列被**無條件降級**，
/// 還印出「關聯的實體已不存在」這個假理由。
/// 2026-08-07 prod 實查：7 筆置頂中有 4 筆正是這種（舊聚合式採購提醒，本來就不帶 entity id）。
#[tokio::test]
#[serial]
async fn reconcile_leaves_null_entity_id_untouched() {
    let pool = setup_pool().await;
    let follower = seed_user(&pool).await;

    let notif = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO notifications
             (id, user_id, type, title, related_entity_type, related_entity_id, priority)
           VALUES ($1, $2, 'document_approval'::notification_type,
                   '[iPig] 採購單未入庫提醒：1 筆採購單待入庫', 'document', NULL, 1)"#,
    )
    .bind(notif)
    .bind(follower)
    .execute(&pool)
    .await
    .expect("seed null-entity pinned notification");

    let svc = NotificationService::new(pool.clone());
    let report_out = svc
        .reconcile_pinned_notifications(false)
        .await
        .expect("reconcile");

    assert!(
        !report_out.resolved.iter().any(|r| r.id == notif),
        "related_entity_id 為 NULL＝無從判斷，不得降級"
    );
    assert_eq!(
        priority_of(&pool, notif).await,
        1,
        "NULL entity 的置頂待辦必須保持原狀"
    );
    assert!(
        report_out.null_entity_id >= 1,
        "NULL entity 的列必須被單獨列出讓維運者看見，實得 {}",
        report_out.null_entity_id
    );
}

#[tokio::test]
#[serial]
async fn reconcile_leaves_in_flight_todo_untouched() {
    let pool = setup_pool().await;
    let vet = seed_user(&pool).await;
    let follower = seed_user(&pool).await;

    // 仍在途：指派給追蹤者、等他確認收到。
    // 必須帶 follow_up_user_id —— submit_for_followup 一定同時設 status 與追蹤者，
    // 用 None 會讓這個 fixture 保護一個正式流程根本產不出來的狀態。
    let report = seed_patrol_report_with_follower(
        &pool,
        vet,
        "awaiting_acknowledgement",
        false,
        Some(follower),
    )
    .await;
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
