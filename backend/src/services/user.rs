use serde::Serialize;
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    middleware::ActorContext,
    models::{
        audit_diff::{AuditRedact, DataDiff},
        AssignableUser, CreateUserRequest, DepartmentMember, PaginationParams, UpdateUserRequest,
        User, UserResponse,
    },
    services::{
        audit::{ActivityLogEntry, AuditEntity},
        AuditService, AuthService,
    },
    AppError, Result,
};

/// Audit-only 輔助型別：記錄角色指派的 before/after（用於 USER_ROLE_CHANGE 事件）。
/// 角色清單無敏感欄位，空 AuditRedact impl 即可。
#[derive(Serialize)]
struct RoleAssignmentSnapshot {
    roles: Vec<String>,
}
impl AuditRedact for RoleAssignmentSnapshot {}

/// 產生使用者列表搜尋用的 ILIKE pattern（前後加 %、trim），供 list 與單元測試使用。
pub fn user_search_pattern(keyword: &str) -> String {
    format!("%{}%", keyword.trim())
}

#[derive(sqlx::FromRow)]
struct UserRoleRow {
    user_id: Uuid,
    code: String,
}

#[derive(sqlx::FromRow)]
struct UserPermRow {
    user_id: Uuid,
    code: String,
}

pub struct UserService;

impl UserService {
    /// 建立用戶（私域註冊 - 管理員 / 系統自動化初始化）— Service-driven audit
    ///
    /// Actor 政策：User（管理員操作）與 System（seed / 自動化 provisioning）均允許；
    /// Anonymous 拒絕。
    /// SEC-PRIV (CSO-r2 #1): 驗證角色指派授權。
    ///
    /// 1. 角色 ID 必須存在且為 active（防靜默失敗）。
    /// 2. 指派「管理員層級」角色須由具同層級的 actor 執行，防止持有
    ///    `admin.user.create/edit` 的非管理員（如 ADMIN_STAFF）自我提權：
    ///    - 指派 SYSTEM_ADMIN：actor 必須本身為 SYSTEM_ADMIN（維持既有不變式）。
    ///    - 指派 legacy `admin`（= 全權限 admin，見 `middleware::Claims::is_admin`）：
    ///      actor 必須為管理員層級（SYSTEM_ADMIN 或 legacy admin）。
    ///
    /// `actor_user_id == None` 代表 System actor（seed / provisioning），受信任放行。
    async fn validate_role_assignment(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        actor_user_id: Option<Uuid>,
        role_ids: &[Uuid],
    ) -> Result<()> {
        if role_ids.is_empty() {
            return Ok(());
        }

        // 1) 角色存在且 active。以「去重後的 ID 數」比對：role_ids 可能含重複，
        //    而 COUNT(*) 只計到資料表中相異的角色列，直接比 role_ids.len() 會把
        //    帶重複 ID 的合法請求誤判為「部分角色無效」（插入端 ON CONFLICT 已容忍重複）。
        let distinct_role_count = role_ids
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len();
        let valid_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM roles WHERE id = ANY($1) AND is_active = true",
        )
        .bind(role_ids)
        .fetch_one(&mut **tx)
        .await?;
        if valid_count != distinct_role_count as i64 {
            return Err(AppError::Validation("部分角色 ID 無效或已停用".to_string()));
        }

        // 2) 管理員層級提權防護（單次查詢取出指派集合內的管理員層級角色碼）
        let assigned_admin_codes: Vec<String> =
            sqlx::query_scalar("SELECT code FROM roles WHERE id = ANY($1) AND code = ANY($2)")
                .bind(role_ids)
                .bind(
                    &[
                        crate::constants::ROLE_SYSTEM_ADMIN,
                        crate::constants::ROLE_ADMIN_LEGACY,
                    ][..],
                )
                .fetch_all(&mut **tx)
                .await?;
        let assigns_system_admin = assigned_admin_codes
            .iter()
            .any(|c| c == crate::constants::ROLE_SYSTEM_ADMIN);
        let assigns_legacy_admin = assigned_admin_codes
            .iter()
            .any(|c| c == crate::constants::ROLE_ADMIN_LEGACY);

