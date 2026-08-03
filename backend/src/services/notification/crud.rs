// 通知 CRUD 操作 + 設定

use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{
    error::AppError,
    models::{
        CreateNotificationRequest, Notification, NotificationItem, NotificationQuery,
        NotificationSettings, PaginatedResponse, UpdateNotificationSettingsRequest,
        PRIORITY_NORMAL, PRIORITY_PINNED,
    },
};

use super::NotificationService;

impl NotificationService {
    /// 取得使用者通知列表
    pub async fn list_notifications(
        &self,
        user_id: Uuid,
        query: &NotificationQuery,
        page: i64,
        per_page: i64,
    ) -> Result<PaginatedResponse<NotificationItem>, AppError> {
        // SEC: clamp 防無上限 per_page 拉爆 DB + saturating 防 page 溢位 panic
        let page = page.max(1);
        let per_page = per_page.clamp(1, crate::constants::MAX_PAGE_SIZE);
        let offset = (page - 1).saturating_mul(per_page);

        // 建立基本查詢（使用 QueryBuilder 避免 SQL injection）
        let mut qb = sqlx::QueryBuilder::<sqlx::Postgres>::new(
            r#"
            SELECT id, type::TEXT, title, content, is_read, read_at,
                   related_entity_type, related_entity_id, created_at, priority
            FROM notifications
            WHERE user_id = "#,
        );
        qb.push_bind(user_id);

        let mut count_qb = sqlx::QueryBuilder::<sqlx::Postgres>::new(
            r#"
            SELECT COUNT(*) as count
            FROM notifications
            WHERE user_id = "#,
        );
        count_qb.push_bind(user_id);

        if let Some(is_read) = query.is_read {
            qb.push(" AND is_read = ").push_bind(is_read);
            count_qb.push(" AND is_read = ").push_bind(is_read);
        }

        if let Some(ref notification_type) = &query.notification_type {
            qb.push(" AND type::TEXT = ")
                .push_bind(notification_type.clone());
            count_qb
                .push(" AND type::TEXT = ")
                .push_bind(notification_type.clone());
        }

        // 緊急置頂（priority=1）永遠排在最上方，其餘按時間新到舊。
        qb.push(" ORDER BY priority DESC, created_at DESC LIMIT ")
            .push_bind(per_page);
        qb.push(" OFFSET ").push_bind(offset);

        let notifications: Vec<NotificationItem> = qb.build_query_as().fetch_all(&self.db).await?;

        let total: (i64,) = count_qb.build_query_as().fetch_one(&self.db).await?;

        Ok(PaginatedResponse::new(
            notifications,
            total.0,
            page,
            per_page,
        ))
    }

    /// 取得未讀通知數量
    pub async fn get_unread_count(&self, user_id: Uuid) -> Result<i64, AppError> {
        let result: (i64,) = sqlx::query_as(
            r#"
            SELECT COUNT(*) FROM notifications
            WHERE user_id = $1 AND is_read = false
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.db)
        .await?;

        Ok(result.0)
    }

