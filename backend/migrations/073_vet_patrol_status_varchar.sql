-- Fix: vet_patrol_reports.status VARCHAR(20) 不夠放 'awaiting_acknowledgement'（26 chars）
-- Migration 063 加了 CHECK constraint 但漏了拓寬欄位長度
ALTER TABLE vet_patrol_reports ALTER COLUMN status TYPE VARCHAR(30);
