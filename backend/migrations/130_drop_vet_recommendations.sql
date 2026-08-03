-- 130: 退役 vet_recommendations 功能 —— DROP TABLE
--
-- 獸醫建議單一來源改為 animal_vet_advice_records（巡場完成同步 + 獸醫手動 comment），
-- vet_recommendations（觀察/手術評論）整個功能退役（後端 handler/service/routes +
-- 前端 dialog/tab 已移除）。prod 0 筆，安全。索引隨表一併 DROP。
-- ⚠️ 不 DROP TYPE vet_record_type —— care_records / care_medication_records 仍共用該 enum type。
DROP TABLE IF EXISTS vet_recommendations;
