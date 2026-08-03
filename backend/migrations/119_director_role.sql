-- 新增「負責人（DIRECTOR）」角色：請假審核鏈的終審關（單位主管 → 負責人）。
-- 全公司層級角色（非部門階層），由 admin 指派給實際負責人帳號。
-- 權限指派於 startup/permissions.rs::ensure_all_role_permissions 統一維護。
INSERT INTO roles (id, code, name, description, is_internal, is_system, created_at, updated_at) VALUES
    (gen_random_uuid(), 'DIRECTOR', '負責人', '公司負責人，請假審核終審（單位主管之上）', true, true, NOW(), NOW())
ON CONFLICT (code) DO NOTHING;
