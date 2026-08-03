// HR 儀表板 + 員工列表 Handlers

use axum::{
    extract::{Query, State},
    response::{IntoResponse, Response},
    Extension, Json,
};
use chrono::Datelike;

use crate::{
    middleware::CurrentUser, models::DashboardCalendarData, repositories::hr as hr_repo,
    services::HrService, AppState, Result,
};

/// 工作人員出勤統計（儀表板用）
pub async fn get_attendance_stats(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    if !current_user.has_permission("hr.attendance.view_all") && !current_user.is_admin() {
        return Err(crate::error::AppError::Forbidden(
            "無權查看出勤統計".to_string(),
        ));
    }
    // coderabbit-fix: 強型別 NaiveDate 直接傳給 repo（取代 String + $1::date cast）
    let parse_date = |raw: &str| {
        chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d")
            .map_err(|_| crate::error::AppError::BadRequest("日期格式應為 YYYY-MM-DD".into()))
    };
    let (start_date, end_date) = match (params.get("start_date"), params.get("end_date")) {
        (Some(s), Some(e)) => (parse_date(s)?, parse_date(e)?),
        _ => {
            let now = chrono::Utc::now();
            let start = chrono::NaiveDate::from_ymd_opt(now.year(), now.month(), 1)
                .unwrap_or_else(|| now.date_naive());
            (start, now.date_naive())
        }
    };
    // R34-1: SQL 下沉 repositories/hr.rs（CLAUDE.md §4「handler 禁直接寫 SQL」）
    let stats =
        hr_repo::list_attendance_stats_by_date_range(&state.db, start_date, end_date).await?;
    let data: Vec<serde_json::Value> = stats
        .into_iter()
        .map(|s| {
            serde_json::json!({
                "user_id": s.user_id.to_string(),
                "display_name": s.display_name,
                "attendance_days": s.attendance_days,
                "late_count": s.late_count,
                "leave_days": s.leave_days,
                // R34-5: overtime_hours 為 Option<f64>，None → JSON null（資料缺失可見）
                "overtime_hours": s.overtime_hours,
            })
        })
        .collect();
    Ok(Json(serde_json::json!({ "data": data })))
}

/// 取得儀表板日曆資料
pub async fn get_dashboard_calendar(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
) -> Result<Json<DashboardCalendarData>> {
    if !current_user.has_permission("hr.attendance.view_all") && !current_user.is_admin() {
        return Err(crate::error::AppError::Forbidden("無權查看 HR 日曆".into()));
    }
    let data = HrService::get_dashboard_calendar(&state.db).await?;
    Ok(Json(data))
}

/// 工作人員簡易資訊
#[derive(Debug, serde::Serialize)]
pub struct StaffInfo {
    pub id: uuid::Uuid,
    pub display_name: String,
    pub email: String,
    pub phone: Option<String>,
    pub organization: Option<String>,
    pub entry_date: Option<chrono::NaiveDate>,
    pub position: Option<String>,
    pub aup_roles: Vec<String>,
    pub years_experience: i32,
    pub trainings: serde_json::Value,
}

/// 最小選擇器 DTO：巡場報告陪同人員下拉用（不含 email / phone / trainings 等 PII）
#[derive(Debug, serde::Serialize)]
pub struct StaffSelectorInfo {
    pub id: uuid::Uuid,
    pub display_name: String,
}

