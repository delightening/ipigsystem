-- Rollback R53-1: 移除 euthanasia_byproduct_samples
--
-- 警告：此表為廢棄物再利用內部稽核紀錄，rollback 會永久遺失資料。
-- 僅限早期 development 階段、無 prod 資料時使用。

DROP TABLE IF EXISTS euthanasia_byproduct_samples;
