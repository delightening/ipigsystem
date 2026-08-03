-- 106: 拆除 CO_EDITOR 計畫協作編輯者角色（R76-2）
--
-- 背景：CO_EDITOR 角色已於應用層完整移除——指派/列出/移除端點、`aup.coeditor.assign`
-- 權限、前端 CoEditorsTab，以及「進入行政預審前須有 ≥1 CO_EDITOR」前置條件（改為「須已
-- 指派 SD」）。本 migration 從 protocol_role enum 徹底移除 CO_EDITOR 值。
-- Postgres 不支援 `ALTER TYPE ... DROP VALUE`，故重建 enum（rename → create → alter column
-- USING → drop old）。protocol_role 僅 `user_protocols.role_in_protocol` 使用（無 default /
-- check constraint，見 007_aup_protocol.sql）。
--
-- 注意：`protocol_activity_type` 的 COEDITOR_ASSIGNED / COEDITOR_REMOVED 值「保留」——
-- 那是歷史稽核事件，移除會破壞既有 protocol_activities 列的讀取（稽核完整性）。

-- 1. 移除既有 CO_EDITOR 成員列（角色已廢除；其編輯權已於 105/R76-1 收回）。
DELETE FROM user_protocols WHERE role_in_protocol = 'CO_EDITOR';

-- 2. 重建 protocol_role enum，去除 CO_EDITOR 值。
ALTER TYPE protocol_role RENAME TO protocol_role_old;
CREATE TYPE protocol_role AS ENUM ('PI', 'CLIENT');
ALTER TABLE user_protocols
    ALTER COLUMN role_in_protocol TYPE protocol_role
    USING role_in_protocol::text::protocol_role;
DROP TYPE protocol_role_old;

-- 3. 清理 CO_EDITOR 指派權限（seed 只補不刪，DB 既存授權 / 權限定義需此處清除）。
DELETE FROM role_permissions WHERE permission_id IN (
    SELECT id FROM permissions WHERE code IN ('aup.coeditor.assign', 'aup.protocol.assign_co_editor')
);
DELETE FROM permissions WHERE code IN ('aup.coeditor.assign', 'aup.protocol.assign_co_editor');
