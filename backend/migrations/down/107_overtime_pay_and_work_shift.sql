-- Down 107: 移除平日加班費分段欄位與員工固定班別。
-- WARNING: data loss on down（DROP COLUMN 丟棄分段 / 班別欄位；UP 清空的舊資料無法復原）。

ALTER TABLE overtime_records
    DROP CONSTRAINT IF EXISTS chk_overtime_calc_unit,
    DROP COLUMN IF EXISTS calc_unit,
    DROP COLUMN IF EXISTS tier1_hours,
    DROP COLUMN IF EXISTS tier2_hours,
    DROP COLUMN IF EXISTS weighted_hours,
    DROP COLUMN IF EXISTS day_count;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS chk_work_shift,
    DROP COLUMN IF EXISTS work_shift;
