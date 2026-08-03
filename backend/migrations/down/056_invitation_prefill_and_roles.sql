-- ============================================================
-- Down migration 056: invitation pre-fill columns + invitation_roles
-- ------------------------------------------------------------
-- WARNING: data loss on down — invitation_roles 內 admin 已預設的角色綁定會遺失，
--          以及 invitations.display_name / phone / position 三欄使用者已輸入的內容。
--          僅在 staging / dev rollback 演練使用，production 採 forward-only。
-- ============================================================

DROP INDEX IF EXISTS idx_invitation_roles_role_id;
DROP TABLE IF EXISTS invitation_roles;

ALTER TABLE invitations
    DROP COLUMN IF EXISTS position,
    DROP COLUMN IF EXISTS phone,
    DROP COLUMN IF EXISTS display_name;
