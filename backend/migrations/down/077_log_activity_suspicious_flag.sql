-- down: 077_log_activity_suspicious_flag
-- 還原為 migration 036 的 v3 版本（12 參數，無 p_is_suspicious）。
DROP FUNCTION IF EXISTS log_activity(
    UUID, VARCHAR, VARCHAR, VARCHAR, UUID, VARCHAR,
    JSONB, JSONB, INET, TEXT, UUID, TEXT[], BOOLEAN
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
    p_changed_fields   TEXT[]  DEFAULT NULL
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
        event_category, event_type,
        entity_type, entity_id, entity_display_name,
        before_data, after_data, changed_fields,
        ip_address, user_agent,
        impersonated_by_user_id
    ) VALUES (
        p_actor_user_id, v_actor_email, v_actor_display_name, v_actor_roles,
        p_event_category, p_event_type,
        p_entity_type, p_entity_id, p_entity_display_name,
        p_before_data, p_after_data, v_changed_fields,
        p_ip_address, p_user_agent,
        p_impersonated_by_user_id
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
