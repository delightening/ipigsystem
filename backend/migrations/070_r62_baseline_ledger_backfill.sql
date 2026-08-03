-- R62-2: 歷史初始庫存補帳
--
-- 背景：2026-05-20 (PR #467) 之前建立的 storage_location_inventory 資料
-- 只寫了 SLI on_hand_qty，沒有對應的 stock_ledger 記錄。
-- 本 migration 對每筆 drift 補一條 adjust_in ledger 記錄，讓兩本帳對齊。
--
-- 安全性：
-- - 只補 recalc_qty = 0（完全沒有 ledger 記錄）的 SLI 列
-- - 不修改任何既有資料
-- - Idempotent：若已補過（ADJ-BASELINE doc 已存在），不會重複插入

DO $$
DECLARE
    v_admin_id       UUID := '5809adec-0d3d-4fca-b401-0ff8211f5861';
    v_doc_date       DATE := '2026-05-25';
    v_remark         TEXT := 'R62-2 歷史初始庫存補帳：2026-05-20 前建立的 SLI 無對應 ledger 記錄，補 adjust_in 對齊';
    v_warehouse_id   UUID;
    v_warehouse_name TEXT;
    v_doc_id         UUID;
    v_doc_no         VARCHAR(50);
    v_line_no        INTEGER;
    v_line_id        UUID;
    v_sli            RECORD;
BEGIN
    -- 跳過已執行的情況（idempotent）
    IF EXISTS (SELECT 1 FROM documents WHERE doc_no LIKE 'ADJ-BASELINE-%') THEN
        RAISE NOTICE 'R62-2 baseline backfill 已執行過，跳過';
        RETURN;
    END IF;

    -- 對每個有 drift 的倉庫建一筆 ADJ document
    FOR v_warehouse_id, v_warehouse_name IN
        SELECT DISTINCT sl.warehouse_id, w.name
        FROM storage_location_inventory sli
        JOIN storage_locations sl ON sl.id = sli.storage_location_id
        JOIN warehouses w ON w.id = sl.warehouse_id
        -- 只選 ledger 累計 = 0 的（完全沒 ledger 記錄）
        WHERE NOT EXISTS (
            SELECT 1 FROM stock_ledger ledger
            WHERE ledger.storage_location_id = sli.storage_location_id
              AND ledger.product_id = sli.product_id
              AND COALESCE(ledger.batch_no, '') = COALESCE(sli.batch_no, '')
              AND COALESCE(ledger.expiry_date, '1900-01-01'::date) = COALESCE(sli.expiry_date, '1900-01-01'::date)
        )
        AND sli.on_hand_qty > 0
    LOOP
        v_doc_id := gen_random_uuid();
        v_doc_no := 'ADJ-BASELINE-' || LEFT(REPLACE(v_warehouse_name, ' ', ''), 10);
        v_line_no := 0;

        INSERT INTO documents (id, doc_type, doc_no, status, warehouse_id, doc_date, remark,
                               created_by, approved_by, approved_at)
        VALUES (v_doc_id, 'ADJ', v_doc_no, 'approved', v_warehouse_id, v_doc_date, v_remark,
                v_admin_id, v_admin_id, NOW());

        RAISE NOTICE '建立 ADJ document: % (倉庫: %)', v_doc_no, v_warehouse_name;

        -- 對該倉庫每筆無 ledger 記錄的 SLI 補帳
        FOR v_sli IN
            SELECT sli.storage_location_id, sli.product_id, sli.on_hand_qty,
                   sli.batch_no, sli.expiry_date, p.base_uom
            FROM storage_location_inventory sli
            JOIN storage_locations sl ON sl.id = sli.storage_location_id
            JOIN products p ON p.id = sli.product_id
            WHERE sl.warehouse_id = v_warehouse_id
              AND sli.on_hand_qty > 0
              AND NOT EXISTS (
                  SELECT 1 FROM stock_ledger ledger
                  WHERE ledger.storage_location_id = sli.storage_location_id
                    AND ledger.product_id = sli.product_id
                    AND COALESCE(ledger.batch_no, '') = COALESCE(sli.batch_no, '')
                    AND COALESCE(ledger.expiry_date, '1900-01-01'::date) = COALESCE(sli.expiry_date, '1900-01-01'::date)
              )
            ORDER BY sli.storage_location_id, sli.product_id
        LOOP
            v_line_no := v_line_no + 1;
            v_line_id := gen_random_uuid();

            -- document_line
            INSERT INTO document_lines (id, document_id, line_no, product_id, qty, uom,
                                        batch_no, expiry_date, storage_location_id, remark)
            VALUES (v_line_id, v_doc_id, v_line_no, v_sli.product_id, v_sli.on_hand_qty,
                    v_sli.base_uom, v_sli.batch_no, v_sli.expiry_date,
                    v_sli.storage_location_id, v_remark);

            -- stock_ledger adjust_in
            INSERT INTO stock_ledger (id, warehouse_id, product_id, trx_date, doc_type, doc_id, doc_no,
                                      line_id, direction, qty_base, batch_no, expiry_date, storage_location_id)
            VALUES (gen_random_uuid(), v_warehouse_id, v_sli.product_id, v_doc_date::timestamptz,
                    'ADJ', v_doc_id, v_doc_no, v_line_id, 'adjust_in', v_sli.on_hand_qty,
                    v_sli.batch_no, v_sli.expiry_date, v_sli.storage_location_id);
        END LOOP;

        RAISE NOTICE '  → % 筆 ledger 記錄已補入', v_line_no;
    END LOOP;
END $$;
