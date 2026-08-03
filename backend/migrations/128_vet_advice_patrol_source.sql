-- 128: 巡場報告 →「病歷獸醫師建議」單一來源化的 schema 準備
--
-- 巡場報告「完成」（complete_followup）後，各筆掛豬的觀察要歸位到該豬病歷的獸醫師
-- 建議（animal_vet_advice_records），並上儀表板。本 migration 只做 schema 準備：
--   1. follow_up：陪同人員填的「追蹤改善」（原表僅 observation + suggested_treatment）。
--   2. source_vet_patrol_entry_id：連結來源巡場條目——供「完成」時 upsert 去重、
--      報告刪除時連帶清理（ON DELETE CASCADE，依使用者決定 a）、病歷標「來源：巡場」。
--      NULL = 獸醫在「獸醫師建議」分頁手動寫的 comment（不受下方唯一約束）。
--   3. 部分 UNIQUE index：同一巡場條目對同一隻豬僅一筆（NULL source 允許多筆）。
-- 同步邏輯與既有 completed 報告的 backfill 於後續 phase（服務層 + 資料回填）。
ALTER TABLE animal_vet_advice_records
    ADD COLUMN IF NOT EXISTS follow_up TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS source_vet_patrol_entry_id UUID
        REFERENCES vet_patrol_entries(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS ux_vet_advice_source_entry_animal
    ON animal_vet_advice_records (source_vet_patrol_entry_id, animal_id)
    WHERE source_vet_patrol_entry_id IS NOT NULL;
