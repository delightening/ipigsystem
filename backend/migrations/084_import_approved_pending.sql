-- 084: 匯入已核准計劃「完整補登」P1 — 補登中旗標 + 申請編號 + 原始版本號
--
-- 背景：匯入已核准計劃原本只建 APPROVED 空殼 + 補登里程碑日期。擴充為「完整補登」：
-- 匯入後標記 import_pending，允許在現有編輯頁補填 working_content（不走 amendment），
-- 按「完成補登」清旗標 + 建 protocol_versions v1 snapshot。
--
-- 另：區分兩個歷史識別碼 — application_no（申請編號，例 APIG-103001）與既有
-- iacuc_no（核准編號，例 PIG-115001）。
ALTER TABLE protocols
    ADD COLUMN application_no          TEXT,
    ADD COLUMN import_pending          BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN original_version_label  TEXT,
    ADD COLUMN study_director_user_id  UUID REFERENCES users(id);

COMMENT ON COLUMN protocols.study_director_user_id IS
  '計劃負責人 / Study Director（本公司員工，自 EXPERIMENT_STAFF 挑選）；補登中可編輯內容並完成補登';
COMMENT ON COLUMN protocols.application_no IS
  '申請編號（例 APIG-103001），與 iacuc_no（核准編號 PIG-115001）區分；匯入補登用';
COMMENT ON COLUMN protocols.import_pending IS
  '匯入補登中：status=APPROVED 但允許編輯 working_content；按「完成補登」後清除（import P1）';
COMMENT ON COLUMN protocols.original_version_label IS
  '原計劃書版本號文字（補登，例 v2.1）；完成補登時填入';
