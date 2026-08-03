-- down: 101_tier1_fk_indexes
DROP INDEX IF EXISTS idx_stock_ledger_product_id;
DROP INDEX IF EXISTS idx_storage_location_inventory_product_id;
DROP INDEX IF EXISTS idx_inventory_snapshots_product_id;
DROP INDEX IF EXISTS idx_journal_entry_lines_account_id;
DROP INDEX IF EXISTS idx_user_roles_role_id;
