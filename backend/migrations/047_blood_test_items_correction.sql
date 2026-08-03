-- R30-16 D3: animal_blood_test_items append-only + correction history + immutability triggers
--
-- Why:
--   血檢結果為 21 CFR §11.10(c) raw data，「除非寫錯否則不應更改」。
--   既有 services/animal/blood_test.rs:232 update flow 直接 DELETE 全部舊 items
--   再 INSERT 新 items（line 232 hard DELETE，無 audit），等於默默覆蓋紀錄。
--
--   本 migration 建立物理層 immutability：
--     1. items 不可被任意 UPDATE（只允許從 superseded_by_id IS NULL 翻成 set 一次）
--     2. items 不可被 DELETE（trigger 直接擋）
--     3. 修正流程改為「INSERT 新 row + UPDATE 原 row 標記 superseded」
--     4. 修正必須帶 correction_reason（service 層強制非空 + DB 層 CHECK）
--
--   對齊 21 CFR §11.10(c)(e) raw data integrity + full audit trail
--   對齊 §11.70 immutability（與 electronic_signatures / user_activity_logs trigger 同 pattern）
--
-- ⚠️ STAGING-ONLY MERGE：trigger 一旦 deploy 即生效；production 直接 merge 前
--    必須在 staging 跑 ≥24h 確認既有寫入流程不被誤擋。

-- =========================================================================
-- Step 1: 加 correction history 欄位
-- =========================================================================
ALTER TABLE animal_blood_test_items
    ADD COLUMN superseded_by_id  UUID REFERENCES animal_blood_test_items(id),
    ADD COLUMN superseded_at     TIMESTAMPTZ,
    ADD COLUMN corrected_by      UUID REFERENCES users(id),
    ADD COLUMN correction_reason TEXT;

COMMENT ON COLUMN animal_blood_test_items.superseded_by_id IS
'R30-16: 指向修正後的新 row。NULL 表示此筆為 current（最新版）。';
COMMENT ON COLUMN animal_blood_test_items.superseded_at IS
'R30-16: 此筆被 supersede 的時間。';
COMMENT ON COLUMN animal_blood_test_items.corrected_by IS
'R30-16: 執行修正的使用者 ID。';
COMMENT ON COLUMN animal_blood_test_items.correction_reason IS
'R30-16: 修正原因（GLP §11.10(e)）。被 supersede 的舊 row 必填，current row 必為 NULL。';

-- 一致性 CHECK：4 欄要嘛全 NULL（current row）要嘛全 NOT NULL（superseded row）
-- 且 correction_reason 至少 5 字（service 層另外要求 ≥10 字，DB 層保底）
ALTER TABLE animal_blood_test_items
    ADD CONSTRAINT chk_blood_test_items_supersede_consistency
    CHECK (
        (superseded_by_id IS NULL AND superseded_at IS NULL AND corrected_by IS NULL AND correction_reason IS NULL)
        OR
        (superseded_by_id IS NOT NULL AND superseded_at IS NOT NULL AND corrected_by IS NOT NULL
         AND correction_reason IS NOT NULL AND char_length(correction_reason) >= 5)
    );

-- =========================================================================
-- Step 2: Index — 查 current items（最常見）走 partial index
-- =========================================================================
CREATE INDEX idx_animal_blood_test_items_current
    ON animal_blood_test_items(blood_test_id)
    WHERE superseded_by_id IS NULL;

CREATE INDEX idx_animal_blood_test_items_superseded_by
    ON animal_blood_test_items(superseded_by_id)
    WHERE superseded_by_id IS NOT NULL;

-- =========================================================================
-- Step 3: BEFORE UPDATE trigger — 只允許「current → superseded」一次性翻轉
-- =========================================================================
-- 規則：
--   - core 欄位（item_name / result_value / result_unit / reference_range /
--     is_abnormal / remark / sort_order / template_id / blood_test_id / created_at）
--     一律不可動
--   - superseded_by_id / superseded_at / corrected_by / correction_reason 4 欄
--     僅允許從 NULL 翻成 set 一次；翻過後不可再動
CREATE OR REPLACE FUNCTION check_blood_test_items_immutable()
RETURNS TRIGGER AS $$
BEGIN
    -- core fields 永不可動
    IF OLD.id IS DISTINCT FROM NEW.id
       OR OLD.blood_test_id IS DISTINCT FROM NEW.blood_test_id
       OR OLD.template_id IS DISTINCT FROM NEW.template_id
       OR OLD.item_name IS DISTINCT FROM NEW.item_name
       OR OLD.result_value IS DISTINCT FROM NEW.result_value
       OR OLD.result_unit IS DISTINCT FROM NEW.result_unit
       OR OLD.reference_range IS DISTINCT FROM NEW.reference_range
       OR OLD.is_abnormal IS DISTINCT FROM NEW.is_abnormal
       OR OLD.remark IS DISTINCT FROM NEW.remark
       OR OLD.sort_order IS DISTINCT FROM NEW.sort_order
       OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
        RAISE EXCEPTION 'animal_blood_test_items core fields immutable (GLP §11.10(c))。
