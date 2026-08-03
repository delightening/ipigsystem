-- ============================================================
-- Down migration 055: vet_patrol_photos table
-- ------------------------------------------------------------
-- WARNING: data loss on down — 所有已上傳的巡場照片紀錄（DB 列）會遺失；
--          實體檔案（file_path 指向 uploads/）需另外人工清理。
--          僅在 staging / dev rollback 演練使用，production 採 forward-only。
-- ============================================================

DROP INDEX IF EXISTS idx_vet_patrol_photos_report;
DROP TABLE IF EXISTS vet_patrol_photos;
