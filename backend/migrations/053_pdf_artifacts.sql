-- ============================================================
-- Migration 053: pdf_artifacts table (R32-A6 / R32 v3)
-- ------------------------------------------------------------
-- 目的：GLP 永久存證每次 PDF 匯出的 artifact，含產出時間 / 產出人 /
-- 對應的 electronic_signature（21 CFR §11.50 「I confirm this PDF
-- represents the official record at time of export」），與 HMAC
-- audit chain 連結。
--
-- 設計參考：
-- - docs/r32-pdf-baseline.md §9（v3 計畫）
-- - 21 CFR §11.50 (signature meanings) + §11.10(c) (record integrity)
-- - GLP §58 audit trail
--
-- 不在本 migration 範圍：
-- - 實際 audit log 寫入 → 由 services/pdf_artifact.rs 在 R32-A4 endpoint
--   呼叫時進行（同 tx 與 INSERT pdf_artifacts atomic）
-- - electronic_signature 產生 → R32-A4 endpoint 呼叫 SignatureService
--   或由使用者按「下載 PDF」時觸發簽章流程（依使用者偏好決定）
-- ============================================================

CREATE TABLE pdf_artifacts (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 資源關聯（對應的業務 entity）
    resource_type               TEXT        NOT NULL,    -- 'protocol' / 'animal_medical' / 'surgery_summary' / 'audit_log' 等
    resource_id                 TEXT        NOT NULL,    -- entity 的 PK；TEXT 而非 UUID 因 audit_log 用 (date_range, filter_hash) 等複合 key

    -- PDF 內容識別
    pdf_blob_hash               TEXT        NOT NULL
                                CHECK (pdf_blob_hash ~ '^[0-9a-f]{64}$'),
                                                          -- SHA-256 hex of PDF binary，DB 層強制 lowercase 64 chars
                                                          -- （服務層另算 + 驗；雙重防護避免手動 SQL / backfill 寫非 canonical 值）
    pdf_size_bytes              BIGINT      NOT NULL CHECK (pdf_size_bytes >= 0),
    doc_type                    TEXT        NOT NULL,    -- pdf-service DOCX_REGISTRY 的 key（如 'medical_record'）

    -- 產出脈絡
    generated_by                UUID        NOT NULL REFERENCES users(id),
    generated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_ip                  INET        NULL,        -- 產出時的客戶端 IP（GLP 稽核需）
    user_agent                  TEXT        NULL,        -- 產出時的瀏覽器 UA

    -- 21 CFR §11 / GLP 對齊
    electronic_signature_id     UUID        NULL REFERENCES electronic_signatures(id),
                                                          -- NULL = 純檢視匯出未要求簽章（如 audit log 列印給內部 review）
                                                          -- NOT NULL = 含簽章（PI / chair 正式提交版本）
    hmac_chain_link             TEXT        NULL,         -- 對應 user_activity_logs.id 的指標，串到 R26 HMAC chain
                                                          -- NULL = 此 artifact 未進 chain（罕見，背景任務批量匯出可能省略）

    -- 附件存放（檔案實體）
    attachment_id               UUID        NULL REFERENCES attachments(id),
                                                          -- 透過既有 attachments 表存實體檔案；NULL = 即時生成不存盤
    storage_strategy            TEXT        NOT NULL DEFAULT 'attachment'
        CHECK (storage_strategy IN ('attachment', 'transient', 's3')),
                                                          -- transient = 不存盤（檔案產出即丟，只留稽核紀錄）；
                                                          -- s3 = 預留未來雲端儲存路徑

    -- Audit 欄位
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pdf_artifacts_attachment_consistency CHECK (
        (storage_strategy = 'attachment' AND attachment_id IS NOT NULL)
        OR (storage_strategy = 'transient' AND attachment_id IS NULL)
        OR (storage_strategy = 's3')
    )
);

-- 查詢索引
-- 複合索引涵蓋 list_artifacts_by_resource 的 WHERE + ORDER BY（避免額外 sort）
CREATE INDEX idx_pdf_artifacts_resource_time
    ON pdf_artifacts (resource_type, resource_id, generated_at DESC);
CREATE INDEX idx_pdf_artifacts_generated_by ON pdf_artifacts (generated_by);
CREATE INDEX idx_pdf_artifacts_generated_at ON pdf_artifacts (generated_at DESC);
CREATE INDEX idx_pdf_artifacts_doc_type ON pdf_artifacts (doc_type);
CREATE INDEX idx_pdf_artifacts_signature ON pdf_artifacts (electronic_signature_id)
    WHERE electronic_signature_id IS NOT NULL;

-- 註解
COMMENT ON TABLE pdf_artifacts IS
    'R32-A6: PDF 匯出永久存證。每次「下載 PDF」按鈕觸發 → 寫一筆。'
    '21 CFR §11.50（signature meaning）+ §11.10(c)（record integrity）對齊。';

COMMENT ON COLUMN pdf_artifacts.pdf_blob_hash IS
    'SHA-256 hex of PDF binary。日後若 PDF 檔案被竄改（手動編輯 / 重新壓縮），'
    '可重算 hash 比對發現不一致 → trigger GLP 警報。';

COMMENT ON COLUMN pdf_artifacts.electronic_signature_id IS
    'NULL = 純檢視匯出（如內部 review 用）；NOT NULL = 含 §11.50 簽章（PI/chair 正式提交版本）。'
    'caller 負責決定是否觸發簽章流程（產 PDF 前先 SignatureService::sign_record_tx）。';

COMMENT ON COLUMN pdf_artifacts.hmac_chain_link IS
    '對應的 user_activity_logs.id（PDF_EXPORT_REQUESTED 事件）。'
    'NULL 罕見 — scheduler / batch 路徑可能省略 chain 寫入，仍保留 artifact 紀錄。';

COMMENT ON COLUMN pdf_artifacts.storage_strategy IS
    'attachment = 透過 attachments 表存盤（預設）；'
    'transient = 不存盤（即時下載即丟）；'
    's3 = 預留未來雲端儲存實作（migration 別處 add column 時實作）。';
