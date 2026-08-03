-- Down for 048_animal_records_permanent_retention.sql
-- 還原為 20 年 hard_delete（migration 044 原狀）
-- ⚠️ 不會復原 description 欄的 [R30-永久保留：...] 後綴；如需精確還原請參考 044 原文。

UPDATE data_retention_policies
   SET retention_years = 20,
       delete_strategy = 'hard_delete',
       updated_at      = NOW()
 WHERE table_name IN (
        'animal_observations',
        'animal_surgeries',
        'animal_blood_tests',
        'animal_weights',
        'animal_vaccinations',
        'animal_sacrifices',
        'care_medication_records',
        'vet_patrol_reports',
        'vet_patrol_entries',
        'animal_vet_advices',
        'animal_vet_advice_records',
        'euthanasia_orders',
        'euthanasia_appeals',
        'animal_sources',
        'reference_standards',
        'formulation_records',
        'stock_ledger',
        'training_records',
        'competency_assessments',
        'role_training_requirements',
        'attendance_records',
        'leave_requests',
        'overtime_records',
        'partners',
        'qa_inspections',
        'qa_non_conformances',
        'qa_audit_schedules',
        'qa_sop_documents',
        'controlled_documents',
        'document_revisions',
        'document_acknowledgments',
        'change_requests'
       );

DELETE FROM data_retention_policies
 WHERE table_name IN ('animal_blood_test_items', 'animal_sudden_deaths');
