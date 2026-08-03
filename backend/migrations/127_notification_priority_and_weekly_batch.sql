-- 127: 通知 priority（緊急置頂）+ 低庫存/效期改週報
--
-- 背景（使用者 2026-07-10 需求）：
--   1) 低庫存、效期預警每天跳太吵、不 urgent → 改成「一週一個」（週一 08:00）。
--   2) 採購未入庫、巡場報告待填追蹤屬 urgent → 需置頂顯示直到完成。
--
-- 做法：
--   A) notifications 加 priority 欄位；清單排序改 priority DESC, created_at DESC（見 crud.rs）。
--   B) low_stock_alert / expiry_alert 的 daily routing → weekly（day_of_week=1 週一，08:00）。
--   C) 回填現有未讀「未入庫提醒 / 需您填寫追蹤改善」為 priority=1，讓既有待辦立即置頂。
--
-- 註：003 seed 仍為 daily；沿用本專案「後續 migration 調整既有 routing」慣例（見 112/115/122），
--     不回改 003，避免同一份 seed 前後不一致。

-- A) priority 欄位（0=一般，1=緊急置頂）
ALTER TABLE notifications
    ADD COLUMN priority SMALLINT NOT NULL DEFAULT 0
    CONSTRAINT chk_notifications_priority CHECK (priority BETWEEN 0 AND 1);

COMMENT ON COLUMN notifications.priority IS
    '0=一般；1=緊急置頂（採購未入庫、巡場待填追蹤等待辦，完成後由 hook 降級回 0）';

-- 排序索引：對齊 list_notifications 的 ORDER BY priority DESC, created_at DESC
CREATE INDEX idx_notifications_user_priority_created
    ON notifications(user_id, priority DESC, created_at DESC);

-- B) 低庫存 / 效期：daily → weekly（週一 08:00）
UPDATE notification_routing
SET frequency   = 'weekly',
    hour_of_day = 8,
    day_of_week = 1,
    updated_at  = NOW()
WHERE event_type IN ('low_stock_alert', 'expiry_alert')
  AND frequency = 'daily';

-- C) 回填既有待辦置頂（僅未讀 + 標題特徵；已讀者不動，避免翻攪舊通知）
UPDATE notifications
SET priority = 1
WHERE priority = 0
  AND is_read = false
  AND (
        (related_entity_type = 'document'           AND title LIKE '%未入庫提醒%')
     OR (related_entity_type = 'vet_patrol_reports' AND title LIKE '%需您填寫追蹤改善%')
  );
