// HR 請假管理

use chrono::{NaiveDate, Utc};
use rust_decimal::Decimal;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    error::AppError,
    middleware::{ActorContext, CurrentUser},
    models::{
        audit_diff::DataDiff, CreateLeaveRequest, LeaveQuery, LeaveRequest, LeaveRequestWithUser,
        LeaveStatus, PaginatedResponse, UpdateLeaveRequest,
    },
    services::{
        audit::{ActivityLogEntry, AuditEntity},
        AuditService,
    },
    Result,
};

use super::HrService;

/// `cancel_leave` 回傳：取消後的紀錄 + 通知派發所需資訊。
///
/// handler 不再自行讀 DB 推導 `was_approved` 或反查申請人名稱（符 CLAUDE.md §4：
/// handler 禁止 SQL / DB 讀取），一律由 service 於交易脈絡內取得後回傳。
pub struct CancelLeaveOutcome {
    pub record: LeaveRequest,
    pub was_approved: bool,
    /// 請假當事人 display_name（主管代取消時 ≠ 取消者）。
    pub applicant_name: String,
}

impl HrService {
    // ============================================
    // Leave
    // ============================================

    pub async fn list_leaves(
        pool: &PgPool,
        query: &LeaveQuery,
        current_user: &CurrentUser,
    ) -> Result<PaginatedResponse<LeaveRequestWithUser>> {
        let page = query.page.unwrap_or(1);
        let per_page = query.per_page.unwrap_or(50).min(500);
        let offset = (page - 1) * per_page;

        // 如果是待審核查詢，篩選所有 PENDING 狀態的請假
        let is_pending_approval = query.pending_approval.unwrap_or(false);

        let total: (i64,) = sqlx::query_as(
            r#"
            SELECT COUNT(*) FROM leave_requests
            WHERE ($1::uuid IS NULL OR user_id = $1)
              AND ($2::text IS NULL OR status::text = $2)
              AND ($3::text IS NULL OR leave_type::text = $3)
              AND ($4::date IS NULL OR start_date >= $4)
              AND ($5::date IS NULL OR end_date <= $5)
              AND ($6::bool = false OR status::text LIKE 'PENDING%')
            "#,
        )
        .bind(query.user_id)
        .bind(&query.status)
        .bind(&query.leave_type)
        .bind(query.from)
        .bind(query.to)
        .bind(is_pending_approval)
        .fetch_one(pool)
        .await?;

        let mut data = sqlx::query_as::<_, LeaveRequestWithUser>(
            r#"
            SELECT
                l.id, l.user_id, u.email as user_email, u.display_name as user_name,
                l.proxy_user_id, proxy.display_name as proxy_user_name,
                l.leave_type::text as leave_type, l.start_date, l.end_date, l.total_days, l.total_hours, l.reason,
                l.is_urgent, l.is_retroactive, l.status::text as status,
                l.current_approver_id, approver.display_name as current_approver_name,
                l.submitted_at, l.created_at
            FROM leave_requests l
            INNER JOIN users u ON l.user_id = u.id
            LEFT JOIN users proxy ON l.proxy_user_id = proxy.id
            LEFT JOIN users approver ON l.current_approver_id = approver.id
            WHERE ($1::uuid IS NULL OR l.user_id = $1)
              AND ($2::text IS NULL OR l.status::text = $2)
              AND ($3::text IS NULL OR l.leave_type::text = $3)
              AND ($4::date IS NULL OR l.start_date >= $4)
              AND ($5::date IS NULL OR l.end_date <= $5)
              AND ($6::bool = false OR l.status::text LIKE 'PENDING%')
            ORDER BY l.created_at DESC
            LIMIT $7 OFFSET $8
            "#,
        )
        .bind(query.user_id)
        .bind(&query.status)
        .bind(&query.leave_type)
        .bind(query.from)
        .bind(query.to)
        .bind(is_pending_approval)
        .bind(per_page)
        .bind(offset)
        .fetch_all(pool)
        .await?;

        // 逐列計算「當前使用者是否可審核」，與 approve/reject 服務層授權完全一致
        // （中央 can_user_approve_leave：兩關 + 職責分離 + admin 卡關代批）。
        // 僅對待審中(PENDING*)的列計算，其餘直接 false，避免多餘查詢。
        for row in &mut data {
            row.can_approve = if row.status.starts_with("PENDING") {
                Self::can_user_approve_leave(pool, row.id, &row.status, row.user_id, current_user)
                    .await?
            } else {
                false
            };
            // 代理確認關（PENDING_PROXY）：僅該假單指定的代理人本人可確認/退回。
            row.can_confirm_proxy = row.status == LeaveStatus::PendingProxy.as_str()
                && row.proxy_user_id == Some(current_user.id);
        }

        Ok(PaginatedResponse::new(data, total.0, page, per_page))
    }

    pub async fn get_leave(
        pool: &PgPool,
        id: Uuid,
        current_user: &CurrentUser,
    ) -> Result<LeaveRequest> {
        let record = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT 
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_one(pool)
        .await?;

        let has_view_all = current_user.has_permission("hr.leave.view_all");
        let is_owner = record.user_id == current_user.id;
        let is_approver = record.current_approver_id == Some(current_user.id);
        if !has_view_all && !is_owner && !is_approver {
            return Err(AppError::Forbidden("無權存取此請假紀錄".into()));
        }

        Ok(record)
    }

    // ============================================
    // 審核資格判定（兩關 + 職責分離 + admin 卡關代批）
    // ============================================

