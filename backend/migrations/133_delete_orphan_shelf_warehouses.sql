-- 133: 刪除 8 個 orphan 空殼倉庫（WH002-009「大倉庫-貨架1~8」）
--
-- 早期（2026-03）把「大倉庫的 8 個貨架」誤建成 8 個獨立倉庫，後來改為正確模型
-- （貨架 = storage_location 掛在倉庫底下），並將這 8 個停用（is_active=false）但未刪除。
-- 現況：is_active=false、0 storage_locations、0 stock_ledger、0 documents 引用 —— 純 orphan
-- 紀錄，已於前端所有選倉器（filter is_active）隱藏，不影響 UI，僅污染 warehouses 表。
--
-- 安全刪除：guard 三個 NOT EXISTS 確保確實無任何引用才刪（即使將來被誤引用也不會刪）。
-- idempotent —— 刪除後不再命中。
DELETE FROM warehouses w
WHERE w.code IN ('WH002', 'WH003', 'WH004', 'WH005', 'WH006', 'WH007', 'WH008', 'WH009')
  AND w.is_active = false
  AND NOT EXISTS (SELECT 1 FROM storage_locations sl WHERE sl.warehouse_id = w.id)
  AND NOT EXISTS (SELECT 1 FROM stock_ledger s WHERE s.warehouse_id = w.id)
  AND NOT EXISTS (
        SELECT 1 FROM documents d
        WHERE d.warehouse_id = w.id OR d.warehouse_from_id = w.id OR d.warehouse_to_id = w.id
  );
