-- #445：byproduct 採樣的兩條來源路徑
--
-- 領域定義（由 vet/SD 確認）：
--   - 安樂死單 (euthanasia_orders) = 獸醫師「強制安樂死」的建議書（vet 提議 → PI 同意），少見。
--   - 犧牲紀錄 (animal_sacrifices) = 計劃內最終犧牲採樣，SD 填寫，是「執行 + 記錄」的共同終點。
--     不論是否走安樂死單，最後都回到 SD 填犧牲單 → animals.status = euthanized。
--
-- byproduct（廢棄物再利用採樣）主要來自「計劃內犧牲」這條路徑，而那條路徑**沒有安樂死單**。
-- 原 euthanasia_id NOT NULL 強制每筆 byproduct 都要有安樂死單 → 犧牲來的 byproduct 記不了。
--
-- 改為 nullable：
--   - 來自強制安樂死單 → euthanasia_id 有值（保留來源）
--   - 來自計劃內犧牲   → euthanasia_id = NULL（仍以 animal_id + source_protocol_id 歸屬）
-- animal_id / source_protocol_id 維持 NOT NULL（byproduct 永遠屬於某動物 + 某計畫）。
-- DROP NOT NULL 不重寫資料、不影響既有列（既有列 euthanasia_id 皆有值）。

ALTER TABLE euthanasia_byproduct_samples
    ALTER COLUMN euthanasia_id DROP NOT NULL;
