//! 通知／待辦分家（migration 143 + `kind` 欄位）的行為契約。
//!
//! 核心規則：**待辦只能由系統偵測動作完成後自動消失，使用者不可手動略過**
//! （使用者 2026-08-07 裁定）。
//!
//! 這條規則的實作重點不在前端不給按鈕 —— 那擋不住直接呼叫 API ——
//! 而在後端的 `mark_as_read` / `mark_all_as_read` 必須排除未完成待辦。
//! 本檔鎖住那個排除。
//!
//! 背景：2026-08-07 查 prod 發現既有置頂待辦的 `is_read` **全部是 true**，
//! 代表使用者早就按過「全部已讀」；當時前端用 `priority` 而非 `is_read` 決定顯示，
//! 才沒有被掩蓋掉。分家後若不擋，一按就把待處理清單清光。

use sqlx::PgPool;
use uuid::Uuid;

use erp_backend::models::NotificationQuery;
use erp_backend::services::NotificationService;

/// 只認 `TEST_DATABASE_URL`；未設時才收明顯是測試庫的 `DATABASE_URL`（名稱含 `test`）。
/// 本測試會跑 migration 並寫入資料。
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
         本測試會寫入資料庫，拒絕在可能是 prod 的連線上執行。"
    );
    url
}

async fn setup_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let pool = PgPool::connect(&test_database_url())
        .await
        .expect("connect test db");
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
           VALUES ($1, $2, 'fake', 'kind split test', true, false)"#,
    )
    .bind(id)
    .bind(format!("kind-split-{}@test.local", &id.to_string()[..8]))
    .execute(pool)
    .await
    .expect("seed user");
    id
}

/// 直接插一列，指定 kind 與 priority。
async fn seed(pool: &PgPool, user: Uuid, kind: &str, priority: i16) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO notifications
             (id, user_id, type, title, priority, kind, is_read)
           VALUES ($1, $2, 'system_alert'::notification_type, 'fixture', $3, $4, false)"#,
    )
    .bind(id)
    .bind(user)
    .bind(priority)
    .bind(kind)
    .execute(pool)
    .await
    .expect("seed notification");
    id
}

async fn row_of(pool: &PgPool, id: Uuid) -> (bool, i16, String) {
    sqlx::query_as("SELECT is_read, priority, kind FROM notifications WHERE id = $1")
        .bind(id)
        .fetch_one(pool)
        .await
        .expect("read notification row")
}

/// 「全部已讀」不得清掉未完成待辦 —— 那等於開一條手動略過的後門。
#[tokio::test]
async fn mark_all_read_must_not_clear_pending_action() {
    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    let info = seed(&pool, user, "info", 0).await;
    let action = seed(&pool, user, "action", 1).await;

    let svc = NotificationService::new(pool.clone());
    svc.mark_all_as_read(user).await.expect("mark all read");

    assert!(row_of(&pool, info).await.0, "一般通知應被標為已讀");
    assert!(
        !row_of(&pool, action).await.0,
        "未完成待辦不得被『全部已讀』標掉 —— 待辦只能由系統偵測完成後消失"
    );
}

/// 指定 id 標已讀同樣不得清掉待辦：前端不給按鈕擋不住直接呼叫 API。
#[tokio::test]
async fn mark_as_read_by_id_must_not_clear_pending_action() {
    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    let action = seed(&pool, user, "action", 1).await;

    let svc = NotificationService::new(pool.clone());
    svc.mark_as_read(user, &[action])
        .await
        .expect("mark as read");

    assert!(
        !row_of(&pool, action).await.0,
        "直接指定 id 也不得把未完成待辦標為已讀"
    );
}

/// **已完成**的待辦（priority 已降 0）不再受保護 —— 它已離開待處理清單，
/// 只是留在鈴鐺歷史裡，理應能被標為已讀。
#[tokio::test]
async fn mark_all_read_does_clear_completed_action() {
    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    let done = seed(&pool, user, "action", 0).await;

    let svc = NotificationService::new(pool.clone());
    svc.mark_all_as_read(user).await.expect("mark all read");

    assert!(
        row_of(&pool, done).await.0,
        "已完成的待辦（priority=0）屬一般歷史通知，應可標為已讀"
    );
}

