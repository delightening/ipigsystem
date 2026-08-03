-- DOWN for 093：還原 euthanasia_byproduct_samples.euthanasia_id 的 NOT NULL 約束。
-- 僅供 staging / dev rollback；prod 採 forward-only。
--
-- ⚠️ 注意：若已有「計劃內犧牲路徑」建立的列（euthanasia_id IS NULL，#445），此 SET NOT NULL
-- 會失敗。rollback 前須先處理這些列（刪除或補 euthanasia_id），否則 ALTER 報錯——這正是
-- 093 解除此約束的原因，故 down 僅在無 NULL 列的環境可套用。

ALTER TABLE euthanasia_byproduct_samples
    ALTER COLUMN euthanasia_id SET NOT NULL;
