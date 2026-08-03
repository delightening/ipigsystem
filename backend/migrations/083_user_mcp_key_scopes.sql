-- 083: MCP key scope + 過期（CSO-r3 #5）
--
-- 背景：個人 MCP key（claude.ai 連線用）原本繼承使用者「全部」角色權限、且永不過期。
-- 外流即成全功能 mutation 管道（batch_return_to_pi / submit_vet_review / notify_secretary）。
--
-- 解法：
--   - scopes：read=唯讀工具、write=可呼叫 mutation 工具。新 key 預設僅 read，
--     需明確要求才給 write（handlers/mcp.rs::check_tool_permission 於 dispatch 端守衛）。
--   - expires_at：限制 key 壽命；新 key 建立時預設 +1 年。
--
-- 既有 key grandfather：scopes 預設 '{read,write}'（不破壞既有寫入工作流）、
-- expires_at NULL（不過期）。新 key 由建立端明確指定。
ALTER TABLE user_mcp_keys
    ADD COLUMN scopes TEXT[] NOT NULL DEFAULT '{read,write}',
    ADD COLUMN expires_at TIMESTAMPTZ;

COMMENT ON COLUMN user_mcp_keys.scopes IS
  'MCP key 權限範圍：read=唯讀工具、write=可呼叫 mutation 工具（CSO-r3 #5）。新 key 預設僅 {read}';
COMMENT ON COLUMN user_mcp_keys.expires_at IS
  'key 過期時間；NULL=不過期（grandfather 既有 key）。新 key 預設 +1 年（CSO-r3 #5）';
