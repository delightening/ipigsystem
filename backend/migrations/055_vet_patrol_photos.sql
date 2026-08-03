-- 獸醫巡場報告：照片附件 + 解說
CREATE TABLE IF NOT EXISTS vet_patrol_photos (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id     UUID        NOT NULL REFERENCES vet_patrol_reports(id) ON DELETE CASCADE,
    file_name     VARCHAR(255) NOT NULL,
    file_path     TEXT         NOT NULL,
    file_size     BIGINT       NOT NULL,
    mime_type     VARCHAR(100) NOT NULL,
    caption       TEXT         NOT NULL DEFAULT '',
    sort_order    INT          NOT NULL DEFAULT 0,
    created_by    UUID         REFERENCES users(id),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vet_patrol_photos_report ON vet_patrol_photos(report_id);
