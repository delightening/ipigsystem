-- Rollback migration 125: 移除 protocols.source_form_version。
-- WARNING: data loss on down（已回填/選定的表單版本鍵會丟失）。
ALTER TABLE protocols DROP COLUMN IF EXISTS source_form_version;
