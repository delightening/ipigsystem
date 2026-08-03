-- R63-B2: 收窄 grafana_readonly 的 DEFAULT PRIVILEGES
-- migration 032 用 ALTER DEFAULT PRIVILEGES 授權所有未來表的 SELECT，
-- 包括 refresh_tokens、passwords 等敏感表。改為只授權特定稽核相關表。
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE SELECT ON TABLES FROM grafana_readonly;
