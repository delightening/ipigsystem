-- R46-1/2: refresh_token reuse detection 降噪所需欄位
--
-- 背景：services/auth/session.rs::handle_refresh_token_reuse 目前對所有
-- 「revoked token 再次出現」一律觸發 family revoke + critical security_alert，
-- 但實際運行多數為 race condition（多分頁同時 refresh）或 browser bug，
-- 告警價值被稀釋。R46 引入兩條啟發式 — race window grace period（≤5s）
-- 與同 IP/UA 降級（critical → warning）— 兩者都需要 refresh_tokens 額外
-- metadata 才能判斷。
--
-- 欄位語意：
--
-- - rotated_at：normal_rotation 撤銷時的時間戳（與 revoked_at 同值，但語意
--   專指「正常輪替」而非泛指撤銷）。reuse detection 時用
--   `now() - rotated_at <= 5s` 判定 race，避開 revoked_reason 字串比對。
--   非 normal_rotation 撤銷（reuse_detected / idle_timeout / password_changed
--   等）保持 NULL，自動排除於 race window 判定外。
--
-- - last_ip / last_user_agent：rotation 當下 client 的 IP / User-Agent。
--   reuse 真案發生時比對 reused request 的 IP/UA：相同 → 同裝置（browser bug
--   或重送），severity 降為 warning；不同 → 疑似 token 外流，維持 critical。
--   既有 row backfill NULL；NULL 視為「資料不足，無法降級」維持 critical（fail-safe）。
--
-- 既有資料：所有現有 row 三欄皆 NULL。對未來 rotation 流程透明 — 新 rotation
-- 寫入新值，舊 token reuse 仍走 critical 路徑（NULL last_ip 不等於當前 IP）。
--
-- 不加 index：欄位僅在 reuse detection 時讀取（單列 SELECT by token_hash
-- 或 family_id），現有 idx_refresh_tokens_family_id 已涵蓋。

-- 注意 last_ip 用 TEXT 而非 INET：sqlx 未啟用 ipnetwork feature，且本表用途
-- 為 equality 比對（reuse 時對照當前請求 IP 字串），不需 CIDR / range operations。
-- 未來若需要 INET 語意（網段比對、地理查詢）再 ALTER 升級。
ALTER TABLE refresh_tokens
    ADD COLUMN rotated_at      TIMESTAMPTZ,
    ADD COLUMN last_ip         TEXT,
    ADD COLUMN last_user_agent TEXT;

COMMENT ON COLUMN refresh_tokens.rotated_at IS
    'R46-1: normal_rotation 撤銷時的時間戳。reuse detection 時用於 race window 判定（≤5s 視為併發 race，不觸發 family revoke）。';
COMMENT ON COLUMN refresh_tokens.last_ip IS
    'R46-2: rotation 當下 client IP。reuse 真案時與當前 request IP 比對，相同則 severity 降為 warning。';
COMMENT ON COLUMN refresh_tokens.last_user_agent IS
    'R46-2: rotation 當下 client User-Agent。reuse 真案時與當前 request UA 比對，相同則 severity 降為 warning。';
