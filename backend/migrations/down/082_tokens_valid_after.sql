-- Rollback CSO-r3 #3/#4: 移除 users.tokens_valid_after 欄位
ALTER TABLE users DROP COLUMN IF EXISTS tokens_valid_after;
