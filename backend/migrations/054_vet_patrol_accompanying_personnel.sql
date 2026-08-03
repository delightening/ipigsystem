-- 獸醫巡場報告：新增「陪同人員」欄位（取代舊的週起/週迄欄位用途）
-- 舊的 week_start / week_end 欄位保留（既有資料不動），但前端不再蒐集。
ALTER TABLE vet_patrol_reports
    ADD COLUMN IF NOT EXISTS accompanying_personnel TEXT;
