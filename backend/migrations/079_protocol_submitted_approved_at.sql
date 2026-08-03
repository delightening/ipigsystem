-- 為 protocols 表新增申請時間與通過時間欄位，供匯入舊通過計畫時記錄歷史時間軸。
ALTER TABLE protocols
    ADD COLUMN IF NOT EXISTS submitted_at DATE,
    ADD COLUMN IF NOT EXISTS approved_at DATE;
