-- 回滾 097：移除 HMAC chain 已知斷鏈白名單。
-- 注意：回滾後 verifier 會把這 35 筆歷史斷鏈重新計入 broken_links；若每日 cron 已啟用
-- 且其範圍涵蓋到這些 row，會重新告警。
DROP TABLE IF EXISTS audit_chain_known_breaks;