    /// 標記通知為已讀
    pub async fn mark_as_read(
        &self,
        user_id: Uuid,
        notification_ids: &[Uuid],
    ) -> Result<(), AppError> {
        sqlx::query(
            r#"
            UPDATE notifications
            SET is_read = true, read_at = NOW()
            WHERE user_id = $1 AND id = ANY($2)
            "#,
        )
        .bind(user_id)
        .bind(notification_ids)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// 標記所有通知為已讀
    pub async fn mark_all_as_read(&self, user_id: Uuid) -> Result<(), AppError> {
        sqlx::query(
            r#"
            UPDATE notifications
            SET is_read = true, read_at = NOW()
            WHERE user_id = $1 AND is_read = false
            "#,
        )
        .bind(user_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// 刪除通知
    pub async fn delete_notification(&self, user_id: Uuid, id: Uuid) -> Result<(), AppError> {
        let result = sqlx::query(
            r#"
            DELETE FROM notifications
            WHERE user_id = $1 AND id = $2
            "#,
        )
        .bind(user_id)
        .bind(id)
        .execute(&self.db)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Notification not found".to_string()));
        }

        Ok(())
    }

    /// 建立通知（一般 priority=0）
    pub async fn create_notification(
        &self,
        request: CreateNotificationRequest,
    ) -> Result<Notification, AppError> {
        let mut tx = self.db.begin().await?;
        let notification = Self::create_notification_tx(&mut tx, request).await?;
        tx.commit().await?;
        Ok(notification)
    }

    /// 建立「緊急置頂」通知（priority=1）。
    ///
    /// 用於採購未入庫、巡場待填追蹤等「待辦，完成前需置頂」的提醒；完成對應動作後由
    /// [`Self::resolve_pinned_notifications`] 降級回 0。
    pub async fn create_pinned_notification(
        &self,
        request: CreateNotificationRequest,
    ) -> Result<Notification, AppError> {
        let mut tx = self.db.begin().await?;
        let notification =
            Self::create_notification_tx_with_priority(&mut tx, request, PRIORITY_PINNED).await?;
        tx.commit().await?;
        Ok(notification)
    }

    /// 完成對應待辦後，解除該實體關聯的置頂通知（priority→NORMAL + 標記已讀）。
    ///
    /// 以 `related_entity_type + related_entity_id` 定位（同一業務實體上僅一則置頂待辦），
    /// 不比對標題字串——避免文字微調 / 多語系翻譯導致 `LIKE` 失效而漏解除。
    /// `priority > NORMAL` 保證只動置頂列、不誤降既有一般通知。best-effort，回傳受影響列數。
    pub async fn resolve_pinned_notifications(
        &self,
        related_entity_type: &str,
        related_entity_id: Uuid,
    ) -> Result<u64, AppError> {
        let result = sqlx::query(
            r#"
            UPDATE notifications
            SET priority = $3,
                is_read  = true,
                read_at  = COALESCE(read_at, NOW())
            WHERE related_entity_type = $1
              AND related_entity_id   = $2
              AND priority > $3
            "#,
        )
        .bind(related_entity_type)
        .bind(related_entity_id)
        .bind(PRIORITY_NORMAL)
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected())
    }

    /// R30-3b: tx 內寫站內通知。callers 可把「業務 mutation + audit + notification」
    /// 包進同一個 tx，達成 all-or-nothing。對應 [`OutboxService::enqueue_tx`] 處理
    /// 外部訊息（email / line / webhook）的另一面。
    ///
    /// 詳見 `docs/dev/notification-and-outbox.md`。
    pub async fn create_notification_tx(
        tx: &mut Transaction<'_, Postgres>,
        request: CreateNotificationRequest,
    ) -> Result<Notification, AppError> {
        Self::create_notification_tx_with_priority(tx, request, PRIORITY_NORMAL).await
    }

    /// tx 內寫站內通知，並指定 priority（0=一般 / 1=緊急置頂）。
    /// [`Self::create_notification_tx`] 與 [`Self::create_pinned_notification`] 皆委派於此，
    /// 集中 INSERT 唯一定義。
    pub(super) async fn create_notification_tx_with_priority(
        tx: &mut Transaction<'_, Postgres>,
        request: CreateNotificationRequest,
        priority: i16,
    ) -> Result<Notification, AppError> {
        let notification_type = request.notification_type.as_str();
        let notification: Notification = sqlx::query_as(
            r#"
            INSERT INTO notifications (id, user_id, type, title, content,
                                       related_entity_type, related_entity_id, priority)
            VALUES (gen_random_uuid(), $1, $2::notification_type, $3, $4, $5, $6, $7)
            RETURNING id, user_id, type::TEXT, title, content, is_read, read_at,
                      related_entity_type, related_entity_id, created_at, priority
            "#,
        )
        .bind(request.user_id)
        .bind(notification_type)
        .bind(&request.title)
        .bind(&request.content)
        .bind(&request.related_entity_type)
        .bind(request.related_entity_id)
        .bind(priority)
        .fetch_one(&mut **tx)
        .await?;
        Ok(notification)
    }

    /// 清理過期通知（90 天前的已讀通知）
    pub async fn cleanup_old_notifications(&self) -> Result<i64, AppError> {
        let result = sqlx::query(
            r#"
            DELETE FROM notifications
            WHERE is_read = true 
              AND read_at < NOW() - INTERVAL '90 days'
            "#,
        )
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected() as i64)
    }

