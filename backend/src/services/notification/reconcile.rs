// 置頂待辦對帳（安全網）
//
// 「待處理」清單的正確性完全取決於各業務流程有沒有在終態呼叫
// [`NotificationService::resolve_pinned_notifications`]。而終態路徑是手寫的——
// 每新增一條（撤回 / 作廢 / 刪除 / 轉單…）就多一次漏接機會，漏接的後果是
// 使用者的待辦永久卡死且**無法自行清除**（待辦依設計不可手動已讀）。
//
// 2026-08-07 事故即為此：巡場報告的 retract / soft delete 兩條路徑沒接，
// 兩則置頂通知綁在已軟刪的報告上卡了一個月。詳見
// `docs/design/features/notification-vs-action-required-2026-08-07.md`。
//
// 本模組是那層安全網：把「置頂中、但關聯實體已不存在或已在終態」的通知降級。
// 它**不改變**「使用者不可手動略過待辦」這個規則——降級的判斷來自業務實體的真實狀態，
// 不是使用者的意願。
//
// 同一份邏輯有兩個呼叫端：
// - 一次性修補：`cargo run --bin reconcile_pinned_notifications`
// - 定期對帳：scheduler（見 `services/scheduler.rs`）

use sqlx::PgPool;
use uuid::Uuid;

use crate::{error::AppError, models::PRIORITY_NORMAL};

use super::NotificationService;

/// 一筆待降級的置頂通知（供 dry-run 列印與 log）。
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OrphanPinnedRow {
    pub id: Uuid,
    pub title: String,
    pub related_entity_type: String,
    pub related_entity_id: Option<Uuid>,
    pub recipient_email: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    /// 人類可讀的降級理由（實體已刪 / 已在終態 / 實體不存在）。
    pub reason: String,
}

/// 對帳結果。
#[derive(Debug, Default)]
pub struct ReconcileReport {
    /// 已降級（dry-run 時為「將被降級」）的列。
    pub resolved: Vec<OrphanPinnedRow>,
    /// 置頂中且經判定仍為合法待辦的筆數。
    pub still_pending: i64,
    /// 本模組不認得其 entity_type、因此未做判斷的筆數（保守不動）。
    pub unknown_entity_types: Vec<(String, i64)>,
}

impl NotificationService {
    /// 對帳所有置頂待辦，降級「關聯實體已不存在或已在終態」者。
    ///
    /// `dry_run = true` 時只查不寫，供上 prod 前核對筆數。
    ///
    /// **保守原則**：只降級能明確證明「不再需要使用者動作」的列。
    /// 認不得的 `related_entity_type` 一律不動，只在報告中列出——
    /// 寧可留下一筆多餘待辦，也不要誤清掉真正待處理的事項。
    pub async fn reconcile_pinned_notifications(
        &self,
        dry_run: bool,
    ) -> Result<ReconcileReport, AppError> {
        let candidates = Self::find_orphan_pinned(&self.db).await?;

        let report = ReconcileReport {
            still_pending: Self::count_pinned(&self.db).await? - candidates.len() as i64,
            unknown_entity_types: Self::count_unknown_entity_types(&self.db).await?,
            resolved: candidates,
        };

        if !dry_run && !report.resolved.is_empty() {
            let ids: Vec<Uuid> = report.resolved.iter().map(|r| r.id).collect();
            sqlx::query(
                r#"
                UPDATE notifications
                SET priority = $2,
                    is_read  = true,
                    read_at  = COALESCE(read_at, NOW())
                WHERE id = ANY($1)
                  AND priority > $2
                "#,
            )
            .bind(&ids)
            .bind(PRIORITY_NORMAL)
            .execute(&self.db)
            .await?;

            for row in &report.resolved {
                tracing::info!(
                    notification_id = %row.id,
                    entity_type = %row.related_entity_type,
                    reason = %row.reason,
                    "置頂待辦對帳：已降級孤兒待辦"
                );
            }
        }

        Ok(report)
    }

    async fn count_pinned(pool: &PgPool) -> Result<i64, AppError> {
        Ok(
            sqlx::query_scalar("SELECT count(*) FROM notifications WHERE priority > 0")
                .fetch_one(pool)
                .await?,
        )
    }

    /// 列出本模組認不得的 entity_type（保守不動，但要讓維運者看見）。
    async fn count_unknown_entity_types(pool: &PgPool) -> Result<Vec<(String, i64)>, AppError> {
        Ok(sqlx::query_as(
            r#"
            SELECT COALESCE(related_entity_type, '(null)'), count(*)
            FROM notifications
            WHERE priority > 0
              AND (related_entity_type IS NULL
                   OR related_entity_type NOT IN ('vet_patrol_reports', 'document'))
            GROUP BY 1
            ORDER BY 2 DESC
            "#,
        )
        .fetch_all(pool)
        .await?)
    }

    /// 找出所有「置頂中但已不需要使用者動作」的通知。
    ///
    /// 每個 entity_type 的終態判定各自定義，集中在此一處，新增待辦類型時同步補一段。
    async fn find_orphan_pinned(pool: &PgPool) -> Result<Vec<OrphanPinnedRow>, AppError> {
        Ok(sqlx::query_as::<_, OrphanPinnedRow>(
            r#"
            -- 巡場報告：報告已軟刪 / 已完成 / row 根本不存在 → 追蹤者已無事可做
            SELECT n.id, n.title, n.related_entity_type, n.related_entity_id,
                   u.email AS recipient_email, n.created_at,
                   CASE
                     WHEN r.id IS NULL              THEN '關聯的巡場報告已不存在'
                     WHEN r.deleted_at IS NOT NULL  THEN '關聯的巡場報告已刪除'
                     ELSE                                '關聯的巡場報告已完成'
                   END AS reason
            FROM notifications n
            JOIN users u ON u.id = n.user_id
            LEFT JOIN vet_patrol_reports r ON r.id = n.related_entity_id
            WHERE n.priority > 0
              AND n.related_entity_type = 'vet_patrol_reports'
              AND (r.id IS NULL OR r.deleted_at IS NOT NULL OR r.status = 'completed')

            UNION ALL

            -- 單據：row 已不存在（硬刪）→ 無從入庫/簽核，待辦不可能再完成
            SELECT n.id, n.title, n.related_entity_type, n.related_entity_id,
                   u.email AS recipient_email, n.created_at,
                   '關聯的單據已不存在' AS reason
            FROM notifications n
            JOIN users u ON u.id = n.user_id
            WHERE n.priority > 0
              AND n.related_entity_type = 'document'
              AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.id = n.related_entity_id)

            ORDER BY created_at
            "#,
        )
        .fetch_all(pool)
        .await?)
    }
}
