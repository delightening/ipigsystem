-- ============================================================
-- Down migration 059: vet_patrol_entry_photos + status 欄位 cleanup
-- ------------------------------------------------------------
-- WARNING: data loss on down — entry photos 列會遺失（檔案另外人工清理）；
--          submitted_at 欄位資料遺失。僅 staging / dev rollback 用。
-- ============================================================

DROP INDEX IF EXISTS idx_vet_patrol_reports_draft_updated;

ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT IF EXISTS vet_patrol_reports_status_check;

ALTER TABLE vet_patrol_reports
    DROP COLUMN IF EXISTS submitted_at;

DROP INDEX IF EXISTS idx_vet_patrol_entry_photos_entry;
DROP TABLE IF EXISTS vet_patrol_entry_photos;
