-- 補登（import P2）：支援院外審查者 / 獸醫師——歷史審查文件中部分審查者非系統帳號，
-- 僅能以「填姓名」記錄。將 review_comments.reviewer_id 與 vet_review_assignments.vet_id
-- 放寬為可為 NULL，並新增對應的 *_name 欄位；以 CHECK 確保「id 或 name 至少其一」。
-- 系統內審查者照常用 FK；院外審查者用姓名。PDF 顯示時 COALESCE(users.display_name, *_name)。

-- review_comments：執秘意見 / 委員意見 / 客戶回覆
ALTER TABLE review_comments
    ALTER COLUMN reviewer_id DROP NOT NULL,
    ADD COLUMN reviewer_name TEXT;

ALTER TABLE review_comments
    ADD CONSTRAINT review_comments_reviewer_identity_chk
    CHECK (reviewer_id IS NOT NULL OR NULLIF(BTRIM(reviewer_name), '') IS NOT NULL);

-- vet_review_assignments：獸醫師評比與意見
ALTER TABLE vet_review_assignments
    ALTER COLUMN vet_id DROP NOT NULL,
    ADD COLUMN vet_name TEXT;

ALTER TABLE vet_review_assignments
    ADD CONSTRAINT vet_review_assignments_vet_identity_chk
    CHECK (vet_id IS NOT NULL OR NULLIF(BTRIM(vet_name), '') IS NOT NULL);

-- 放行 FINAL_REVIEW / FINAL 審查階段：委員二審。原 chk_review_stage（007）漏列，
-- 但 PDF build_committee_items 早已讀取 FINAL_REVIEW/FINAL 渲染 opinion_2nd
-- （此前因約束擋下而為休眠路徑）。補登委員二審意見需此階段，亦修正既有不一致。
ALTER TABLE review_comments DROP CONSTRAINT IF EXISTS chk_review_stage;
ALTER TABLE review_comments
    ADD CONSTRAINT chk_review_stage CHECK (
        review_stage IS NULL OR review_stage IN (
            'PRE_REVIEW', 'PRE_REVIEW_REVISION_REQUIRED', 'VET_REVIEW',
            'VET_REVISION_REQUIRED', 'UNDER_REVIEW', 'FINAL_REVIEW', 'FINAL'
        )
    );
