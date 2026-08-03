-- R57: session idle timeout 8h → 10h
-- 對齊 backend constants.rs SESSION_IDLE_TIMEOUT_MINUTES = 600
-- 前端同步加入 per-tab idle tracking（閒置分頁前端清畫面，不影響活躍分頁）
UPDATE system_settings
SET value = '600', updated_at = NOW()
WHERE key = 'session_timeout_minutes';
