-- ============================================================
-- Migration 110: 通知路由支援「關係型收件人解析器」目標（P0 統一派送骨架）
--
-- 目標：邁向「零寫死通知」——每個事件、每個收件人來源都在 notification_routing
-- 宣告。除了既有的「角色型」(target_kind='role') 收件人，新增「解析器型」
-- (target_kind='resolver') 以表達關係型對象（例：這張假單的申請人、這個計畫的 PI）。
--
-- 本 migration 僅擴充 schema 並回填，不改任何既有列的行為（皆為 role 型）。
-- 詳見 docs/design/features/notification-routing-unification-feasibility-2026-06-26.md
-- ============================================================

-- 1. 新增目標欄位
ALTER TABLE notification_routing
    ADD COLUMN IF NOT EXISTS target_kind  VARCHAR(20) NOT NULL DEFAULT 'role'
        CONSTRAINT chk_nr_target_kind CHECK (target_kind IN ('role', 'resolver')),
    ADD COLUMN IF NOT EXISTS target_value VARCHAR(80);

-- 2. 回填既有列：皆為角色型，target_value = role_code
UPDATE notification_routing SET target_value = role_code WHERE target_value IS NULL;
ALTER TABLE notification_routing ALTER COLUMN target_value SET NOT NULL;

-- 3. 放寬 role_code：resolver 型列無對應角色（NULL）。
--    （保留 role_code 欄供既有 get_recipients_by_event 等舊路徑過渡期使用。）
ALTER TABLE notification_routing ALTER COLUMN role_code DROP NOT NULL;

-- 4. 保留 role_code → roles(code) 外鍵：resolver 列 role_code 為 NULL（FK 不檢查 NULL），
--    角色型列仍維持對 roles.code 的參照完整性（避免角色刪除/改名後 orphan 角色型路由）。

-- 5. 唯一鍵改以 target 表達：允許 resolver 列，仍防同事件同目標重複。
--    舊唯一鍵 (event_type, role_code) 對 resolver 列（role_code NULL）天然相容（NULL 互異），
--    留著無害；新增以 target 為準的唯一鍵作為主要約束。
ALTER TABLE notification_routing
    ADD CONSTRAINT uq_nr_event_target UNIQUE (event_type, target_kind, target_value);

CREATE INDEX IF NOT EXISTS idx_notification_routing_event_target
    ON notification_routing(event_type, is_active, target_kind);

COMMENT ON COLUMN notification_routing.target_kind  IS 'role=持有該角色者; resolver=關係型收件人解析器（key 見 services/notification/resolvers.rs）';
COMMENT ON COLUMN notification_routing.target_value IS 'target_kind=role 時為 roles.code；target_kind=resolver 時為 resolver key';