/// active EXPERIMENT_STAFF 清單（排序為場內慣用順序）
async fn fetch_active_experiment_staff(pool: &sqlx::PgPool) -> Result<Vec<StaffInfo>> {
    let staff = sqlx::query_as::<
        _,
        (
            uuid::Uuid,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<chrono::NaiveDate>,
            Option<String>,
            Vec<String>,
            i32,
            serde_json::Value,
        ),
    >(
        r#"SELECT id, display_name, email, phone, organization,
               entry_date, position, aup_roles, years_experience, trainings
        FROM (
            SELECT DISTINCT u.id, u.display_name, u.email, u.phone, u.organization,
                   u.entry_date, u.position, u.aup_roles, u.years_experience, u.trainings
            FROM users u
            INNER JOIN user_roles ur ON u.id = ur.user_id
            INNER JOIN roles r ON ur.role_id = r.id
            WHERE u.is_active = true AND r.code = 'EXPERIMENT_STAFF'
        ) s
        ORDER BY
            CASE
                WHEN display_name LIKE '%怡均%' THEN 1
                WHEN display_name LIKE '%莉珊%' THEN 2
                WHEN display_name LIKE '%芮蓁%' THEN 3
                WHEN display_name LIKE '%永發%' THEN 4
                WHEN display_name LIKE '%映潔%' THEN 5
                WHEN display_name LIKE '%意萍%' THEN 6
                WHEN display_name LIKE '%佳棋%' THEN 7
                WHEN display_name LIKE '%實習生%' THEN 8
                ELSE 99
            END,
            display_name"#,
    )
    .fetch_all(pool)
    .await?;
    Ok(staff
        .into_iter()
        .map(
            |(
                id,
                display_name,
                email,
                phone,
                organization,
                entry_date,
                position,
                aup_roles,
                years_experience,
                trainings,
            )| StaffInfo {
                id,
                display_name,
                email,
                phone,
                organization,
                entry_date,
                position,
                aup_roles,
                years_experience,
                trainings,
            },
        )
        .collect())
}

/// 工作人員列表（供請假代理人 / 巡場報告陪同人員選擇）
///
/// 回傳內容依權限分級（least-privilege）：
/// - HR 權限（hr.leave.create / hr.attendance.view_all）或 admin → 完整 `StaffInfo`
/// - 僅 animal.vet.recommend（獸醫選巡場報告陪同人員）→ 最小欄位 `StaffSelectorInfo`，
///   避免將 staff PII 擴大暴露給 VET 角色
pub async fn list_staff_for_proxy(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
) -> Result<Response> {
    let has_hr_view = current_user.has_permission("hr.leave.create")
        || current_user.has_permission("hr.attendance.view_all")
        || current_user.is_admin();
    if !has_hr_view && !current_user.has_permission("animal.vet.recommend") {
        return Err(crate::error::AppError::Forbidden(
            "無權查看工作人員列表".into(),
        ));
    }
    let staff = fetch_active_experiment_staff(&state.db).await?;
    if has_hr_view {
        return Ok(Json(staff).into_response());
    }
    let selector: Vec<StaffSelectorInfo> = staff
        .into_iter()
        .map(|s| StaffSelectorInfo {
            id: s.id,
            display_name: s.display_name,
        })
        .collect();
    Ok(Json(selector).into_response())
}

/// 內部員工列表（排除 admin；供特休管理、人員訓練等使用）
pub async fn list_internal_users_for_balance(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
) -> Result<Json<Vec<StaffInfo>>> {
    if !current_user.is_admin()
        && !current_user
            .roles
            .contains(&crate::constants::ROLE_ADMIN_STAFF.to_string())
        && !current_user.has_permission("hr.balance.manage")
        && !current_user.has_permission("training.view")
        && !current_user.has_permission("training.manage")
    {
        return Err(crate::error::AppError::Forbidden(
            "無權查看員工列表".to_string(),
        ));
    }
    let staff = sqlx::query_as::<
        _,
        (
            uuid::Uuid,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<chrono::NaiveDate>,
            Option<String>,
            Vec<String>,
            i32,
            serde_json::Value,
        ),
    >(
        r#"SELECT u.id, u.display_name, u.email, u.phone, u.organization,
               u.entry_date, u.position, u.aup_roles, u.years_experience, u.trainings
        FROM users u
        WHERE u.is_active = true AND u.is_internal = true AND u.email != 'admin@ipigsystem.asia'
        AND NOT EXISTS (
            SELECT 1 FROM user_roles ur JOIN roles r ON ur.role_id = r.id
            WHERE ur.user_id = u.id AND (r.code = 'SYSTEM_ADMIN' OR r.code = 'admin')
        )
        ORDER BY u.display_name"#,
    )
    .fetch_all(&state.db)
    .await?;
    let result: Vec<StaffInfo> = staff
        .into_iter()
        .map(
            |(
                id,
                display_name,
                email,
                phone,
                organization,
                entry_date,
                position,
                aup_roles,
                years_experience,
                trainings,
            )| StaffInfo {
                id,
                display_name,
                email,
                phone,
                organization,
                entry_date,
                position,
                aup_roles,
                years_experience,
                trainings,
            },
        )
        .collect();
    Ok(Json(result))
}
