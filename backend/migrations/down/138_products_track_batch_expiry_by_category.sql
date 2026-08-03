-- Rollback migration 138（R84-3 依類別回填批號/效期追蹤旗標）。
-- WARNING: data loss on down —— 純資料 migration（無 schema 變更）。此 down 會把
-- DRG/MED/CON/CHM 品項的 track_batch/track_expiry 設回 false，但**無法還原**這些品項在
-- migration 138 執行前是否本來就有人刻意設為 true（forward 只「開啟」不記錄原值）。
-- 僅供 staging / dev rollback 演練；prod 採 forward-only，勿執行。
UPDATE products
SET track_batch = false,
    track_expiry = false,
    updated_at = NOW()
WHERE category_code IN ('DRG', 'MED', 'CON', 'CHM');
