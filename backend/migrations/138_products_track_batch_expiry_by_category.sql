-- 138: 依 SKU 類別回填品項批號/效期追蹤旗標（R84-3）
--
-- 背景：products.track_batch / track_expiry 過去一律 DEFAULT false，導致多數藥品/耗材
-- 其實有批號效期卻沒開追蹤。R84-3 以 SKU 類別當「起點預設值」把該追蹤的類別一次補開。
-- 搭配同 PR 對 requires_batch_expiry() 擴大涵蓋 PR/TR/SR，讓退貨/調撥也強制填批號效期。
--
-- 設計依據：docs/spec/modules/ERP流程.md §6.2.1（設計已與使用者定案、PR #1026 合併）。
-- 類別對照：DRG 藥品 / MED 醫材 / CON 耗材 / CHM 化學品 → 天生有批號效期 → 兩旗標開 true。
--
-- 刻意保守的範圍決定（與設計表的差異，已於 PR 明講）：
--   本 migration「只開啟」DRG/MED/CON/CHM，**不強制**把 EQP/GEN 設回 false。
--   原因：強制設 false 會覆蓋使用者可能刻意為某個 GEN/EQP 品項開啟的追蹤，屬破壞性動作；
--   而 EQP/GEN 的欄位預設本就是 false（009 建表 DEFAULT false），新品項不受影響。
--   「起點預設值、使用者可事後逐品項調整」的精神，用「只補開該追蹤的類別」即可達成。
--
-- 兩旗標分開設定（設計要求），只是這次類別判斷剛好一致，故合併於同一句 UPDATE。
-- track_expiry=true 僅使「未來單據」對該品項要求效期，不影響既有歷史 stock_ledger/庫存列。
--
-- default_expiry_days 這次不設全類別統一預設天數（各品項效期差異大，改由使用者逐品項填）。
--
-- 冪等：以 category_code 為條件的 UPDATE，重跑結果一致。
UPDATE products
SET track_batch = true,
    track_expiry = true,
    updated_at = NOW()
WHERE category_code IN ('DRG', 'MED', 'CON', 'CHM')
  AND (track_batch = false OR track_expiry = false);
