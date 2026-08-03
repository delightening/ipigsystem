-- ============================================================
-- Migration 114: 將 dispatch 驅動事件的誤導性 'both' channel 改回 'in_app'（P3-1）
--
-- 這些事件經 dispatch_event 派送，而 dispatch_event 目前只建站內通知、不寄 email
-- （email 能力於 P3-2 才接上）。其 seed channel='both' 從未真正寄信，屬誤導。
-- 改回 in_app 讓路由頁設定誠實反映實際行為；email 改為「admin 之後逐一開」（opt-in），
-- 對齊使用者決策（先不主動開 email）。
--
-- 注意：equipment_* 仍維持 'both'——其 email 走 equipment.rs 自身路徑（尚未遷移 dispatch），
-- 確實會寄信，故不在此重置。
-- ============================================================

UPDATE notification_routing
   SET channel = 'in_app', updated_at = NOW()
 WHERE channel = 'both'
   AND event_type IN (
       'protocol_approved', 'protocol_rejected',
       'amendment_approved', 'amendment_rejected',
       'animal_abnormal_record', 'animal_sudden_death'
   );
