-- R35-15 rollback
DROP INDEX IF EXISTS idx_refresh_tokens_family_id;
ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS revoked_reason;
ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS family_id;
