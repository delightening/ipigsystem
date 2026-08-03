-- ============================================================
-- Down migration 060: messaging system (R40-A)
-- ------------------------------------------------------------
-- WARNING: data loss on down — 所有訊息 / thread / 附件 DB row 全失；
--          attachments 實體檔案需另外人工清理（uploads/messaging/）。
--          僅 staging / dev rollback 演練使用。
-- ============================================================

DROP TRIGGER IF EXISTS trg_messages_update_thread_timestamp ON messages;
DROP FUNCTION IF EXISTS update_thread_last_message_at();

DROP INDEX IF EXISTS idx_message_attachments_orphan;
DROP INDEX IF EXISTS idx_message_attachments_message;
DROP TABLE IF EXISTS message_attachments;

DROP INDEX IF EXISTS idx_messages_deleted_for_gc;
DROP INDEX IF EXISTS idx_messages_thread_created;
DROP TABLE IF EXISTS messages;

DROP INDEX IF EXISTS idx_message_thread_participants_user;
DROP TABLE IF EXISTS message_thread_participants;

DROP INDEX IF EXISTS idx_message_threads_last_message_at;
DROP TABLE IF EXISTS message_threads;
