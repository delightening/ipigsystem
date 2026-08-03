-- Rollback migration 131: 移除 GRN 上架分配審計表與未上架來源 view。
-- WARNING: data loss on down（line_shelf_allocations 內的上架分配審計軌跡會丟失）。
DROP VIEW IF EXISTS v_grn_line_unshelved;
DROP TABLE IF EXISTS line_shelf_allocations;
