-- Rollback migration 143（通知的 kind 欄位）。
--
-- 回退後前端的「待處理」入口會查不到 kind 欄位而 500，故僅供
-- 「連同 code 一起回退」的 staging / dev 情境；prod 採 forward-only。
--
-- 資料不會遺失：kind 是新增欄位，priority 仍保有「這則待辦未完成」的資訊。

DROP INDEX IF EXISTS idx_notifications_action_pending;

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notifications_kind;

ALTER TABLE notifications DROP COLUMN IF EXISTS kind;
