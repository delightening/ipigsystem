-- R39+++ 巡場觀察條目支援多隻動物（同條觀察可掛多隻豬）
--
-- 設計：junction table (M:N) 取代 vet_patrol_entries.animal_id 單一 FK。
--   - vet_patrol_entries.animal_id 暫保留（標記為 deprecated，內部寫第一隻當主動物）
--     讓既有 read-path（PDF export, vet advice sync）轉換期可漸進改造；之後 PR 統一拿掉。
--   - junction 帶 FK + ON DELETE CASCADE：entry 砍掉時 junction 連帶清；animal 砍掉時亦同。

CREATE TABLE IF NOT EXISTS vet_patrol_entry_animals (
    entry_id  UUID NOT NULL REFERENCES vet_patrol_entries(id) ON DELETE CASCADE,
    animal_id UUID NOT NULL REFERENCES animals(id)            ON DELETE CASCADE,
    PRIMARY KEY (entry_id, animal_id)
);

-- 反向查詢：「動物 X 出現在哪些 entry」
CREATE INDEX IF NOT EXISTS idx_vet_patrol_entry_animals_animal
    ON vet_patrol_entry_animals(animal_id);

-- Backfill：把既有單一 animal_id 灌進 junction
INSERT INTO vet_patrol_entry_animals (entry_id, animal_id)
SELECT id, animal_id
FROM vet_patrol_entries
WHERE animal_id IS NOT NULL
ON CONFLICT DO NOTHING;
