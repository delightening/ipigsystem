-- Rollback migration 141。僅供 staging / dev rollback；prod 採 forward-only。

-- ── schema 部分：可逆，直接反向 ──
DROP INDEX IF EXISTS uq_species_code_lower;

-- ── 資料部分：刻意不還原 ──
-- IRREVERSIBLE: 141 的 backfill 無法安全反向。
--
-- backfill 把 species_id 為 NULL 的列填成「與 breed 對應的物種」，但 141 之前就已經
-- 填好的 115 列同樣符合這個條件，資料上無從區分哪些是本 migration 寫進去的。
-- 若用 `species_id = <對應物種>` 當條件清空，會連 migration 之前就存在的正確資料一起抹掉
-- ——down 不得修改它沒有建立的資料，故此處不做。
--
-- 同理不刪除 'LYD' 物種列：無法確定該列是本 migration 建立的，還是環境中原本就有。
--
-- 影響評估：多填的 species_id 不會讓回退後的舊程式出錯（該欄在 141 之前即為 nullable
-- 且已有 115 列有值）。真要重做請以新的 forward migration 處理。
