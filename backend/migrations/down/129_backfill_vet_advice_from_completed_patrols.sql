-- 還原 129：刪掉巡場同步 / 回填產生的病歷獸醫師建議（source_vet_patrol_entry_id 非 NULL）。
-- WARNING: data loss on down（巡場來源的建議紀錄硬刪；原始巡場報告仍在、為真正來源）。
-- 手動建議（source 為 NULL）保留不動。
-- 註：down 依序 129 → 128；128 隨後 DROP COLUMN source_vet_patrol_entry_id，本檔先清列、冪等安全。
DELETE FROM animal_vet_advice_records WHERE source_vet_patrol_entry_id IS NOT NULL;
