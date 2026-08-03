-- R30-17 follow-up: 動物 / 計劃書 / 藥物批號 / 人員 / QA / SOP 紀錄改永久保留
--
-- Why:
--   migration 044 把多數動物業務紀錄設為 20 年 hard_delete，但使用者明確要求：
--   「動物相關紀錄、計劃書、藥物使用批號/效期、人員紀錄都要永久保留；
--    只有純營運資料（帳務 / 通知 / 設施 / 環境 / 設備 / 邀請 等）保留 20 年。」
--   原 20 年策略源自 OECD §8 的最低條文解，對異種器官移植研究機構（個體
--   生命週期可達數十年、跨世代追蹤）不合用。
--
--   另外 R30-16 migration 047 在 animal_blood_test_items 加 BEFORE DELETE
--   trigger 完全擋 DELETE。若保留 animal_blood_tests 的 hard_delete 策略，
--   retention enforcer 跑時 cascade 會撞 trigger 整個 fail。本 migration 將
--   parent (animal_blood_tests) 改 never 後，cascade 永遠不會發生，trigger
--   也不需要 escape hatch。
--
-- What:
--   以下 32 表 UPDATE delete_strategy = 'never', retention_years = NULL；
--   另 2 表（animal_blood_test_items / animal_sudden_deaths）INSERT 新 policy。
--
-- 永久（never）：動物業務紀錄 + 試劑批號流向 + 人員 + QA + SOP / 文件控管 +
--                   供應商
-- 維持 20 年（hard_delete）：純營運資料（帳務 / 通知 / 設施 / 環境 / 設備 / 邀請
--                            / 倉位 / 安全稽核 / AI 查詢稽核）

-- =========================================================================
-- A-1 動物業務紀錄（14）
-- =========================================================================
UPDATE data_retention_policies
   SET retention_years = NULL,
       delete_strategy = 'never',
       description     = COALESCE(description, '') || ' [R30-永久保留：動物紀錄不可刪]',
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
        'animal_sources'
       );

-- =========================================================================
-- A-1b 補 policy：animal_blood_test_items / animal_sudden_deaths
-- 兩筆均不存在於 migration 044 seed，故走純 INSERT；DOWN migration 的 DELETE 才能安全清掉。
-- =========================================================================
INSERT INTO data_retention_policies (table_name, retention_years, delete_strategy, description) VALUES
    ('animal_blood_test_items',  NULL, 'never',
     'R30-16 append-only raw data：BEFORE DELETE trigger 物理層強制不可刪'),
    ('animal_sudden_deaths',     NULL, 'never',
     '動物個體事件紀錄');

-- =========================================================================
-- A-3 藥物 / 試劑批號效期（3）
-- =========================================================================
UPDATE data_retention_policies
   SET retention_years = NULL,
       delete_strategy = 'never',
       description     = COALESCE(description, '') || ' [R30-永久保留：藥物批號/效期/流向]',
       updated_at      = NOW()
 WHERE table_name IN (
        'reference_standards',
        'formulation_records',
        'stock_ledger'
       );

-- =========================================================================
-- A-4 人員紀錄（6）
-- =========================================================================
UPDATE data_retention_policies
   SET retention_years = NULL,
       delete_strategy = 'never',
       description     = COALESCE(description, '') || ' [R30-永久保留：人員紀錄]',
       updated_at      = NOW()
 WHERE table_name IN (
        'training_records',
        'competency_assessments',
        'role_training_requirements',
        'attendance_records',
        'leave_requests',
        'overtime_records'
       );

-- =========================================================================
-- Q2 供應商（1）— 試劑供應商屬動物試驗證據鏈一環
-- =========================================================================
UPDATE data_retention_policies
   SET retention_years = NULL,
       delete_strategy = 'never',
       description     = COALESCE(description, '') || ' [R30-永久保留：供應商屬證據鏈]',
       updated_at      = NOW()
 WHERE table_name = 'partners';

