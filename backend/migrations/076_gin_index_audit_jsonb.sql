-- R35-21: GIN index on audit JSONB columns for jsonb path query performance
-- user_activity_logs: before_data, after_data (partitioned — index propagates to partitions)
CREATE INDEX IF NOT EXISTS idx_ual_before_data_gin
    ON user_activity_logs USING gin (before_data jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_ual_after_data_gin
    ON user_activity_logs USING gin (after_data jsonb_path_ops);

-- audit_logs: before_data, after_data
CREATE INDEX IF NOT EXISTS idx_audit_logs_before_data_gin
    ON audit_logs USING gin (before_data jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_audit_logs_after_data_gin
    ON audit_logs USING gin (after_data jsonb_path_ops);
