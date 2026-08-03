-- 請假流程重設計的通知路由調整：
--   1) leave_proxy_rejected：代理人退回申請 → 通知申請人本人（resolver event_subject，
--      與 leave_approved / leave_proxy_assigned 同模式，見 migration 112 / 115）。
--   2) leave_submitted 新增 DIRECTOR 收件角色：新終審關由負責人簽核，需收到「待審」通知。
INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_proxy_rejected', NULL, 'in_app', '請假代理人退回（通知申請人）', 'immediate', 'resolver', 'event_subject')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;

-- 移除舊流程遺留的 ADMIN_STAFF「leave_submitted」路由：行政已退出請假審核鏈
-- （改為 代理確認 → 單位主管 → 負責人），續留只會讓行政收到無須經手的通知。
DELETE FROM notification_routing
 WHERE event_type = 'leave_submitted' AND role_code = 'ADMIN_STAFF';

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_submitted', 'DIRECTOR', 'in_app', '請假申請（通知負責人）', 'immediate', 'role', 'DIRECTOR')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
