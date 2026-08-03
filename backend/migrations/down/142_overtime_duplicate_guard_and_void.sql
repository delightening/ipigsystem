-- Rollback migration 142（R86-2 加班防重 + 作廢通道）。
-- WARNING: data loss on down —— 已作廢的單會失去 voided_by / voided_at / void_reason，
-- 且 status='voided' 會違反回退後的 CHECK 約束，故先把 voided 併回 rejected。
-- 僅供 staging / dev rollback；prod 採 forward-only。
DROP INDEX IF EXISTS idx_overtime_records_no_duplicate;

UPDATE overtime_records SET status = 'rejected' WHERE status = 'voided';

ALTER TABLE overtime_records DROP CONSTRAINT chk_overtime_status;
ALTER TABLE overtime_records ADD CONSTRAINT chk_overtime_status
    CHECK (status IN ('draft', 'pending', 'pending_admin_staff', 'pending_admin', 'approved', 'rejected'));

ALTER TABLE overtime_records
    DROP COLUMN IF EXISTS voided_by,
    DROP COLUMN IF EXISTS voided_at,
    DROP COLUMN IF EXISTS void_reason;
