-- Rollback migration 116: 移除職務代理人通知路由
DELETE FROM notification_routing
 WHERE event_type IN ('leave_proxy_assigned', 'leave_proxy_effective')
   AND target_kind = 'resolver' AND target_value = 'event_subject';
