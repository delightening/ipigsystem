-- ============================================================
-- Migration 101: animal.field_correction.review permission seed (R71-1)
-- ------------------------------------------------------------
-- 動物欄位修正審核改用細粒度權限取代 is_admin() 硬編碼。
-- Service: AnimalFieldCorrectionService::review
-- Handler: POST /animals/animal-field-corrections/:id/review（+ 待審清單）
--
-- 設計：
-- - admin 因 has_permission 對 admin 短路回 true，仍具此權限（無回歸）。
-- - 不自動分配給其他角色 — 由 admin 在角色管理 UI 指派給審核者角色，
--   達成「送件(animal.animal.edit) vs 核准(本權限)」的軟性職責分離（R71-1 D2）。
-- ============================================================

INSERT INTO permissions (id, code, name, module, description, created_at) VALUES
    (
        gen_random_uuid(),
        'animal.field_correction.review',
        '審核動物欄位修正',
        'animal',
        '審核（核准/拒絕）動物身分欄位修正申請（耳號/出生日期/性別/品種）。admin 預設具備；可指派給審核者角色以委派審核。',
        NOW()
    )
ON CONFLICT (code) DO NOTHING;
