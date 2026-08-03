-- Down for 114: 還原 up 將這些事件由 'both' 改為 'in_app' 的變更（回 seed 原狀 'both'）。
-- 注意：純資料變更。若 up 之後 admin 又調整過 channel，此 down 會覆蓋為 'both'。

UPDATE notification_routing
   SET channel = 'both', updated_at = NOW()
 WHERE channel = 'in_app'
   AND event_type IN (
       'protocol_approved', 'protocol_rejected',
       'amendment_approved', 'amendment_rejected',
       'animal_abnormal_record', 'animal_sudden_death'
   );
