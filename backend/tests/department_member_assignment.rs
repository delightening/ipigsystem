// 整合測試：部門成員指派（users.department_id）— 啟用請假 L1 單位主管關。
//
// 背景：
//   - PR #843 補上 users.department_id、#844 重設計審核鏈，但缺「指派使用者部門」的
//     service/API，故 department_id 一律 NULL、L1 單位主管關休眠。
//   - 本測試驗證新 UserService::assign_user_department / remove_user_department 能真正
//     設定 / 清除 department_id，並讓代理確認後正確進入 PENDING_L1。
use chrono::NaiveDate;
use sqlx::PgPool;
use uuid::Uuid;

use erp_backend::constants::ROLE_EXPERIMENT_STAFF;
use erp_backend::middleware::{ActorContext, CurrentUser};
use erp_backend::models::{CreateLeaveRequest, LeaveStatus};
use erp_backend::services::{AuditService, HrService, UserService};

async fn pool() -> PgPool {
    let url = std::env::var("TEST_DATABASE_URL")
        .or_else(|_| std::env::var("DATABASE_URL"))
        .expect("TEST_DATABASE_URL or DATABASE_URL must be set");
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .expect("connect test DB");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations");
    AuditService::init_hmac_key(Some(
        "test-hmac-key-do-not-use-in-prod-base64-padding".to_string(),
    ));
    pool
}

async fn mk_user(pool: &PgPool, email: &str) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO users (id, email, password_hash, display_name, is_active) \
         VALUES ($1, $2, 'x', $3, true)",
    )
    .bind(id)
    .bind(email)
    .bind(email)
    .execute(pool)
    .await
    .expect("insert user");
    id
}

/// 建立部門並指派主管，回傳部門 id。
async fn mk_department(pool: &PgPool, manager_id: Uuid, suffix: &Uuid, tag: &str) -> Uuid {
    let dept = Uuid::new_v4();
    sqlx::query("INSERT INTO departments (id, code, name, manager_id) VALUES ($1, $2, $3, $4)")
        .bind(dept)
        .bind(format!("{tag}{}", &suffix.to_string()[..6]))
        .bind("測試部門")
        .bind(manager_id)
        .execute(pool)
        .await
        .expect("insert dept");
    dept
}

fn cur(id: Uuid, roles: &[&str]) -> CurrentUser {
    CurrentUser {
        id,
        email: format!("{id}@t.com"),
        roles: roles.iter().map(|r| r.to_string()).collect(),
        permissions: vec![],
        jti: String::new(),
        exp: 0,
        impersonated_by: None,
    }
}

fn draft_payload(proxy: Uuid) -> CreateLeaveRequest {
    CreateLeaveRequest {
        proxy_user_id: Some(proxy),
        leave_type: "PERSONAL".to_string(),
        start_date: NaiveDate::from_ymd_opt(2026, 7, 3).expect("valid date"),
        end_date: NaiveDate::from_ymd_opt(2026, 7, 3).expect("valid date"),
        start_time: None,
        end_time: None,
        total_days: 0.5,
        total_hours: Some(4.0),
        reason: Some("測試".to_string()),
        supporting_documents: None,
        is_urgent: None,
        is_retroactive: None,
    }
}

