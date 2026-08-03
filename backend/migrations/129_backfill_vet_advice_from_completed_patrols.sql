-- 129: backfill 既有「已完成」巡場報告 → 病歷獸醫師建議
--
-- #128 加了 source 欄、Phase 2 把同步搬到 complete_followup()。既有 completed 報告是
-- 改 code 前完成的、不會被新流程自動補，本 migration 一次性回填（與 complete_followup 的
-- upsert 同邏輯）。每個「掛豬的 entry × 每隻豬」一筆（觀察 + 建議 + 追蹤改善）。
-- 冪等：ON CONFLICT DO NOTHING（重跑不重複、與新流程 upsert 不打架）。
-- 場級觀察（無 junction 列）自然略過。created_by/updated_by 取報告建立者（填寫的獸醫）。
INSERT INTO animal_vet_advice_records
    (animal_id, advice_date, observation, suggested_treatment, follow_up,
     source_vet_patrol_entry_id, created_by, updated_by)
SELECT ea.animal_id, r.patrol_date, e.observation, e.suggestion, e.follow_up, e.id,
       r.created_by, r.created_by
  FROM vet_patrol_reports r
  JOIN vet_patrol_entries e ON e.report_id = r.id
  JOIN vet_patrol_entry_animals ea ON ea.entry_id = e.id
 WHERE r.status = 'completed' AND r.deleted_at IS NULL
   AND (e.observation <> '' OR e.suggestion <> '' OR e.follow_up <> '')
ON CONFLICT (source_vet_patrol_entry_id, animal_id)
    WHERE source_vet_patrol_entry_id IS NOT NULL
DO NOTHING;
