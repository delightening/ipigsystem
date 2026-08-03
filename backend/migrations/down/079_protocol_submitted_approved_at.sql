-- WARNING: data loss on down（移除使用者匯入時填寫的申請/通過時間）
ALTER TABLE protocols
    DROP COLUMN IF EXISTS submitted_at,
    DROP COLUMN IF EXISTS approved_at;
