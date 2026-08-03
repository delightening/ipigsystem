-- R30-10 down: 移除 electronic_signatures.meaning 欄位 + signature_meaning enum
--
-- 注意：DROP COLUMN 會永久刪除 meaning 資料。
-- production rollback 前請先匯出備份：
--   COPY (SELECT id, meaning FROM electronic_signatures) TO '/tmp/esig_meaning_backup.csv' WITH CSV HEADER;

DROP INDEX IF EXISTS idx_esig_meaning;

ALTER TABLE electronic_signatures
    DROP COLUMN IF EXISTS meaning;

DROP TYPE IF EXISTS signature_meaning;
