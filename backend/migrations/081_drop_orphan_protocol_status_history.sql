-- 移除孤兒表 protocol_status_history：自 migration 007 建立後從未有任何寫入端，
-- 唯二讀取端（qau 狀態變更指標、GDPR data_export 清單）均已改接 protocol_activities，
-- 此表恆為空表，無保留價值。實際的計畫狀態時間軸由 protocol_activities 承載。
DROP TABLE IF EXISTS protocol_status_history;
