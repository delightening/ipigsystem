-- ============================================================
-- Migration 103: aup.pi_invite.approve permission seed (R71-2)
-- ------------------------------------------------------------
-- PI 帳號開通信「核准寄送」改用細粒度權限取代 is_admin() 硬編碼。
-- Service: ProtocolService::approve_send_pi_invite
-- Handler: POST /pi-account-invites/:id/approve-send
--
-- 命名：對齊 AUP 域既有慣例 aup.{entity}.{action}（如 aup.amendment.approve）。
-- 設計：
-- - admin 因 has_permission 對 admin 短路回 true，仍可核准寄送（無回歸；原為 is_admin only）。
-- - 不自動分配給其他角色 —— 維持現行「僅 admin」行為；如需委派由 admin 於角色管理 UI 指派。
--
-- NOTE: 版號 103。本 PR 須在 #722（101, R71-1）、#725（102, R71-6）之後合併，
--       以維持 sqlx::migrate! 版序（101 → 102 → 103）。
-- ============================================================

INSERT INTO permissions (id, code, name, module, description, created_at) VALUES
    (
        gen_random_uuid(),
        'aup.pi_invite.approve',
        '核准寄送 PI 開通信',
        'aup',
        '核准並寄送計畫 PI 帳號的「設定密碼」開通信（寄送開通信為敏感動作）',
        NOW()
    )
ON CONFLICT (code) DO NOTHING;
