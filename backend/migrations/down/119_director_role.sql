-- Rollback 119: 移除 DIRECTOR 角色及其關聯。
-- WARNING: data loss on down（若已指派給使用者或設路由，將一併移除）。
DELETE FROM notification_routing WHERE role_code = 'DIRECTOR';
DELETE FROM role_permissions WHERE role_id IN (SELECT id FROM roles WHERE code = 'DIRECTOR');
DELETE FROM user_roles WHERE role_id IN (SELECT id FROM roles WHERE code = 'DIRECTOR');
DELETE FROM roles WHERE code = 'DIRECTOR';
