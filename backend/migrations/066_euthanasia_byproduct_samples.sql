-- R53-1: euthanasia_byproduct_samples 表（廢棄物再利用內部紀錄）
--
-- 背景與框架：豬隻計畫案結案安樂死時，獸醫將會被廢棄處理的組織/血液
-- 再利用給其他研究需求方。**這是廢棄物再利用 (byproduct reuse)，不是
-- PI 資產轉移**：結案豬隻組織本將焚化廢棄，多採只是廢棄物的另一去向，
-- PI 計畫案 deliverables 不受影響。故 PI 看不到去向 = 正常 lifecycle。
--
-- 設計決策（與使用者 2026-05-15 敲定，TODO.md R53 §規格決策）：
--   - 命名 `euthanasia_byproduct_samples`（不用 extra_samples）
--   - 用 animal.id 主鍵（耳號穩定不太可能變動）
--   - requester 支援兩種：FK to users (in-system) 或 free text (external)
--   - source_protocol_id 必填 — 任何採樣都對應到一個結案計畫案
--   - soft delete (deleted_at) — 內部稽核 / GLP 需要保留歷史
--
-- Audit policy（R53-6 配套）：
--   PI viewer audit log 此 entity_type 整類隱形（不只欄位 level redact）。
--   實作在 services/audit.rs 的 viewer-side filter。
--
-- Permission（R53-2 配套）：
--   `animal.byproduct_sample.view` / `animal.byproduct_sample.write`
--   給 VET / QAU / admin；PI / GUEST 不帶。

CREATE TABLE euthanasia_byproduct_samples (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 關聯：哪一筆安樂死、哪一隻動物、哪一個來源計畫案
    euthanasia_id        UUID NOT NULL REFERENCES euthanasia_orders(id) ON DELETE RESTRICT,
    animal_id            UUID NOT NULL REFERENCES animals(id) ON DELETE RESTRICT,
    source_protocol_id   UUID NOT NULL REFERENCES protocols(id) ON DELETE RESTRICT,

    -- 採樣資訊
    sampled_at           TIMESTAMPTZ NOT NULL,
    sample_content       TEXT        NOT NULL,  -- 採樣內容（組織種類 / 血液量 / ...）

    -- 需求方：in-system researcher (requester_user_id) 或 external (requester_text)
    -- 至少一個有值，由 CHECK 強制
    requester_user_id    UUID REFERENCES users(id) ON DELETE RESTRICT,
    requester_text       TEXT,

    -- 採樣者（必為已登入的 vet）
    collector_id         UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    notes                TEXT,

    -- audit 欄位
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by           UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

    -- soft delete
    deleted_at           TIMESTAMPTZ,

    -- 至少 requester_user_id 或 requester_text 其中之一
    CONSTRAINT byproduct_samples_requester_present CHECK (
        requester_user_id IS NOT NULL
        OR (requester_text IS NOT NULL AND length(trim(requester_text)) > 0)
    )
);

-- 索引：查詢通常 by euthanasia / animal / protocol，soft delete 過濾掉
CREATE INDEX idx_byproduct_samples_euthanasia
    ON euthanasia_byproduct_samples(euthanasia_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_byproduct_samples_animal
    ON euthanasia_byproduct_samples(animal_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_byproduct_samples_protocol
    ON euthanasia_byproduct_samples(source_protocol_id) WHERE deleted_at IS NULL;

COMMENT ON TABLE euthanasia_byproduct_samples IS
    'R53-1: 廢棄物再利用紀錄 — 結案豬隻組織/血液多採給其他研究方。PI viewer 不可見此 entity_type。';
COMMENT ON COLUMN euthanasia_byproduct_samples.requester_user_id IS
    'in-system 研究人員 FK。external researcher 用 requester_text，兩欄至少一個有值。';
COMMENT ON COLUMN euthanasia_byproduct_samples.requester_text IS
    'external researcher free text（其他單位研究者）。in-system 用 requester_user_id，兩欄至少一個有值。';
COMMENT ON COLUMN euthanasia_byproduct_samples.collector_id IS
    '採樣者（必須為已登入的 vet 角色，ActorContext::User 強制）。';
