-- ============================================================
-- Migration 112: HR 死路由事件改走 resolver（P2b）
--
-- leave_approved / overtime_approved / leave_cancelled 原本收件人寫死、不查路由表
-- （路由設定無效＝死路由）。改走 dispatch_event 後以 resolver 解析「當事人」：
-- - leave_approved / overtime_approved → event_subject（申請人本人）
-- - leave_cancelled                    → leave_request_approvers（曾核准的經手人）
--
-- 這些事件對象由實體關係天然決定，UI 將標註為不可調（見 P4）。
-- ============================================================

-- 申請人本人（resolver 由 ctx.subject_user_id 提供，並驗證 active）。
INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_approved',    NULL, 'in_app', '請假核准（通知申請人）', 'immediate', 'resolver', 'event_subject'),
    ('overtime_approved', NULL, 'in_app', '加班核准（通知申請人）', 'immediate', 'resolver', 'event_subject')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;

-- leave_cancelled：原碼通知「核准經手人」，但 seed 另有從未被使用的 ADMIN_STAFF/admin
-- 角色死列。移除死列、改以 approvers resolver，維持原 working 行為（不擴散通知給全體 admin）。
DELETE FROM notification_routing
 WHERE event_type = 'leave_cancelled' AND target_kind = 'role';

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_cancelled', NULL, 'in_app', '請假取消（通知核准經手人）', 'immediate', 'resolver', 'leave_request_approvers')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
