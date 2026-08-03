-- Down migration for 047_signature_bridge_sessions
-- 用途：staging rollback；移除 R30-27c bridge session 表。
-- 注意：rollback 後進行中的 bridge session 全部失效（admin 須重新觸發簽章）。
-- WARNING: data loss on down (進行中 sessions 與 audit 軌跡 payload 全部丟失)

DROP INDEX IF EXISTS idx_signature_bridge_sessions_expires_at;
DROP INDEX IF EXISTS idx_signature_bridge_sessions_user_id;
DROP TABLE IF EXISTS signature_bridge_sessions;
