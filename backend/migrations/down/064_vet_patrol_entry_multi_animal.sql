-- Down: 刪掉 junction table 回到單一 animal_id 設計
--
-- 注意：若有 entry 多選了 N 隻動物，rollback 後只保留 animal_id（原欄位）的那一隻，
-- 其餘關聯在 junction table 刪除後遺失。

DROP INDEX IF EXISTS idx_vet_patrol_entry_animals_animal;
DROP TABLE IF EXISTS vet_patrol_entry_animals;
