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
    /// 收件人的 **user_id**，刻意不帶 email。
    ///
    /// 本結構會被排程的 `warn!` 寫進營運日誌（Loki 留存久、存取範圍比 DB 廣），
    /// email 屬直接識別個人的資料，不應為了維運方便而長期落在日誌裡。
    /// 真的需要對應到人時，維運者用這個 id 查 `users` 表即可 —— 那是有存取控管的路徑。
    pub user_id: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
    /// 人類可讀的降級理由（實體已刪 / 已在終態 / 實體不存在）。
    pub reason: String,
}

/// 對帳結果。
#[derive(Debug, Default)]
pub struct ReconcileReport {
    /// 已降級（dry-run 時為「將被降級」）的列。
    pub resolved: Vec<OrphanPinnedRow>,
    /// 置頂中、**已判定為仍需使用者動作**的筆數。
    ///
    /// 已扣掉 [`Self::resolved`] 與 [`Self::unknown_entity_types`] ——
    /// 後者是「未做判斷」而非「判定為合法」，混進來會讓這個數字被高估，
    /// 使維運者誤以為所有剩餘置頂列都已驗證過。
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
        let unknown = Self::count_unknown_entity_types(&self.db).await?;
        let unknown_total: i64 = unknown.iter().map(|(_, n)| *n).sum();

        let report = ReconcileReport {
            // 未知 entity_type 的列也計在 count_pinned 內，但它們是「未做判斷」，
            // 不能算進「已判定仍需動作」。兩者互斥（unknown 的定義就是不在候選類型內），
            // 直接相減即可。
            still_pending: Self::count_pinned(&self.db).await?
                - candidates.len() as i64
                - unknown_total,
            unknown_entity_types: unknown,
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
            -- 巡場報告：報告已軟刪 / 已完成 / 已撤回 / row 根本不存在 → 追蹤者已無事可做。
            --
            -- 「已撤回」＝ status='draft' 且 follow_up_user_id IS NULL：置頂待辦只在
            -- submit_for_followup 建立（該處必定同時設 status='awaiting_acknowledgement'
            -- 與 follow_up_user_id），所以這個組合唯一的來源就是撤回。必須納入 ——
            -- 撤回正是 2026-08-07 事故的觸發路徑，若該處的解除將來回歸，
            -- 這道安全網要接得住。
            SELECT n.id, n.title, n.related_entity_type, n.related_entity_id,
                   n.user_id, n.created_at,
                   CASE
                     WHEN r.id IS NULL              THEN '關聯的巡場報告已不存在'
                     WHEN r.deleted_at IS NOT NULL  THEN '關聯的巡場報告已刪除'
                     WHEN r.status = 'completed'    THEN '關聯的巡場報告已完成'
                     ELSE                                '關聯的巡場報告已撤回（無指派追蹤者）'
                   END AS reason
            FROM notifications n
            LEFT JOIN vet_patrol_reports r ON r.id = n.related_entity_id
            WHERE n.priority > 0
              AND n.related_entity_type = 'vet_patrol_reports'
              AND (r.id IS NULL
                   OR r.deleted_at IS NOT NULL
                   OR r.status = 'completed'
                   OR (r.status = 'draft' AND r.follow_up_user_id IS NULL))

            UNION ALL

            -- 單據：row 已不存在（硬刪）→ 無從入庫/簽核，待辦不可能再完成
            SELECT n.id, n.title, n.related_entity_type, n.related_entity_id,
                   n.user_id, n.created_at,
                   '關聯的單據已不存在' AS reason
            FROM notifications n
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
