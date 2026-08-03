-- 105: 執行秘書（IACUC_STAFF）計畫內容唯讀 — 移除 edit / submit 授權
--
-- 背景：執秘原持有 aup.protocol.edit / aup.protocol.submit，可代為修改與送出任一計畫；
-- 依原始 spec §4.1（docs/archive/legacy/spec_v2/role.md：執秘「編輯草稿 ✗ / 提交計畫 ✗」）
-- 與使用者裁定，執秘對計畫內容應為唯讀（保留審查指派 / 核准 / 變更狀態等協調權）。
--
-- startup/permissions.rs 的 role_permissions seeding 為 INSERT ... ON CONFLICT DO NOTHING
-- （只補不刪），故已從 seed 清單移除的 edit / submit 不會自動從 DB 撤除，需本 migration 清理。
-- 對應程式側收緊：services/access.rs::can_edit_protocol、handlers/protocol/crud.rs::submit_protocol
-- 已改為僅 admin / PI / SD 放行。

DELETE FROM role_permissions
WHERE role_id IN (
    SELECT id FROM roles WHERE code = 'IACUC_STAFF'
)
AND permission_id IN (
    SELECT id FROM permissions WHERE code IN ('aup.protocol.edit', 'aup.protocol.submit')
);
