-- Rollback R46-1/2: 移除 refresh_tokens reuse detection 降噪欄位
--
-- 警告：rollback 後 reuse detection 將回到 PR #359 (R35-15) 行為 —
-- 任何 revoked token 再次出現一律觸發 family revoke + critical alert，
-- 含併發 race condition 與 browser bug 也會誤觸發。

ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS rotated_at;
ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS last_ip;
ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS last_user_agent;
