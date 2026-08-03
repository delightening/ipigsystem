//! AUP 計畫結案守門回歸測試。
//!
//! 需求：計畫結案（`CLOSED`）前，該 IACUC 下所有動物必須皆已離場終態
//! （安樂死 / 猝死 / 已轉讓）；若仍有存活動物（未分配 / 實驗中 / 實驗完成），
//! 結案應被拒絕。存活判定對齊 `AnimalStatus::is_active_in_facility`
//! （`status NOT IN euthanized/sudden_death/transferred`）。
//! 守門實作於 `services/protocol/status.rs::change_status_tx`。

mod common;

use common::TestApp;
use serial_test::serial;
use uuid::Uuid;

use erp_backend::middleware::ActorContext;
use erp_backend::models::{AnimalStatus, ChangeStatusRequest, ProtocolStatus};
use erp_backend::services::ProtocolService;
use erp_backend::AppError;

const SYSTEM_TEST: ActorContext = ActorContext::System {
    reason: "protocol_close_animal_guard",
};

/// 建立一個 APPROVED 且帶指定 iacuc_no 的計畫，回傳 (protocol_id, iacuc_no)。
async fn seed_approved_protocol(app: &TestApp) -> (Uuid, String) {
    let admin_id: Uuid =
        sqlx::query_scalar("SELECT id FROM users WHERE email LIKE '%admin%' LIMIT 1")
            .fetch_one(&app.db_pool)
            .await
            .expect("fetch admin");
    let id = Uuid::new_v4();
    let unique = &Uuid::new_v4().to_string()[..8];
    let iacuc_no = format!("IACUC-CLOSE-{unique}");
    sqlx::query(
        r#"INSERT INTO protocols (id, protocol_no, iacuc_no, title, status, pi_user_id, created_by, created_at, updated_at)
           VALUES ($1, $2, $3, 'close animal guard', 'APPROVED'::protocol_status, $4, $4, NOW(), NOW())"#,
    )
    .bind(id)
    .bind(format!("PR-{unique}"))
    .bind(&iacuc_no)
    .bind(admin_id)
    .execute(&app.db_pool)
    .await
    .expect("insert approved protocol");
    (id, iacuc_no)
}

/// 於指定 iacuc_no 下建立一隻指定狀態的動物。
async fn seed_animal(app: &TestApp, iacuc_no: &str, status: AnimalStatus) {
    let unique = &Uuid::new_v4().to_string()[..6];
    sqlx::query(
        r#"INSERT INTO animals (id, ear_tag, status, breed, gender, entry_date, iacuc_no)
           VALUES (gen_random_uuid(), $1, $2, 'miniature', 'male', NOW(), $3)"#,
    )
    .bind(format!("E{unique}"))
    .bind(status)
    .bind(iacuc_no)
    .execute(&app.db_pool)
    .await
    .expect("insert animal");
}

/// 於指定 protocol 下建立一隻「已預約但未分配」動物：只設 reserved_protocol_id，
/// iacuc_no 保持 NULL（預約不寫 iacuc_no，僅正式分配才寫）。用於驗證守門涵蓋 earmark。
async fn seed_reserved_animal(app: &TestApp, protocol_id: Uuid) {
    let unique = &Uuid::new_v4().to_string()[..6];
    sqlx::query(
        r#"INSERT INTO animals (id, ear_tag, status, breed, gender, entry_date, reserved_protocol_id)
           VALUES (gen_random_uuid(), $1, $2, 'miniature', 'male', NOW(), $3)"#,
    )
    .bind(format!("R{unique}"))
    .bind(AnimalStatus::Unassigned)
    .bind(protocol_id)
    .execute(&app.db_pool)
    .await
    .expect("insert reserved animal");
}

fn close_req() -> ChangeStatusRequest {
    ChangeStatusRequest {
        to_status: ProtocolStatus::Closed,
        remark: None,
        reviewer_ids: None,
        vet_id: None,
    }
}

async fn fetch_status(app: &TestApp, protocol_id: Uuid) -> String {
    sqlx::query_scalar::<_, String>("SELECT status::text FROM protocols WHERE id = $1")
        .bind(protocol_id)
        .fetch_one(&app.db_pool)
        .await
        .expect("fetch status")
}

// ── 存活動物存在時結案應被拒絕 ────────────────────────────────────────────────
#[tokio::test]
#[serial]
async fn close_blocked_when_animal_in_experiment() {
    let app = TestApp::spawn().await;
    let (protocol_id, iacuc_no) = seed_approved_protocol(&app).await;
    // 一隻已犧牲（安樂死）+ 一隻實驗中（存活）→ 存活動物存在，結案應被拒
    seed_animal(&app, &iacuc_no, AnimalStatus::Euthanized).await;
    seed_animal(&app, &iacuc_no, AnimalStatus::InExperiment).await;

    let err = ProtocolService::change_status(&app.db_pool, &SYSTEM_TEST, protocol_id, &close_req())
        .await
        .expect_err("計畫下仍有存活動物時結案應被拒絕");
    assert!(
        matches!(err, AppError::BusinessRule(_)),
        "應為 BusinessRule，實得：{err:?}"
    );
    assert_eq!(
        fetch_status(&app, protocol_id).await,
        "APPROVED",
        "守門失效時計畫會被錯誤結案"
    );
}

