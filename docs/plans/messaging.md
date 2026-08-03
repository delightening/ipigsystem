# R40-A 站內信系統 設計文件

> 立案：2026-05-10
> 決策確認：2026-05-10（使用者裁定 R40-1 ~ R40-8 + access matrix 最終版）
> 預估工時：~12-15h（最小可運作版 MVP）

## 1. 目標

加入 user-to-user 站內信功能，補既有 `notifications`（系統 → user 單向）的不足。

**範圍**：
- 1-1 對話 + 群組 thread
- 圖片附件（複用 R39 imageCompress + FileService）
- Polling 30s realtime（不做 WebSocket / SSE / push）
- Admin 全可看 body
- 軟刪 30 天 → hard delete + 檔案清除

**不做**：手機推播、email 同步、加密、search/全文檢索、archived folder

## 2. 角色分類（access matrix）

ipig_system `roles` 表共 16 個 role code。Messaging 內聚為 4 個 category + 1 個 external：

| Category | 含 roles |
|---|---|
| **admin** | `admin` |
| **pi** | `PI`, `STUDY_DIRECTOR` |
| **vet** | `VET` |
| **staffs** | `ADMIN_STAFF`, `EXPERIMENT_STAFF`, `INTERN`, `PURCHASING`, `WAREHOUSE_MANAGER`, `EQUIPMENT_MAINTENANCE`, `IACUC_STAFF`, `IACUC_CHAIR`, `QAU`, `REVIEWER` |
| **external** | `CLIENT`, `GUEST` — 不能寄/收訊息 |

### Allowed pairs（雙向）

```
        admin   pi    vet   staffs
admin    ✓      ✓     ✓     ✓
pi       ✓      ✗     ✗     ✓
vet      ✓      ✗     ✓     ✓
staffs   ✓      ✓     ✓     ✓
```

實作於 `services/access.rs::messaging_pair_allowed(sender_cat, recipient_cat) -> bool`。

群組 thread 的允許性 = 「所有參與者兩兩配對都 allowed」（任一對禁止則建立失敗）。

## 3. Schema（migration 060_messaging.sql）

```sql
-- 對話 thread（1-1 也是 thread，僅 type='direct' + 2 participants）
CREATE TABLE message_threads (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    type            VARCHAR(20)  NOT NULL CHECK (type IN ('direct','group')),
    subject         VARCHAR(200), -- group thread 才用；direct 為 NULL
    created_by      UUID         NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(), -- 排序用，每次 message INSERT 觸發更新
    deleted_at      TIMESTAMPTZ  -- 軟刪（thread 全部參與者都退出時）
);
CREATE INDEX idx_message_threads_last_message_at ON message_threads(last_message_at DESC)
    WHERE deleted_at IS NULL;

-- 參與者（1-1 = 2 列；group = N 列）
CREATE TABLE message_thread_participants (
    thread_id      UUID         NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_read_at   TIMESTAMPTZ, -- NULL = 從未讀；用來計算 unread badge
    left_at        TIMESTAMPTZ, -- 軟退出，仍可看歷史但不接新訊息（先暫存欄位給 group 模式用）
    PRIMARY KEY (thread_id, user_id)
);
CREATE INDEX idx_message_thread_participants_user ON message_thread_participants(user_id, last_read_at)
    WHERE left_at IS NULL;

-- 訊息（內容）
CREATE TABLE messages (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id   UUID         NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    sender_id   UUID         NOT NULL REFERENCES users(id), -- 不 CASCADE：使用者刪除後訊息保留
    body        TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    edited_at   TIMESTAMPTZ, -- 未來編輯功能用，初版不開放編輯
    deleted_at  TIMESTAMPTZ  -- 軟刪
);
CREATE INDEX idx_messages_thread_created ON messages(thread_id, created_at DESC)
    WHERE deleted_at IS NULL;
-- GC 用 partial index：30 天前的軟刪訊息
CREATE INDEX idx_messages_deleted_for_gc ON messages(deleted_at)
    WHERE deleted_at IS NOT NULL;

-- 訊息附件（圖片）— 對應 R40-3 圖片決策，沿用 R39 entry photo schema
CREATE TABLE message_attachments (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id  UUID         NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    file_name   VARCHAR(255) NOT NULL,
    file_path   TEXT         NOT NULL,
    file_size   BIGINT       NOT NULL,
    mime_type   VARCHAR(100) NOT NULL,
    sort_order  INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_message_attachments_message ON message_attachments(message_id);

-- Trigger：每次 message INSERT 時更新所屬 thread.last_message_at
CREATE OR REPLACE FUNCTION update_thread_last_message_at()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE message_threads SET last_message_at = NOW() WHERE id = NEW.thread_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_messages_update_thread_timestamp
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_thread_last_message_at();
```

## 4. API 端點（routes/messaging.rs）

