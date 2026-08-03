-- CSO-r3 #3/#4：撤銷未過期 access token + 角色變更即時生效
--
-- 背景：改密碼 / 重設密碼原本只撤銷 refresh token，未過期的 access JWT
-- 仍可用到其 exp（預設 15 分鐘）；JWT 內的 roles 快照在角色變更後也會殘留
-- 同樣窗口。SEC-23 的 jwt_blacklist 僅能撤銷「當前 jti」（logout），無法
-- 一次撤銷該使用者「全部已簽發」的 token。
--
-- 解法：users.tokens_valid_after 記錄「access token 須晚於此時間簽發才有效」。
-- 改密碼 / 重設 / 角色變更時設為 NOW()；middleware/auth.rs::auth_middleware
-- 比對 JWT iat < tokens_valid_after → 拒絕（401）。NULL = 無限制（預設）。
ALTER TABLE users ADD COLUMN tokens_valid_after TIMESTAMPTZ;

COMMENT ON COLUMN users.tokens_valid_after IS
  'access token 須晚於此時間簽發才有效；改密碼/重設/角色變更時設 NOW()（CSO-r3 #3/#4）。NULL=無限制';
