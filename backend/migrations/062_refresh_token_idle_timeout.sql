-- R41-1: Backend idle session enforcement
--
-- 增加 `last_used_at` 欄位記錄每個 refresh token 的最後活動時間。
-- 後續 refresh 流程會檢查 `now - last_used_at > AUTH_IDLE_TIMEOUT_MINUTES`，
-- 超過閾值則 reject refresh（強制使用者重新登入），對齊 NICS 附表十普級
-- 「存取控制 / 帳號管理」閒置鎖定要求。
--
-- 既有 token 背填策略：所有現有 row 設為 NOW()，視為「剛使用過」—
-- migration 部署當下不會立即把使用者踢出（避免遷移瞬間造成大量登入失效）。
-- 後續 refresh 才會開始強制執行閒置檢查。

ALTER TABLE refresh_tokens
    ADD COLUMN last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- 索引：refresh 流程已 WHERE token_hash = $1 取單行，不需 last_used_at 索引；
-- 但若未來想做 ops 查詢「閒置中的 session」則可加。本 PR 不加，避免無謂索引。