| Method | Path | 用途 |
|---|---|---|
| `GET` | `/messages/threads` | 列我參與的 threads（按 last_message_at desc，含每 thread 未讀數） |
| `POST` | `/messages/threads` | 建 thread + 第一封訊息（body: type, recipient_ids[], subject?, body, attachment_ids[]?） |
| `GET` | `/messages/threads/:id` | 看單一 thread 的訊息（paginated） |
| `POST` | `/messages/threads/:id` | 在 thread 內發訊息 |
| `POST` | `/messages/threads/:id/read` | 標已讀（更新 last_read_at = NOW()）|
| `DELETE` | `/messages/:id` | 軟刪自己發的訊息 |
| `POST` | `/messages/attachments` | 上傳圖片（multipart）→ 拿 attachment_id 給後續 thread/message 用 |
| `GET` | `/messages/attachments/:id/download` | 下載附件 |
| `GET` | `/messages/unread_count` | Polling endpoint：回未讀 thread 數量（30s 客戶端輪詢） |

權限：所有端點要 `messaging.send` permission；admin role 自動有。

## 5. 服務層（services/messaging/）

```
services/messaging/
  mod.rs            — MessagingService 主入口
  thread.rs         — Thread CRUD + participants 管理
  message.rs        — Message CRUD
  attachment.rs     — Attachment upload/delete（呼叫 FileService）
  access.rs         — pair allowed 檢查（讀使用者 roles → category → matrix）
```

關鍵函式：
- `MessagingService::create_thread(actor, type, recipients, subject, first_body, attachment_ids)` — 驗 pair allowed → INSERT thread + participants + first message
- `MessagingService::send_message(actor, thread_id, body, attachment_ids)` — 驗 actor 為 thread participant → INSERT
- `MessagingService::list_threads(actor, page)` — JOIN participants 過濾自己；含 unread_count subquery
- `MessagingService::mark_read(actor, thread_id)` — UPDATE last_read_at
- `MessagingService::cleanup_soft_deleted_messages()` — scheduler GC：刪 30 天前軟刪訊息 + 對應 attachments + 實體檔案

Audit：
- `MESSAGE_THREAD_CREATED` 寫一筆（actor, thread_id, recipients, subject）— **不 redact body**（per R40-7 admin 全可看）
- `MESSAGE_SENT` 每封寫一筆（簡短 metadata，body 進 audit_data）
- `MESSAGE_DELETED` 軟刪寫一筆

## 6. 前端 UI（components/messaging/）

```
pages/messaging/
  MessagingPage.tsx           — 主頁（左側 thread list + 右側 thread view）
  hooks/useMessagingPolling.ts — 30s polling unread_count
components/messaging/
  ThreadList.tsx              — 列表
  ThreadView.tsx              — 對話 + 訊息 + 附件預覽
  MessageComposer.tsx         — 輸入框 + 附件上傳（複用 imageCompress + capture="environment"）
  RecipientPicker.tsx         — SearchableSelect over /hr/staff（已有）+ access matrix 過濾
  NewThreadDialog.tsx         — 建新對話 + 選收件人（1 個 = direct, 多個 = group）
```

導航：頂部選單加「💬 站內信」+ unread badge（讀 polling endpoint）。

## 7. Scheduler GC（services/scheduler.rs）

新增 `messaging_gc` job（每日 03:40 UTC，避開 R39 vet_patrol_draft_gc 03:35）：
- DELETE 軟刪 ≥30 天的 messages（CASCADE 清 attachments DB row）
- 撈出 attachments file_path → tx commit 後 unlink 檔案
- 同步清空 thread（若所有 messages 都已軟刪 + 所有 participants 已 left）

## 8. 工時拆分（MVP）

| 項目 | 時 |
|---|---|
| migration 060 + down + 文件 | 0.5h |
| backend services（thread/message/attachment/access） | 4h |
| backend handlers + routes | 1.5h |
| backend scheduler GC | 0.5h |
| audit + permission | 0.5h |
| frontend MessagingPage + 4 components | 4h |
| frontend polling + unread badge | 0.5h |
| 測試 + bug fix | 1.5h |
| **合計** | **~13h** |

## 9. 後續擴充（不在 MVP）

- 訊息編輯（edited_at 欄位已預留）
- 全文檢索（Postgres tsvector）
- WebSocket realtime（升級 polling）
- PWA push notification
- 訊息引用 / 回覆指定
- 表情反應
- 已讀回執明細（誰已讀，目前只記 last_read_at）
- 草稿 auto-save
- export thread to PDF（合規）

## 10. 對應 R39 deferred refactors

R40-B 的 6 個 refactor 可在此 PR 一起做：
- R40-15 `ListReportsQuery` enum 化（同一 PR 內練習 pattern 後直接套到新 messaging endpoints）
- R40-16/17/18 photo handler dedupe（messaging attachment 共用 R39 helper 統一抽出來）
- R40-19 `"draft"/"submitted"` const enum
- R40-20 access guard pattern（messaging 也有 access matrix 需求，順便建 `services/access.rs::messaging_*`）

但這會把 PR 變大。建議：R40-A 站內信獨立 ship；R40-B refactors 另一個 PR。
