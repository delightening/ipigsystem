-- Down for 110: 移除通知路由的 resolver 目標欄位，還原 role_code 約束與原唯一鍵。
-- WARNING: data loss on down（resolver 型路由列 role_code 為 NULL，還原 NOT NULL 前需先刪除）

DROP INDEX IF EXISTS idx_notification_routing_event_target;
ALTER TABLE notification_routing DROP CONSTRAINT IF EXISTS uq_nr_event_target;

-- resolver 列 role_code 為 NULL，還原 NOT NULL / FK 前須先移除
DELETE FROM notification_routing WHERE target_kind = 'resolver';

ALTER TABLE notification_routing DROP COLUMN IF EXISTS target_value;
ALTER TABLE notification_routing DROP COLUMN IF EXISTS target_kind;

ALTER TABLE notification_routing ALTER COLUMN role_code SET NOT NULL;
-- role_code → roles(code) 外鍵未被 up 移除（保留），故 down 不需重建。
ALTER TABLE notification_routing
    ADD CONSTRAINT notification_routing_event_type_role_code_key
    UNIQUE (event_type, role_code);
