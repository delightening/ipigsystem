-- down: 076_gin_index_audit_jsonb
DROP INDEX IF EXISTS idx_ual_before_data_gin;
DROP INDEX IF EXISTS idx_ual_after_data_gin;
DROP INDEX IF EXISTS idx_audit_logs_before_data_gin;
DROP INDEX IF EXISTS idx_audit_logs_after_data_gin;
