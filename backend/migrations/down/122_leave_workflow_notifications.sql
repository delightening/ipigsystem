-- Rollback 122: 移除本 migration 新增的通知路由列，並還原被移除的 ADMIN_STAFF 路由。
DELETE FROM notification_routing
 WHERE event_type = 'leave_proxy_rejected' AND target_kind = 'resolver' AND target_value = 'event_subject';
DELETE FROM notification_routing
 WHERE event_type = 'leave_submitted' AND target_kind = 'role' AND target_value = 'DIRECTOR';
-- 還原 forward migration 移除的 ADMIN_STAFF「leave_submitted」路由（與 003 seed 一致）。
INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_submitted', 'ADMIN_STAFF', 'in_app', '請假申請', 'immediate', 'role', 'ADMIN_STAFF')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
