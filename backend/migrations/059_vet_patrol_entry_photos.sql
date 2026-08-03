-- R39: 獸醫巡場報告 entry-level 照片附件
--
-- 動機：原本照片只能掛在 report-level（vet_patrol_photos），UX 上每個觀察條目
-- 需要分別掛照片（「豬 12 號膝蓋腫」這筆觀察直接附腫脹照片）。
-- 沿用 vet_patrol_photos 結構，FK 改為指向 entry，舊表保留作為「整體環境照」用途。
--
-- 同時：
-- 1. 既有 status 欄位（022 migration default 'draft'）正式啟用 — 既有報告全部 backfill 'submitted'
--    （之前 status 從未被使用，所有「已儲存」報告語義上等同「已送出」）
-- 2. 加 submitted_at 時戳 + CHECK constraint 限制狀態
-- 3. R39 auto-save draft pattern：dialog 第一次輸入即 POST 建 draft，按「送出」才轉 submitted
--    7 天未動的 draft 由 scheduler nightly 自動清掉（vet_patrol_reports.status='draft' AND updated_at < NOW() - 7d）

-- ── 1. entry-level 照片表 ──────────────────────────────
CREATE TABLE IF NOT EXISTS vet_patrol_entry_photos (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id      UUID         NOT NULL REFERENCES vet_patrol_entries(id) ON DELETE CASCADE,
    file_name     VARCHAR(255) NOT NULL,
    file_path     TEXT         NOT NULL,
    file_size     BIGINT       NOT NULL,
    mime_type     VARCHAR(100) NOT NULL,
    caption       TEXT         NOT NULL DEFAULT '',
    sort_order    INT          NOT NULL DEFAULT 0,
    created_by    UUID         REFERENCES users(id),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vet_patrol_entry_photos_entry ON vet_patrol_entry_photos(entry_id);

-- ── 2. status 欄位正式啟用 ──────────────────────────────

-- 既有報告全部視為已送出（之前無 draft 概念）
UPDATE vet_patrol_reports
SET status = 'submitted'
WHERE status = 'draft' AND deleted_at IS NULL;

-- 加 submitted_at 時戳（既有資料 backfill 用 updated_at 當代理）
ALTER TABLE vet_patrol_reports
    ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;

UPDATE vet_patrol_reports
SET submitted_at = updated_at
WHERE submitted_at IS NULL AND status = 'submitted';

-- CHECK constraint：限制 status 值
ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT IF EXISTS vet_patrol_reports_status_check;
ALTER TABLE vet_patrol_reports
    ADD CONSTRAINT vet_patrol_reports_status_check
    CHECK (status IN ('draft', 'submitted'));

-- 草稿過期 GC 用的 partial index（scheduler 每日掃 status='draft' 老資料）
CREATE INDEX IF NOT EXISTS idx_vet_patrol_reports_draft_updated
    ON vet_patrol_reports(updated_at)
    WHERE status = 'draft' AND deleted_at IS NULL;
