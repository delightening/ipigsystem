-- 移除「行政（PENDING_HR）終審」關，改為「負責人（PENDING_DIRECTOR）終審」。
-- 新審核鏈：代理確認 → 單位主管 → 負責人。原本停在「待行政審核」的在途假單，
-- 語意上屬「等待終審」，遷移到「待負責人簽核」。
-- （PENDING_L1「待單位主管」維持不變；PENDING_L2 / PENDING_GM 於 migration 116 已淨空。）
UPDATE leave_requests
   SET status = 'PENDING_DIRECTOR'::leave_status, updated_at = NOW()
 WHERE status = 'PENDING_HR'::leave_status;
