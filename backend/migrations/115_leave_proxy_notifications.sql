-- ============================================================
-- Migration 115: 職務代理人通知事件（送審指定 + 核准生效）
--
-- 請假新增「必選職務代理人」需求：送審通知代理人「你被指定」、最終核准通知「已生效」。
-- 兩事件收件人皆為「代理人本人」，走 resolver event_subject（由 ctx.subject_user_id 提供、
-- 並驗證 active），與 leave_approved / overtime_approved 同模式（見 migration 112）。
-- ============================================================

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('leave_proxy_assigned',  NULL, 'in_app', '請假送審（通知職務代理人：被指定）', 'immediate', 'resolver', 'event_subject'),
    ('leave_proxy_effective', NULL, 'in_app', '請假核准（通知職務代理人：已生效）', 'immediate', 'resolver', 'event_subject')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
