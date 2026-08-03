-- down 069: revert storage-precision tracking columns
DROP INDEX IF EXISTS idx_stock_ledger_storage_prod_date;
ALTER TABLE stock_ledger DROP COLUMN IF EXISTS storage_location_id;

DROP INDEX IF EXISTS idx_document_lines_storage_to_id;
DROP INDEX IF EXISTS idx_document_lines_storage_from_id;
ALTER TABLE document_lines
    DROP COLUMN IF EXISTS storage_location_to_id,
    DROP COLUMN IF EXISTS storage_location_from_id;
