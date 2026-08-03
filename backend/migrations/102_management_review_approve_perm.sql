-- ============================================================
-- Migration 102: glp.management_review.approve permission seed (R71-6)
-- ------------------------------------------------------------
-- 軟性 SoD：管理審查結案（status → completed/closed）須具此權限，
-- 防任何持 glp.management_review.manage 編輯權者經泛型 update 自行結案、繞過簽核。
-- Service guard: GlpComplianceService::update_management_review
--
-- 設計：
-- - admin 因 has_permission 對 admin 短路回 true，仍可結案（無回歸）。
-- - 授予所有「現有持有 .manage 的角色」（與 change.request.approve 同 pattern），
--   確保既有可結案者不被擋下；SoD 分離由「新 manage-only 角色不自動獲得 approve」達成。
--
-- NOTE: 版號 102。本 PR 須在 #722（migration 101，R71-1）之後合併，
--       以維持 sqlx::migrate! 版序（101 → 102）。
-- ============================================================

INSERT INTO permissions (id, code, name, module, description, created_at) VALUES
    (
        gen_random_uuid(),
        'glp.management_review.approve',
        '核准管理審查',
        'glp',
        '將管理審查結案（completed/closed）；軟性 SoD，與編輯權 glp.management_review.manage 分離',
        NOW()
    )
ON CONFLICT (code) DO NOTHING;

-- 授予所有現有持有 .manage 的角色（無回歸；比照 change.request.approve）
INSERT INTO role_permissions (role_id, permission_id)
SELECT rp.role_id, np.id
FROM role_permissions rp
JOIN permissions mp ON mp.id = rp.permission_id AND mp.code = 'glp.management_review.manage'
JOIN permissions np ON np.code = 'glp.management_review.approve'
ON CONFLICT DO NOTHING;
