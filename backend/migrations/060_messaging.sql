-- R40-A: 站內信系統（user-to-user messaging）
--
-- 來源：使用者於 2026-05-10 確認 R40-1 ~ R40-8 決策。
-- 設計細節：docs/plans/messaging.md
--
-- Schema 概念：
-- - thread = 對話容器（1-1 是 type='direct' + 2 participants；多人是 'group' + N participants）
-- - participants = thread 成員清單（含每人 last_read_at 用於計算未讀）
-- - messages = thread 內的內容
-- - attachments = 訊息圖片附件（沿用 R39 imageCompress + FileService）
--
-- 軟刪策略：thread / message / participant 都用 deleted_at 軟刪；scheduler `messaging_gc`
-- 每日清掉 ≥30 天的軟刪 message + 對應 attachment 實體檔案。
--
-- Access matrix（admin↔ANY、vet↔staffs/vet、PI↔staffs、staffs↔staffs）由 service 層
-- `services/access.rs::messaging_pair_allowed` 動態檢查；不在 schema 內硬編碼。

-- ── thread ──────────────────────────────
CREATE TABLE IF NOT EXISTS message_threads (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    type            VARCHAR(20)  NOT NULL CHECK (type IN ('direct', 'group')),
    -- group thread 才用主旨；direct（1-1）為 NULL，UI 顯示對方名稱
    subject         VARCHAR(200),
    created_by      UUID         NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- 排序用：每次 message INSERT 由 trigger 更新；列表 ORDER BY 此欄位 DESC
    last_message_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- thread 軟刪（所有 participants 都 left 後可設）
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_message_threads_last_message_at
    ON message_threads(last_message_at DESC)
    WHERE deleted_at IS NULL;

-- ── participants ──────────────────────────────
CREATE TABLE IF NOT EXISTS message_thread_participants (
    thread_id      UUID         NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- 用於計算未讀：messages WHERE created_at > last_read_at AND sender_id != user_id
    last_read_at   TIMESTAMPTZ,
    -- group 模式可退出；MVP 不開放退出但欄位先留
    left_at        TIMESTAMPTZ,
    PRIMARY KEY (thread_id, user_id)
);

-- 列我參與的 threads + 計算未讀用
CREATE INDEX IF NOT EXISTS idx_message_thread_participants_user
    ON message_thread_participants(user_id, last_read_at)
    WHERE left_at IS NULL;

-- ── messages ──────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id   UUID         NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    -- 不 CASCADE：使用者軟刪 / 停用後訊息保留可追溯（per R40-7 admin 全可看）
    sender_id   UUID         NOT NULL REFERENCES users(id),
    body        TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- 預留給未來編輯功能；MVP 不開放
    edited_at   TIMESTAMPTZ,
    -- 軟刪：使用者刪自己的訊息；30 天後 GC hard delete
    deleted_at  TIMESTAMPTZ
);

-- thread view 主查詢用
CREATE INDEX IF NOT EXISTS idx_messages_thread_created
    ON messages(thread_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- GC scan 用：找超過 30 天的軟刪訊息批次清
CREATE INDEX IF NOT EXISTS idx_messages_deleted_for_gc
    ON messages(deleted_at)
    WHERE deleted_at IS NOT NULL;

-- ── attachments ──────────────────────────────
-- 上傳流程：先 POST /messages/attachments 拿 attachment_id（message_id=NULL，
-- 標 uploaded_by），之後 create_thread / send_message 帶 attachment_ids 補綁。
-- 每次補綁時 SQL 必須 assert `WHERE id = ANY(...) AND message_id IS NULL AND uploaded_by = sender_id`，
-- 防止跨使用者挪用孤兒附件。
CREATE TABLE IF NOT EXISTS message_attachments (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- NULL 表示孤兒（剛上傳尚未附給訊息）；補綁 SQL 用 IS NULL 篩選
    message_id  UUID         REFERENCES messages(id) ON DELETE CASCADE,
    -- 上傳者；FK 不 CASCADE 因 audit 訊息保留 outlive 帳號
    uploaded_by UUID         NOT NULL REFERENCES users(id),
    file_name   VARCHAR(255) NOT NULL,
    file_path   TEXT         NOT NULL,
    file_size   BIGINT       NOT NULL,
    mime_type   VARCHAR(100) NOT NULL,
    sort_order  INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_message_attachments_message
    ON message_attachments(message_id)
    WHERE message_id IS NOT NULL;

-- 孤兒附件 GC 用：找超過 24 小時未綁定的孤兒
CREATE INDEX IF NOT EXISTS idx_message_attachments_orphan
    ON message_attachments(uploaded_by, created_at)
    WHERE message_id IS NULL;

-- ── trigger：訊息發送時更新 thread 的 last_message_at ──────────
CREATE OR REPLACE FUNCTION update_thread_last_message_at()
RETURNS TRIGGER AS $$
BEGIN
    -- 用 GREATEST：避免歷史訊息匯入或亂序寫入時把 last_message_at 倒退
    UPDATE message_threads
    SET last_message_at = GREATEST(last_message_at, NEW.created_at)
    WHERE id = NEW.thread_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_messages_update_thread_timestamp ON messages;
CREATE TRIGGER trg_messages_update_thread_timestamp
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_thread_last_message_at();
