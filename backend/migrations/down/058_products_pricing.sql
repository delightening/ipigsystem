-- R35-16 down: 移除 products 價格欄位
--
-- 注意：執行此 down 會永久刪除任何已輸入的 cost_price / selling_price 數值。
-- production rollback 前請先匯出備份：
--   COPY (SELECT id, sku, cost_price, selling_price FROM products
--         WHERE cost_price IS NOT NULL OR selling_price IS NOT NULL)
--     TO '/tmp/products_pricing_backup.csv' WITH CSV HEADER;

DROP INDEX IF EXISTS idx_products_selling_price_nonnull;

ALTER TABLE products
    DROP COLUMN IF EXISTS selling_price,
    DROP COLUMN IF EXISTS cost_price;
