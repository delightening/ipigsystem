-- R35-15: refresh token rotation + reuse detection
--
-- 既有 rotation 已實作（services/auth/session.rs 撤銷舊 token + 發新 token），
-- 本 migration 補上 reuse detection 必要的 schema：
--
-- - family_id: 同一登入鏈的所有 token 共享。reuse 觸發時 WHERE family_id = $1
--              整族撤銷，避免 attacker 拿到鏈中任一 token 後繼續橫移。
-- - revoked_reason: 區分撤銷原因（normal_rotation / reuse_detected /
--                   password_changed / admin_logout 等），便於 audit 與除錯。
--
-- 既有 token 背填策略：family_id = id（每個既有 token 各自獨立 family，
-- 後續 refresh 時新 token 加入相同 family）。對使用者透明，無需強制重登。

ALTER TABLE refresh_tokens ADD COLUMN family_id UUID;
UPDATE refresh_tokens SET family_id = id WHERE family_id IS NULL;
ALTER TABLE refresh_tokens ALTER COLUMN family_id SET NOT NULL;

ALTER TABLE refresh_tokens ADD COLUMN revoked_reason TEXT;

-- family revoke 走 WHERE family_id = $1，需 index 避免 table scan
CREATE INDEX idx_refresh_tokens_family_id ON refresh_tokens(family_id);
