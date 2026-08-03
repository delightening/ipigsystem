-- Rollback import P1: 移除補登旗標 / 申請編號 / 原始版本號欄
ALTER TABLE protocols
    DROP COLUMN IF EXISTS application_no,
    DROP COLUMN IF EXISTS import_pending,
    DROP COLUMN IF EXISTS original_version_label,
    DROP COLUMN IF EXISTS study_director_user_id;
