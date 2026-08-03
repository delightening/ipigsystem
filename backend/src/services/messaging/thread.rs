use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

use crate::{
    middleware::ActorContext,
    services::{
        audit::{ActivityLogEntry, AuditEntity},
        AuditService,
    },
    AppError, Result,
};

use super::{access, message::MessageWithSender};

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct MessageThread {
    pub id: Uuid,
    #[serde(rename = "type")]
    #[sqlx(rename = "type")]
    pub thread_type: String,
    pub subject: Option<String>,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub last_message_at: DateTime<Utc>,
}

impl crate::models::audit_diff::AuditRedact for MessageThread {}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ThreadParticipantSummary {
    pub user_id: Uuid,
    pub display_name: String,
    pub email: String,
    pub last_read_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
pub struct ThreadSummary {
    #[serde(flatten)]
    pub thread: MessageThread,
    pub participants: Vec<ThreadParticipantSummary>,
    pub unread_count: i64,
    pub last_message_preview: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ThreadWithMessages {
    #[serde(flatten)]
    pub thread: MessageThread,
    pub participants: Vec<ThreadParticipantSummary>,
    pub messages: Vec<MessageWithSender>,
}

#[derive(Debug, Deserialize)]
pub struct CreateThreadRequest {
    /// "direct" | "group"
    #[serde(rename = "type")]
    pub thread_type: String,
    pub recipient_ids: Vec<Uuid>,
    /// group thread 用；direct 可空
    pub subject: Option<String>,
    pub body: String,
    #[serde(default)]
    pub attachment_ids: Vec<Uuid>,
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub body: String,
    #[serde(default)]
    pub attachment_ids: Vec<Uuid>,
}

pub(super) async fn create(
    pool: &PgPool,
    actor: &ActorContext,
    req: &CreateThreadRequest,
) -> Result<ThreadWithMessages> {
    let sender_id = actor.require_user()?.id;

    if req.recipient_ids.is_empty() {
        return Err(AppError::Validation("至少須一個收件人".into()));
    }
    if req.recipient_ids.contains(&sender_id) {
        return Err(AppError::Validation("收件人不能包含自己".into()));
    }
    if req.thread_type != "direct" && req.thread_type != "group" {
        return Err(AppError::Validation("type 必須為 direct 或 group".into()));
    }
    if req.thread_type == "direct" && req.recipient_ids.len() != 1 {
        return Err(AppError::Validation(
            "direct thread 須恰好 1 位收件人".into(),
        ));
    }
    if req.body.trim().is_empty() && req.attachment_ids.is_empty() {
        return Err(AppError::Validation("訊息內容與附件不可同時為空".into()));
    }

    // 去重後的完整 participant 集合（sender + recipients）— 驗證與寫入共用同一份，
    // 避免重複 id 讓 all-pairs 檢查產生假的 self-pair（如同一 PI 送兩次 → Pi↔Pi 誤拒，bot #365）。
    let mut all_participants = req.recipient_ids.clone();
    all_participants.push(sender_id);
    all_participants.sort();
    all_participants.dedup();

    // Access matrix 檢查：sender → 每個 recipient
    access::ensure_can_message_all(pool, sender_id, &req.recipient_ids).await?;
    // #365：group thread 另驗「所有 participant 兩兩配對」（含 recipient↔recipient），
    // 防止第三方建群把禁止配對（vet↔PI）拉進同 thread 繞過 matrix。
    if req.thread_type == "group" {
        access::ensure_all_pairs_allowed(pool, &all_participants).await?;
    }

    let mut tx = pool.begin().await?;

    let thread = sqlx::query_as::<_, MessageThread>(
        r#"INSERT INTO message_threads (type, subject, created_by)
           VALUES ($1, $2, $3)
           RETURNING id, type, subject, created_by, created_at, last_message_at"#,
    )
    .bind(&req.thread_type)
    .bind(req.subject.as_deref())
    .bind(sender_id)
    .fetch_one(&mut *tx)
    .await?;

    // Insert participants：sender + recipients（已於上方去重）；單次 bulk INSERT via UNNEST
    sqlx::query(
        r#"INSERT INTO message_thread_participants (thread_id, user_id)
           SELECT $1, * FROM UNNEST($2::uuid[])
           ON CONFLICT DO NOTHING"#,
    )
    .bind(thread.id)
    .bind(&all_participants)
    .execute(&mut *tx)
    .await?;

    // Sender 標已讀（自己發的當然已讀）
    sqlx::query(
        r#"UPDATE message_thread_participants SET last_read_at = NOW()
           WHERE thread_id = $1 AND user_id = $2"#,
    )
    .bind(thread.id)
    .bind(sender_id)
    .execute(&mut *tx)
    .await?;

    // Insert first message
    let message_id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO messages (thread_id, sender_id, body)
           VALUES ($1, $2, $3)
           RETURNING id"#,
    )
    .bind(thread.id)
    .bind(sender_id)
    .bind(req.body.trim())
    .fetch_one(&mut *tx)
    .await?;

    // 將 orphan attachments（attach 到本 message）；強制 uploaded_by = sender
    // 防止跨使用者挪用孤兒附件
    if !req.attachment_ids.is_empty() {
        let updated = sqlx::query(
            r#"UPDATE message_attachments SET message_id = $1
               WHERE id = ANY($2) AND message_id IS NULL AND uploaded_by = $3"#,
        )
        .bind(message_id)
        .bind(&req.attachment_ids)
        .bind(sender_id)
        .execute(&mut *tx)
        .await?;
        if updated.rows_affected() != req.attachment_ids.len() as u64 {
            return Err(AppError::Validation(
                "部分附件 ID 無效、已被使用、或非您所上傳".into(),
            ));
        }
    }

