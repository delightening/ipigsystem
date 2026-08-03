-- 131: GRN 未上架來源追溯 — 上架分配審計表 + 未上架來源 view
--
-- Background（2026-07-16 倉儲 UX 決策）：
--   採購入庫（GRN）核准後改為「軟擋」——缺儲位仍可核准，倉庫總量上升但未落貨架，
--   產生「未分配庫存」。使用者需知道「這批未分配是哪張 GRN 造成的」，並在事後
--   分配（上架）時精確扣回來源明細，達到帳實可對帳。
--
--   現況：
--     - 倉庫總量真相 = stock_ledger 累計（每筆帶 doc_id/line_id，可追溯來源單）
--     - 儲位層級量 = storage_location_inventory
--     - 「未分配」= 倉庫總量 − 儲位量（inventory.rs 即時算，無獨立表）
--     - 「分配」（assign_unassigned）只 UPSERT storage_location_inventory、不寫 ledger，
--       且不記錄「消耗了哪張來源單的未分配量」→ 無法精確歸屬。
--
-- This migration adds:
--   1. line_shelf_allocations — append-only 上架分配審計。分配時逐筆記錄
--      「某來源 GRN 明細的多少量，被上架到哪個儲位」。document_line_id 可為 NULL，
--      以容納 legacy／來源不明（如 070 baseline backfill）的分配。
--   2. v_grn_line_unshelved — 每條「已核准 GRN 且明細儲位為 NULL」的剩餘未上架量
--      （line.qty − Σ 已分配），供來源追溯 API 與分配時的 FIFO 攤扣。
--
-- 不新增 documents.shelving_status 欄位：上架狀態由本 view 即時推導，避免 denormalized
-- 欄位漂移（與既有 v_purchase_order_receipt_status 同哲學）。

-- ── line_shelf_allocations：上架分配審計（append-only）─────────────────
CREATE TABLE line_shelf_allocations (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    -- 來源 GRN 明細。ON DELETE SET NULL：即使來源明細日後被移除，審計軌跡仍保留。
    -- NULL = legacy／來源不明的分配（攤不回任何未上架明細時）。
    document_line_id    UUID          REFERENCES document_lines(id) ON DELETE SET NULL,
    storage_location_id UUID          NOT NULL REFERENCES storage_locations(id),
    product_id          UUID          NOT NULL REFERENCES products(id),
    batch_no            VARCHAR(50),
    expiry_date         DATE,
    qty                 NUMERIC(18,4) NOT NULL CHECK (qty > 0),
    created_by          UUID          REFERENCES users(id),
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- 追溯查詢：「某來源明細已被分配多少」（view 的 LEFT JOIN 聚合）。
CREATE INDEX idx_line_shelf_alloc_line
    ON line_shelf_allocations(document_line_id)
    WHERE document_line_id IS NOT NULL;

-- 儲位/產品維度查詢（某儲位上架來源、某產品分配歷史）。
CREATE INDEX idx_line_shelf_alloc_loc_prod
    ON line_shelf_allocations(storage_location_id, product_id);

-- ── v_grn_line_unshelved：GRN 明細剩餘未上架量 ─────────────────────────
-- 只涵蓋「已核准 GRN 且明細 storage_location_id IS NULL」——即核准時未落貨架、
-- 造成未分配的來源明細。remaining_unshelved = 明細數量 − 已分配（>0 才列出）。
-- doc_created_at 供分配時 FIFO（最舊來源先扣）。
CREATE VIEW v_grn_line_unshelved AS
SELECT
    dl.id                                     AS document_line_id,
    d.id                                      AS document_id,
    d.doc_no,
    d.doc_date,
    d.warehouse_id,
    d.partner_id,
    d.created_at                              AS doc_created_at,
    dl.line_no,
    dl.product_id,
    dl.batch_no,
    dl.expiry_date,
    dl.qty                                    AS line_qty,
    dl.qty - COALESCE(SUM(a.qty), 0)          AS remaining_unshelved
FROM documents d
JOIN document_lines dl ON dl.document_id = d.id
LEFT JOIN line_shelf_allocations a ON a.document_line_id = dl.id
WHERE d.doc_type = 'GRN'
  AND d.status = 'approved'
  AND dl.storage_location_id IS NULL
GROUP BY dl.id, d.id, d.doc_no, d.doc_date, d.warehouse_id, d.partner_id,
         d.created_at, dl.line_no, dl.product_id, dl.batch_no, dl.expiry_date, dl.qty
HAVING dl.qty - COALESCE(SUM(a.qty), 0) > 0;
