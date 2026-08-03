-- R70-4: 能力評鑑 result 欄補 CHECK 約束
-- #704 reviewer 發現 result 欄無列舉約束，可寫任意字串。
-- 有效值來源：frontend/src/pages/admin/CompetencyAssessmentPage.tsx RESULTS 清單。
--
-- 採兩階段方式避免生產環境鎖表：
--   1. NOT VALID: 快速加 metadata 約束（無需掃描既有列）
--   2. VALIDATE CONSTRAINT: 使用 ShareUpdateExclusiveLock（允許並行讀寫）驗證既有資料
ALTER TABLE competency_assessments
    ADD CONSTRAINT competency_assessments_result_check
    CHECK (result IN ('competent', 'not_yet_competent', 'requires_supervision')) NOT VALID;

ALTER TABLE competency_assessments
    VALIDATE CONSTRAINT competency_assessments_result_check;
