-- ============================================================
-- Migration 050: event_outbox（R30-3a Transactional Event Outbox）
-- ------------------------------------------------------------
-- 目的：解耦「業務 tx commit」與「外部訊息送達」(email / line / webhook)：
--   - 業務 tx 內 INSERT outbox row（< 1ms，無外部 I/O）
--   - 獨立 worker process (bin/outbox_worker.rs) 後續 poll + 送 + retry
--   - 通知失敗最多 retry 5 次（exp backoff），仍失敗 → DEAD，alert 觸發人工介入
--
-- 命名 event_outbox（非 notification_outbox）以預留 future webhook /
-- indexing / search reindex 等用例。Design doc: docs/design/r30-3-event-outbox.md
-- ============================================================

CREATE TABLE IF NOT EXISTS event_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 內容
    channel TEXT NOT NULL,           -- 'email' / 'line' / 'webhook' / 'reindex' (future)
    payload JSONB NOT NULL,          -- channel adapter 解析的訊息結構

    -- 狀態機: PENDING → SENDING → DONE | FAILED → DEAD
    -- 唯一允許的 transitions（見 services/outbox/mod.rs）：
    --   enqueue_tx → PENDING
    --   claim_batch: PENDING/FAILED → SENDING
    --   mark_done: SENDING → DONE
    --   mark_failed: SENDING → FAILED 或 DEAD（依 attempt_count）
    --   reset_stuck cron: SENDING (>10min) → PENDING
    status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING','SENDING','DONE','FAILED','DEAD')),
    -- attempt_count 語意：已失敗次數（default 0 = 從未失敗）
    -- mark_failed 流程：先遞增，再依新值算 next_attempt_at
    attempt_count INT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error TEXT,

    -- 追蹤
    enqueued_by UUID REFERENCES users(id),
    enqueued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    done_at TIMESTAMPTZ,

    -- 來源 entity（debug + IDOR + audit cross-ref）
    source_entity TEXT,              -- 'amendment' / 'euthanasia' / 'role' / 'signature'
    source_entity_id UUID
);

-- worker 取件用：只 index 待處理事件 + next_attempt_at 排序
CREATE INDEX IF NOT EXISTS idx_event_outbox_pending
    ON event_outbox (next_attempt_at)
    WHERE status IN ('PENDING','FAILED');

-- 來源 entity 反查（debug / cross-ref audit）
CREATE INDEX IF NOT EXISTS idx_event_outbox_source
    ON event_outbox (source_entity, source_entity_id);

-- 監控/管理查詢：依 status + 入隊時間
CREATE INDEX IF NOT EXISTS idx_event_outbox_status
    ON event_outbox (status, enqueued_at);

-- 卡 SENDING 偵測（reset_stuck cron 用）
CREATE INDEX IF NOT EXISTS idx_event_outbox_stuck_sending
    ON event_outbox (started_at)
    WHERE status = 'SENDING';

COMMENT ON TABLE event_outbox IS
    'R30-3a: Transactional outbox for guaranteed-delivery side effects (notifications, webhooks). Worker: bin/outbox_worker.rs';
COMMENT ON COLUMN event_outbox.channel IS
    'Adapter routing key: email / line / webhook / reindex. ChannelRegistry::send 依此分流';
COMMENT ON COLUMN event_outbox.attempt_count IS
    '已失敗次數（default 0）。mark_failed 先 +1 再依新值算 next_attempt_at。6 次失敗後狀態變 DEAD';
COMMENT ON COLUMN event_outbox.next_attempt_at IS
    '下次 worker 嘗試送出的最早時間。claim_batch 用 WHERE next_attempt_at <= NOW()';
COMMENT ON COLUMN event_outbox.source_entity IS
    '入隊來源 entity 類型（amendment / euthanasia 等），方便從 outbox row 反查業務紀錄';