/// 兩個計數互斥：同一件事不會在鈴鐺與驚嘆號各被數一次。
#[tokio::test]
async fn the_two_counters_are_disjoint() {
    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    seed(&pool, user, "info", 0).await;
    seed(&pool, user, "info", 0).await;
    seed(&pool, user, "action", 1).await;

    let svc = NotificationService::new(pool.clone());
    let unread = svc.get_unread_count(user).await.expect("unread count");
    let pending = svc
        .get_action_required_count(user)
        .await
        .expect("action count");

    assert_eq!(unread, 2, "鈴鐺只數未讀『通知』，不含待辦");
    assert_eq!(pending, 1, "驚嘆號只數未完成待辦");
}

/// 待辦計數**不看 `is_read`**：待辦的存否由業務狀態決定，不由使用者看過與否決定。
#[tokio::test]
async fn action_count_ignores_is_read() {
    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    let action = seed(&pool, user, "action", 1).await;
    sqlx::query("UPDATE notifications SET is_read = true, read_at = NOW() WHERE id = $1")
        .bind(action)
        .execute(&pool)
        .await
        .expect("force is_read");

    let svc = NotificationService::new(pool.clone());
    assert_eq!(
        svc.get_action_required_count(user)
            .await
            .expect("action count"),
        1,
        "即使被標為已讀（例如舊資料），未完成待辦仍須計入待處理"
    );
}

/// `?kind=` 篩選讓兩個入口各取所需。
#[tokio::test]
async fn kind_filter_separates_the_two_entries() {
    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    seed(&pool, user, "info", 0).await;
    seed(&pool, user, "action", 1).await;

    let svc = NotificationService::new(pool.clone());
    let only_action = svc
        .list_notifications(
            user,
            &NotificationQuery {
                is_read: None,
                notification_type: None,
                kind: Some("action".to_string()),
            },
            1,
            20,
        )
        .await
        .expect("list action");
    assert_eq!(only_action.data.len(), 1);
    assert_eq!(only_action.data[0].kind, "action");

    // 未帶 kind ＝ 不篩選，維持舊前端相容（部署期間新舊前端並存）
    let all = svc
        .list_notifications(
            user,
            &NotificationQuery {
                is_read: None,
                notification_type: None,
                kind: None,
            },
            1,
            20,
        )
        .await
        .expect("list all");
    assert_eq!(all.data.len(), 2, "未帶 kind 應回全部，不可預設篩選");
}

/// 建立端：`kind` 由 `priority` 決定，集中在唯一的 INSERT 點綁定。
/// 若兩者脫鉤（例如 priority=1 卻標成 info），該列會同時不出現在兩個入口。
#[tokio::test]
async fn create_binds_kind_to_priority() {
    use erp_backend::models::{CreateNotificationRequest, NotificationType};

    let pool = setup_pool().await;
    let user = seed_user(&pool).await;
    let svc = NotificationService::new(pool.clone());

    let plain = svc
        .create_notification(CreateNotificationRequest {
            user_id: user,
            notification_type: NotificationType::SystemAlert,
            title: "一般".into(),
            content: None,
            related_entity_type: None,
            related_entity_id: None,
        })
        .await
        .expect("create plain");
    assert_eq!(plain.kind, "info");
    assert_eq!(plain.priority, 0);

    let pinned = svc
        .create_pinned_notification(CreateNotificationRequest {
            user_id: user,
            notification_type: NotificationType::SystemAlert,
            title: "待辦".into(),
            content: None,
            related_entity_type: None,
            related_entity_id: None,
        })
        .await
        .expect("create pinned");
    assert_eq!(pinned.kind, "action");
    assert_eq!(pinned.priority, 1);
}
