-- 回填內部員工部門（試驗部 / 行政部），啟用請假 L1「單位主管」審核。
-- 緣由：migration 118 建 users.department_id（全 NULL），註明「待部門指派功能上線再填」。
--       本次依現行人員手動分類（2026-07-03，負責人確認）回填；多角色者依主要職能歸部。
-- 範圍：僅內部員工。外部（is_internal=false）/系統/離職者不指派（保持 NULL、不走請假流程）。
-- 識別：以 email 為穩定鍵。其他環境（dev/test）無對應 email → UPDATE 0 rows（no-op）。冪等。
-- 依賴：118（department_id 欄）、005（departments seed：EXPERIMENT/ADMIN）。

-- ── 試驗部（EXPERIMENT）──────────────────────────────────────────────
UPDATE users SET department_id = 'e0000000-0000-0000-0000-000000000001'::uuid, updated_at = NOW()
WHERE email IN (
    'toccatico@gmail.com',    -- 葉沂萱（獸醫 VET）
    'raying80@gmail.com',     -- 王永發
    'q9182736455@gmail.com',  -- 余姿儀（實習生）
    'jliu90826@gmail.com',    -- 劉佳棋
    'lisa82103031@gmail.com', -- 林莉珊
    'keytyne@gmail.com',      -- 潘映潔（研究助理，兼倉管）
    'museum1925@gmail.com',   -- 許芮蓁（兼倉管）
    'monkey20531@gmail.com'   -- 陳怡均（兼試驗部門主管，見下）
);

-- ── 行政部（ADMIN）─────────────────────────────────────────────────
UPDATE users SET department_id = 'e0000000-0000-0000-0000-000000000002'::uuid, updated_at = NOW()
WHERE email IN (
    'smen1971@gmail.com',     -- 王意萍
    'jason4617987@gmail.com'  -- 王子瑄（負責人）
);

-- ── 試驗部門主管 = 陳怡均（供請假 L1 部門主管審核反查）───────────────────
--    以 JOIN 限定：對應 user 不存在時不動 manager_id（避免誤清為 NULL）。
UPDATE departments d SET manager_id = u.id, updated_at = NOW()
FROM users u
WHERE d.code = 'EXPERIMENT' AND u.email = 'monkey20531@gmail.com';
