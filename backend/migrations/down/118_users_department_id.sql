-- Rollback migration 118: 移除 users.department_id。
-- WARNING: data loss on down（若已有使用者部門指派，DROP COLUMN 會丟失）。
DROP INDEX IF EXISTS idx_users_department_id;
ALTER TABLE users DROP COLUMN IF EXISTS department_id;
