-- ============================================================
-- Down migration 051: audit chain v3 with signature fingerprint
-- ============================================================
-- ⚠️ IRREVERSIBLE WARNING — once v3 rows exist, dropping `extra_input`
-- breaks chain verification for all v3 rows (HMAC mismatch on every v3 row).
--
-- To roll back safely:
-- 1. Stop writes (downtime) — set ENABLE_R30_9A_V3 env var to false
-- 2. Confirm no v3 rows: SELECT COUNT(*) FROM user_activity_logs WHERE hmac_version = 3;
--    Result must be 0
-- 3. Then run this down migration
--
-- If v3 rows exist, do NOT drop the column — instead forward-migrate
-- (re-write each v3 row as v2, losing sig fingerprint binding).
-- ============================================================

-- TOCTOU 防護：先取 ACCESS EXCLUSIVE lock（與 ALTER TABLE 同等級），
-- 阻止任何並發 INSERT 在 count 與 DROP 之間插入新的 v3 row。
-- Lock 在 transaction commit 時釋放（migration 通常單 tx 跑）。
LOCK TABLE user_activity_logs IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE
    v3_count BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_activity_logs'
          AND column_name = 'extra_input'
          AND table_schema = current_schema()
    ) THEN
        RAISE NOTICE '051_audit_chain_v3: extra_input column does not exist, skipping';
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v3_count
    FROM user_activity_logs WHERE hmac_version = 3;

    IF v3_count > 0 THEN
        RAISE EXCEPTION
            '051_audit_chain_v3 down blocked: % v3 rows exist. Dropping extra_input would break chain verification.',
            v3_count;
    END IF;
END
$$;

ALTER TABLE user_activity_logs DROP COLUMN IF EXISTS extra_input;
