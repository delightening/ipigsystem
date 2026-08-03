-- 068: bump session idle timeout 6h → 8h
--
-- Background: 原本 system_settings.session_timeout_minutes = 360 (6h)，
-- 但 scheduler 從未呼叫 cleanup_expired，所以 server-side 強制登出未在跑；
-- 同時前端 SessionTimeoutWarning 用 6h 倒數會主動 logout，造成「<6h 被登出」。
--
-- 本 migration 配套：
--   1. constants.rs: ABSOLUTE_SESSION_TIMEOUT_MINUTES 480 → 1440 (24h 上限)
--   2. handlers/auth/session.rs: heartbeat handler ID bug 修正（sliding session 恢復）
--   3. services/session_manager.rs: end_excess_sessions 改 LRU 排序
--   4. services/scheduler.rs: 新增 cleanup_expired 5min cron
--   5. frontend: 移除 SessionTimeoutWarning 倒數 dialog
--   6. docs/security/SESSION_LOGOUT_MANAGEMENT.md: 規格落地
--
-- 詳見 PROGRESS.md §9 2026-05-18 「Sliding session overhaul」

UPDATE system_settings
SET value = '"480"', updated_at = NOW()
WHERE key = 'session_timeout_minutes';

-- 確保 key 存在（若早期 DB 沒透過 003 seed 過）
INSERT INTO system_settings (key, value, description)
VALUES ('session_timeout_minutes', '"480"', 'Session idle 逾時（分鐘） — 2026-05-18 6h→8h，配套 sliding session 修復')
ON CONFLICT (key) DO NOTHING;
