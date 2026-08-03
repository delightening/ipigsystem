-- CSO #3: TOTP 防重放 — 記錄每用戶最後成功驗證的 TOTP 時間步（time-step）。
-- 問題：verify_totp_code 用 check_current（±1 step ≈ 90s 窗）且不追蹤已用碼，
-- 攔截到的有效碼可在窗內重複認證，破壞 TOTP 一次性。
-- 修法：登入 2FA 成功時記錄該碼的 time-step；後續登入拒絕 step <= 已記錄者。
--
-- 註：本檔原規劃 079，但 079 已由未合併的 feat/historical-records 佔用，改用 080
-- 避免號碼衝突（對齊 047/049 collision 先例）。
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_totp_step BIGINT;

COMMENT ON COLUMN users.last_totp_step IS
    'CSO #3：最後成功驗證的 TOTP time-step（unix_time / period）。登入 2FA 拒絕 step <= 此值，防同窗重放。';
