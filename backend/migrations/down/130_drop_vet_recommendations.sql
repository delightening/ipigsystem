-- 還原 130：重建 vet_recommendations 表（空表；原功能已退役、無資料回填）。
-- 對齊 006_animal_management.sql 的原始 DDL。
CREATE TABLE IF NOT EXISTS vet_recommendations (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    record_type vet_record_type NOT NULL,
    record_id   UUID          NOT NULL,
    content     TEXT          NOT NULL,
    urgency     VARCHAR(20)   DEFAULT 'normal',
    is_urgent   BOOLEAN       NOT NULL DEFAULT false,
    attachments JSONB,
    created_by  UUID          REFERENCES users(id),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_urgency CHECK (urgency IN ('normal', 'urgent', 'critical'))
);
CREATE INDEX IF NOT EXISTS idx_vet_recommendations_record ON vet_recommendations(record_type, record_id);
