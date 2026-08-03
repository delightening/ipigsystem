-- ============================================================
-- Down migration 061: vet_patrol two-phase workflow rollback
-- ============================================================

DROP INDEX IF EXISTS idx_vet_patrol_reports_follow_up_pending;

ALTER TABLE vet_patrol_reports
    DROP COLUMN IF EXISTS follow_up_submitted_at;
ALTER TABLE vet_patrol_reports
    DROP COLUMN IF EXISTS follow_up_user_id;

ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT IF EXISTS vet_patrol_reports_status_check;

-- 回退 status：'awaiting_follow_up' / 'completed' → 'submitted'
UPDATE vet_patrol_reports
SET status = 'submitted'
WHERE status IN ('awaiting_follow_up', 'completed');

ALTER TABLE vet_patrol_reports
    ADD CONSTRAINT vet_patrol_reports_status_check
    CHECK (status IN ('draft', 'submitted'));
