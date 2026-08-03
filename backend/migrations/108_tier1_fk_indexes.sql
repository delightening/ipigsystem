-- W4: Tier 1 業務 JOIN FK 索引（PostgreSQL 不自動為 FK 子欄位建索引）。
-- 對象為「跟動物數無關但隨營運成長的大表 / 高頻 JOIN」的 FK 子欄位。
-- 指向 users 的 128 個審計欄（created_by 等）預設不補（命中低、拖慢寫入）。
--
-- 註：本 migration 為**非並行** CREATE INDEX IF NOT EXISTS（sqlx::migrate! 每個 migration
-- 包 transaction，CREATE INDEX CONCURRENTLY 無法在 transaction 內執行）。prod 若資料量大、
-- 需零停機，改用配套 runbook 手動跑（無 transaction 包裹）：
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stock_ledger_product_id ON stock_ledger(product_id);
--   ...（其餘同名，加 CONCURRENTLY）
-- 手動建好後本 migration 因 IF NOT EXISTS 成為 no-op；fresh DB / 測試由本 migration 建立。
-- 詳見 docs/design/db_performance_refactor_plan.md W4。

CREATE INDEX IF NOT EXISTS idx_stock_ledger_product_id
    ON stock_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_storage_location_inventory_product_id
    ON storage_location_inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_snapshots_product_id
    ON inventory_snapshots(product_id);
CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_account_id
    ON journal_entry_lines(account_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role_id
    ON user_roles(role_id);