        // System actor（None）受信任，跳過 actor 角色檢查。
        if let Some(uid) = actor_user_id {
            if assigns_system_admin || assigns_legacy_admin {
                let actor_admin_codes: Vec<String> = sqlx::query_scalar(
                    r#"SELECT r.code FROM user_roles ur
                       INNER JOIN roles r ON ur.role_id = r.id
                       WHERE ur.user_id = $1 AND r.code = ANY($2)"#,
                )
                .bind(uid)
                .bind(
                    &[
                        crate::constants::ROLE_SYSTEM_ADMIN,
                        crate::constants::ROLE_ADMIN_LEGACY,
                    ][..],
                )
                .fetch_all(&mut **tx)
                .await?;
                let actor_is_system_admin = actor_admin_codes
                    .iter()
                    .any(|c| c == crate::constants::ROLE_SYSTEM_ADMIN);
                let actor_is_admin_tier = !actor_admin_codes.is_empty();

                if assigns_system_admin && !actor_is_system_admin {
                    return Err(AppError::Forbidden(
                        "僅 SYSTEM_ADMIN 可指派 SYSTEM_ADMIN 角色".to_string(),
                    ));
                }
                if assigns_legacy_admin && !actor_is_admin_tier {
                    return Err(AppError::Forbidden(
                        "僅管理員可指派 admin（系統管理員）角色".to_string(),
                    ));
                }
            }
        }
        Ok(())
    }

    pub async fn create(
        pool: &PgPool,
        actor: &ActorContext,
        req: &CreateUserRequest,
    ) -> Result<User> {
        match actor {
            ActorContext::User(_) | ActorContext::System { .. } => {}
            ActorContext::Anonymous => {
                return Err(AppError::Forbidden(
                    "建立使用者須由已登入管理員或系統觸發".into(),
                ));
            }
        }
        let mut tx = pool.begin().await?;

        // 檢查 email 是否已存在
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)")
                .bind(&req.email)
                .fetch_one(&mut *tx)
                .await?;

        if exists {
            return Err(AppError::Conflict("Email already exists".to_string()));
        }

        // Hash 密碼
        let password_hash = AuthService::hash_password(&req.password)?;

        // 建立用戶 - 新用戶預設需要變更密碼
        let user = sqlx::query_as::<_, User>(
            r#"
            INSERT INTO users (
                id, email, password_hash, display_name, phone, phone_ext, organization,
                entry_date, position, aup_roles, years_experience, trainings,
                is_internal, is_active, must_change_password, expires_at, created_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, true, true, $14, NOW(), NOW())
            RETURNING *
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(&req.email)
        .bind(&password_hash)
        .bind(&req.display_name)
        .bind(&req.phone)
        .bind(&req.phone_ext)
        .bind(&req.organization)
        .bind(req.entry_date)
        .bind(&req.position)
        .bind(&req.aup_roles)
        .bind(req.years_experience)
        .bind(sqlx::types::Json(&req.trainings))
        .bind(req.is_internal)
        .bind(req.expires_at)
        .fetch_one(&mut *tx)
        .await?;

        if !req.role_ids.is_empty() {
            // SEC-PRIV (CSO-r2 #1): 建立使用者時亦需角色指派授權檢查（create 路徑原本零防護）。
            let actor_user_id = match actor {
                ActorContext::User(u) => Some(u.id),
                _ => None,
            };
            Self::validate_role_assignment(&mut tx, actor_user_id, &req.role_ids).await?;
            sqlx::query(
                "INSERT INTO user_roles (user_id, role_id) SELECT $1, unnest($2::uuid[]) ON CONFLICT DO NOTHING"
            )
            .bind(user.id)
            .bind(&req.role_ids)
            .execute(&mut *tx)
            .await?;
        }

        let display = format!("{} <{}>", user.display_name, user.email);
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "ADMIN",
                event_type: "USER_CREATE",
                entity: Some(AuditEntity::new("user", user.id, &display)),
                data_diff: Some(DataDiff::create_only(&user)),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(user)
    }

    /// 取得用戶列表
    ///
    /// `include_inactive=false`（預設）只回在職帳號；`true` 一併回傳**停用但未刪除**的
    /// 帳號，供管理頁「顯示停用帳號」開關使用（停用者仍帶 `is_active=false`，前端據此
    /// 標記）。已軟刪除（匿名化，email 為 `…@deleted.local`）的帳號**永不回傳**，即使
    /// `include_inactive=true`——刪除者不應出現在「顯示停用」清單。停用與軟刪除皆為
    /// `is_active=false`，靠 email 網域後綴區分（見 `delete`）。
    pub async fn list(
        pool: &PgPool,
        keyword: Option<&str>,
        include_inactive: bool,
        pagination: &PaginationParams,
    ) -> Result<Vec<UserResponse>> {
        let suffix = pagination.sql_suffix();
        // is_active 過濾為布林開關（非使用者輸入），依 include_inactive 決定是否放行停用者
        let active_filter = if include_inactive {
            ""
        } else {
            "is_active = true AND "
        };
        // 已軟刪除（匿名化）帳號永不列出，即使開啟「顯示停用帳號」。以 email 網域後綴
        // 辨識（見 delete 的匿名化改寫）；停用但未刪除的帳號仍正常回傳。
        let deleted_pattern = format!("%{}", crate::constants::DELETED_USER_EMAIL_DOMAIN);
        let users = if let Some(kw) = keyword {
            let pattern = user_search_pattern(kw);
            let sql = [
                "SELECT * FROM users WHERE ",
                active_filter,
                "email NOT LIKE $2 AND (email ILIKE $1 OR display_name ILIKE $1) \
                 ORDER BY created_at DESC",
                suffix.as_str(),
            ]
            .concat();
            sqlx::query_as::<_, User>(sqlx::AssertSqlSafe(sql))
                .bind(&pattern)
                .bind(&deleted_pattern)
                .fetch_all(pool)
                .await?
        } else {
            let sql = [
                "SELECT * FROM users WHERE ",
                active_filter,
                "email NOT LIKE $1 ORDER BY created_at DESC",
                suffix.as_str(),
            ]
            .concat();
            sqlx::query_as::<_, User>(sqlx::AssertSqlSafe(sql))
                .bind(&deleted_pattern)
                .fetch_all(pool)
                .await?
        };

        let user_ids: Vec<Uuid> = users.iter().map(|u| u.id).collect();

        let (roles_map, perms_map) = if user_ids.is_empty() {
            (HashMap::new(), HashMap::new())
        } else {
            let role_rows = sqlx::query_as::<_, UserRoleRow>(
                r#"SELECT ur.user_id, r.code
                   FROM user_roles ur
                   INNER JOIN roles r ON ur.role_id = r.id
                   WHERE ur.user_id = ANY($1)
                   ORDER BY r.code"#,
            )
            .bind(&user_ids)
            .fetch_all(pool)
            .await?;

            let perm_rows = sqlx::query_as::<_, UserPermRow>(
                r#"SELECT DISTINCT ur.user_id, p.code
                   FROM user_roles ur
                   INNER JOIN role_permissions rp ON ur.role_id = rp.role_id
                   INNER JOIN permissions p ON rp.permission_id = p.id
                   WHERE ur.user_id = ANY($1)
                   ORDER BY p.code"#,
            )
            .bind(&user_ids)
            .fetch_all(pool)
            .await?;

            let mut rm: HashMap<Uuid, Vec<String>> = HashMap::new();
            for row in role_rows {
                rm.entry(row.user_id).or_default().push(row.code);
            }
            let mut pm: HashMap<Uuid, Vec<String>> = HashMap::new();
            for row in perm_rows {
                pm.entry(row.user_id).or_default().push(row.code);
            }
            (rm, pm)
        };

        let result = users
            .iter()
            .map(|user| {
                let roles = roles_map.get(&user.id).cloned().unwrap_or_default();
                let permissions = perms_map.get(&user.id).cloned().unwrap_or_default();
                UserResponse::from_user(user, roles, permissions)
            })
            .collect();

        Ok(result)
    }

    /// 列出所有在職使用者的精簡資料（id / display_name / email / roles），供計畫
    /// PI / Study Director 下拉指派使用。不回傳權限清單等敏感欄位，授權門檻較
    /// `list`（admin.user.view）低，由 handler 以計畫匯入權限把關。
    pub async fn list_assignable_users(pool: &PgPool) -> Result<Vec<AssignableUser>> {
        let users = sqlx::query_as::<_, AssignableUser>(
            r#"SELECT u.id, u.display_name, u.email,
                      COALESCE(ARRAY_AGG(r.code) FILTER (WHERE r.code IS NOT NULL), '{}') AS roles
               FROM users u
               LEFT JOIN user_roles ur ON ur.user_id = u.id
               LEFT JOIN roles r ON ur.role_id = r.id
               WHERE u.is_active = true
               GROUP BY u.id, u.display_name, u.email
               ORDER BY u.display_name"#,
        )
        .fetch_all(pool)
        .await?;
        Ok(users)
    }

    /// 取得原始 User（供內部邏輯使用，如 2FA）
    pub async fn get_user_raw(pool: &PgPool, id: Uuid) -> Result<User> {
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
            .bind(id)
            .fetch_optional(pool)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))
    }

    /// 取得單一用戶
    pub async fn get_by_id(pool: &PgPool, id: Uuid) -> Result<UserResponse> {
        let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
            .bind(id)
            .fetch_optional(pool)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        let (roles, permissions) = AuthService::get_user_roles_permissions(pool, user.id).await?;

        Ok(UserResponse::from_user(&user, roles, permissions))
    }

    /// 更新用戶 — Service-driven audit
    ///
    /// 完整流程在同一 tx 內：欄位更新 + 角色重指派 + audit（包括 SECURITY 類
    /// ROLE_CHANGE / ACCOUNT_STATUS_CHANGE 事件）。
    pub async fn update(
        pool: &PgPool,
        actor: &ActorContext,
        id: Uuid,
        req: &UpdateUserRequest,
    ) -> Result<UserResponse> {
        // Actor 政策：User 或 System 均可；Anonymous 拒絕。
        // actor_user_id = Some(uid) 表示是真實 User（需角色檢查）；None 表示 System（受信任，略過）。
        let actor_user_id: Option<Uuid> = match actor {
            ActorContext::User(user) => Some(user.id),
            ActorContext::System { .. } => None,
            ActorContext::Anonymous => {
                return Err(AppError::Forbidden(
                    "更新使用者須由已登入管理員或系統觸發".into(),
                ));
            }
        };
        let mut tx = pool.begin().await?;

        // SELECT FOR UPDATE 取 before（同時檢查使用者存在）
        let before_user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        // 如果要更新 email，檢查是否已被使用
        if let Some(ref new_email) = req.email {
            let exists: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND id != $2)",
            )
            .bind(new_email)
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;

            if exists {
                return Err(AppError::Conflict("Email already exists".to_string()));
            }
        }

        // 更新用戶
        let trainings_json = req.trainings.as_ref().map(sqlx::types::Json);
        let updated_user = sqlx::query_as::<_, User>(
            r#"
            UPDATE users SET
                email = COALESCE($1, email),
                display_name = COALESCE($2, display_name),
                phone = COALESCE($3, phone),
                phone_ext = COALESCE($4, phone_ext),
                organization = COALESCE($5, organization),
                entry_date = COALESCE($6, entry_date),
                position = COALESCE($7, position),
                aup_roles = COALESCE($8, aup_roles),
                years_experience = COALESCE($9, years_experience),
                trainings = COALESCE($10, trainings),
                is_internal = COALESCE($11, is_internal),
                is_active = COALESCE($12, is_active),
                expires_at = COALESCE($13, expires_at),
                version = version + 1,
                updated_at = NOW()
            WHERE id = $14
              AND ($15::INT IS NULL OR version = $15)
            RETURNING *
            "#,
        )
        .bind(&req.email)
        .bind(&req.display_name)
        .bind(&req.phone)
        .bind(&req.phone_ext)
        .bind(&req.organization)
        .bind(req.entry_date)
        .bind(&req.position)
        .bind(&req.aup_roles)
        .bind(req.years_experience)
        .bind(trainings_json)
        .bind(req.is_internal)
        .bind(req.is_active)
        .bind(req.expires_at)
        .bind(id)
        .bind(req.version)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::Conflict("使用者資料已被其他人修改，請重新載入後再試".into()))?;

        // 基本 USER_UPDATE 事件（before/after diff 自動 redact password_hash 等）
        let display = format!("{} <{}>", updated_user.display_name, updated_user.email);
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "ADMIN",
                event_type: "USER_UPDATE",
                entity: Some(AuditEntity::new("user", updated_user.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before_user), Some(&updated_user))),
                request_context: None,
            },
        )
        .await?;

        // SECURITY：帳號狀態變更另寫一筆（供監控系統快速篩選）
        if before_user.is_active != updated_user.is_active {
            AuditService::log_activity_tx(
                &mut tx,
                actor,
                ActivityLogEntry {
                    event_category: "SECURITY",
                    event_type: "USER_STATUS_CHANGE",
                    entity: Some(AuditEntity::new("user", updated_user.id, &display)),
                    data_diff: Some(DataDiff::compute(Some(&before_user), Some(&updated_user))),
                    request_context: None,
                },
            )
            .await?;
        }

        // 如果要更新角色
        if let Some(ref role_ids) = req.role_ids {
            // before 角色清單只在實際要變更角色時才查（避免一般欄位更新的冗餘 DB round-trip）
            let before_roles: Vec<String> = sqlx::query_scalar(
                r#"SELECT r.code FROM user_roles ur
                   INNER JOIN roles r ON ur.role_id = r.id
                   WHERE ur.user_id = $1
                   ORDER BY r.code"#,
            )
            .bind(id)
            .fetch_all(&mut *tx)
            .await?;

            // SEC-PRIV (CSO-r2 #1): 角色指派授權檢查（存在性 + 管理員層級提權防護，
            // 同時涵蓋 SYSTEM_ADMIN 與 legacy `admin`）。
            Self::validate_role_assignment(&mut tx, actor_user_id, role_ids).await?;

            // 刪除現有角色
            sqlx::query("DELETE FROM user_roles WHERE user_id = $1")
                .bind(id)
                .execute(&mut *tx)
                .await?;

            if !role_ids.is_empty() {
                sqlx::query(
                    "INSERT INTO user_roles (user_id, role_id) SELECT $1, unnest($2::uuid[]) ON CONFLICT DO NOTHING"
                )
                .bind(id)
                .bind(role_ids)
                .execute(&mut *tx)
                .await?;
            }

            // 取 after 角色清單，若有變動則寫 SECURITY 類 ROLE_CHANGE 事件
            let after_roles: Vec<String> = sqlx::query_scalar(
                r#"SELECT r.code FROM user_roles ur
                   INNER JOIN roles r ON ur.role_id = r.id
                   WHERE ur.user_id = $1
                   ORDER BY r.code"#,
            )
            .bind(id)
            .fetch_all(&mut *tx)
            .await?;

            if before_roles != after_roles {
                // CSO-r3 #4：角色實際變動 → 撤銷該使用者所有未過期 access token，
                // 使 JWT 內過時的 roles 快照即時失效（須重新登入取得新角色）。
                sqlx::query("UPDATE users SET tokens_valid_after = NOW() WHERE id = $1")
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;

                let before_snap = RoleAssignmentSnapshot {
                    roles: before_roles,
                };
                let after_snap = RoleAssignmentSnapshot { roles: after_roles };
                AuditService::log_activity_tx(
                    &mut tx,
                    actor,
                    ActivityLogEntry {
                        event_category: "SECURITY",
                        event_type: "USER_ROLE_CHANGE",
                        entity: Some(AuditEntity::new("user", updated_user.id, &display)),
                        data_diff: Some(DataDiff::compute(Some(&before_snap), Some(&after_snap))),
                        request_context: None,
                    },
                )
                .await?;
            }
        }

        tx.commit().await?;

        let (roles, permissions) =
            AuthService::get_user_roles_permissions(pool, updated_user.id).await?;

        Ok(UserResponse::from_user(&updated_user, roles, permissions))
    }

    /// GDPR：自帳號停用（軟刪除，is_active=false）— Service-driven audit
    pub async fn deactivate_self(pool: &PgPool, actor: &ActorContext, id: Uuid) -> Result<()> {
        let user = actor.require_user()?;
        // 守門：此 API 僅允許使用者停用自己的帳號，actor.id 必須 == id
        if user.id != id {
            return Err(AppError::Forbidden(
                "deactivate_self 僅允許停用自己的帳號".into(),
            ));
        }
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        // L-3（安全稽核 2026-07-04）：一併設 tokens_valid_after=NOW()，撤銷該使用者
        // 所有裝置未過期的 access token——auth middleware 的 enforce_tokens_valid_after
        // 在載入權限前先擋，故其他裝置立即 401（原本會殘留至 access token TTL）。
        let after = sqlx::query_as::<_, User>(
            "UPDATE users SET is_active = false, tokens_valid_after = NOW(), updated_at = NOW() WHERE id = $1 RETURNING *",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;

        let display = format!("{} <{}>", after.display_name, after.email);
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "SECURITY",
                event_type: "USER_DEACTIVATE_SELF",
                entity: Some(AuditEntity::new("user", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(())
    }

    /// 刪除用戶（改為 soft delete + 停用，避免 CASCADE 級聯刪除 16+ 關聯表）
    /// H3: 原為硬刪除，會導致 HR、認證、計畫書等所有關聯資料被靜默刪除
    /// Service-driven audit
    ///
    /// Actor 政策：User（管理員）與 System（過期帳號自動清理）均允許；Anonymous 拒絕。
    pub async fn delete(pool: &PgPool, actor: &ActorContext, id: Uuid) -> Result<()> {
        match actor {
            ActorContext::User(_) | ActorContext::System { .. } => {}
            ActorContext::Anonymous => {
                return Err(AppError::Forbidden(
                    "刪除使用者須由已登入管理員或系統觸發".into(),
                ));
            }
        }
        let mut tx = pool.begin().await?;

        // SELECT FOR UPDATE 取 before（含原 email，soft-delete 後 email 會被匿名化）
        let before = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        // 撤銷所有 refresh tokens（登出）
        sqlx::query("DELETE FROM refresh_tokens WHERE user_id = $1")
            .bind(id)
            .execute(&mut *tx)
            .await?;

        // Soft delete: 停用 + 匿名化 email/phone/phone_ext/organization/position，但
        // **保留 display_name**（R63-B6 收窄，2026-07-04）——「誰記錄的」屬 GLP 歸屬資料，
        // 須隨歷史紀錄保留（見 AUDIT_LOGGING.md / PROGRESS §9）。已刪除帳號靠 email 網域
        // 後綴 $2 = DELETED_USER_EMAIL_DOMAIN 排除於清單/選單（與 list 共用常數），不靠名字。
        let after = sqlx::query_as::<_, User>(
            r#"UPDATE users SET
                is_active = false,
                email = 'deleted_' || id::text || $2,
                phone = NULL,
                phone_ext = NULL,
                organization = NULL,
                position = NULL,
                updated_at = NOW()
            WHERE id = $1
            RETURNING *"#,
        )
        .bind(id)
        .bind(crate::constants::DELETED_USER_EMAIL_DOMAIN)
        .fetch_one(&mut *tx)
        .await?;

        // 使用 before 的原 email 供稽核查詢「誰被刪了」
        let display = format!("{} <{}>", before.display_name, before.email);
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "SECURITY",
                event_type: "USER_DELETE",
                entity: Some(AuditEntity::new("user", before.id, &display)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
        )
        .await?;

        tx.commit().await?;

        Ok(())
    }

    // ============================================
    // 部門成員指派（users.department_id）— 啟用請假 L1 單位主管關
    // ============================================

    /// 列出部門成員（在職）。`dept_id = Some` 篩單一部門；`None` 回所有已指派部門的
    /// 在職使用者（供組織圖一次載入，避免逐部門 N+1）。
    pub async fn list_department_members(
        pool: &PgPool,
        dept_id: Option<Uuid>,
    ) -> Result<Vec<DepartmentMember>> {
        let members = sqlx::query_as::<_, DepartmentMember>(
            r#"SELECT id, display_name, email, department_id
               FROM users
               WHERE is_active = true
                 AND department_id IS NOT NULL
                 AND ($1::uuid IS NULL OR department_id = $1)
               ORDER BY display_name"#,
        )
        .bind(dept_id)
        .fetch_all(pool)
        .await?;
        Ok(members)
    }

    /// 共用：於既有 tx 內寫入 department_id 變更 + USER_DEPARTMENT_CHANGE audit。
    /// `before` 須為已 SELECT FOR UPDATE 取得的當前列，供 DataDiff 與 HMAC chain 使用。
    async fn write_department_change_tx(
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        actor: &ActorContext,
        before: &User,
        dept_id: Option<Uuid>,
    ) -> Result<User> {
        let after = sqlx::query_as::<_, User>(
            "UPDATE users SET department_id = $1, updated_at = NOW() WHERE id = $2 RETURNING *",
        )
        .bind(dept_id)
        .bind(before.id)
        .fetch_one(&mut **tx)
        .await?;

        let display = format!("{} <{}>", after.display_name, after.email);
        AuditService::log_activity_tx(
            tx,
            actor,
            ActivityLogEntry {
                event_category: "ADMIN",
                event_type: "USER_DEPARTMENT_CHANGE",
                entity: Some(AuditEntity::new("user", after.id, &display)),
                data_diff: Some(DataDiff::compute(Some(before), Some(&after))),
                request_context: None,
            },
        )
        .await?;
        Ok(after)
    }

    /// 指派使用者所屬部門（設定 users.department_id）— Service-driven audit。
    /// Actor 政策：User（管理員）/ System 允許；Anonymous 拒絕。
    pub async fn assign_user_department(
        pool: &PgPool,
        actor: &ActorContext,
        user_id: Uuid,
        dept_id: Uuid,
    ) -> Result<User> {
        match actor {
            ActorContext::User(_) | ActorContext::System { .. } => {}
            ActorContext::Anonymous => {
                return Err(AppError::Forbidden(
                    "指派部門須由已登入管理員或系統觸發".into(),
                ));
            }
        }
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 FOR UPDATE")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        // 已在目標部門則無需更新（免冗餘 UPDATE 與 no-op audit 記錄）。
        if before.department_id == Some(dept_id) {
            return Ok(before);
        }

        // 指派目標部門須存在且在職。FOR SHARE 鎖住該部門列直到 commit，避免與
        // 「同時停用該部門」的交易產生 TOCTOU（否則檢查通過後、UPDATE 前部門可能被停用）。
        let dept_active: Option<bool> =
            sqlx::query_scalar("SELECT is_active FROM departments WHERE id = $1 FOR SHARE")
                .bind(dept_id)
                .fetch_optional(&mut *tx)
                .await?;
        if dept_active != Some(true) {
            return Err(AppError::Validation("部門不存在或已停用".to_string()));
        }

        let after =
            Self::write_department_change_tx(&mut tx, actor, &before, Some(dept_id)).await?;
        tx.commit().await?;
        Ok(after)
    }

    /// 將使用者移出指定部門（清為 NULL）— Service-driven audit。
    /// 安全守則：僅當該使用者「目前確實屬於此部門」才清除，避免誤清已改調他部門者。
    /// 參數順序與 `assign_user_department` 一致（user_id, dept_id），避免呼叫端誤植。
    pub async fn remove_user_department(
        pool: &PgPool,
        actor: &ActorContext,
        user_id: Uuid,
        dept_id: Uuid,
    ) -> Result<User> {
        match actor {
            ActorContext::User(_) | ActorContext::System { .. } => {}
            ActorContext::Anonymous => {
                return Err(AppError::Forbidden(
                    "移除部門成員須由已登入管理員或系統觸發".into(),
                ));
            }
        }
        let mut tx = pool.begin().await?;

        let before = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 FOR UPDATE")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        if before.department_id != Some(dept_id) {
            return Err(AppError::Validation(
                "此使用者不屬於指定部門，無法移除".to_string(),
            ));
        }

        let after = Self::write_department_change_tx(&mut tx, actor, &before, None).await?;
        tx.commit().await?;
        Ok(after)
    }
}

#[cfg(test)]
mod tests {
    use super::user_search_pattern;

    #[test]
    fn test_user_search_pattern_empty() {
        assert_eq!(user_search_pattern(""), "%%");
        assert_eq!(user_search_pattern("   "), "%%");
    }

    #[test]
    fn test_user_search_pattern_trim() {
        assert_eq!(user_search_pattern("  abc  "), "%abc%");
    }

    #[test]
    fn test_user_search_pattern_normal() {
        assert_eq!(user_search_pattern("john"), "%john%");
        assert_eq!(
            user_search_pattern("test@example.com"),
            "%test@example.com%"
        );
    }
}
