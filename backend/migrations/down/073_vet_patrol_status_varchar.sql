-- Revert: 縮回 VARCHAR(20)（注意：若已有 >20 字元的資料會失敗）
ALTER TABLE vet_patrol_reports ALTER COLUMN status TYPE VARCHAR(20);
