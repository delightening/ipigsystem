-- ============================================================
-- Migration 056: invitation pre-fill columns + invitation_roles join table
-- ============================================================
-- 目的：邀請發出時 admin 可預設受邀人基本資料 + 鎖定角色，治理上由
-- admin 決定權限，受邀人 accept 時僅能修改身份欄位（display_name /
-- phone / organization / position），不能改動 email 與 roles。
-- ============================================================

ALTER TABLE invitations
    ADD COLUMN IF NOT EXISTS display_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS phone        VARCHAR(20),
    ADD COLUMN IF NOT EXISTS position     VARCHAR(100);

CREATE TABLE IF NOT EXISTS invitation_roles (
    invitation_id UUID NOT NULL REFERENCES invitations(id) ON DELETE CASCADE,
    role_id       UUID NOT NULL REFERENCES roles(id)       ON DELETE RESTRICT,
    PRIMARY KEY (invitation_id, role_id)
);

CREATE INDEX IF NOT EXISTS idx_invitation_roles_role_id ON invitation_roles(role_id);
