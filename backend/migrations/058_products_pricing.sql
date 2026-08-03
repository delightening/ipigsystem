-- R35-16: products 主檔加價格欄位（cost_price / selling_price）
--
-- 動機：
-- 1. R35-3「庫存價值卡片」需要 products 上的 selling_price 才能計算 SUM(qty × price)。
-- 2. 既有 `document_lines.unit_price` 是「單筆採購/銷售單上的單價」（隨單記錄），
--    不適合當「現在庫存的市值」。需要 products 主檔層級的價格。
-- 3. 拆 cost / selling 兩欄是因為「採購成本」與「庫存市值」概念不同：
--    - cost_price：最近採購均價或標準成本（用於成本會計）
--    - selling_price：目前對外定價（用於庫存價值估算 + 報價）
--
-- 補強說明：原 R35-16 plan 寫「products.unit_price 拆 cost/selling」是錯誤前提
-- （products 從來沒 unit_price 欄位）— 實際上是「從零加上兩欄」。
--
-- Backfill：本 migration 不做 backfill。新欄位皆 nullable，初始值 NULL。
-- 上線後由 ERP 維運人員透過 product update API 填入；缺價產品在「庫存價值」
-- 計算中不計入，與 plan 行為一致。

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS cost_price    NUMERIC(18,4),
    ADD COLUMN IF NOT EXISTS selling_price NUMERIC(18,4);

-- 部分索引：只索引「有定價」的產品 — 加速 selling_price IS NOT NULL 的庫存價值查詢
-- (storage_location_inventory JOIN products WHERE p.selling_price IS NOT NULL)
CREATE INDEX IF NOT EXISTS idx_products_selling_price_nonnull
    ON products(id)
    WHERE selling_price IS NOT NULL;

COMMENT ON COLUMN products.cost_price IS 'R35-16: 標準成本/最近採購均價（NUMERIC(18,4)）。NULL 代表尚未維護';
COMMENT ON COLUMN products.selling_price IS 'R35-16: 目前對外定價（NUMERIC(18,4)）。NULL 代表尚未維護；於庫存價值計算中不計入';
