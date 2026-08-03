-- Rollback migration 136: 移除 document_lines 明細層級倉庫欄位（SO 多倉銷貨）。
-- WARNING: data loss on down（各明細反推回填的 warehouse_id 會丟失；回退後 SO 逐行倉來源
-- 資訊需重新由 storage_location 反推）。索引與欄位一併移除。
DROP INDEX IF EXISTS idx_document_lines_warehouse_id;
ALTER TABLE document_lines DROP COLUMN IF EXISTS warehouse_id;
