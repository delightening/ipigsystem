-- ============================================================
-- Migration 104: signature_bridge_sessions.payload at-rest 加密（R66-C6）
-- ------------------------------------------------------------
-- 背景：payload（含明文密碼 + 手寫筆跡 SVG + stroke_data）原以 JSONB 明文存。改為
-- app 層 XChaCha20-Poly1305 AEAD 信封字串（"<version>:<base64(nonce‖ct+tag)>"，
-- AAD = session_id ‖ user_id；見 docs/security/AT_REST_ENCRYPTION.md），故欄位型別
-- 由 JSONB 改 TEXT（信封非合法 JSON）。
--
-- 既有 in-flight row：JSONB → TEXT 經 payload::text 轉為明文 JSON 字串（legacy）；
-- consume 端以 is_encrypted_envelope 判別後相容讀取（payload 短效 ≤1hr，多自然汰換）。
-- 本表僅 admin 改權限時短命 session、列數極少 → ALTER 取 ACCESS EXCLUSIVE 鎖瞬時完成。
-- ============================================================

ALTER TABLE signature_bridge_sessions
    ALTER COLUMN payload TYPE TEXT USING payload::text;

COMMENT ON COLUMN signature_bridge_sessions.payload IS
    'AEAD 加密信封（XChaCha20-Poly1305，AAD=session_id‖user_id）的 mutation_signature payload。R66-C6 前為 JSONB 明文。';
