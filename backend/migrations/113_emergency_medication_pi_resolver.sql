-- ============================================================
-- Migration 113: emergency_medication 的 PI 收件人改走 resolver（P2b-animal）
--
-- 順帶修正原 notify_emergency_medication 的潛在 bug：PI 查詢誤用 up.role（user_protocols
-- 無此欄位，正確為 up.role_in_protocol）。有 iacuc_no 時原查詢 runtime 報錯，導致整個
-- 緊急給藥通知失敗（連 VET 都收不到）。改走 dispatch_event 後：VET 由既有角色列、PI 由
-- protocol_pi resolver（正確欄位）解析。
-- ============================================================

INSERT INTO notification_routing
    (event_type, role_code, channel, description, frequency, target_kind, target_value)
VALUES
    ('emergency_medication', NULL, 'in_app', '緊急給藥（通知計畫 PI）', 'immediate', 'resolver', 'protocol_pi')
ON CONFLICT (event_type, target_kind, target_value) DO NOTHING;
