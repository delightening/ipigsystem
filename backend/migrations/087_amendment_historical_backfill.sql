-- 087: 補登歷史變更申請（Amendment Import Backfill）P6-1 — schema 基礎
--
-- 背景：補登匯入的舊計劃（import_approved）能開新的 live 變更申請，但「紙本世界
-- 早已核准過的歷史變更」（變更第 1 號、第 2 號…）無處補登。本計畫新增一條補登路徑，
-- 平行 import P1–P5：跳過 live 審查、回填原始日期、不產生 live 電子簽章、直接落 EFFECTIVE。
--
-- 本 migration 僅鋪 schema 基礎（P6-1）：
--   1. amendments.is_historical — 補登歷史變更標記
--   2. protocols.imported_at    — 永久「匯入計劃」標記（與暫態 import_pending 區分），
--      作為補登歷史變更的 gate；既有 prod imports 由 audit log 回填。

-- ── amendments：歷史補登標記 ──────────────────────────────────
ALTER TABLE amendments
    ADD COLUMN is_historical BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN amendments.is_historical IS
  '補登歷史變更（紙本核准回溯）：跳過 live 審查、可由 DRAFT 直接 finalize 至 EFFECTIVE、approved/rejected_signature_id 維持 NULL（無 live 電子簽章）';

-- ── protocols：永久 imported 標記 ─────────────────────────────
ALTER TABLE protocols
    ADD COLUMN imported_at TIMESTAMPTZ;

COMMENT ON COLUMN protocols.imported_at IS
  'import_approved 建立時間；非 NULL = 補登匯入計劃（永久標記，與暫態 import_pending 區分）。補登歷史變更僅允許於此類計劃';

-- 既有 prod imports 回填 imported_at：取最早一筆 PROTOCOL_IMPORT_APPROVED audit 事件時間。
-- entity_type='protocol' + entity_id=protocol.id（user_activity_logs 為分離欄位，非 JSON）。
UPDATE protocols p
SET imported_at = sub.ts
FROM (
    SELECT entity_id AS protocol_id, MIN(created_at) AS ts
    FROM user_activity_logs
    WHERE event_type = 'PROTOCOL_IMPORT_APPROVED'
      AND entity_type = 'protocol'
      AND entity_id IS NOT NULL
    GROUP BY entity_id
) sub
WHERE p.id = sub.protocol_id
  AND p.imported_at IS NULL;
