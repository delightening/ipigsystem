-- 移除 competency_assessments.result 的 CHECK 約束
ALTER TABLE competency_assessments
    DROP CONSTRAINT IF EXISTS competency_assessments_result_check;
