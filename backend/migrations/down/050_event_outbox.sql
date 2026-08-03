-- ============================================================
-- Down migration 050: event_outbox（R30-3a）
-- ============================================================
-- WARNING: DROP TABLE 是資料破壞操作。
-- 僅在 outbox 為空時可安全回退；否則 PENDING / FAILED 事件會永久丟失。
--
-- Down 前必執行：
--   SELECT COUNT(*) FROM event_outbox WHERE status NOT IN ('DONE','DEAD');
--   結果必須為 0。
--
-- 若有未處理事件，先：
--   1. 停掉 outbox_worker container（停止 enqueue 端業務）
--   2. 等 worker 把 PENDING/FAILED 全部 drain 到 DONE/DEAD
--   3. 再執行本 down migration
-- ============================================================

-- SQL 層 assert：表存在且仍有未處理事件 → fail（不只放警告）
DO $$
DECLARE
    pending_count BIGINT;
BEGIN
    -- 表已不存在（重複 down 等）→ 視為 noop，後續 DROP IF EXISTS 自動跳過
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'event_outbox' AND table_schema = current_schema()
    ) THEN
        RAISE NOTICE '050_event_outbox: table does not exist, skipping';
        RETURN;
    END IF;

    SELECT COUNT(*) INTO pending_count
    FROM event_outbox WHERE status NOT IN ('DONE','DEAD');

    IF pending_count > 0 THEN
        RAISE EXCEPTION
            '050_event_outbox down blocked: % unprocessed events (status NOT IN (DONE,DEAD)). Drain worker first.',
            pending_count;
    END IF;
END
$$;

DROP INDEX IF EXISTS idx_event_outbox_pending;
DROP INDEX IF EXISTS idx_event_outbox_source;
DROP INDEX IF EXISTS idx_event_outbox_status;
DROP INDEX IF EXISTS idx_event_outbox_stuck_sending;

DROP TABLE IF EXISTS event_outbox;
