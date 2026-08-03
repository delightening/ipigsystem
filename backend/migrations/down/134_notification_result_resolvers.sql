-- Down for 134: 移除審核結果回通知的三個 resolver 列。

DELETE FROM notification_routing
 WHERE target_kind = 'resolver'
   AND target_value = 'event_subject'
   AND event_type IN (
       'equipment_disposal_result',
       'equipment_maintenance_result',
       'leave_rejected'
   );
