-- 069: ERP storage-precision tracking — per-line transfer source/target + ledger storage trail
--
-- Background (2026-05-20 ERP audit findings):
--   1. TR (調撥) UI 顯示 per-line 來源/目標貨架，但 backend `document_lines` schema
--      只有 `storage_location_id` (single)，frontend 送的 from/to 被 silently 丟棄
--      → TR 提交「成功」但 per-line storage 永久遺失
--   2. `stock_ledger` 只到 warehouse 級，GLP §11 要求 immutable audit trail 到
--      storage level — JOIN 三張表才能重建現況，不夠 defensive
--   3. PR/DO/SR/RTN 等 doc type 之 storage_location_inventory 從未被 backend
--      扣減/增加 → silent drift（本 migration 不修 drift，只開資料模型；
--      ledger.rs 4 個 function 在同 PR 內補上）
--
-- This migration adds:
--   - document_lines.storage_location_from_id + storage_location_to_id (TR 用)
--   - stock_ledger.storage_location_id (immutable audit trail per movement)
--   - Indexes for the new columns
--
-- Backfill policy (documented in PROGRESS.md §9):
--   - prod 目前 0 TR records — TR 部分零回填問題
--   - 既有 PR/DO/SR/RTN 已造成的 storage_location_inventory drift **不 backfill** —
--     2026-05-20 後新操作正確，之前差異視為 baseline。GLP audit 透過 document_lines
--     歷史可重建 (但不會 mutate existing storage_location_inventory)
--   - 既有 stock_ledger entries 之新欄 = NULL（symmetric 與 backfill 策略一致）

-- ── document_lines: per-line transfer source/target ──────────────────
ALTER TABLE document_lines
    ADD COLUMN storage_location_from_id UUID REFERENCES storage_locations(id),
    ADD COLUMN storage_location_to_id   UUID REFERENCES storage_locations(id);

CREATE INDEX IF NOT EXISTS idx_document_lines_storage_from_id
    ON document_lines(storage_location_from_id)
    WHERE storage_location_from_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_document_lines_storage_to_id
    ON document_lines(storage_location_to_id)
    WHERE storage_location_to_id IS NOT NULL;

-- ── stock_ledger: storage-precision audit trail ──────────────────────
ALTER TABLE stock_ledger
    ADD COLUMN storage_location_id UUID REFERENCES storage_locations(id);

-- 查詢場景：「某貨架最近 N 筆異動」、「某產品在某貨架的歷史」。
-- 與既有 idx_stock_ledger_wh_prod_date 互補 — 此 index 鎖到 storage 顆粒度。
CREATE INDEX IF NOT EXISTS idx_stock_ledger_storage_prod_date
    ON stock_ledger(storage_location_id, product_id, trx_date DESC)
    WHERE storage_location_id IS NOT NULL;
