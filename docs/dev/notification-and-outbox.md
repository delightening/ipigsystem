# 通知系統 + Event Outbox 開發指南

> **適用範圍**：backend Rust service 想在業務 mutation 後通知使用者（站內 / email / line / webhook）的所有路徑。
> **狀態**：2026-05-03 R30-3a/b 完成後生效

---

## TL;DR

每個業務 service fn 在自己的 `Transaction<'_, Postgres>` 內，可以同時做 **4 件事**，全部 all-or-nothing：

1. 業務 UPDATE / INSERT
2. `AuditService::log_activity_tx` — HMAC chain audit
3. `NotificationService::create_notification_tx` — 站內通知（DB row）
4. `OutboxService::enqueue_tx` — 外部訊息（email / line / webhook）

```rust
let mut tx = pool.begin().await?;

sqlx::query("UPDATE my_table SET ... WHERE id = $1")
    .bind(id).execute(&mut *tx).await?;

AuditService::log_activity_tx(&mut tx, actor, ActivityLogEntry { ... }).await?;

NotificationService::create_notification_tx(&mut tx, CreateNotificationRequest {
    user_id: target_user_id,
    notification_type: NotificationType::SystemAlert,
    title: "...".into(),
    content: Some("...".into()),
    related_entity_type: Some("my_entity".into()),
    related_entity_id: Some(id),
}).await?;

OutboxService::enqueue_tx(&mut tx, actor, "email", serde_json::json!({
    "to": user_email,
    "subject": "...",
    "plain_body": "...",
    "html_body": "..."
}), ("my_entity", id)).await?;

tx.commit().await?;  // ← 4 件事 atomic
```

如果 commit 失敗，所有 4 件事都 rollback：業務不會悄悄 drift，audit 不會缺，通知也不會送出。

---

## 為什麼分兩層？

| 機制 | 用途 | 寫到哪 | 送達保證 |
|---|---|---|---|
| **站內通知** (`notifications` 表) | 使用者登入後在 UI 看到的紅點 / 通知列表 | DB row（同 tx 寫入即生效） | ✅ DB 寫入即達成 |
| **Event Outbox** (`event_outbox` 表) | 外部系統收到的訊息：email / line / webhook | DB row（同 tx 入隊）→ 獨立 worker 後續送 + retry | ✅ retry 5 次 + DEAD-letter alert |

兩者**可獨立用，也可一起用**。常見組合：

| 場景 | 站內 | Outbox email | 範例 |
|---|---|---|---|
| 系統內 admin 變更 | ✅ | — | role 變更通知 admin |
| 關鍵業務事件 | ✅ | ✅ | euthanasia 超時、amendment EFFECTIVE |
| 外部系統 callback | — | ✅ | webhook to LINE / Google Calendar |
| 內部 background sync | — | ✅ | reindex search engine（future） |

---

## API 速查

### 站內通知

```rust
// services/notification/crud.rs
pub async fn create_notification_tx(
    tx: &mut Transaction<'_, Postgres>,
    request: CreateNotificationRequest,
) -> Result<Notification, AppError>
```

**Request**：

```rust
CreateNotificationRequest {
    user_id: Uuid,
    notification_type: NotificationType,  // SystemAlert / TaskAssigned / ...
    title: String,
    content: Option<String>,
    related_entity_type: Option<String>,    // 'animal' / 'protocol' / 'amendment' / ...
    related_entity_id: Option<Uuid>,
}
```

**已封裝的 domain helper**（推薦先找看看）：
- `notify_euthanasia_timeout_approved_tx`
- `notify_euthanasia_order` / `notify_euthanasia_appeal` / `notify_euthanasia_approved`
- 其他 `services/notification/*.rs` — animal / amendment / equipment / hr / protocol

> 寫新的 helper 而非直接呼叫 `create_notification_tx`，讓 title/content 邏輯集中。
> Helper 命名：`notify_{event}_tx`，與既有 non-tx 版本同檔但加 `_tx` 後綴。

### Event Outbox

```rust
// services/outbox/mod.rs
pub async fn enqueue_tx(
    tx: &mut Transaction<'_, Postgres>,
    actor: &ActorContext,
    channel: &str,                    // 'email' / 'line' / ... 必須與註冊的 ChannelAdapter 一致
    payload: serde_json::Value,        // adapter 自定義 schema，見下方
    source: (&str, Uuid),             // (entity_type, entity_id) 用於 audit cross-ref
) -> Result<Uuid, AppError>            // 回傳 outbox row id
```

#### `email` channel payload schema

```json
{
    "to": "user@example.com",
    "to_name": "顯示名稱（optional）",
    "subject": "...",
    "plain_body": "...",
    "html_body": "..."
}
```

**注意**：
- caller 自己 render plain/html。EmailAdapter 不做 template 邏輯
- SMTP 設定有 30s TTL 快取，admin 改 SMTP 後 ≤30s 生效
- SMTP 未配置 / 收件人無效 → 回 Err（worker 會 retry / DEAD-letter，**不會被吞**）

#### Future channels（未實作）

- `line` — 訊息推播
- `webhook` — 外部 HTTP POST
- `reindex` — search engine reindex

實作新 channel：在 `services/outbox/` 內新增 `XxxAdapter` 實作 `ChannelAdapter` trait + `register` 進 `bin/outbox_worker.rs::init_runtime` 的 `ChannelRegistry`。

---

## Outbox 內部運作