-- =========================================================================
-- Q3 QA 紀錄（4）— GLP §1.3 QAU 紀錄
-- =========================================================================
UPDATE data_retention_policies
   SET retention_years = NULL,
       delete_strategy = 'never',
       description     = COALESCE(description, '') || ' [R30-永久保留：GLP §1.3 QAU 紀錄]',
       updated_at      = NOW()
 WHERE table_name IN (
        'qa_inspections',
        'qa_non_conformances',
        'qa_audit_schedules',
        'qa_sop_documents'
       );

-- =========================================================================
-- Q4 SOP / 文件控管（4）— 試驗依據版本不可遺失
-- =========================================================================
UPDATE data_retention_policies
   SET retention_years = NULL,
       delete_strategy = 'never',
       description     = COALESCE(description, '') || ' [R30-永久保留：試驗依據 SOP 版本]',
       updated_at      = NOW()
 WHERE table_name IN (
        'controlled_documents',
        'document_revisions',
        'document_acknowledgments',
        'change_requests'
       );

-- =========================================================================
-- 維持 20 年的純營運資料（沒動，列在這裡作文件）：
--   設備：equipment / equipment_calibrations / equipment_maintenance_records /
--         equipment_idle_requests
--   設施：buildings / zones / pens
--   環境：environment_monitoring_points / environment_readings
--   管理：management_reviews / risk_register
--   Audit/Security：user_activity_logs (partition_drop) / user_activity_aggregates /
--                   security_alerts / security_alert_config /
--                   security_notification_channels / login_events /
--                   ip_blocklist / user_sessions
--   邀請 / API key：invitations / user_mcp_keys
--   倉位：storage_locations
--   一般文件：documents / attachments
--   帳務：journal_entries / journal_entry_lines / ap_payments / ar_receipts
--   運維：notifications / ai_query_logs
-- =========================================================================

-- =========================================================================
-- Assertion：fail-fast 確認 32 UPDATE + 2 INSERT 共 34 筆 policy 都已就位
-- 若 migration 044 漏建任何一筆，UPDATE 會 silent skip（affected rows = 0），
-- 沒有此守衛時 migration 會靜默通過、導致部分表的 retention 未真正改為 never。
-- =========================================================================
DO $$
DECLARE
    v_count INTEGER;
    v_expected CONSTANT INTEGER := 34;
    v_tables CONSTANT TEXT[] := ARRAY[
        -- 動物業務（14 + 2 新）
        'animal_observations', 'animal_surgeries', 'animal_blood_tests',
        'animal_weights', 'animal_vaccinations', 'animal_sacrifices',
        'care_medication_records', 'vet_patrol_reports', 'vet_patrol_entries',
        'animal_vet_advices', 'animal_vet_advice_records',
        'euthanasia_orders', 'euthanasia_appeals', 'animal_sources',
        'animal_blood_test_items', 'animal_sudden_deaths',
        -- 試劑批號（3）
        'reference_standards', 'formulation_records', 'stock_ledger',
        -- 人員（6）
        'training_records', 'competency_assessments', 'role_training_requirements',
        'attendance_records', 'leave_requests', 'overtime_records',
        -- 供應商（1）
        'partners',
        -- QA（4）
        'qa_inspections', 'qa_non_conformances', 'qa_audit_schedules', 'qa_sop_documents',
        -- SOP / 文件控管（4）
        'controlled_documents', 'document_revisions',
        'document_acknowledgments', 'change_requests'
    ];
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM data_retention_policies
     WHERE delete_strategy = 'never'
       AND retention_years IS NULL
       AND table_name = ANY(v_tables);

    IF v_count <> v_expected THEN
        RAISE EXCEPTION 'migration 048 assertion failed: expected % rows with delete_strategy=never; got %. Verify migration 044 seed contains all expected table_names.',
            v_expected, v_count;
    END IF;
END;
$$;
