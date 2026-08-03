-- Rollback CSO-r3 #5: 移除 user_mcp_keys.scopes / expires_at 欄位
ALTER TABLE user_mcp_keys
    DROP COLUMN IF EXISTS scopes,
    DROP COLUMN IF EXISTS expires_at;
