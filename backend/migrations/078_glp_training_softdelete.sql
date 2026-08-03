-- R63-A3: role_training_requirements hard DELETE → soft-delete
-- GLP §11.10(e) 禁止遮蔽舊紀錄
-- 編號 075→078：避開已合併的 075_grafana（GIN index 076 / suspicious flag 077 之後）

ALTER TABLE role_training_requirements
    ADD COLUMN deleted_at TIMESTAMPTZ;

-- soft-delete 後，原 UNIQUE(role_code, training_topic) 會擋住「軟刪除後重新加入同一筆」
-- （被軟刪的列仍佔用唯一鍵）。改為僅在 active（未刪除）列上強制唯一。
ALTER TABLE role_training_requirements
    DROP CONSTRAINT IF EXISTS role_training_requirements_role_code_training_topic_key;

CREATE UNIQUE INDEX idx_training_requirements_active
    ON role_training_requirements (role_code, training_topic)
    WHERE deleted_at IS NULL;
