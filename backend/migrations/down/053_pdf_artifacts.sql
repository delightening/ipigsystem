-- ============================================================
-- Down migration 053: pdf_artifacts table (R32-A6)
-- ------------------------------------------------------------
-- ⚠️ 不可逆 — 一旦寫入 artifact 後 DROP，GLP 稽核紀錄遺失。
--
-- 安全 rollback 流程：
-- 1. 確認 SELECT COUNT(*) FROM pdf_artifacts; = 0
-- 2. 確認沒有上線 endpoint 還在寫此表（grep 'pdf_artifacts' backend/src）
-- 3. 才能跑此 down migration
-- ============================================================

-- LOCK TABLE 不支援 IF EXISTS — 移到 DO block 內 EXECUTE 動態執行，
-- 避免 table 不存在時 down migration 直接報「relation does not exist」中斷。
-- TOCTOU 防護：仍維持 ACCESS EXCLUSIVE 阻止並發 INSERT（先檢查表存在再 lock）。
DO $$
DECLARE
    artifact_count BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'pdf_artifacts'
          AND table_schema = current_schema()
    ) THEN
        RAISE NOTICE '053_pdf_artifacts: table does not exist, skipping';
        RETURN;
    END IF;

    -- 表存在後才 lock
    EXECUTE 'LOCK TABLE pdf_artifacts IN ACCESS EXCLUSIVE MODE';

    SELECT COUNT(*) INTO artifact_count FROM pdf_artifacts;

    IF artifact_count > 0 THEN
        RAISE EXCEPTION
            '053_pdf_artifacts down blocked: % artifacts exist. Dropping would lose GLP audit trail.',
            artifact_count;
    END IF;
END
$$;

DROP INDEX IF EXISTS idx_pdf_artifacts_signature;
DROP INDEX IF EXISTS idx_pdf_artifacts_doc_type;
DROP INDEX IF EXISTS idx_pdf_artifacts_generated_at;
DROP INDEX IF EXISTS idx_pdf_artifacts_generated_by;
DROP INDEX IF EXISTS idx_pdf_artifacts_resource_time;

DROP TABLE IF EXISTS pdf_artifacts;
