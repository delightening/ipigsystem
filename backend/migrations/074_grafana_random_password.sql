-- CSO audit 2026-05-27: migration 032 使用了 hardcoded placeholder 密碼。
-- 若 grafana_readonly role 密碼仍為 'CHANGE_ME_AT_DEPLOY'，改為隨機 64 字元密碼。
-- 實際 Grafana 連線應透過 Docker Secrets 中的 grafana_pg_password 設定。
DO $$
DECLARE
    _random_pw TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_readonly') THEN
        _random_pw := md5(random()::text || clock_timestamp()::text)
                   || md5(random()::text || clock_timestamp()::text);
        EXECUTE format('ALTER ROLE grafana_readonly PASSWORD %L', _random_pw);
        RAISE NOTICE 'grafana_readonly password rotated (use Docker Secret to set the actual password)';
    END IF;
END
$$;
