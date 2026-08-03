-- Rollback migration 139（R84-5 沖銷單關聯欄位地基）。
-- WARNING: data loss on down —— 若已有沖銷單寫入 reverses_doc_id，回退會丟失該關聯。
-- 僅供 staging / dev rollback；prod 採 forward-only。
DROP INDEX IF EXISTS idx_documents_reverses_doc_id_unique;

ALTER TABLE documents
    DROP COLUMN IF EXISTS reverses_doc_id;
