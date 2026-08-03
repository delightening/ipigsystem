-- 089: attachments.entity_id UUID → VARCHAR(100)
--
-- Bug：上傳計畫書 / 動物等附件時 `POST /protocols/:id/attachments` 回 500，
-- DB 錯誤「column "entity_id" is of type uuid but expression is of type text」。
--
-- 根因：attachments.entity_id 自 003_notifications 起建為 UUID，但整個 upload 模組
-- 全程將其視為 text：
--   * save_attachment INSERT 以 &str（text）綁定 entity_id（未轉型）；
--   * list/download/delete 讀取一律用 entity_id::text；
--   * vet_recommendation 附件 entity_id 為「{record_type}_{record_id}」複合鍵（非 UUID）。
-- schema 型別與實際用法矛盾，INSERT 因 text→uuid 無 assignment cast 而失敗。
--
-- 修正：將欄位改為 VARCHAR(100)（與 electronic_signatures.entity_id 一致），對齊
-- 程式碼用法，同時支援 UUID 與複合鍵 entity_id。
-- attachments 目前為空，型別轉換零資料風險；idx_attachments_entity 由 PG 自動重建。

ALTER TABLE attachments
    ALTER COLUMN entity_id TYPE VARCHAR(100) USING entity_id::text;
