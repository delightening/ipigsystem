-- Down for 047_blood_test_items_correction.sql
-- ⚠️ 不會復原 supersede chain 資料；只還原 schema 形狀。
--    Production 已存在 supersede chain 時，先確認 reporting / audit 已備份再 down。

DROP TRIGGER IF EXISTS check_blood_test_items_no_delete_trigger ON animal_blood_test_items;
DROP TRIGGER IF EXISTS check_blood_test_items_immutable_trigger ON animal_blood_test_items;
DROP FUNCTION IF EXISTS check_blood_test_items_no_delete();
DROP FUNCTION IF EXISTS check_blood_test_items_immutable();

DROP INDEX IF EXISTS idx_animal_blood_test_items_superseded_by;
DROP INDEX IF EXISTS idx_animal_blood_test_items_current;

ALTER TABLE animal_blood_test_items
    DROP CONSTRAINT IF EXISTS chk_blood_test_items_supersede_consistency;

ALTER TABLE animal_blood_test_items
    DROP COLUMN IF EXISTS correction_reason,
    DROP COLUMN IF EXISTS corrected_by,
    DROP COLUMN IF EXISTS superseded_at,
    DROP COLUMN IF EXISTS superseded_by_id;
