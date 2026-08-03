-- 107: 加班管理——平日加班費分段欄位 + 員工固定班別
--
-- 背景：既有 overtime_records 以「補休」為核心（multiplier 為補休乘數，service 明示不計加班費）。
-- 本次導入「平日加班費」：依員工固定班別（早班 7:30–16:30 / 常規班 8:30–17:30）的下班時間，
-- 由打卡 clock_out 自動界定加班時段，四捨五入至 30 分鐘（≥15 分進位、<15 分捨去），
-- 分段前 2h ×1.33、超過 2h ×1.66，產出加權係數時數（weighted_hours）。
-- 本階段「不接薪資」，僅算時數×係數，實際金額留待薪資模組換算。
--
-- 加班類型沿用 A/B/C/D，重新分配「給錢 vs 給補休」：
--   A 平日加班   → 加班費（calc_unit='hour'，分段係數，本 migration 新欄位承載）
--   B 休息日值班 → 加班費（calc_unit='day'，按天計，day_count）
--   C 國定假日值班 / D 天災值班 → 補休（既有 comp_time 機制不變）

-- 1. 員工固定班別。預設常規班；早班僅少數人手動設定。
ALTER TABLE users
    ADD COLUMN work_shift VARCHAR(20) NOT NULL DEFAULT 'standard',
    ADD CONSTRAINT chk_work_shift CHECK (work_shift IN ('early', 'standard'));

COMMENT ON COLUMN users.work_shift IS '固定班別：early=7:30–16:30，standard=8:30–17:30';

-- 2. overtime_records 新增平日加班費分段 / 值班按天欄位。
ALTER TABLE overtime_records
    ADD COLUMN calc_unit      VARCHAR(10)  NOT NULL DEFAULT 'hour',
    ADD COLUMN tier1_hours    NUMERIC(5,2) NOT NULL DEFAULT 0,
    ADD COLUMN tier2_hours    NUMERIC(5,2) NOT NULL DEFAULT 0,
    ADD COLUMN weighted_hours NUMERIC(6,2) NOT NULL DEFAULT 0,
    ADD COLUMN day_count      NUMERIC(4,1) NOT NULL DEFAULT 0,
    ADD CONSTRAINT chk_overtime_calc_unit CHECK (calc_unit IN ('hour', 'day'));

COMMENT ON COLUMN overtime_records.calc_unit      IS '計費單位：hour=平日按時數分段(A)；day=值班按天(B/C/D)';
COMMENT ON COLUMN overtime_records.tier1_hours    IS '平日加班前 2 小時時數（×1.33）';
COMMENT ON COLUMN overtime_records.tier2_hours    IS '平日加班超過 2 小時時數（×1.66）';
COMMENT ON COLUMN overtime_records.weighted_hours IS '加權係數時數 = tier1×1.33 + tier2×1.66（供薪資模組換算加班費）';
COMMENT ON COLUMN overtime_records.day_count      IS '值班天數（calc_unit=day 時使用，B/C/D）';

-- 3. 清空舊加班 / 補休資料。
-- WARNING: data loss（依需求「直接清空過去資料」，預期本無資料）。
-- A/B 由補休改為加班費後，舊資料語意不再一致；C/D 補休改採新流程，故一併清空重來。
-- 刪除順序避開對 leave_balance_usage 之 annual 來源資料的連動（僅刪 comp_time 來源）。
DELETE FROM leave_balance_usage WHERE source_type = 'comp_time';
DELETE FROM comp_time_balances;
DELETE FROM overtime_approvals;
DELETE FROM overtime_records;
