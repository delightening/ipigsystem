-- ============================================================
-- Migration 134: 審核結果回通知填單人（設備報廢 / 維修驗收 / 請假駁回）
--
-- 補上「核准/駁回後通知送單人本人」的三個事件路由，收件人皆走
-- resolver `event_subject`（由 ctx.subject_user_id 提供、並驗證 active），
-- 與 leave_approved / leave_proxy_* 同模式（見 migration 112 / 115 / 122）。
--   - equipment_disposal_result   → 報廢申請人（equipment_disposals.applied_by）
--   - equipment_maintenance_result → 維修保養登錄者（equipment_maintenance_records.created_by）
--   - leave_rejected              → 請假申請人（leave_requests.user_id）
--
-- channel 一律 in_app（站內通知中心）；不觸發 email。收件人零寫死，
-- 由 notification_routing 表決定。
-- ============================================================

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('equipment_disposal_result',    NULL, 'in_app', '設備報廢審核結果（通知申請人）',   'immediate', 'resolver', 'event_subject'),
    ('equipment_maintenance_result', NULL, 'in_app', '設備維修驗收結果（通知登錄人）',   'immediate', 'resolver', 'event_subject'),
    ('leave_rejected',               NULL, 'in_app', '請假駁回（通知申請人）',           'immediate', 'resolver', 'event_subject')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
