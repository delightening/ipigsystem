-- Rollback 121: 將「待負責人簽核」遷回「待行政審核」。
-- 注意：全面上線後 PENDING_DIRECTOR 為正常終審狀態，此反向遷移僅供 dev / staging
-- 於整體回退時使用（forward-only 環境勿執行）。
UPDATE leave_requests
   SET status = 'PENDING_HR'::leave_status, updated_at = NOW()
 WHERE status = 'PENDING_DIRECTOR'::leave_status;
