-- 反向 090：移除 PI 帳號開通信追蹤表。
-- 注意：不會還原已建立的 PI 使用者帳號或已 relink 的 protocols.pi_user_id
--（那些屬資料變更，非 schema；dev rollback 場景如需還原請另行處理）。
DROP TABLE IF EXISTS pi_account_invites;
