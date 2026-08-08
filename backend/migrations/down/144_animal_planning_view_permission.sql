-- Rollback migration 144（動物預約與試驗規劃的專屬檢視 / 操作權限）。
--
-- 回退後 handlers 若仍要求這兩個權限會全數 403，
-- 故本 down 僅供「連同 code 一起回退」的 staging / dev 情境；prod 採 forward-only。
--
-- role_permissions 對 permission_id 有 FK，先刪授權列再刪權限本身。
DELETE FROM role_permissions
WHERE permission_id IN (
    SELECT id FROM permissions
    WHERE code IN ('animal.planning.view', 'animal.planning.manage')
);

DELETE FROM permissions
WHERE code IN ('animal.planning.view', 'animal.planning.manage');
