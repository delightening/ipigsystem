-- 137: 庫存量表非負約束（R84-2）
--
-- 背景：庫存量表過去只靠應用層邏輯擋負庫存，資料庫本身沒有兜底。R84-1（同單同品項
-- 透支）修復後，補上資料庫層的最後防線，讓「倉庫不可能有 -5 支針筒」這件物理事實
-- 由 DB 強制保證，任何繞過應用層的寫入路徑（未來的 bug、手動改資料）都會被擋下。
--
-- 安全性：2026-07-22 已查證 prod——inventory_snapshots.on_hand_qty_base 與
-- storage_location_inventory.on_hand_qty 皆 0 筆負值，無既存髒資料，可直接加驗證式約束
-- （plain validated CHECK，非 NOT VALID）。兩張量表資料量小，驗證掃描成本可忽略。
--
-- 追蹤：docs/TODO.md R84-2、docs/spec/modules/ERP流程.md §6.1。
ALTER TABLE inventory_snapshots
    ADD CONSTRAINT chk_inventory_snapshots_on_hand_nonneg
    CHECK (on_hand_qty_base >= 0);

ALTER TABLE storage_location_inventory
    ADD CONSTRAINT chk_storage_location_inventory_on_hand_nonneg
    CHECK (on_hand_qty >= 0);
