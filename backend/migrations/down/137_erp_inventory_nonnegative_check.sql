-- Rollback migration 137: 移除庫存量表非負約束（R84-2）。
-- 非破壞性（只移除約束，不動資料）。
ALTER TABLE inventory_snapshots
    DROP CONSTRAINT IF EXISTS chk_inventory_snapshots_on_hand_nonneg;

ALTER TABLE storage_location_inventory
    DROP CONSTRAINT IF EXISTS chk_storage_location_inventory_on_hand_nonneg;
