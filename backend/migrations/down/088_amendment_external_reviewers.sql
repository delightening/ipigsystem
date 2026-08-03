-- 反向 088：移除 amendment_review_assignments 院外委員支援。
-- 注意：若已有 reviewer_id 為 NULL 的補登資料，restore NOT NULL 會失敗——
-- 需先清除或回填該等列（dev rollback 場景）。
ALTER TABLE amendment_review_assignments
    DROP CONSTRAINT IF EXISTS chk_amendment_reviewer_identity;
ALTER TABLE amendment_review_assignments
    DROP COLUMN IF EXISTS reviewer_name,
    ALTER COLUMN reviewer_id SET NOT NULL;
