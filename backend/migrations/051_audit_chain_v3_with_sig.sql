-- ============================================================
-- Migration 051: audit chain v3 with signature fingerprint (R30-9a)
-- ------------------------------------------------------------
-- 目的：把 entity_type / entity_id / extra_input 三個欄位納入 HMAC chain
-- hash 計算，修補 v2 chain 的 entity gap（攻擊者若有 DB 寫權限可改 entity_id
-- 不破壞 chain hash），並讓 SIGNATURE_CREATE / SIGNATURE_INVALIDATED 事件能
-- 額外綁定 sig fingerprint（防偽造簽章逃過 chain 偵測）。
--
-- ⚠️ **不可逆 migration** — 一旦 v3 row 寫入：
-- - verifier 必須同時支援 v1 / v2 / v3 三種編碼公式
-- - 移除 extra_input 欄位 = 破壞所有 v3 row 的 chain 完整性
--
-- Backfill 策略：
-- - 既有 row：extra_input = NULL（v2 row 不使用此欄位）
-- - 新 row：依 event_type 路由
--   - SIGNATURE_CREATE / SIGNATURE_INVALIDATED → v3 + extra_input (sig_id:hash)
--   - 其他 event → v2（保留現狀，extra_input = NULL）
--
-- 漸進升級：未來其他 event_type 升 v3 為各別 forward migration（同樣不可逆）
--
-- Design doc: docs/design/r30-9-signature-audit-chain.md §3
-- ============================================================

-- 加 extra_input 欄位（hmac_version 已存在於 migration 037）
ALTER TABLE user_activity_logs
    ADD COLUMN IF NOT EXISTS extra_input TEXT NULL;

COMMENT ON COLUMN user_activity_logs.extra_input IS
    'R30-9a: HMAC chain v3 額外輸入。SIGNATURE_CREATE: <sig_id>:<content_hash>; '
    'SIGNATURE_INVALIDATED: <sig_id>:<invalidated_reason>（原始字串，非 hash）. '
    'v2 row 為 NULL（不參與 hash 計算）';

-- hmac_version 註解更新：補上 v3 說明
COMMENT ON COLUMN user_activity_logs.hmac_version IS
    'HMAC chain hash 編碼版本: '
    '1 = legacy string-concat (pre-R26-6, 已棄寫)；'
    '2 = length-prefix canonical (R26-6 SDD)；'
    '3 = v3 含 entity_type / entity_id / extra_input (R30-9a SIGNATURE_*)';
