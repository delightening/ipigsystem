-- down: 075_grafana_revoke_default_privileges
-- 還原 grafana_readonly 的 DEFAULT PRIVILEGES（回到 migration 032 的狀態）
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO grafana_readonly;
