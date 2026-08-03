-- Rollback migration 140（還原 is_deleted 死欄與其索引）。
-- WARNING: 還原後 is_deleted 全為 DEFAULT false（原本即恆為 false，無真實資料遺失）。
-- 僅供 staging / dev rollback；prod 採 forward-only。

-- roles
ALTER TABLE roles ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

-- animals
ALTER TABLE animals ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_animals_not_deleted
    ON animals(id)
    WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_animals_status_deleted_created
    ON animals(status, is_deleted, created_at DESC);
