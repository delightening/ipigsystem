-- 回滾 095：恢復 created_at 預設為 now()（transaction_timestamp）。
-- 注意：回滾後「單一 tx 寫多筆 audit」的 HMAC chain 斷鏈根因會重新出現。
ALTER TABLE user_activity_logs ALTER COLUMN created_at SET DEFAULT now();