血檢結果不可直接修改；如需修正，使用 BloodTestService::correct_item_with_reason 走 supersede 流程。'
            USING ERRCODE = 'P0001';
    END IF;

    -- supersede 相關欄位：only NULL → set 一次性翻轉
    IF OLD.superseded_by_id IS NOT NULL
       OR OLD.superseded_at IS NOT NULL
       OR OLD.corrected_by IS NOT NULL
       OR OLD.correction_reason IS NOT NULL THEN
        RAISE EXCEPTION 'animal_blood_test_items already superseded; 修正紀錄不可二次修改 (GLP §11.70)。'
            USING ERRCODE = 'P0001';
    END IF;

    -- 翻轉時 4 欄必須一致 set（CHECK constraint 也會擋，但 trigger 提前出更清楚的錯訊）
    IF NEW.superseded_by_id IS NULL
       OR NEW.superseded_at IS NULL
       OR NEW.corrected_by IS NULL
       OR NEW.correction_reason IS NULL THEN
        RAISE EXCEPTION 'supersede 必須同時設定 superseded_by_id / superseded_at / corrected_by / correction_reason 4 欄。'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_blood_test_items_immutable_trigger ON animal_blood_test_items;
CREATE TRIGGER check_blood_test_items_immutable_trigger
    BEFORE UPDATE ON animal_blood_test_items
    FOR EACH ROW
    EXECUTE FUNCTION check_blood_test_items_immutable();

COMMENT ON FUNCTION check_blood_test_items_immutable() IS
'GLP §11.10(c)/§11.70：blood test items core fields 永不可改；supersede 4 欄僅允許一次性 NULL→set 翻轉。';

-- =========================================================================
-- Step 4: BEFORE DELETE trigger — 完全禁止 DELETE
-- =========================================================================
-- ⚠️ 例外：parent animal_blood_tests 被 DELETE 時 ON DELETE CASCADE 會觸發本 trigger。
--    main 上 animal_blood_tests 走 soft_delete_blood_test（services/animal/blood_test.rs:300），
--    不會真的 DELETE parent。但為了讓 cascade 場景仍可（若未來有合理需求），
--    這裡以 session GUC `app.bypass_blood_test_items_delete = 'true'` 作為 escape hatch。
--    所有 escape hatch 觸發都會留下 RAISE NOTICE，便於 audit。
CREATE OR REPLACE FUNCTION check_blood_test_items_no_delete()
RETURNS TRIGGER AS $$
DECLARE
    bypass TEXT;
BEGIN
    -- 取 session-level GUC；若未設定為 NULL（current_setting with missing_ok=true）
    bypass := current_setting('app.bypass_blood_test_items_delete', true);
    IF bypass = 'true' THEN
        RAISE NOTICE 'blood_test_items DELETE bypassed via app.bypass_blood_test_items_delete (id=%, blood_test_id=%)', OLD.id, OLD.blood_test_id;
        RETURN OLD;
    END IF;

    RAISE EXCEPTION 'animal_blood_test_items is append-only (GLP §11.70)。不可 DELETE。
若需修正，使用 BloodTestService::correct_item_with_reason；如為合法 cascade 場景，
service 層需在同 tx 內 SET LOCAL app.bypass_blood_test_items_delete = ''true''.'
        USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_blood_test_items_no_delete_trigger ON animal_blood_test_items;
CREATE TRIGGER check_blood_test_items_no_delete_trigger
    BEFORE DELETE ON animal_blood_test_items
    FOR EACH ROW
    EXECUTE FUNCTION check_blood_test_items_no_delete();

COMMENT ON FUNCTION check_blood_test_items_no_delete() IS
'GLP §11.70：blood_test_items 一律不可 DELETE。修正請走 supersede 流程。session GUC app.bypass_blood_test_items_delete 為 escape hatch（會 RAISE NOTICE 留軌跡）。';
