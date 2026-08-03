-- Rollback migration 128: 移除 animal_vet_advice_records 的巡場來源欄位。
-- WARNING: data loss on down（follow_up 內容 + 巡場來源連結會丟失）。
DROP INDEX IF EXISTS ux_vet_advice_source_entry_animal;
ALTER TABLE animal_vet_advice_records
    DROP COLUMN IF EXISTS source_vet_patrol_entry_id,
    DROP COLUMN IF EXISTS follow_up;
