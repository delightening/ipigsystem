-- DOWN for 091: 還原 v_low_stock_alerts 至 091 之前的定義（欄位與 LowStockAlert struct 不同步的舊版）。
-- 純 view 變更，無資料遺失。僅供 staging / dev rollback；prod 採 forward-only。
-- 注意：還原後 LowStockAlert 反序列化會再次 FromRow 失敗（這正是 091 修掉的問題）。

DROP VIEW IF EXISTS v_low_stock_alerts;

CREATE VIEW v_low_stock_alerts AS
SELECT
    p.id AS product_id,
    p.sku,
    p.name AS product_name,
    inv.warehouse_id,
    w.code AS warehouse_code,
    inv.on_hand_qty_base AS on_hand_qty,
    p.base_uom,
    CASE
        WHEN inv.on_hand_qty_base <= 0::numeric THEN 'out_of_stock'::text
        WHEN p.safety_stock IS NOT NULL AND inv.on_hand_qty_base < p.safety_stock THEN 'below_safety'::text
        WHEN p.reorder_point IS NOT NULL AND inv.on_hand_qty_base < p.reorder_point THEN 'below_reorder'::text
        ELSE NULL::text
    END AS stock_status
FROM inventory_snapshots inv
    JOIN products p ON inv.product_id = p.id
    JOIN warehouses w ON inv.warehouse_id = w.id
WHERE p.is_active
  AND w.is_active
  AND (
        inv.on_hand_qty_base <= 0::numeric
        OR (p.safety_stock IS NOT NULL AND inv.on_hand_qty_base < p.safety_stock)
        OR (p.reorder_point IS NOT NULL AND inv.on_hand_qty_base < p.reorder_point)
      );
