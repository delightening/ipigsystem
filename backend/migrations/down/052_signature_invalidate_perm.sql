-- Down migration 052: 移除 signature.invalidate permission
-- 同時清理可能已分配給角色的 role_permissions 紀錄（FK CASCADE 應自動處理，
-- 顯式 DELETE 為防 FK 設計變更時意外保留孤兒 row）。

DELETE FROM role_permissions
    WHERE permission_id IN (
        SELECT id FROM permissions WHERE code = 'signature.invalidate'
    );

DELETE FROM permissions WHERE code = 'signature.invalidate';
