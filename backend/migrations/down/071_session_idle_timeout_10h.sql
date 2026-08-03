-- down 071: revert session idle timeout 10h → 8h
UPDATE system_settings
SET value = '480', updated_at = NOW()
WHERE key = 'session_timeout_minutes';
