-- DOWN for 117_animal_reservation_planning.sql
-- WARNING: data loss on down（planned_experiments 內容與 animals 預約連結欄一併移除）
-- 僅供 staging / dev rollback；production 採 forward-only。

-- 先移除 animals 上的約束/索引/欄位（其中一欄 FK 參照 planned_experiments，須先於 DROP TABLE）
ALTER TABLE animals DROP CONSTRAINT IF EXISTS chk_animal_reservation_single;
DROP INDEX IF EXISTS idx_animals_reserved_protocol;
DROP INDEX IF EXISTS idx_animals_reserved_planned;
ALTER TABLE animals DROP COLUMN IF EXISTS reserved_protocol_id;
ALTER TABLE animals DROP COLUMN IF EXISTS reserved_planned_experiment_id;

-- 再移除 planned_experiments 表（含其索引）
DROP INDEX IF EXISTS idx_planned_experiments_protocol;
DROP TABLE IF EXISTS planned_experiments;
