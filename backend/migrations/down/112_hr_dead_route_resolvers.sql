-- Down for 112: 移除 HR resolver 列，還原 leave_cancelled 的角色型 seed 列。
-- WARNING: down 會重建 leave_cancelled 的 ADMIN_STAFF/admin 角色列（up 曾移除這些死列）。

DELETE FROM notification_routing
 WHERE target_kind = 'resolver'
   AND event_type IN ('leave_approved', 'overtime_approved')
   AND target_value = 'event_subject';

DELETE FROM notification_routing
 WHERE event_type = 'leave_cancelled'
   AND target_kind = 'resolver'
   AND target_value = 'leave_request_approvers';

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_cancelled', 'ADMIN_STAFF', 'in_app', '請假取消', 'immediate', 'role', 'ADMIN_STAFF'),
    ('leave_cancelled', 'admin',       'in_app', '請假取消', 'immediate', 'role', 'admin')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
