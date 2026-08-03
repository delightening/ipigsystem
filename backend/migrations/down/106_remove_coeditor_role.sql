-- Down 106: 還原 protocol_role enum 的 CO_EDITOR 值。
-- 註：已刪除的 CO_EDITOR 成員列無法復原，僅還原 enum 值本身。

ALTER TYPE protocol_role RENAME TO protocol_role_old;
CREATE TYPE protocol_role AS ENUM ('PI', 'CLIENT', 'CO_EDITOR');
ALTER TABLE user_protocols
    ALTER COLUMN role_in_protocol TYPE protocol_role
    USING role_in_protocol::text::protocol_role;
DROP TYPE protocol_role_old;
