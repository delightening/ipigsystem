-- Rollback CSO #3: 移除 users.last_totp_step 欄位
ALTER TABLE users DROP COLUMN IF EXISTS last_totp_step;
