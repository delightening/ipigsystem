-- R53-14 rollback: revert requester split + billing fields
--
-- 注意：rollback 後 requester_org_name + requester_contact_name 資料會合併
-- 回 requester_text。需確認既有 row 都能轉回 free text（org / contact 兩欄
-- concat），否則先手動處理。

ALTER TABLE euthanasia_byproduct_samples
    DROP CONSTRAINT IF EXISTS byproduct_samples_work_time_order,
    DROP CONSTRAINT IF EXISTS byproduct_samples_requester_present;

ALTER TABLE euthanasia_byproduct_samples
    ADD COLUMN requester_text TEXT;

-- Best-effort backfill：「機構 / 聯絡人」串成單一字串
UPDATE euthanasia_byproduct_samples
SET requester_text = CASE
    WHEN requester_org_name IS NOT NULL AND requester_contact_name IS NOT NULL
        THEN requester_org_name || ' / ' || requester_contact_name
    WHEN requester_org_name IS NOT NULL
        THEN requester_org_name
    WHEN requester_contact_name IS NOT NULL
        THEN requester_contact_name
    ELSE NULL
END
WHERE requester_user_id IS NULL;

ALTER TABLE euthanasia_byproduct_samples
    DROP COLUMN work_ended_at,
    DROP COLUMN work_started_at,
    DROP COLUMN special_equipment_used,
    DROP COLUMN requester_contact_name,
    DROP COLUMN requester_org_name;

ALTER TABLE euthanasia_byproduct_samples
    ADD CONSTRAINT byproduct_samples_requester_present CHECK (
        requester_user_id IS NOT NULL
        OR (requester_text IS NOT NULL AND length(trim(requester_text)) > 0)
    );
