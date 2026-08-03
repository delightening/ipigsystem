-- ============================================================
-- Migration 049: signature_bridge_sessions（R30-27c 桌機↔手機簽名 bridge）
-- 原 047 與 PR #296 047_blood_test_items_correction.sql 同 prefix collision；
-- 重編為 049（PR #300 用 048）。檔案內容不變。
-- ------------------------------------------------------------
-- 目的：admin 在桌機觸發 role/permission 變更，跳出 QR 由手機掃描後完成簽名，
-- payload 透過此表回傳桌機。對應 21 CFR §11.10(d) — 簽章不可否認性，
-- 同時改善桌機滑鼠手寫困難的 UX 痛點。
--
-- 流程（R30-27c-1 backend）：
--   1. 桌機 dialog → POST /signing-bridge/start (auth)
--      → INSERT row、回傳 session_id + mobile_token (5 分鐘 TTL、單次使用)
--   2. 手機掃 QR → 開 /sign/:session_id?token=... (公開 page，token-bearer 認證)
--      → 完成簽名 → POST /signing-bridge/:id/submit
--      → token bcrypt 驗證 → 寫 payload + status='COMPLETED'
--   3. 桌機輪詢 GET /signing-bridge/:id/status (auth, owner-only)
--      → status 變 COMPLETED → 取 payload → 串入 mutation_signature 送出
--
-- Status:
--   PENDING   — 已 start，等待手機 submit
--   COMPLETED — 手機 submit 完成，桌機尚未取走 payload
--   CONSUMED  — 桌機取走 payload，session 失效
--   EXPIRED   — TTL 過期（cron 定期清；status 由桌機讀取時 lazy 更新）
-- ============================================================

CREATE TABLE IF NOT EXISTS signature_bridge_sessions (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- 發起者 user_id；status 端點僅允許 owner 取 payload
    user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- mobile_token bcrypt hash（不存 plaintext）；submit 端點 verify
    mobile_token_hash VARCHAR(255) NOT NULL,
    -- 此次簽章的目的（純 audit / debug 用）：'role.create' / 'role.update' / 'role.delete'
    purpose         VARCHAR(50)  NOT NULL,
    -- 手機 submit 後存的 payload（含 password / handwriting_svg / stroke_data）
    -- payload 為 ciphertext-at-rest 的 JSON；本 PR 暫存 plaintext JSON，後續加 column 級加密
    payload         JSONB,
    status          VARCHAR(20)  NOT NULL DEFAULT 'PENDING'
                       CHECK (status IN ('PENDING', 'COMPLETED', 'CONSUMED', 'EXPIRED')),
    expires_at      TIMESTAMPTZ  NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- payload 寫入時間（手機 submit 那刻）
    submitted_at    TIMESTAMPTZ,
    -- payload 取走時間（桌機 status 讀到 COMPLETED → 改 CONSUMED 那刻）
    consumed_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_signature_bridge_sessions_user_id
    ON signature_bridge_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_signature_bridge_sessions_expires_at
    ON signature_bridge_sessions(expires_at)
    WHERE status = 'PENDING';

COMMENT ON TABLE signature_bridge_sessions IS
    'R30-27c：桌機 ↔ 手機簽名 bridge session。短命（5min TTL）+ 單次使用，避免 QR 截圖被回放。';
COMMENT ON COLUMN signature_bridge_sessions.mobile_token_hash IS
    'bcrypt hash of mobile_token（plaintext 只在 start 端點當下回給桌機，桌機編入 QR 給手機）。';
COMMENT ON COLUMN signature_bridge_sessions.payload IS
    '手機 submit 的 mutation_signature payload（password + handwriting_svg + stroke_data）。';
