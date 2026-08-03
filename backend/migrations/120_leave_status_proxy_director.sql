-- 請假流程重設計：新增兩個審核狀態。
--   PENDING_PROXY    ：代理人確認（送審後第一關）
--   PENDING_DIRECTOR ：負責人簽核（單位主管之上的終審關）
--
-- PostgreSQL 16 允許在交易區塊內 ADD VALUE（sqlx::migrate! 每支 migration 包一個交易），
-- 但**同一交易內不可引用**新加入的 enum 值。故「既有列狀態遷移」置於下一支 migration（121），
-- 確保新值已 commit 後才被 UPDATE 使用。
ALTER TYPE leave_status ADD VALUE IF NOT EXISTS 'PENDING_PROXY';
ALTER TYPE leave_status ADD VALUE IF NOT EXISTS 'PENDING_DIRECTOR';
