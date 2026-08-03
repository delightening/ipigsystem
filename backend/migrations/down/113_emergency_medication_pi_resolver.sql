-- Down for 113: 移除 emergency_medication 的 protocol_pi resolver 列。

DELETE FROM notification_routing
 WHERE event_type = 'emergency_medication'
   AND target_kind = 'resolver'
   AND target_value = 'protocol_pi';