    let display = format!(
        "{} 訊息（{} 人）",
        if thread.thread_type == "group" {
            "群組"
        } else {
            "1-1"
        },
        all_participants.len()
    );
    AuditService::log_activity_tx(
        &mut tx,
        actor,
        ActivityLogEntry {
            event_category: "MESSAGING",
            event_type: "MESSAGE_THREAD_CREATED",
            entity: Some(AuditEntity::new("message_threads", thread.id, &display)),
            data_diff: None,
            request_context: None,
        },
    )
    .await?;

    tx.commit().await?;

    // Re-fetch with full hydration
    get(pool, actor, thread.id).await
}

pub(super) async fn list_for_user(pool: &PgPool, user_id: Uuid) -> Result<Vec<ThreadSummary>> {
    let threads = sqlx::query_as::<_, MessageThread>(
        r#"SELECT t.id, t.type, t.subject, t.created_by, t.created_at, t.last_message_at
           FROM message_threads t
           JOIN message_thread_participants p ON p.thread_id = t.id
           WHERE p.user_id = $1
             AND t.deleted_at IS NULL
             AND p.left_at IS NULL
           ORDER BY t.last_message_at DESC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    let mut out = Vec::with_capacity(threads.len());
    for t in threads {
        let participants = list_participants(pool, t.id).await?;
        let unread_count: i64 = sqlx::query_scalar(
            r#"SELECT COUNT(*) FROM messages m
               JOIN message_thread_participants p
                 ON p.thread_id = m.thread_id AND p.user_id = $1
               WHERE m.thread_id = $2
                 AND m.deleted_at IS NULL
                 AND m.sender_id <> $1
                 AND (p.last_read_at IS NULL OR m.created_at > p.last_read_at)"#,
        )
        .bind(user_id)
        .bind(t.id)
        .fetch_one(pool)
        .await?;
        let last_message_preview: Option<String> = sqlx::query_scalar(
            r#"SELECT body FROM messages
               WHERE thread_id = $1 AND deleted_at IS NULL
               ORDER BY created_at DESC LIMIT 1"#,
        )
        .bind(t.id)
        .fetch_optional(pool)
        .await?;
        out.push(ThreadSummary {
            thread: t,
            participants,
            unread_count,
            last_message_preview: last_message_preview.map(|s| {
                let trimmed: String = s.chars().take(80).collect();
                if s.chars().count() > 80 {
                    format!("{trimmed}...")
                } else {
                    trimmed
                }
            }),
        });
    }
    Ok(out)
}

pub(super) async fn get(
    pool: &PgPool,
    actor: &ActorContext,
    thread_id: Uuid,
) -> Result<ThreadWithMessages> {
    let user_id = actor.require_user()?.id;
    let is_admin = actor
        .as_user()
        .map(|u| u.has_permission("messaging.admin_view"))
        .unwrap_or(false);

    // Access：必須是 participant，admin 可看任意 thread
    let is_participant: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
              SELECT 1 FROM message_thread_participants
              WHERE thread_id = $1 AND user_id = $2 AND left_at IS NULL
           )"#,
    )
    .bind(thread_id)
    .bind(user_id)
    .fetch_one(pool)
    .await?;
    if !is_participant && !is_admin {
        return Err(AppError::Forbidden("您不在此對話中".into()));
    }

    let thread = sqlx::query_as::<_, MessageThread>(
        r#"SELECT id, type, subject, created_by, created_at, last_message_at
           FROM message_threads
           WHERE id = $1 AND deleted_at IS NULL"#,
    )
    .bind(thread_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| AppError::NotFound("找不到對話".into()))?;

    let participants = list_participants(pool, thread.id).await?;
    let messages = super::message::list_for_thread(pool, thread.id).await?;

    Ok(ThreadWithMessages {
        thread,
        participants,
        messages,
    })
}

pub(super) async fn list_participants(
    pool: &PgPool,
    thread_id: Uuid,
) -> Result<Vec<ThreadParticipantSummary>> {
    let rows = sqlx::query_as::<_, ThreadParticipantSummary>(
        r#"SELECT p.user_id, COALESCE(u.display_name, u.email) AS display_name, u.email,
                  p.last_read_at
           FROM message_thread_participants p
           JOIN users u ON u.id = p.user_id
           WHERE p.thread_id = $1 AND p.left_at IS NULL
           ORDER BY p.joined_at"#,
    )
    .bind(thread_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub(super) async fn mark_read(pool: &PgPool, user_id: Uuid, thread_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"UPDATE message_thread_participants
           SET last_read_at = NOW()
           WHERE thread_id = $1 AND user_id = $2 AND left_at IS NULL"#,
    )
    .bind(thread_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub(super) async fn unread_thread_count(pool: &PgPool, user_id: Uuid) -> Result<i64> {
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(DISTINCT m.thread_id) FROM messages m
           JOIN message_thread_participants p
             ON p.thread_id = m.thread_id AND p.user_id = $1
           WHERE m.deleted_at IS NULL
             AND m.sender_id <> $1
             AND p.left_at IS NULL
             AND (p.last_read_at IS NULL OR m.created_at > p.last_read_at)"#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;
    Ok(count)
}
