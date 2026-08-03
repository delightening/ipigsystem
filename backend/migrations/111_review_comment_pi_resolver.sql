-- ============================================================
-- Migration 111: review_comment_created 收件人全走路由（P2a）
--
-- notify_review_comment_created 原本「PI/SD 寫死 + IACUC_STAFF 走路由」混合，
-- 改走統一派送 dispatch_event 後，PI/SD 由 resolver `protocol_pi_sd` 解析。
-- 本 migration 新增該 resolver 列，使 review_comment_created 的收件人＝
-- IACUC_STAFF 角色列（既有 seed）＋ protocol_pi_sd resolver 列（本列），行為等價。
-- ============================================================

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('review_comment_created', NULL, 'in_app', '新審查意見（計畫 PI / 計劃負責人）', 'immediate', 'resolver', 'protocol_pi_sd')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
