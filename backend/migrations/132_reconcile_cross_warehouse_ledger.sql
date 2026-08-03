-- 132: 對帳跨倉錯配的 stock_ledger（ledger 跟隨實體儲位）
--
-- 背景：部分 GRN / TR 單據把庫存上架到「不同倉庫」的儲位（例：GRN-260624-001 收進「大倉庫」，
-- 卻把明細上架到「儲藏室」的 A01 儲位）。stock_ledger.warehouse_id 記成收貨/來源倉，但該列的
-- storage_location_id 指的儲位屬於別的倉 → 倉庫級查詢（SUM(stock_ledger) per warehouse）與
-- 儲位級查詢（storage_location_inventory JOIN storage_locations per warehouse）互相對不上，
-- 產品「未分配庫存」誤顯示為未上架、「已在儲位」為 0。
--
-- 使用者裁定（2026-07-18）：同一倉才對，跨倉是錯配，且以「實體儲位」為準（ledger 跟隨儲位）。
--
-- 修法：把每一筆「warehouse_id ≠ 自身 storage_location 所屬倉」的 stock_ledger 列，warehouse_id
-- 改為該 storage_location 所屬倉。idempotent —— 套用後 WHERE 不再命中（可安全重跑 / 還原後重套）。
-- 配套：crud.rs 於建單 / 改單加 assert_lines_shelf_in_warehouse 擋未來再產生跨倉（single-warehouse
-- 單據；TR 調撥 from/to 另計）。
UPDATE stock_ledger s
SET warehouse_id = loc.warehouse_id
FROM storage_locations loc
WHERE loc.id = s.storage_location_id
  AND s.storage_location_id IS NOT NULL
  AND s.warehouse_id <> loc.warehouse_id;
