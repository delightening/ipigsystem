-- 091: 重建 v_low_stock_alerts 對齊 LowStockAlert struct，修 FromRow 500
--
-- 問題：`v_low_stock_alerts` view 的欄位與它唯一消費者 `LowStockAlert` struct
-- （models/stock.rs，由 services/notification/alert.rs 以 `SELECT * → Vec<LowStockAlert>` 反序列化）
-- 全面不同步：view 給 `sku` / `on_hand_qty`、缺 `warehouse_name` / `safety_stock` / `reorder_point`，
-- 但 struct 要 `product_sku` / `qty_on_hand` / `warehouse_name` / `safety_stock` / `reorder_point`。
-- sqlx FromRow 只報第一個缺欄（warehouse_name），故 prod 日誌只見 warehouse_name；
-- 實際只要 view 有低庫存資料，GET /api/v1/notifications/alerts/low-stock 與低庫存告警 scheduler 必 500。
-- 詳見 PROGRESS.md 2026-06-03「系統報錯彙總 + 全面 recurrence 稽核」。
--
-- 修法：DROP + CREATE 重建 view，欄位完整對齊 struct（含 product_sku / qty_on_hand /
-- warehouse_name / safety_stock / reorder_point）。商業邏輯（CASE / WHERE）與原 view 等價。
-- view 僅 alert.rs 使用、無相依物件，DROP 安全。前端 dashboard 走的是另一端點
-- /inventory/low-stock（inventory.rs Rust 手建），不受影響。

DROP VIEW IF EXISTS v_low_stock_alerts;

CREATE VIEW v_low_stock_alerts AS
SELECT
    inv.warehouse_id,
    w.name AS warehouse_name,
    p.id AS product_id,
    p.sku AS product_sku,
    p.name AS product_name,
    p.base_uom,
    inv.on_hand_qty_base AS qty_on_hand,
    p.safety_stock,
    p.reorder_point,
    CASE
        WHEN inv.on_hand_qty_base <= 0::numeric THEN 'out_of_stock'::text
        WHEN p.safety_stock IS NOT NULL AND inv.on_hand_qty_base < p.safety_stock THEN 'below_safety'::text
        WHEN p.reorder_point IS NOT NULL AND inv.on_hand_qty_base < p.reorder_point THEN 'below_reorder'::text
        ELSE 'below_safety'::text
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