// ── 未分配 / 實驗完成 同屬「存活」（未離場）→ 亦應擋下 ──────────────────────────
#[tokio::test]
#[serial]
async fn close_blocked_when_animal_completed_or_unassigned() {
    let app = TestApp::spawn().await;

    for alive_status in [AnimalStatus::Completed, AnimalStatus::Unassigned] {
        let (protocol_id, iacuc_no) = seed_approved_protocol(&app).await;
        seed_animal(&app, &iacuc_no, alive_status).await;

        let label = alive_status.display_name();
        let err =
            ProtocolService::change_status(&app.db_pool, &SYSTEM_TEST, protocol_id, &close_req())
                .await
                .expect_err(&format!("狀態 {label} 未離場，結案應被拒絕"));
        assert!(
            matches!(err, AppError::BusinessRule(_)),
            "狀態 {label} 應為 BusinessRule，實得：{err:?}"
        );
        assert_eq!(
            fetch_status(&app, protocol_id).await,
            "APPROVED",
            "守門失效時計畫會被錯誤結案（狀態 {label}）"
        );
    }
}

// ── 已預約（earmark）但未分配的動物亦應阻擋結案（iacuc_no NULL、走 reserved_protocol_id） ──
#[tokio::test]
#[serial]
async fn close_blocked_when_animal_reserved() {
    let app = TestApp::spawn().await;
    let (protocol_id, _iacuc_no) = seed_approved_protocol(&app).await;
    // 一隻已預約給此計畫、尚未正式分配（iacuc_no NULL）→ 守門須經 reserved_protocol_id 涵蓋
    seed_reserved_animal(&app, protocol_id).await;

    let err = ProtocolService::change_status(&app.db_pool, &SYSTEM_TEST, protocol_id, &close_req())
        .await
        .expect_err("有動物預約給此計畫時結案應被拒絕");
    assert!(
        matches!(err, AppError::BusinessRule(_)),
        "應為 BusinessRule，實得：{err:?}"
    );
    assert_eq!(
        fetch_status(&app, protocol_id).await,
        "APPROVED",
        "守門未涵蓋 reserved earmark → 計畫被錯誤結案"
    );
}

// ── 所有動物皆已離場（安樂死 / 猝死 / 已轉讓）→ 可結案 ───────────────────────────
#[tokio::test]
#[serial]
async fn close_allowed_when_all_animals_left() {
    let app = TestApp::spawn().await;
    let (protocol_id, iacuc_no) = seed_approved_protocol(&app).await;
    seed_animal(&app, &iacuc_no, AnimalStatus::Euthanized).await;
    seed_animal(&app, &iacuc_no, AnimalStatus::SuddenDeath).await;
    seed_animal(&app, &iacuc_no, AnimalStatus::Transferred).await;

    ProtocolService::change_status(&app.db_pool, &SYSTEM_TEST, protocol_id, &close_req())
        .await
        .expect("所有動物皆已離場時結案應成功");
    assert_eq!(fetch_status(&app, protocol_id).await, "CLOSED");
}

// ── 計畫下完全沒有動物 → 可結案 ─────────────────────────────────────────────
#[tokio::test]
#[serial]
async fn close_allowed_when_no_animals() {
    let app = TestApp::spawn().await;
    let (protocol_id, _iacuc_no) = seed_approved_protocol(&app).await;

    ProtocolService::change_status(&app.db_pool, &SYSTEM_TEST, protocol_id, &close_req())
        .await
        .expect("無動物時結案應成功");
    assert_eq!(fetch_status(&app, protocol_id).await, "CLOSED");
}

// ── 已軟刪除的存活動物不應阻擋結案 ──────────────────────────────────────────────
#[tokio::test]
#[serial]
async fn close_allowed_when_alive_animal_soft_deleted() {
    let app = TestApp::spawn().await;
    let (protocol_id, iacuc_no) = seed_approved_protocol(&app).await;
    // 建立一隻實驗中動物後軟刪除 → 不計入存活
    let unique = &Uuid::new_v4().to_string()[..6];
    sqlx::query(
        r#"INSERT INTO animals (id, ear_tag, status, breed, gender, entry_date, iacuc_no, deleted_at)
           VALUES (gen_random_uuid(), $1, $2, 'miniature', 'male', NOW(), $3, NOW())"#,
    )
    .bind(format!("E{unique}"))
    .bind(AnimalStatus::InExperiment)
    .bind(&iacuc_no)
    .execute(&app.db_pool)
    .await
    .expect("insert soft-deleted animal");

    ProtocolService::change_status(&app.db_pool, &SYSTEM_TEST, protocol_id, &close_req())
        .await
        .expect("僅存軟刪除動物時結案應成功");
    assert_eq!(fetch_status(&app, protocol_id).await, "CLOSED");
}
