-- ============================================================
-- Migration 116: 請假審核改為兩關，收斂已移除的關卡狀態
--
-- 流程由「主管→行政→總經理(GM)」三關改為「主管→行政(終核)」兩關。
-- 進行中(in-flight)落在已移除關卡的假單，退回「待行政」關依新規則重審：
--   PENDING_GM（待總經理核准，已移除） → PENDING_HR
--   PENDING_L2（待二級審核，未使用）   → PENDING_HR
-- 兩關卡皆在 HR 之後/附近，退回 HR 由合法行政/admin（職責分離下）完成終核。
-- enum 值本身保留（歷史稽核與 leave_approvals.approval_level 仍可能引用）。
-- ============================================================

UPDATE leave_requests
   SET status = 'PENDING_HR'::leave_status, updated_at = NOW()
 WHERE status IN ('PENDING_GM'::leave_status, 'PENDING_L2'::leave_status);
