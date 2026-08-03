-- 088: 補登歷史變更 P6-3 — amendment_review_assignments 支援院外委員
--
-- 平行 085（review_comments / vet_review_assignments 院外審查者）。歷史 MAJOR 變更的
-- 委員審查可能由非系統使用者進行 → reviewer_id 改 nullable + 新增 reviewer_name。
-- live 審查指派照常填 reviewer_id（FK）；補登院外委員填 reviewer_name。

ALTER TABLE amendment_review_assignments
    ALTER COLUMN reviewer_id DROP NOT NULL,
    ADD COLUMN reviewer_name TEXT;

COMMENT ON COLUMN amendment_review_assignments.reviewer_name IS
  '院外審查委員姓名（補登歷史變更用，reviewer_id 為 NULL 時填）';

-- 系統內委員（FK）或院外委員（姓名）至少其一
ALTER TABLE amendment_review_assignments
    ADD CONSTRAINT chk_amendment_reviewer_identity
    CHECK (reviewer_id IS NOT NULL OR NULLIF(BTRIM(reviewer_name), '') IS NOT NULL);

-- 注意：既有 UNIQUE(amendment_id, reviewer_id) 在 reviewer_id NULL 時不阻擋重複院外同名
-- 委員，與 085 一致；補登為全量取代語意，重複由 service 控制。
