-- 135: 清除死亡終態動物殘留的 pen_location
--
-- 已安樂死 / 猝死的動物本應無 pen_location —— 所有寫入路徑（安樂死單執行
-- `services/euthanasia.rs`、犧牲確認 `services/animal/medical.rs::upsert_sacrifice`、
-- 猝死 `record_sudden_death`）都會將 pen_location 設為 NULL。但歷史 / 匯入資料可能在
-- 這些清除邏輯加入前就已終態，殘留 pen_location（例：耳號 251 詳情頁仍顯示欄號 A14），
-- 導致其（在 #999 查詢層修正前）誤現於欄位視圖與計數。
--
-- 本 migration 為一次性資料整備，把這些殘留 pen_location 設為 NULL，使資料與 app 寫入
-- 路徑保證的狀態一致。範圍僅限 is_terminal()（euthanized / sudden_death）—— 不含
-- transferred：轉讓完成（`services/animal/transfer.rs`）刻意保留 pen_location，僅在轉讓
-- 豬重新入組時才清，故不在此整備範圍。
--
-- 僅影響死亡終態且 pen_location 非 NULL 者；idempotent（跑過後不再命中）。
-- 不動 pen_id / status 等其他欄位，不觸及活躍動物。bump updated_at 讓依 updated_at 的
-- 快取 / ETag 重新整理。
UPDATE animals
SET pen_location = NULL,
    updated_at = NOW()
WHERE status IN ('euthanized', 'sudden_death')
  AND pen_location IS NOT NULL
  AND deleted_at IS NULL;
