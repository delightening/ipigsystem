-- 還原 080：重建 protocol_status_history（結構同 migration 007）。
-- 註：此表向來為空，重建後亦無資料；僅供 schema rollback 演練。
CREATE TABLE IF NOT EXISTS protocol_status_history (
    id          UUID            PRIMARY KEY,
    protocol_id UUID            NOT NULL REFERENCES protocols(id) ON DELETE CASCADE,
    from_status protocol_status,
    to_status   protocol_status NOT NULL,
    changed_by  UUID            NOT NULL REFERENCES users(id),
    remark      TEXT,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_protocol_status_history_protocol_id ON protocol_status_history(protocol_id);
