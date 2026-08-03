-- ============================================================
-- Down migration 054: vet_patrol_reports.accompanying_personnel
-- ------------------------------------------------------------
-- WARNING: data loss on down — 已輸入的陪同人員字串會遺失。
--          僅在 staging / dev rollback 演練使用，production 採 forward-only。
-- ============================================================

ALTER TABLE vet_patrol_reports
    DROP COLUMN IF EXISTS accompanying_personnel;
