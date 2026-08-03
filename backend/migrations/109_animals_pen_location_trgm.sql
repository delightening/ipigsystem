-- W2: pen_location 補 pg_trgm GIN 索引。
-- 動物列表 keyword 搜尋為 (p.ear_tag ILIKE '%x%' OR p.pen_location ILIKE '%x%')。
-- ear_tag 已有 idx_animals_ear_tag_trgm（030），但 pen_location 無 → OR 兩側無法都走索引，
-- 大表退化為全表 Seq Scan（50k 實測 keyword COUNT 6.9ms 全表）。兩側皆 trgm 後 planner
-- 可 BitmapOr 兩個 trgm 索引（選擇性高的關鍵字）。pg_trgm extension 由 030 建立。
-- 註：sqlx::migrate! 包 transaction 故此處非 CONCURRENTLY；animals 為小表，
-- 非並行建索引僅毫秒級鎖寫，可接受。大表 FK 索引另走 W4 的 CONCURRENTLY runbook。
CREATE INDEX IF NOT EXISTS idx_animals_pen_location_trgm
    ON animals USING gin (pen_location gin_trgm_ops);
