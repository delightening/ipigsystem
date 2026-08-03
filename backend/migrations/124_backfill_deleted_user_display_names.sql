-- 回填已刪除帳號的 display_name，讓歷史紀錄（體重/觀察/手術…）的「記錄者」顯示真名。
-- 緣由：R63-B6（PR #503）刪除時把 display_name 抹成 '已刪除使用者'。R63-B6 收窄
--       （2026-07-04，負責人裁定）後 delete() 不再抹除，但**既有**已刪除帳號的名字
--       已遺失。本次自其 USER_DELETE 稽核事件還原原名。
-- 資料源：user_activity_logs.entity_display_name = '原名 <原email>'（見 UserService::delete）。
-- 範圍：僅 email 為 …@deleted.local 且 display_name 仍為 '已刪除使用者' 者。
-- 限制：稽核 log 分區歸檔（audit_archive job）後，極舊刪除帳號無 USER_DELETE 可查 →
--       該筆維持 '已刪除使用者'，無法還原（可接受）。
-- 冪等：還原後 display_name != '已刪除使用者'，重跑即 no-op。dev/test 無對應資料 → 0 rows。
-- 依賴：004（user_activity_logs / entity_display_name）、delete() 的匿名化 email 網域。
-- 效能：子查詢先以 entity_id IN (待回填帳號) 收窄，避免對龐大 user_activity_logs
--       全表 DISTINCT ON + 排序（Gemini review 建議）。

UPDATE users u
SET display_name = regexp_replace(src.entity_display_name, ' <[^>]*>$', ''),
    updated_at = NOW()
FROM (
    SELECT DISTINCT ON (entity_id)
           entity_id,
           entity_display_name
    FROM user_activity_logs
    WHERE event_type = 'USER_DELETE'
      AND entity_type = 'user'
      AND entity_display_name IS NOT NULL
      AND entity_id IN (
          SELECT id FROM users
          WHERE email LIKE '%@deleted.local'
            AND display_name = '已刪除使用者'
      )
    ORDER BY entity_id, created_at DESC
) src
WHERE u.id = src.entity_id
  AND u.email LIKE '%@deleted.local'
  AND u.display_name = '已刪除使用者';
