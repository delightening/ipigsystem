-- Down migration 105: 還原執行秘書（IACUC_STAFF）的 aup.protocol.edit / submit 授權
--
-- 重新分配 edit / submit 給 IACUC_STAFF（撤回唯讀收緊）。

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code = 'IACUC_STAFF'
  AND p.code IN ('aup.protocol.edit', 'aup.protocol.submit')
ON CONFLICT DO NOTHING;
