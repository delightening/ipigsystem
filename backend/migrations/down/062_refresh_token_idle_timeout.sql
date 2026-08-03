-- Rollback R41-1: 移除 refresh_tokens.last_used_at 欄位
ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS last_used_at;
