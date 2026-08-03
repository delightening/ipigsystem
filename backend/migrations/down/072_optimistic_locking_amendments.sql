-- P1-34 down: 移除 amendments.version 欄位
ALTER TABLE amendments DROP COLUMN IF EXISTS version;