    /// 申請人所屬部門是否有「可審核 L1」的合法主管（在職、且非申請人本人）。
    async fn l1_has_eligible_approver(pool: &PgPool, applicant_id: Uuid) -> Result<bool> {
        let exists: (bool,) = sqlx::query_as(
            r#"SELECT EXISTS(
                SELECT 1 FROM users u
                JOIN departments d ON u.department_id = d.id
                JOIN users m ON m.id = d.manager_id
                WHERE u.id = $1 AND m.is_active = true AND m.deleted_at IS NULL
                  AND d.manager_id <> $1
            )"#,
        )
        .bind(applicant_id)
        .fetch_one(pool)
        .await?;
        Ok(exists.0)
    }

    /// 指定使用者是否為申請人所屬部門的主管。
    async fn is_dept_manager_of(pool: &PgPool, applicant_id: Uuid, user_id: Uuid) -> Result<bool> {
        let exists: (bool,) = sqlx::query_as(
            r#"SELECT EXISTS(
                SELECT 1 FROM users u JOIN departments d ON u.department_id = d.id
                WHERE u.id = $1 AND d.manager_id = $2
            )"#,
        )
        .bind(applicant_id)
        .bind(user_id)
        .fetch_one(pool)
        .await?;
        Ok(exists.0)
    }

    /// 負責人（終審）關是否有合法審核人：在職 DIRECTOR、非申請人、且未批過本單前關（職責分離）。
    async fn director_has_eligible_approver(
        pool: &PgPool,
        leave_id: Uuid,
        applicant_id: Uuid,
    ) -> Result<bool> {
        let exists: (bool,) = sqlx::query_as(
            r#"SELECT EXISTS(
                SELECT 1 FROM users u
                JOIN user_roles ur ON ur.user_id = u.id
                JOIN roles r ON r.id = ur.role_id
                WHERE r.code = $1 AND u.is_active = true AND u.deleted_at IS NULL
                  AND u.id <> $2
                  AND NOT EXISTS (
                    SELECT 1 FROM leave_approvals la
                    WHERE la.leave_request_id = $3 AND la.approver_id = u.id AND la.action = 'APPROVE'
                      AND la.approval_level <> 'PENDING_PROXY'
                  )
            )"#,
        )
        .bind(crate::constants::ROLE_DIRECTOR)
        .bind(applicant_id)
        .bind(leave_id)
        .fetch_one(pool)
        .await?;
        Ok(exists.0)
    }

    /// 職責分離：使用者是否已在本單「核准」過任一**審核關**（批過前關者不得再批後關）。
    /// 代理確認（approval_level='PENDING_PROXY'）不算審核，故排除——否則「單位主管兼代理人」
    /// 於確認代理後會被 SoD 擋住而無法審核 PENDING_L1，導致假單卡關。
    async fn has_prior_approval(pool: &PgPool, leave_id: Uuid, user_id: Uuid) -> Result<bool> {
        let exists: (bool,) = sqlx::query_as(
            r#"SELECT EXISTS(
                SELECT 1 FROM leave_approvals
                WHERE leave_request_id = $1 AND approver_id = $2 AND action = 'APPROVE'
                  AND approval_level <> 'PENDING_PROXY'
            )"#,
        )
        .bind(leave_id)
        .bind(user_id)
        .fetch_one(pool)
        .await?;
        Ok(exists.0)
    }

    /// 使用者是否為此關的「指定審核人」（非 admin 代批）：L1=單位主管、DIRECTOR=負責人。
    fn is_designated_for(status: &str, is_dept_manager: bool, is_director: bool) -> bool {
        match status {
            s if s == LeaveStatus::PendingL1.as_str() => is_dept_manager,
            s if s == LeaveStatus::PendingDirector.as_str() => is_director,
            _ => false,
        }
    }

    /// 中央授權判定：使用者能否審核（核准/駁回）此單當前關卡。
    /// 規則：不可批自己、批過前關者不得再批(SoD)、該關指定審核人可批、
    /// admin 僅在「該關無其他合法審核人（卡關）」時可代批。
    /// 例外（SoD 放寬）：終審（DIRECTOR）關卡關且無其他合法 DIRECTOR 時，
    /// admin 即使批過前關仍可代批，避免單一審批人組織下假單永久死鎖。
    pub async fn can_user_approve_leave(
        pool: &PgPool,
        leave_id: Uuid,
        status: &str,
        applicant_id: Uuid,
        user: &CurrentUser,
    ) -> Result<bool> {
        // 不可審核自己的假單（任何關卡、任何角色皆不放寬）
        if applicant_id == user.id {
            return Ok(false);
        }
        let is_admin = user.is_admin();
        let is_director = user
            .roles
            .iter()
            .any(|r| r == crate::constants::ROLE_DIRECTOR);
        // 職責分離（SoD）：是否已在本單「核准」過前一審核關（代理確認不算）。
        let has_prior = Self::has_prior_approval(pool, leave_id, user.id).await?;
        match status {
            s if s == LeaveStatus::PendingL1.as_str() => {
                // SoD：批過前關者不得再批本關（L1 不放寬）。
                if has_prior {
                    return Ok(false);
                }
                if Self::is_dept_manager_of(pool, applicant_id, user.id).await? {
                    return Ok(true);
                }
                Ok(is_admin && !Self::l1_has_eligible_approver(pool, applicant_id).await?)
            }
            s if s == LeaveStatus::PendingDirector.as_str() => {
                // 指定負責人（未批過前關）→ 正常簽核。
                if is_director && !has_prior {
                    return Ok(true);
                }
                // 終審關卡關代批：無其他合法 DIRECTOR 時，admin 可代批終審。
                // 此處刻意放寬 SoD——即使 admin 批過前關仍可代批。否則在單一審批人組織下，
                // admin 於前關用掉 SoD 額度後，終審關將無人可簽 → 假單永久死鎖。
                // director_has_eligible_approver 已排除「批過前關者」，故僅在真正無他人時才代批，
                // 且系統一定有 admin，終審恆有真人簽核。
                Ok(is_admin
                    && !Self::director_has_eligible_approver(pool, leave_id, applicant_id).await?)
            }
            _ => Ok(false),
        }
    }

    /// 使用者是否具「負責人」角色。申請人未必等於當前操作者（`hr.leave.manage` 可代人送審），
    /// 故查 DB 而非讀 `CurrentUser.roles`。
    async fn user_is_director(pool: &PgPool, user_id: Uuid) -> Result<bool> {
        let exists: (bool,) = sqlx::query_as(
            r#"SELECT EXISTS(
                SELECT 1 FROM users u
                JOIN user_roles ur ON ur.user_id = u.id
                JOIN roles r ON r.id = ur.role_id
                WHERE u.id = $1 AND r.code = $2
                  AND u.is_active = true AND u.deleted_at IS NULL
            )"#,
        )
        .bind(user_id)
        .bind(crate::constants::ROLE_DIRECTOR)
        .fetch_one(pool)
        .await?;
        Ok(exists.0)
    }

    /// 職務代理人驗證：必填、不可為申請人本人、須在職、且不可於同時段也在請假。
    /// 例外：負責人之上無人可代理其職務，代理人改為選填——未指定時其假單走報備制
    /// （見 `submit_leave`），不進代理確認關。
    async fn validate_proxy(
        pool: &PgPool,
        applicant_id: Uuid,
        proxy_id: Option<Uuid>,
        start: NaiveDate,
        end: NaiveDate,
    ) -> Result<()> {
        let Some(proxy_id) = proxy_id else {
            if Self::user_is_director(pool, applicant_id).await? {
                return Ok(());
            }
            return Err(AppError::BadRequest("請假必須指定職務代理人".into()));
        };
        if proxy_id == applicant_id {
            return Err(AppError::BadRequest("職務代理人不可為申請人本人".into()));
        }
        let active: (bool,) = sqlx::query_as(
            "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND is_active = true AND deleted_at IS NULL)",
        )
        .bind(proxy_id)
        .fetch_one(pool)
        .await?;
        if !active.0 {
            return Err(AppError::BadRequest("所選職務代理人無效或已停用".into()));
        }
        // 排除「同時段也在請假」的代理人（未終結/已核准且日期重疊）。
        let overlap: (bool,) = sqlx::query_as(
            r#"SELECT EXISTS(
                SELECT 1 FROM leave_requests
                WHERE user_id = $1
                  AND status IN ('PENDING_PROXY','PENDING_L1','PENDING_L2','PENDING_HR','PENDING_GM','PENDING_DIRECTOR','APPROVED')
                  AND start_date <= $3 AND end_date >= $2
            )"#,
        )
        .bind(proxy_id)
        .bind(start)
        .bind(end)
        .fetch_one(pool)
        .await?;
        if overlap.0 {
            return Err(AppError::BadRequest(
                "所選職務代理人於該期間也在請假，請改選他人".into(),
            ));
        }
        Ok(())
    }

    /// 檢查時數是否為 0.5 的倍數
    fn is_half_hour_multiple(v: f64) -> bool {
        v >= 0.5 && (v * 2.0 - (v * 2.0).round()).abs() < 1e-9
    }

    pub async fn create_leave(
        pool: &PgPool,
        actor: &ActorContext,
        payload: &CreateLeaveRequest,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;
        let user_id = user.id;

        // 職務代理人必選 + 驗證（不可自己、須在職、排除同時段也請假者）
        Self::validate_proxy(
            pool,
            user_id,
            payload.proxy_user_id,
            payload.start_date,
            payload.end_date,
        )
        .await?;

        let effective_hours = payload.total_hours.unwrap_or(payload.total_days * 8.0);
        if !Self::is_half_hour_multiple(effective_hours) {
            return Err(AppError::BadRequest(
                "請假時數須為 0.5 小時的倍數（如 0.5、1、1.5、2...）".into(),
            ));
        }
        let total_days = payload
            .total_hours
            .map(|h| h / 8.0)
            .unwrap_or(payload.total_days);
        let total_hours = Some(payload.total_hours.unwrap_or(payload.total_days * 8.0));

        let id = Uuid::new_v4();

        // 處理 supporting_documents 轉為 JSON
        let supporting_docs = payload
            .supporting_documents
            .as_ref()
            .map(|docs| serde_json::json!(docs))
            .unwrap_or_else(|| serde_json::json!([]));

        // 理由處理：特休假可以為空，其他假別需要檢查
        let reason = payload.reason.clone().unwrap_or_default();

        let mut tx = pool.begin().await?;

        let record = sqlx::query_as::<_, LeaveRequest>(
            r#"
            INSERT INTO leave_requests (
                id, user_id, proxy_user_id, leave_type, start_date, end_date, start_time, end_time,
                total_days, total_hours, reason, supporting_documents, is_urgent, is_retroactive, status
            ) VALUES ($1, $2, $3, $4::leave_type, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, 'DRAFT'::leave_status)
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .bind(user_id)
        .bind(payload.proxy_user_id)
        .bind(&payload.leave_type)
        .bind(payload.start_date)
        .bind(payload.end_date)
        .bind(payload.start_time)
        .bind(payload.end_time)
        .bind(total_days)
        .bind(total_hours)
        .bind(&reason)
        .bind(&supporting_docs)
        .bind(payload.is_urgent.unwrap_or(false))
        .bind(payload.is_retroactive.unwrap_or(false))
        .fetch_one(&mut *tx)
        .await?;

        let display = format!(
            "{} {}~{}",
            record.leave_type, record.start_date, record.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type: "LEAVE_CREATE",
                entity: Some(AuditEntity::new("leave_request", record.id, &display)),
                data_diff: Some(DataDiff::create_only(&record)),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(record)
    }

    pub async fn update_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
        payload: &UpdateLeaveRequest,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;

        // 同 create_leave：時數須為 0.5 的倍數。優先檢查 total_hours；
        // 若僅提供 total_days，換算為時數再檢查（避免 0.3 天 = 2.4 小時 的偷渡）
        if let Some(hours) = payload.total_hours {
            if !Self::is_half_hour_multiple(hours) {
                return Err(AppError::BadRequest(
                    "請假時數須為 0.5 小時的倍數（如 0.5、1、1.5、2...）".into(),
                ));
            }
        } else if let Some(days) = payload.total_days {
            if !Self::is_half_hour_multiple(days * 8.0) {
                return Err(AppError::BadRequest(
                    "請假天數換算為時數後須為 0.5 小時的倍數".into(),
                ));
            }
        }

        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("請假申請不存在".into()))?;

        if before.user_id != user.id && !user.has_permission("hr.leave.manage") {
            return Err(AppError::Forbidden("無權修改他人的請假申請".into()));
        }

        if before.status != "DRAFT" {
            return Err(AppError::BusinessRule("僅草稿狀態的請假可更新".into()));
        }

        let after = sqlx::query_as::<_, LeaveRequest>(
            r#"
            UPDATE leave_requests
            SET start_date = COALESCE($2, start_date),
                end_date = COALESCE($3, end_date),
                start_time = COALESCE($4, start_time),
                end_time = COALESCE($5, end_time),
                total_days = COALESCE($6, total_days),
                total_hours = COALESCE($7, total_hours),
                reason = COALESCE($8, reason),
                proxy_user_id = COALESCE($9, proxy_user_id),
                updated_at = NOW()
            WHERE id = $1 AND status = 'DRAFT'::leave_status
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .bind(payload.start_date)
        .bind(payload.end_date)
        .bind(payload.start_time)
        .bind(payload.end_time)
        .bind(payload.total_days)
        .bind(payload.total_hours)
        .bind(&payload.reason)
        .bind(payload.proxy_user_id)
        .fetch_one(&mut *tx)
        .await?;

        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type: "LEAVE_UPDATE",
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(after)
    }

    pub async fn delete_leave(pool: &PgPool, actor: &ActorContext, id: Uuid) -> Result<()> {
        let user = actor.require_user()?;
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 AND status = 'DRAFT'::leave_status FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("請假申請不存在或非草稿狀態".into()))?;

        if before.user_id != user.id && !user.has_permission("hr.leave.manage") {
            return Err(AppError::Forbidden("無權刪除他人的請假申請".into()));
        }

        sqlx::query("DELETE FROM leave_requests WHERE id = $1 AND status = 'DRAFT'::leave_status")
            .bind(id)
            .execute(&mut *tx)
            .await?;

        let display = format!(
            "{} {}~{}",
            before.leave_type, before.start_date, before.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type: "LEAVE_DELETE",
                entity: Some(AuditEntity::new("leave_request", before.id, &display)),
                data_diff: Some(DataDiff::delete_only(&before)),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(())
    }

    /// 以 FOR UPDATE 鎖定並載入單筆請假（供狀態轉移前讀取，DRY 共用）。
    async fn lock_leave_for_update(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        id: Uuid,
    ) -> Result<LeaveRequest> {
        sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| AppError::NotFound("請假申請不存在".into()))
    }

    /// 寫入一筆審核歷程（leave_approvals）。approval_level 記錄當前關卡狀態、action 為 APPROVE/REJECT。
    async fn insert_leave_approval(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave_id: Uuid,
        approver_id: Uuid,
        approval_level: &str,
        action: &str,
        comments: Option<&str>,
    ) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO leave_approvals (id, leave_request_id, approver_id, approval_level, action, comments)
            VALUES ($1, $2, $3, $4, $5, $6)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(leave_id)
        .bind(approver_id)
        .bind(approval_level)
        .bind(action)
        .bind(comments)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    pub async fn submit_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("請假申請不存在".into()))?;

        if before.user_id != user.id && !user.has_permission("hr.leave.manage") {
            return Err(AppError::Forbidden("無權送審他人的請假申請".into()));
        }

        if before.status != "DRAFT" {
            return Err(AppError::BusinessRule("僅草稿狀態的請假可送審".into()));
        }

        // 送審時再驗證職務代理人（草稿可能未帶或代理人狀態已變）
        Self::validate_proxy(
            pool,
            before.user_id,
            before.proxy_user_id,
            before.start_date,
            before.end_date,
        )
        .await?;

        // 負責人本人請假走報備制：沒有人可代理其職務，終審關也只剩他自己
        // （`can_user_approve_leave` 首條即禁止批自己的單，admin 代批同樣被擋）→
        // 送出即核准並扣餘額，否則假單會永久卡在終審關。
        const SELF_REPORT_COMMENT: &str = "負責人報備制：送出即核准";
        let director_self_report =
            before.proxy_user_id.is_none() && Self::user_is_director(pool, before.user_id).await?;

        let after = if director_self_report {
            Self::deduct_leave_balance(&mut tx, &before).await?;
            Self::insert_leave_approval(
                &mut tx,
                id,
                before.user_id,
                LeaveStatus::PendingDirector.as_str(),
                "APPROVE",
                Some(SELF_REPORT_COMMENT),
            )
            .await?;
            sqlx::query_as::<_, LeaveRequest>(
                r#"
                UPDATE leave_requests
                SET status = 'APPROVED'::leave_status, current_approver_id = NULL,
                    submitted_at = NOW(), approved_at = NOW(), updated_at = NOW()
                WHERE id = $1 AND status = 'DRAFT'::leave_status
                RETURNING
                    id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                    start_time, end_time, total_days, total_hours, reason, supporting_documents,
                    annual_leave_source_id, is_urgent, is_retroactive,
                    status::text as status, current_approver_id, submitted_at, approved_at,
                    rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                    created_at, updated_at
                "#,
            )
            .bind(id)
            .fetch_one(&mut *tx)
            .await?
        } else {
            // 審核鏈第一關為「代理人確認」（非負責人時 validate_proxy 已保證 proxy 非空）。
            // current_approver_id 設為代理人，供「待我確認」清單反查。
            sqlx::query_as::<_, LeaveRequest>(
                r#"
                UPDATE leave_requests
                SET status = 'PENDING_PROXY'::leave_status, current_approver_id = proxy_user_id,
                    submitted_at = NOW(), updated_at = NOW()
                WHERE id = $1 AND status = 'DRAFT'::leave_status
                RETURNING
                    id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                    start_time, end_time, total_days, total_hours, reason, supporting_documents,
                    annual_leave_source_id, is_urgent, is_retroactive,
                    status::text as status, current_approver_id, submitted_at, approved_at,
                    rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                    created_at, updated_at
                "#,
            )
            .bind(id)
            .fetch_one(&mut *tx)
            .await?
        };

        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                // 報備制與一般送審分開記事件，稽核查詢時可直接篩出負責人自核的假單。
                event_type: if director_self_report {
                    "LEAVE_DIRECTOR_SELF_APPROVE"
                } else {
                    "LEAVE_SUBMIT"
                },
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(after)
    }

    /// 代理人確認：PENDING_PROXY →（單位主管有主管）PENDING_L1，否則跳關 → PENDING_DIRECTOR。
    /// 僅該假單指定的職務代理人本人可確認。
    pub async fn proxy_confirm_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;
        let mut tx = pool.begin().await?;

        // 資源不存在時亦回 Forbidden（與存在但非代理人一致），避免以 404/403 差異
        // 探測特定假單是否存在（existence oracle 防護）。
        let before = match Self::lock_leave_for_update(&mut tx, id).await {
            Ok(b) => b,
            Err(AppError::NotFound(_)) => {
                return Err(AppError::Forbidden("僅指定的職務代理人可確認此請假".into()))
            }
            Err(e) => return Err(e),
        };

        if before.proxy_user_id != Some(user.id) {
            return Err(AppError::Forbidden("僅指定的職務代理人可確認此請假".into()));
        }
        if before.status != LeaveStatus::PendingProxy.as_str() {
            return Err(AppError::BusinessRule(
                "僅待代理確認狀態的請假可由代理人確認".into(),
            ));
        }

        // 卡關自動跳關：申請人部門無合法單位主管時，直接進「待負責人簽核」關。
        let next_status = if Self::l1_has_eligible_approver(pool, before.user_id).await? {
            LeaveStatus::PendingL1.as_str()
        } else {
            LeaveStatus::PendingDirector.as_str()
        };

        // 代理確認記入審核歷程（action 沿用 APPROVE，approval_level 標記 PENDING_PROXY 以資區分）。
        Self::insert_leave_approval(
            &mut tx,
            id,
            user.id,
            LeaveStatus::PendingProxy.as_str(),
            "APPROVE",
            None,
        )
        .await?;

        let after = sqlx::query_as::<_, LeaveRequest>(
            r#"
            UPDATE leave_requests
            SET status = $2::leave_status, current_approver_id = NULL, updated_at = NOW()
            WHERE id = $1 AND status = 'PENDING_PROXY'::leave_status
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .bind(next_status)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| {
            AppError::Conflict("此請假狀態已被其他操作變更，請重新整理後再試".to_string())
        })?;

        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type: "LEAVE_PROXY_CONFIRM",
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(after)
    }

    /// 代理人退回：PENDING_PROXY → DRAFT（供申請人重新指定代理人）。保留原 proxy_user_id 與歷程。
    pub async fn proxy_reject_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
        reason: Option<&str>,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;
        let mut tx = pool.begin().await?;

        // existence oracle 防護：不存在時亦回 Forbidden（與非代理人一致）。
        let before = match Self::lock_leave_for_update(&mut tx, id).await {
            Ok(b) => b,
            Err(AppError::NotFound(_)) => {
                return Err(AppError::Forbidden("僅指定的職務代理人可退回此請假".into()))
            }
            Err(e) => return Err(e),
        };

        if before.proxy_user_id != Some(user.id) {
            return Err(AppError::Forbidden("僅指定的職務代理人可退回此請假".into()));
        }
        if before.status != LeaveStatus::PendingProxy.as_str() {
            return Err(AppError::BusinessRule(
                "僅待代理確認狀態的請假可由代理人退回".into(),
            ));
        }

        Self::insert_leave_approval(
            &mut tx,
            id,
            user.id,
            LeaveStatus::PendingProxy.as_str(),
            "REJECT",
            reason,
        )
        .await?;

        // 退回草稿：清 current_approver_id 與 submitted_at，保留 proxy_user_id 供申請人參考。
        let after = sqlx::query_as::<_, LeaveRequest>(
            r#"
            UPDATE leave_requests
            SET status = 'DRAFT'::leave_status, current_approver_id = NULL,
                submitted_at = NULL, updated_at = NOW()
            WHERE id = $1 AND status = 'PENDING_PROXY'::leave_status
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| {
            AppError::Conflict("此請假狀態已被其他操作變更，請重新整理後再試".to_string())
        })?;

        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type: "LEAVE_PROXY_REJECT",
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(after)
    }

    pub async fn approve_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
        comments: Option<&str>,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;
        let approver_id = user.id;
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;

        // 授權判定（中央邏輯，含「不可批自己」「職責分離」「卡關 admin 代批」）。
        if !Self::can_user_approve_leave(pool, before.id, &before.status, before.user_id, user)
            .await?
        {
            return Err(AppError::Forbidden(
                "您無權審核此請假，或已審核過本單前一關".into(),
            ));
        }

        // 是否為 admin 代批（非該關指定審核人）→ 稽核事件區分
        let is_director = user
            .roles
            .iter()
            .any(|r| r == crate::constants::ROLE_DIRECTOR);
        let is_dept_manager = Self::is_dept_manager_of(pool, before.user_id, approver_id).await?;
        let is_override = user.is_admin()
            && !Self::is_designated_for(&before.status, is_dept_manager, is_director);

        // 兩關流程：待單位主管(L1) → 待負責人(DIRECTOR，終審) → 已核准
        let next_status = match before.status.as_str() {
            s if s == LeaveStatus::PendingL1.as_str() => LeaveStatus::PendingDirector.as_str(),
            s if s == LeaveStatus::PendingDirector.as_str() => LeaveStatus::Approved.as_str(),
            _ => return Err(AppError::Validation("無法核准此狀態的請假".to_string())),
        };

        // 最終核准時，檢查並扣除假別餘額（同一 tx 內，餘額異動與狀態變更原子化）
        let is_final_approval = next_status == LeaveStatus::Approved.as_str();
        if is_final_approval {
            Self::deduct_leave_balance(&mut tx, &before).await?;
        }

        sqlx::query(
            r#"
            INSERT INTO leave_approvals (id, leave_request_id, approver_id, approval_level, action, comments)
            VALUES ($1, $2, $3, $4, 'APPROVE', $5)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(id)
        .bind(approver_id)
        .bind(&before.status)
        .bind(comments)
        .execute(&mut *tx)
        .await?;

        let approved_at = if is_final_approval {
            Some(Utc::now())
        } else {
            None
        };

        // SEC-BIZ-5: 使用 WHERE status 條件防止 race condition（TOCTOU）
        // 若另一個請求已先修改狀態，此 UPDATE 不會匹配任何行 → 回傳衝突錯誤
        let after_opt = sqlx::query_as::<_, LeaveRequest>(
            r#"
            UPDATE leave_requests
            SET status = $2::leave_status, approved_at = $3, current_approver_id = NULL, updated_at = NOW()
            WHERE id = $1 AND status = $4::leave_status
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .bind(next_status)
        .bind(approved_at)
        .bind(&before.status)
        .fetch_optional(&mut *tx)
        .await?;

        let after = after_opt.ok_or_else(|| {
            AppError::Conflict("此請假狀態已被其他操作變更，請重新整理後再試".to_string())
        })?;

        // event_type 區分中途/最終核准 + admin 代批（override），方便稽核查詢
        let event_type = match (is_final_approval, is_override) {
            (true, true) => "LEAVE_APPROVE_FINAL_OVERRIDE",
            (true, false) => "LEAVE_APPROVE_FINAL",
            (false, true) => "LEAVE_APPROVE_INTERIM_OVERRIDE",
            (false, false) => "LEAVE_APPROVE_INTERIM",
        };
        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type,
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(after)
    }

    pub async fn reject_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
        reason: &str,
    ) -> Result<LeaveRequest> {
        let user = actor.require_user()?;
        let rejecter_id = user.id;
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;

        // SEC-BIZ: 只有待審核（PENDING*）的請假可被駁回。
        // 缺少此守衛時，已核准的請假可被翻成 REJECTED 但餘額不會回補（reject 不走 restore_leave_balance），
        // 造成員工特休/補休默默損失，且終態（CANCELLED/REVOKED）也會被竄改。
        if !before.status.starts_with("PENDING") {
            return Err(AppError::Conflict(format!(
                "只有待審核的請假可駁回（目前狀態：{}）",
                before.status
            )));
        }

        // 授權判定：駁回與核准同一資格（該關合法審核人，含 SoD 與 admin 卡關代批）。
        if !Self::can_user_approve_leave(pool, before.id, &before.status, before.user_id, user)
            .await?
        {
            return Err(AppError::Forbidden(
                "您無權駁回此請假，或已審核過本單前一關".into(),
            ));
        }

        sqlx::query(
            r#"
            INSERT INTO leave_approvals (id, leave_request_id, approver_id, approval_level, action, comments)
            VALUES ($1, $2, $3, $4, 'REJECT', $5)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(id)
        .bind(rejecter_id)
        .bind(&before.status)
        .bind(reason)
        .execute(&mut *tx)
        .await?;

        let after = sqlx::query_as::<_, LeaveRequest>(
            r#"
            UPDATE leave_requests
            SET status = 'REJECTED'::leave_status, rejected_at = NOW(), updated_at = NOW()
            WHERE id = $1
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;

        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type: "LEAVE_REJECT",
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(after)
    }

    /// 計算有效請假時數（total_hours 優先，否則換算天數 × 8）
    #[cfg(test)]
    pub(super) fn effective_hours(total_hours: Option<f64>, total_days: f64) -> f64 {
        total_hours.unwrap_or(total_days * 8.0)
    }

    pub async fn cancel_leave(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
        reason: Option<&str>,
    ) -> Result<CancelLeaveOutcome> {
        let current = actor.require_user()?;
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, LeaveRequest>(
            r#"
            SELECT
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            FROM leave_requests WHERE id = $1 FOR UPDATE
            "#,
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("找不到請假紀錄".into()))?;

        // SEC-IDOR: 只有本人或具 hr.leave.manage 權限者可取消（與 update/delete_leave 一致）
        if before.user_id != current.id && !current.has_permission("hr.leave.manage") {
            return Err(AppError::Forbidden("無權取消他人請假".into()));
        }

        let was_approved = before.status == LeaveStatus::Approved.as_str();

        let after = sqlx::query_as::<_, LeaveRequest>(
            r#"
            UPDATE leave_requests
            SET status = 'CANCELLED'::leave_status, current_approver_id = NULL,
                cancelled_at = NOW(), cancellation_reason = $2, updated_at = NOW()
            WHERE id = $1 AND status IN ('DRAFT'::leave_status, 'PENDING_PROXY'::leave_status, 'PENDING_L1'::leave_status, 'PENDING_L2'::leave_status, 'PENDING_HR'::leave_status, 'PENDING_GM'::leave_status, 'PENDING_DIRECTOR'::leave_status, 'APPROVED'::leave_status)
            RETURNING
                id, user_id, proxy_user_id, leave_type::text as leave_type, start_date, end_date,
                start_time, end_time, total_days, total_hours, reason, supporting_documents,
                annual_leave_source_id, is_urgent, is_retroactive,
                status::text as status, current_approver_id, submitted_at, approved_at,
                rejected_at, cancelled_at, revoked_at, cancellation_reason, revocation_reason,
                created_at, updated_at
            "#,
        )
        .bind(id)
        .bind(reason)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| {
            AppError::BusinessRule(
                "請假狀態不允許取消（可能已經是已取消 / 駁回 / 撤銷）".to_string(),
            )
        })?;

        // 已核准的請假取消時，回復餘額（同一 tx 內，原子化）
        if was_approved {
            Self::restore_leave_balance(&mut tx, &before).await?;
        }

        // 已核准狀態取消要特別標記（可能牽涉薪資/考勤結算）
        let event_type = if was_approved {
            "LEAVE_CANCEL_RETROACTIVE"
        } else {
            "LEAVE_CANCEL"
        };
        let display = format!(
            "{} {}~{}",
            after.leave_type, after.start_date, after.end_date
        );
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "HR",
                event_type,
                entity: Some(AuditEntity::new("leave_request", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        // 通知須以「請假當事人」為主體（主管代取消時 ≠ 取消者）。
        let applicant_name =
            crate::repositories::user::find_user_display_name_by_id(pool, after.user_id)
                .await?
                .unwrap_or_else(|| "申請人".to_string());

        Ok(CancelLeaveOutcome {
            record: after,
            was_approved,
            applicant_name,
        })
    }

    // ============================================
    // Balance deduction / restoration helpers
    // ============================================

    /// 扣除特休假餘額（FIFO：先到期先扣）並記錄 leave_balance_usage
    async fn deduct_annual_leave(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave: &LeaveRequest,
    ) -> Result<()> {
        let mut remaining = leave.total_days;
        let entitlements: Vec<(Uuid, Decimal)> = sqlx::query_as(
            r#"
            SELECT id, (entitled_days - used_days) as available
            FROM annual_leave_entitlements
            WHERE user_id = $1 AND NOT is_expired AND (entitled_days - used_days) > 0
            ORDER BY expires_at ASC
            FOR UPDATE
            "#,
        )
        .bind(leave.user_id)
        .fetch_all(&mut **tx)
        .await?;

        let total_available: Decimal = entitlements.iter().map(|e| e.1).sum();
        if total_available < remaining {
            return Err(AppError::BusinessRule(format!(
                "特休假餘額不足：需要 {} 天，剩餘 {} 天",
                remaining, total_available
            )));
        }

        for (ent_id, available) in entitlements {
            if remaining <= Decimal::ZERO {
                break;
            }
            let deduct = remaining.min(available);
            Self::apply_annual_deduction(tx, leave.id, ent_id, deduct).await?;
            remaining -= deduct;
        }
        Ok(())
    }

    /// 執行單筆特休假扣除（UPDATE + INSERT usage）
    async fn apply_annual_deduction(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave_id: Uuid,
        entitlement_id: Uuid,
        days: Decimal,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE annual_leave_entitlements SET used_days = used_days + $2, updated_at = NOW() WHERE id = $1",
        )
        .bind(entitlement_id)
        .bind(days)
        .execute(&mut **tx)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO leave_balance_usage
                (id, leave_request_id, source_type, annual_leave_entitlement_id, days_used, action)
            VALUES ($1, $2, 'annual', $3, $4, 'deduct')
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(leave_id)
        .bind(entitlement_id)
        .bind(days)
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    /// 扣除補休餘額（FIFO：先到期先扣）並記錄 leave_balance_usage
    async fn deduct_comp_time(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave: &LeaveRequest,
    ) -> Result<()> {
        let hours_dec = leave
            .total_hours
            .unwrap_or_else(|| leave.total_days * Decimal::from(8));

        let balances: Vec<(Uuid, Decimal)> = sqlx::query_as(
            r#"
            SELECT id, (original_hours - used_hours) as available
            FROM comp_time_balances
            WHERE user_id = $1 AND NOT is_expired AND (original_hours - used_hours) > 0
            ORDER BY expires_at ASC
            FOR UPDATE
            "#,
        )
        .bind(leave.user_id)
        .fetch_all(&mut **tx)
        .await?;

        let total_available: Decimal = balances.iter().map(|b| b.1).sum();
        if total_available < hours_dec {
            return Err(AppError::BusinessRule(format!(
                "補休餘額不足：需要 {} 小時，剩餘 {} 小時",
                hours_dec, total_available
            )));
        }

        let mut remaining = hours_dec;
        for (bal_id, available) in balances {
            if remaining <= Decimal::ZERO {
                break;
            }
            let deduct = remaining.min(available);
            Self::apply_comp_deduction(tx, leave.id, bal_id, deduct).await?;
            remaining -= deduct;
        }
        Ok(())
    }

    /// 執行單筆補休扣除（UPDATE + INSERT usage）
    async fn apply_comp_deduction(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave_id: Uuid,
        balance_id: Uuid,
        hours: Decimal,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE comp_time_balances SET used_hours = used_hours + $2, updated_at = NOW() WHERE id = $1",
        )
        .bind(balance_id)
        .bind(hours)
        .execute(&mut **tx)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO leave_balance_usage
                (id, leave_request_id, source_type, comp_time_balance_id, hours_used, action)
            VALUES ($1, $2, 'comp_time', $3, $4, 'deduct')
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(leave_id)
        .bind(balance_id)
        .bind(hours)
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    /// 核准時依假別檢查並扣除餘額（僅 ANNUAL / COMPENSATORY 需要）
    async fn deduct_leave_balance(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave: &LeaveRequest,
    ) -> Result<()> {
        match leave.leave_type.as_str() {
            "ANNUAL" => Self::deduct_annual_leave(tx, leave).await,
            "COMPENSATORY" => Self::deduct_comp_time(tx, leave).await,
            _ => Ok(()), // 其他假別無額度限制
        }
    }

    /// 取消/銷假時依假別回復餘額（僅 ANNUAL / COMPENSATORY 需要）
    async fn restore_leave_balance(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave: &LeaveRequest,
    ) -> Result<()> {
        match leave.leave_type.as_str() {
            "ANNUAL" => Self::restore_annual_leave(tx, leave).await,
            "COMPENSATORY" => Self::restore_comp_time(tx, leave).await,
            _ => Ok(()),
        }
    }

    /// 回復特休假餘額：依 leave_balance_usage 的 deduct 紀錄逐筆還原
    async fn restore_annual_leave(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave: &LeaveRequest,
    ) -> Result<()> {
        let usages: Vec<(Uuid, Uuid, Decimal)> = sqlx::query_as(
            r#"
            SELECT id, annual_leave_entitlement_id, days_used
            FROM leave_balance_usage
            WHERE leave_request_id = $1 AND source_type = 'annual' AND action = 'deduct'
            "#,
        )
        .bind(leave.id)
        .fetch_all(&mut **tx)
        .await?;

        for (usage_id, ent_id, days) in usages {
            sqlx::query(
                "UPDATE annual_leave_entitlements SET used_days = used_days - $2, updated_at = NOW() WHERE id = $1",
            )
            .bind(ent_id)
            .bind(days)
            .execute(&mut **tx)
            .await?;

            sqlx::query(
                r#"
                INSERT INTO leave_balance_usage
                    (id, leave_request_id, source_type, annual_leave_entitlement_id, days_used, action)
                VALUES ($1, $2, 'annual', $3, $4, 'restore')
                "#,
            )
            .bind(Uuid::new_v4())
            .bind(leave.id)
            .bind(ent_id)
            .bind(days)
            .execute(&mut **tx)
            .await?;

            let _ = usage_id; // 僅用於未來稽核需求
        }
        Ok(())
    }

    /// 回復補休餘額：依 leave_balance_usage 的 deduct 紀錄逐筆還原
    async fn restore_comp_time(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        leave: &LeaveRequest,
    ) -> Result<()> {
        let usages: Vec<(Uuid, Uuid, Decimal)> = sqlx::query_as(
            r#"
            SELECT id, comp_time_balance_id, hours_used
            FROM leave_balance_usage
            WHERE leave_request_id = $1 AND source_type = 'comp_time' AND action = 'deduct'
            "#,
        )
        .bind(leave.id)
        .fetch_all(&mut **tx)
        .await?;

        for (usage_id, bal_id, hours) in usages {
            sqlx::query(
                "UPDATE comp_time_balances SET used_hours = used_hours - $2, updated_at = NOW() WHERE id = $1",
            )
            .bind(bal_id)
            .bind(hours)
            .execute(&mut **tx)
            .await?;

            sqlx::query(
                r#"
                INSERT INTO leave_balance_usage
                    (id, leave_request_id, source_type, comp_time_balance_id, hours_used, action)
                VALUES ($1, $2, 'comp_time', $3, $4, 'restore')
                "#,
            )
            .bind(Uuid::new_v4())
            .bind(leave.id)
            .bind(bal_id)
            .bind(hours)
            .execute(&mut **tx)
            .await?;

            let _ = usage_id;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::HrService;

    // --- is_designated_for（兩關指定審核人判定） ---

    #[test]
    fn test_designated_l1_is_dept_manager() {
        // 待部門主管關：只有部門主管是指定審核人
        assert!(HrService::is_designated_for("PENDING_L1", true, false));
        assert!(!HrService::is_designated_for("PENDING_L1", false, true));
        assert!(!HrService::is_designated_for("PENDING_L1", false, false));
    }

    #[test]
    fn test_designated_director_is_director_role() {
        // 待負責人關：只有 DIRECTOR 是指定審核人（單位主管身分不算）
        assert!(HrService::is_designated_for(
            "PENDING_DIRECTOR",
            false,
            true
        ));
        assert!(!HrService::is_designated_for(
            "PENDING_DIRECTOR",
            true,
            false
        ));
        assert!(!HrService::is_designated_for(
            "PENDING_DIRECTOR",
            false,
            false
        ));
    }

    #[test]
    fn test_designated_other_status_false() {
        // 非審核關卡（草稿/已核准/已移除的 GM 關）無指定審核人
        assert!(!HrService::is_designated_for("DRAFT", true, true));
        assert!(!HrService::is_designated_for("PENDING_GM", true, true));
        assert!(!HrService::is_designated_for("APPROVED", true, true));
    }

    // --- is_half_hour_multiple ---

    #[test]
    fn test_is_half_hour_multiple_valid() {
        assert!(HrService::is_half_hour_multiple(0.5));
        assert!(HrService::is_half_hour_multiple(1.0));
        assert!(HrService::is_half_hour_multiple(1.5));
        assert!(HrService::is_half_hour_multiple(8.0));
        assert!(HrService::is_half_hour_multiple(0.5));
    }

    #[test]
    fn test_is_half_hour_multiple_invalid() {
        assert!(!HrService::is_half_hour_multiple(0.0)); // 小於 0.5
        assert!(!HrService::is_half_hour_multiple(0.3));
        assert!(!HrService::is_half_hour_multiple(1.1));
        assert!(!HrService::is_half_hour_multiple(2.3));
    }

    #[test]
    fn test_is_half_hour_multiple_boundary() {
        assert!(!HrService::is_half_hour_multiple(0.4));
        assert!(HrService::is_half_hour_multiple(0.5));
        assert!(!HrService::is_half_hour_multiple(0.6));
    }

    // --- effective_hours ---

    #[test]
    fn test_effective_hours_uses_total_hours_when_provided() {
        assert_eq!(HrService::effective_hours(Some(4.0), 1.0), 4.0);
        assert_eq!(HrService::effective_hours(Some(0.5), 3.0), 0.5);
    }

    #[test]
    fn test_effective_hours_converts_days_when_no_hours() {
        assert_eq!(HrService::effective_hours(None, 1.0), 8.0);
        assert_eq!(HrService::effective_hours(None, 0.5), 4.0);
        assert_eq!(HrService::effective_hours(None, 2.0), 16.0);
    }
}
