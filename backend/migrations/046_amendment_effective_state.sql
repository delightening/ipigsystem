-- ============================================================
-- Migration 046: Amendment EFFECTIVE 終態 + effective_from（R30-25a）
-- ------------------------------------------------------------
-- 目的（GLP §58 traceability）：APPROVED ≠ 正式生效。新增 EFFECTIVE
-- 終態 + effective_from 時間戳，使「於 YYYY-MM-DD 套用的是哪一版
-- amendment」可追溯至絕對日期。
--
-- Schema-only：本 migration 只加 enum 變體與欄位，**不改 workflow**。
-- 後端暫不寫入 EFFECTIVE / effective_from（後續 R30-25b 再接）。
--
-- 注意（PG 規則）：ALTER TYPE ADD VALUE 在同一 tx 中加入後不能立即
-- 在同 tx 內使用該值；本 migration 沒有 INSERT EFFECTIVE row，符合規則。
-- ============================================================

ALTER TYPE amendment_status ADD VALUE IF NOT EXISTS 'EFFECTIVE';

ALTER TABLE amendments
    ADD COLUMN IF NOT EXISTS effective_from TIMESTAMPTZ NULL;

COMMENT ON COLUMN amendments.effective_from IS
    'R30-25 GLP §58：amendment 正式生效時點。NULL = 尚未生效（含 APPROVED 但未啟用）。';
