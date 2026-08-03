-- 計畫書範本版本登記（院區層級，admin 管理）。
-- 記錄整個「計畫書範本 / 申請表單 + SOP」的版本歷程；每個版本可上傳對應的
-- 現行 SOP 與表單文件（沿用 attachments，entity_type='protocol_template_version'）。
-- 與個別計劃的 protocol_versions（內容快照）無關；個別計劃以 original_version_label
-- 文字對應到此登記簿。

CREATE TABLE protocol_template_versions (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    version_label  TEXT        NOT NULL UNIQUE,
    effective_date DATE,
    is_current     BOOLEAN     NOT NULL DEFAULT false,
    notes          TEXT,
    created_by     UUID        NOT NULL REFERENCES users(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 至多一個「現行版本」：is_current=true 的列僅能有一筆。
CREATE UNIQUE INDEX idx_protocol_template_versions_current
    ON protocol_template_versions (is_current)
    WHERE is_current = true;
