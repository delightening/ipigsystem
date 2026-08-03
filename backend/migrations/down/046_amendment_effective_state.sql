-- Down migration for 046_amendment_effective_state
-- 用途：staging rollback；移除 R30-25a 加入的 effective_from 欄。
-- 注意：rollback 後若有 row 已寫入 effective_from，資料會遺失。
-- WARNING: data loss on down (effective_from values dropped)

ALTER TABLE amendments
    DROP COLUMN IF EXISTS effective_from;

-- IRREVERSIBLE: PostgreSQL 無法乾淨移除 enum 值（DROP TYPE 需先 ALTER COLUMN
-- 換型 + recreate enum，且若有任何 row 使用 'EFFECTIVE' 則無法回收）。
-- 依 README 規範 rule 4，amendment_status 的 'EFFECTIVE' 變體保留不退。
-- 後續 forward migration 若需移除，請走「新 enum + ALTER COLUMN cast + DROP 舊 enum」。
