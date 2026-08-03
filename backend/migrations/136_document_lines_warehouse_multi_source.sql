-- 136: SO 多倉銷貨 — document_lines 明細層級倉庫
--
-- 背景：銷貨單 SO 過去是「單一表頭倉庫」（documents.warehouse_id），一張 SO 只能出同一倉的貨。
-- 需求：讓 SD 在同一張 SO 上銷不同倉庫來源的貨（不同商品分屬不同倉、或同商品跨倉湊數量）。
--
-- 設計：延續 2026-07-18 裁定「以實體儲位為準，ledger 跟隨儲位」（見 migration 132）。SO 不再靠
-- 單一表頭倉，改為「每行倉庫 = 該行儲位所屬倉」。核准時逐行照此倉扣帳，stock_ledger.warehouse_id
-- 仍等於該列 storage_location 所屬倉 → 跨倉錯配不變式逐行成立，與 132/133 對帳收尾一致。
--
-- 本欄為反正規化欄位（denormalized），供核准扣帳與報表逐行取倉，免每次 JOIN storage_locations。
-- 建/改單時由 crud.rs 從 storage_location_id 反推回填。其他單據沿用表頭 documents.warehouse_id。
ALTER TABLE document_lines ADD COLUMN warehouse_id UUID REFERENCES warehouses(id);

-- 回填既有明細：以實體儲位所屬倉為準（延續 ledger 跟隨儲位）。idempotent。
UPDATE document_lines dl
SET warehouse_id = loc.warehouse_id
FROM storage_locations loc
WHERE loc.id = dl.storage_location_id
  AND dl.storage_location_id IS NOT NULL;

CREATE INDEX idx_document_lines_warehouse_id ON document_lines(warehouse_id);

COMMENT ON COLUMN document_lines.warehouse_id IS
  'SO 多倉銷貨：該行所屬倉庫，以 storage_location_id 反推回填（ledger 跟隨儲位，延續 2026-07-18 裁定）。SO 核准逐行照此扣帳；其他單據沿用表頭 documents.warehouse_id（本欄可為 NULL）。';
