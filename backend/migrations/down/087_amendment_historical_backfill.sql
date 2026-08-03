-- Rollback 087：移除補登歷史變更標記 + 永久匯入標記。
-- imported_at 的 audit 回填隨欄位 DROP 一併消失，無需另外還原。
ALTER TABLE amendments DROP COLUMN IF EXISTS is_historical;
ALTER TABLE protocols DROP COLUMN IF EXISTS imported_at;
