-- Down migration 104: signature_bridge_sessions.payload TEXT → JSONB（R66-C6 rollback）
-- WARNING: 加密信封非合法 JSON，rollback 無法還原為原 JSON → 既有 payload 一律清為 NULL
-- （in-flight session 需重新簽署）。對齊 049 down 的 data-loss-on-down 立場；payload 短效
-- （≤1hr）、影響極小。

ALTER TABLE signature_bridge_sessions
    ALTER COLUMN payload TYPE JSONB USING NULL::jsonb;

COMMENT ON COLUMN signature_bridge_sessions.payload IS
    '手機 submit 的 mutation_signature payload（password + handwriting_svg + stroke_data）。';
