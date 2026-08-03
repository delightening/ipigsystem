-- Down for 111: 移除 review_comment_created 的 protocol_pi_sd resolver 列。

DELETE FROM notification_routing
 WHERE event_type = 'review_comment_created'
   AND target_kind = 'resolver'
   AND target_value = 'protocol_pi_sd';
