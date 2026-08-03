-- Rollback 127
-- 還原 low_stock_alert / expiry_alert 回 daily（與 003 seed 一致）
UPDATE notification_routing
SET frequency   = 'daily',
    day_of_week = NULL,
    updated_at  = NOW()
WHERE event_type IN ('low_stock_alert', 'expiry_alert')
  AND frequency = 'weekly';

-- 移除 priority 欄位與索引（連帶清掉回填的置頂標記）
DROP INDEX IF EXISTS idx_notifications_user_priority_created;
ALTER TABLE notifications DROP COLUMN IF EXISTS priority;
