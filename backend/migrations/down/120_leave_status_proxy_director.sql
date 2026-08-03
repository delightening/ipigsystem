-- IRREVERSIBLE: PostgreSQL 無法安全移除 enum 值（一旦被任何列引用即無法 DROP）。
-- 如需回退，請改用「將引用列遷回舊值」的資料修正（見 down/121），enum 值本身留存無害。
SELECT 1;
