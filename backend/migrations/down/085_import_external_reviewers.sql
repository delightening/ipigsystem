-- 反向：移除院外審查者 / 獸醫師支援。
-- 注意：若已有 reviewer_id / vet_id 為 NULL 的補登資料，restore NOT NULL 會失敗——
-- 需先清除或回填該等列（dev rollback 場景）。

-- 還原 chk_review_stage（移除 FINAL_REVIEW / FINAL）。
-- 注意：若已有 FINAL_REVIEW/FINAL 列，restore 會失敗——需先回填該等列。
ALTER TABLE review_comments DROP CONSTRAINT IF EXISTS chk_review_stage;
ALTER TABLE review_comments
    ADD CONSTRAINT chk_review_stage CHECK (
        review_stage IS NULL OR review_stage IN (
            'PRE_REVIEW', 'PRE_REVIEW_REVISION_REQUIRED', 'VET_REVIEW',
            'VET_REVISION_REQUIRED', 'UNDER_REVIEW'
        )
    );

ALTER TABLE vet_review_assignments
    DROP CONSTRAINT IF EXISTS vet_review_assignments_vet_identity_chk;
ALTER TABLE vet_review_assignments
    DROP COLUMN IF EXISTS vet_name,
    ALTER COLUMN vet_id SET NOT NULL;

ALTER TABLE review_comments
    DROP CONSTRAINT IF EXISTS review_comments_reviewer_identity_chk;
ALTER TABLE review_comments
    DROP COLUMN IF EXISTS reviewer_name,
    ALTER COLUMN reviewer_id SET NOT NULL;
