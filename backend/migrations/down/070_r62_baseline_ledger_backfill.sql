-- down 070: revert R62-2 baseline ledger backfill
-- 刪除補帳 documents + document_lines + stock_ledger（CASCADE 處理 lines/ledger FK）
DELETE FROM stock_ledger WHERE doc_no LIKE 'ADJ-BASELINE-%';
DELETE FROM document_lines WHERE document_id IN (
    SELECT id FROM documents WHERE doc_no LIKE 'ADJ-BASELINE-%'
);
DELETE FROM documents WHERE doc_no LIKE 'ADJ-BASELINE-%';
