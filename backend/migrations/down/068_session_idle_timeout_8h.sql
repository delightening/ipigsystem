-- down 068: revert session idle timeout 8h → 6h
UPDATE system_settings
SET value = '"360"', updated_at = NOW()
WHERE key = 'session_timeout_minutes';