    /// 取得通知設定（若無則建立預設列，相容 migration 前建立的使用者）
    pub async fn get_settings(&self, user_id: Uuid) -> Result<NotificationSettings, AppError> {
        let settings: Option<NotificationSettings> = sqlx::query_as(
            r#"
            SELECT * FROM notification_settings WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_optional(&self.db)
        .await?;

        match settings {
            Some(s) => Ok(s),
            None => {
                let created: NotificationSettings = sqlx::query_as(
                    r#"
                    INSERT INTO notification_settings (user_id)
                    VALUES ($1)
                    ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
                    RETURNING *
                    "#,
                )
                .bind(user_id)
                .fetch_one(&self.db)
                .await?;
                Ok(created)
            }
        }
    }

    /// 更新通知設定（若無列則先建立，相容 migration 前建立的使用者）
    pub async fn update_settings(
        &self,
        user_id: Uuid,
        request: UpdateNotificationSettingsRequest,
    ) -> Result<NotificationSettings, AppError> {
        let settings: Option<NotificationSettings> = sqlx::query_as(
            r#"
            UPDATE notification_settings
            SET 
                email_low_stock = COALESCE($2, email_low_stock),
                email_expiry_warning = COALESCE($3, email_expiry_warning),
                email_document_approval = COALESCE($4, email_document_approval),
                email_protocol_status = COALESCE($5, email_protocol_status),
                email_monthly_report = COALESCE($6, email_monthly_report),
                expiry_warning_days = COALESCE($7, expiry_warning_days),
                low_stock_notify_immediately = COALESCE($8, low_stock_notify_immediately),
                updated_at = NOW()
            WHERE user_id = $1
            RETURNING *
            "#,
        )
        .bind(user_id)
        .bind(request.email_low_stock)
        .bind(request.email_expiry_warning)
        .bind(request.email_document_approval)
        .bind(request.email_protocol_status)
        .bind(request.email_monthly_report)
        .bind(request.expiry_warning_days)
        .bind(request.low_stock_notify_immediately)
        .fetch_optional(&self.db)
        .await?;

        match settings {
            Some(s) => Ok(s),
            None => {
                sqlx::query(
                    "INSERT INTO notification_settings (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING",
                )
                .bind(user_id)
                .execute(&self.db)
                .await?;
                // 插入後再執行一次 UPDATE（此時列已存在）
                let created: NotificationSettings = sqlx::query_as(
                    r#"
                    UPDATE notification_settings
                    SET 
                        email_low_stock = COALESCE($2, email_low_stock),
                        email_expiry_warning = COALESCE($3, email_expiry_warning),
                        email_document_approval = COALESCE($4, email_document_approval),
                        email_protocol_status = COALESCE($5, email_protocol_status),
                        email_monthly_report = COALESCE($6, email_monthly_report),
                        expiry_warning_days = COALESCE($7, expiry_warning_days),
                        low_stock_notify_immediately = COALESCE($8, low_stock_notify_immediately),
                        updated_at = NOW()
                    WHERE user_id = $1
                    RETURNING *
                    "#,
                )
                .bind(user_id)
                .bind(request.email_low_stock)
                .bind(request.email_expiry_warning)
                .bind(request.email_document_approval)
                .bind(request.email_protocol_status)
                .bind(request.email_monthly_report)
                .bind(request.expiry_warning_days)
                .bind(request.low_stock_notify_immediately)
                .fetch_one(&self.db)
                .await?;
                Ok(created)
            }
        }
    }
}
