-- 動物試驗申請須知（全院共用一份 + 版次制）+ 申請人簽署紀錄。
-- 緣由：舊計劃書匯入盤點發現系統缺「申請須知簽署」結構（實體歸檔每計劃皆有
--      「2-申請須知簽名檔」）。見 docs/design/application-notice-acknowledgement-design.md。
-- 範圍：本 migration 僅建 schema（PR-A）。簽署 service / `signature_meaning` 的
--      ACKNOWLEDGE 值（HMAC 步驟）/ 送審驗證 / 前端，皆於後續 PR。

-- 1) 須知版本（全院共用一份 + 版次，如「2019年9月修訂版」）
CREATE TABLE application_notices (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    version_label  TEXT        NOT NULL UNIQUE,
    title          TEXT        NOT NULL,
    -- 須知正文（markdown），顯示給申請人線上閱讀
    content        TEXT        NOT NULL,
    -- 選填：原始 PDF/docx 正本留底（沿用 attachments）
    attachment_id  UUID        REFERENCES attachments(id),
    effective_from DATE        NOT NULL,
    is_active      BOOLEAN     NOT NULL DEFAULT false,
    created_by     UUID        NOT NULL REFERENCES users(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 同時至多一個「生效版本」：is_active=true 的列僅能有一筆。
CREATE UNIQUE INDEX idx_application_notices_active
    ON application_notices (is_active)
    WHERE is_active = true;

-- 2) 申請人簽署紀錄（一計劃一筆，重簽 = upsert）
CREATE TABLE protocol_notice_acknowledgements (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- 一計劃一筆；計劃硬刪時連帶刪（scaffold）
    protocol_id          UUID        NOT NULL UNIQUE REFERENCES protocols(id) ON DELETE CASCADE,
    notice_id            UUID        NOT NULL REFERENCES application_notices(id),
    signer_id            UUID        NOT NULL REFERENCES users(id),
    -- 手寫電子簽章；匯入舊計劃可空（方案 A：改掛紙本掃描，見設計 §5.2）
    signature_id         UUID        REFERENCES electronic_signatures(id),
    -- 匯入舊計劃的紙本須知簽名掃描（方案 A）
    notice_attachment_id UUID        REFERENCES attachments(id),
    acknowledged_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 「依須知版本撈簽署」合規報表用
CREATE INDEX idx_notice_ack_notice ON protocol_notice_acknowledgements (notice_id);