/// 透過 service 指派部門後：department_id 被設定、出現在成員清單，且代理確認後進 PENDING_L1。
#[tokio::test]
async fn assign_via_service_enables_l1_stage() {
    let pool = pool().await;
    let s = Uuid::new_v4();
    let admin = mk_user(&pool, &format!("admin-{s}@t.com")).await;
    let applicant = mk_user(&pool, &format!("app-{s}@t.com")).await;
    let proxy = mk_user(&pool, &format!("proxy-{s}@t.com")).await;
    let mgr = mk_user(&pool, &format!("mgr-{s}@t.com")).await;
    let dept = mk_department(&pool, mgr, &s, "A").await;

    let admin_actor = ActorContext::User(cur(admin, &["admin"]));
    let updated = UserService::assign_user_department(&pool, &admin_actor, applicant, dept)
        .await
        .expect("assign_user_department");
    assert_eq!(updated.department_id, Some(dept));

    // 成員清單（單一部門）應含被指派者。
    let members = UserService::list_department_members(&pool, Some(dept))
        .await
        .expect("list members");
    assert!(members.iter().any(|m| m.id == applicant));

    // 送審 → 代理確認 → PENDING_L1（單位主管關真正生效）。
    let actor = ActorContext::User(cur(applicant, &[ROLE_EXPERIMENT_STAFF]));
    let created = HrService::create_leave(&pool, &actor, &draft_payload(proxy))
        .await
        .expect("create_leave");
    HrService::submit_leave(&pool, &actor, created.id)
        .await
        .expect("submit");
    let proxy_actor = ActorContext::User(cur(proxy, &[ROLE_EXPERIMENT_STAFF]));
    let confirmed = HrService::proxy_confirm_leave(&pool, &proxy_actor, created.id)
        .await
        .expect("proxy_confirm");
    assert_eq!(confirmed.status, LeaveStatus::PendingL1.as_str());
}

/// 移除成員：僅當該員確屬指定部門才清除；對不相干部門的移除請求被拒。
#[tokio::test]
async fn remove_only_when_member_belongs() {
    let pool = pool().await;
    let s = Uuid::new_v4();
    let admin = mk_user(&pool, &format!("admin-{s}@t.com")).await;
    let applicant = mk_user(&pool, &format!("app-{s}@t.com")).await;
    let mgr = mk_user(&pool, &format!("mgr-{s}@t.com")).await;
    let dept_a = mk_department(&pool, mgr, &s, "A").await;
    let dept_b = mk_department(&pool, mgr, &s, "B").await;

    let admin_actor = ActorContext::User(cur(admin, &["admin"]));
    UserService::assign_user_department(&pool, &admin_actor, applicant, dept_a)
        .await
        .expect("assign to A");

    // 從「不屬於」的部門 B 移除 → 應被拒，department_id 不變。
    let wrong = UserService::remove_user_department(&pool, &admin_actor, applicant, dept_b).await;
    assert!(wrong.is_err(), "不屬於此部門者不得被移除");
    let still = UserService::get_user_raw(&pool, applicant)
        .await
        .expect("get user");
    assert_eq!(still.department_id, Some(dept_a));

    // 從真正所屬部門 A 移除 → 成功，department_id 清為 NULL。
    let removed = UserService::remove_user_department(&pool, &admin_actor, applicant, dept_a)
        .await
        .expect("remove from A");
    assert_eq!(removed.department_id, None);
    let members = UserService::list_department_members(&pool, Some(dept_a))
        .await
        .expect("list members");
    assert!(!members.iter().any(|m| m.id == applicant));
}

/// 指派到不存在 / 已停用的部門 → 驗證錯誤。
#[tokio::test]
async fn assign_rejects_invalid_department() {
    let pool = pool().await;
    let s = Uuid::new_v4();
    let admin = mk_user(&pool, &format!("admin-{s}@t.com")).await;
    let applicant = mk_user(&pool, &format!("app-{s}@t.com")).await;

    let admin_actor = ActorContext::User(cur(admin, &["admin"]));
    let result =
        UserService::assign_user_department(&pool, &admin_actor, applicant, Uuid::new_v4()).await;
    assert!(result.is_err(), "指派到不存在的部門應失敗");
}

/// Anonymous actor 不得指派部門（Service 層拒絕）。
#[tokio::test]
async fn anonymous_actor_cannot_assign() {
    let pool = pool().await;
    let s = Uuid::new_v4();
    let applicant = mk_user(&pool, &format!("app-{s}@t.com")).await;
    let mgr = mk_user(&pool, &format!("mgr-{s}@t.com")).await;
    let dept = mk_department(&pool, mgr, &s, "A").await;

    let result =
        UserService::assign_user_department(&pool, &ActorContext::Anonymous, applicant, dept).await;
    assert!(result.is_err(), "Anonymous 不得指派部門");
}
