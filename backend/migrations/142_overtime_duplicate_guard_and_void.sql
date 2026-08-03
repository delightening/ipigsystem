-- 142: 加班補登防重 + 作廢通道（R86-2）
--
-- 背景：`overtime_records` 只有 pkey(id)，`create_overtime` 也沒有任何重複檢查，
-- 而補登腳本（docs/ops/overtime-backfill-template.js）明寫「中斷可重新執行」。
-- 一旦重跑，同一天同一時段的加班會被建成兩筆；兩筆各自走完核准後，
-- `comp_time_balances` 也會各授一份補休 → 補休餘額翻倍。
-- 且 `delete_overtime` 只受理 draft，已核准的重複單完全沒有事後撤銷路徑。
--
-- 本 migration 兩件事：
-- (1) 防重：DB 層 partial unique index。應用層 check-then-insert 擋不住並發重送
--     （兩個請求都查到「沒有重複」再各插一筆），唯一索引才是可靠的最後防線。
--     鍵取 (user_id, overtime_date, start_time, end_time)：同一人同一天分兩個時段
--     加班仍可分別開單，只有起訖完全相同的才視為重複。
--     排除 rejected / voided：被駁回或已作廢的單不佔位，可以重新申請同一時段。
-- (2) 作廢：新增 status='voided' 與作廢欄位，讓已核准的錯誤單有正式撤銷路徑
--     （ADMIN 單簽 + 理由必填；補休已被使用者則於 service 層擋下）。
--     原單保留不刪，狀態改為 voided，稽核鏈與原始內容都留著。

-- (1) 允許 voided 狀態
ALTER TABLE overtime_records DROP CONSTRAINT chk_overtime_status;
ALTER TABLE overtime_records ADD CONSTRAINT chk_overtime_status
    CHECK (status IN ('draft', 'pending', 'pending_admin_staff', 'pending_admin', 'approved', 'rejected', 'voided'));

-- (2) 作廢軌跡欄位
ALTER TABLE overtime_records
    ADD COLUMN voided_by   UUID        REFERENCES users(id),
    ADD COLUMN voided_at   TIMESTAMPTZ,
    ADD COLUMN void_reason TEXT;

COMMENT ON COLUMN overtime_records.voided_by IS
    'R86-2 作廢通道：作廢此已核准加班單的管理者（ADMIN 單簽）。';
COMMENT ON COLUMN overtime_records.void_reason IS
    'R86-2 作廢通道：作廢理由（必填，一併寫入 user_activity_logs 稽核鏈）。';

-- (3) 防重唯一索引
CREATE UNIQUE INDEX idx_overtime_records_no_duplicate
    ON overtime_records (user_id, overtime_date, start_time, end_time)
    WHERE status NOT IN ('rejected', 'voided');

COMMENT ON INDEX idx_overtime_records_no_duplicate IS
    'R86-2 防重：同一人同一天同一起訖時間只能有一筆有效加班單（駁回/作廢的不佔位）。';
