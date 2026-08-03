-- 077_log_activity_suspicious_flag.sql
-- R28-5 follow-up：log_activity 加 p_is_suspicious 參數，讓 SECURITY 事件（失敗登入 /
-- 帳號鎖定 / 權限拒絕 / honeypot 等）能在走 HMAC chain 的同時保留 is_suspicious=true +
-- event_severity='warning' + suspicious_reason。
--
-- 背景：R28-5 把 log_security_event* 從直接 INSERT 改走 log_activity_tx（HMAC chain），
-- 但 stored proc 不設這三欄 → 退回 schema 預設（info / false / NULL），admin「只看可疑」
-- 篩選會漏掉真正的安全事件。修法用顯式 bool flag（只由 log_security_event* 傳 true），
-- 不用 event_category 判斷（因 SECURITY 分類也含改密碼 / 開權限等正常操作，會誤標）。
--
-- 這三欄不在 HMAC input 內（見 HmacInput），故不影響 chain 完整性。

DROP FUNCTION IF EXISTS log_activity(
    UUID, VARCHAR, VARCHAR, VARCHAR, UUID, VARCHAR,
    JSONB, JSONB, INET, TEXT, UUID, TEXT[]
);

CREATE FUNCTION log_activity(
    p_actor_user_id    UUID,
    p_event_category   VARCHAR(50),
    p_event_type       VARCHAR(100),
    p_entity_type      VARCHAR(50),
    p_entity_id        UUID,
    p_entity_display_name VARCHAR(255),
    p_before_data      JSONB   DEFAULT NULL,
    p_after_data       JSONB   DEFAULT NULL,
    p_ip_address       INET    DEFAULT NULL,
    p_user_agent       TEXT    DEFAULT NULL,
    p_impersonated_by_user_id UUID   DEFAULT NULL,
    p_changed_fields   TEXT[]  DEFAULT NULL,
    p_is_suspicious    BOOLEAN DEFAULT false
) RETURNS UUID AS $$
DECLARE
    v_id                 UUID;
    v_actor_email        VARCHAR(255);
    v_actor_display_name VARCHAR(100);
    v_actor_roles        JSONB;
    v_changed_fields     TEXT[];
BEGIN
    SELECT email, display_name
    INTO   v_actor_email, v_actor_display_name
    FROM   users WHERE id = p_actor_user_id;

    SELECT jsonb_agg(r.code)
    INTO   v_actor_roles
    FROM   user_roles ur
    JOIN   roles r ON ur.role_id = r.id
    WHERE  ur.user_id = p_actor_user_id;

    -- changed_fields 來源優先級（同 migration 036，R26-5 修正）：
    --   1. app 層提供 → 直接用
    --   2. before/after 都有 → 取聯集中值不同者
    --   3. 其他 → NULL
    IF p_changed_fields IS NOT NULL THEN
        v_changed_fields := p_changed_fields;
    ELSIF p_before_data IS NOT NULL AND p_after_data IS NOT NULL THEN
        IF jsonb_typeof(p_before_data) = 'object' AND jsonb_typeof(p_after_data) = 'object' THEN
            SELECT array_agg(DISTINCT key ORDER BY key)
            INTO   v_changed_fields
            FROM (
                SELECT jsonb_object_keys(p_before_data) AS key
                UNION
                SELECT jsonb_object_keys(p_after_data) AS key
            ) all_keys
            WHERE  (p_before_data->key) IS DISTINCT FROM (p_after_data->key);
        END IF;
    END IF;

    INSERT INTO user_activity_logs (
        actor_user_id, actor_email, actor_display_name, actor_roles,
        event_category, event_type, event_severity,
        entity_type, entity_id, entity_display_name,
        before_data, after_data, changed_fields,
        ip_address, user_agent,
        impersonated_by_user_id,
        is_suspicious, suspicious_reason
    ) VALUES (
        p_actor_user_id, v_actor_email, v_actor_display_name, v_actor_roles,
        p_event_category, p_event_type,
        CASE WHEN p_is_suspicious THEN 'warning' ELSE 'info' END,
        p_entity_type, p_entity_id, p_entity_display_name,
        p_before_data, p_after_data, v_changed_fields,
        p_ip_address, p_user_agent,
        p_impersonated_by_user_id,
        p_is_suspicious,
        CASE WHEN p_is_suspicious THEN 'Security event: ' || COALESCE(p_event_type, '') ELSE NULL END
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_activity IS
    'v4 (R28-5 follow-up): 加 p_is_suspicious — SECURITY 事件走 HMAC chain 時保留
     is_suspicious / event_severity=warning / suspicious_reason。沿用 v3 changed_fields 修正。';
