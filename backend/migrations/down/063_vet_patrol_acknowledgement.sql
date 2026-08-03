-- Down migration: 移除 awaiting_acknowledgement 階段，回到三狀態流程
--
-- 注意：若還有 awaiting_acknowledgement 的報告，會 rollback 失敗（constraint 阻擋）。
-- 需先把它們手動推進到 awaiting_follow_up 或 draft 才能 down。

DROP INDEX IF EXISTS idx_vet_patrol_reports_pending_ack;

ALTER TABLE vet_patrol_reports
    DROP COLUMN IF EXISTS acknowledged_at,
    DROP COLUMN IF EXISTS acknowledged_by_id;

ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT IF EXISTS vet_patrol_reports_status_check;

ALTER TABLE vet_patrol_reports
    ADD CONSTRAINT vet_patrol_reports_status_check
    CHECK (status IN ('draft', 'awaiting_follow_up', 'completed'));
