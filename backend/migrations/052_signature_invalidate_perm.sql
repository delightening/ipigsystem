-- ============================================================
-- Migration 052: signature.invalidate permission seed (R30-9b)
-- ------------------------------------------------------------
-- 新權限給後台 admin 撤銷 electronic_signatures。
-- Service: SignatureService::invalidate（已存在於 R30-9）
-- Handler: POST /signatures/:id/invalidate（R30-9b 本 PR 新加）
--
-- 設計（R30-9 design doc §4.4）：
-- - admin only — 撤銷簽章是稀有/緊急動作（signer key compromise / 離職撤回）
-- - 不自動分配給任何角色 — 由 admin 在 role 管理 UI 手動勾選
-- - 撤銷不會 revert 已使用該簽章的 record，純為稽核痕跡
-- ============================================================

INSERT INTO permissions (id, code, name, module, description, created_at) VALUES
    (
        gen_random_uuid(),
        'signature.invalidate',
        '撤銷電子簽章',
        'signature',
        '撤銷已存在的電子簽章（不自動 revert 使用該簽章的記錄；僅供稀有/緊急情境使用，如 signer key compromise / 離職撤回）',
        NOW()
    )
ON CONFLICT (code) DO NOTHING;