```text
業務 service          event_outbox 表          outbox_worker
─────────             ─────────────            ──────────────
enqueue_tx(...)  →  PENDING row
                                        ←  poll every 5s
                                            (FOR UPDATE SKIP LOCKED)
                                        →  SENDING + started_at
                                            ChannelAdapter::send()
                                              ↓
                            Ok          ←  mark_done → DONE
                            Err         ←  mark_failed → FAILED
                                            (attempt_count++,
                                             next_attempt_at += backoff)
                                            ↓
                                        若 attempt_count = 6 → DEAD
                                            （Prometheus alert）
```

### Retry policy

| 失敗第 N 次 | next_attempt_at |
|---|---|
| 1 | +10s |
| 2 | +1m |
| 3 | +10m |
| 4 | +1h |
| 5 | +6h |
| 6 | **DEAD**（不再排，alert 觸發） |

總嘗試 = 6 次（首次 + 5 retry）

### 多 worker 部署

`docker compose --scale outbox-worker=3` 即可。`claim_batch` 用 `FOR UPDATE SKIP LOCKED` 互斥，每 row 同一時間只有一個 worker 處理。

### Worker crash recovery

每 60s `OutboxService::reset_stuck` 把卡 `SENDING` 超過 10min 的 row 重設回 `PENDING`，避免 worker OOM/kill -9 後 row 永久卡住。

---

## 完整範例：euthanasia 超時自動核准

`services/euthanasia.rs::approve_timeout_order_tx` (R30-3b 實作參考)：

```rust
async fn approve_timeout_order_tx(
    pool: &PgPool,
    actor: &ActorContext,
    order_id: Uuid,
    vet_user_id: Uuid,
    now: chrono::DateTime<Utc>,  // caller-provided 確保與 SELECT 用同一時間戳
) -> Result<bool, AppError> {
    let mut tx = pool.begin().await?;

    // 1. CAS UPDATE 業務 row（用 caller now 取代 DB NOW() 防漂移）
    let updated: Option<(i32,)> = sqlx::query_as(
        "UPDATE euthanasia_orders SET status='approved', ... \
         WHERE id=$1 AND status='pending_pi' AND deadline_at < $2 \
         RETURNING version",
    ).bind(order_id).bind(now).fetch_optional(&mut *tx).await?;

    if updated.is_none() {
        tx.rollback().await?;
        return Ok(false);  // race
    }

    // 2. Audit chain
    AuditService::log_activity_tx(&mut tx, actor, ActivityLogEntry { ... }).await?;

    // 3. 站內通知
    NotificationService::notify_euthanasia_timeout_approved_tx(
        &mut tx, order_id, vet_user_id,
    ).await?;

    // 4. Email outbox
    enqueue_timeout_email_tx(&mut tx, actor, vet_user_id, order_id, ...).await?;

    tx.commit().await?;
    Ok(true)
}
```

呼叫端（cron loop）變成 thin loop（`now` 算一次 propagate）：

```rust
let now = Utc::now();
for order in &candidates {
    match Self::approve_timeout_order_tx(pool, &actor, order.id, order.vet_user_id, now).await {
        Ok(true) => count += 1,
        Ok(false) => {} // race, noop
        Err(e) => tracing::error!(order_id=%order.id, error=%e, "..."),
    }
}
```

---

## 常見坑

| 坑 | 解法 |
|---|---|
| Outbox 寫了但 commit 失敗，業務 UPDATE 沒回滾 | 永遠用 `&mut tx` 把 4 件事**都**進同一個 tx |
| 站內通知用 `create_notification`（無 _tx）導致兩個 connection | 改用 `create_notification_tx` 並傳 `&mut tx` |
| email payload 包密碼 / 個資 | payload 會以 plaintext 存 `event_outbox.payload` 直到 DONE。敏感資料應 hash 或在 worker 解析時查 DB |
| Email HTML body 注入 (XSS) | 從 `plain_body` 或任何動態變數構造 `html_body` 時，**必須** HTML escape（`&` `<` `>` `"` `'` 五個字元）。用 `crate::utils::html_escape::html_escape_minimal()` 通用 helper（最小實作，含完整 unit tests）。如需更完整的 HTML 處理（屬性、URL、JS）請評估引入 `html-escape` crate。**禁止**直接 `format!("<p>{}</p>", user_input)` |
| Channel 字串拼錯 → router 找不到 adapter | 用常數封裝（如 `const CHANNEL_EMAIL: &str = "email"`），與 ChannelAdapter::channel() 對齊 |
| Outbox 表暴漲 | DONE 30 天後可加 cron archive；DEAD 永久保留供稽核（design doc §9） |

---

## 監控

Prometheus metrics（worker exporter）：
- `outbox_pending_count` — 待處理事件數
- `outbox_failed_count` — FAILED 狀態（可 retry）
- `outbox_dead_count` — DEAD 狀態 → **alert > 0**
- `outbox_send_duration_seconds` — 每筆送出耗時
- `outbox_send_total{channel,status}` — 送出總數

Alertmanager 規則：`outbox_dead_count > 0 for 5m` → email IT。

---

## 相關文件

- Design doc：[`docs/design/r30-3-event-outbox.md`](../design/r30-3-event-outbox.md)
- HMAC chain：[`docs/security/HMAC_VERSIONING.md`](../security/HMAC_VERSIONING.md)
- Audit pattern：CLAUDE.md §「ActorContext::Anonymous 適用情境」
- 既有 channel adapters：`backend/src/services/outbox/`
