-- P1-34: amendments 表加 optimistic locking version 欄位
--
-- animals / protocols / euthanasia_orders / euthanasia_appeals 已有 version 欄位且 service 層已檢查。
-- amendments 是唯一缺少 version 的可並行編輯表。
--
-- 模式：UPDATE ... SET version = version + 1 WHERE id = $1 AND version = $N
--       命中 0 row → 409 Conflict（另一使用者已先修改）

ALTER TABLE amendments
    ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
