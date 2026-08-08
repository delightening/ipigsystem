-- 143: 動物預約與試驗規劃 —— 拆出專屬的「檢視」與「操作」權限
--
-- 問題一：`handlers/planned_experiment.rs` 原本讀寫共用 `animal.info.assign`，
-- 連唯讀的 `get_reservation_planning` 也擋在該權限之後 → 研究主持人（SD）與
-- 試驗工作人員**連頁面都進不來**，而不只是看不到操作按鈕。
--
-- 問題二（實作時查 prod 才發現）：`animal.info.assign` 是**兩個功能共用**的權限 ——
-- 除本頁外，`handlers/animal/animal_core.rs::batch_assign_animals`（動物列表的批次
-- 分配到計畫）也用它。而 prod 上持有者為 EXPERIMENT_STAFF / IACUC_STAFF / VET / admin，
-- 亦即**目前試驗工作人員與獸醫本來就能操作本頁**。
-- 因此無法沿用它當「僅執秘可操作」的閘 —— 從那些角色拔掉會連帶砍掉批次分配功能。
-- 解法：本頁改用專屬的 `animal.planning.manage`，`animal.info.assign` 維持原狀不動。
--
-- 裁定（使用者 2026-08-07）：
--   檢視 animal.planning.view：IACUC_STAFF、EXPERIMENT_STAFF（全體）、
--                              STUDY_DIRECTOR、DIRECTOR（admin 自動 bypass）
--   操作 animal.planning.manage：僅 IACUC_STAFF（admin 自動 bypass）
--   ❌ 皆不給：VET、PI
--
-- SD 是從試驗工作人員名單指派而來，故檢視權授予全體 EXPERIMENT_STAFF；
-- STUDY_DIRECTOR 另列，涵蓋「已指派為 SD 但帳號未帶 EXPERIMENT_STAFF」的情形。
--
-- ⚠️ 行為變更：EXPERIMENT_STAFF 與 VET 將**失去**本頁的操作能力（新增預定試驗 /
-- 預約 / 分配 / 解除 / 備註編輯），改為唯讀（VET 連唯讀也沒有）。
-- 他們在動物列表的批次分配（batch_assign_animals）不受影響。
--
-- 詳見 docs/audit/button-permission-gate-2026-08-07.md §6。

INSERT INTO permissions (id, code, name, module, description, created_at)
VALUES
    (
        gen_random_uuid(),
        'animal.planning.view',
        '檢視動物預約與試驗規劃',
        'animal',
        '可檢視全場動物按試驗分組的分配清冊與缺口（唯讀）',
        NOW()
    ),
    (
        gen_random_uuid(),
        'animal.planning.manage',
        '管理動物預約與試驗規劃',
        'animal',
        '可新增預定試驗、批次預約 / 解除預約、正式分配進實驗、編輯規劃頁備註',
        NOW()
    )
ON CONFLICT (code) DO NOTHING;

-- 檢視：四個角色。admin / SYSTEM_ADMIN 不需顯式授權（middleware 的 is_admin 一律放行）。
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE p.code = 'animal.planning.view'
  AND r.code IN ('IACUC_STAFF', 'EXPERIMENT_STAFF', 'STUDY_DIRECTOR', 'DIRECTOR')
ON CONFLICT DO NOTHING;

-- 操作：僅執行秘書。
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE p.code = 'animal.planning.manage'
  AND r.code = 'IACUC_STAFF'
ON CONFLICT DO NOTHING;
