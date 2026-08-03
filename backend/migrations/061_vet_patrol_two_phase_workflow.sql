-- R39+: 巡場報告兩階段流程（獸醫 → 陪同人員）
--
-- 流程：
--   [draft] ──獸醫填觀察+建議──> [awaiting_follow_up] ──陪同人員填追蹤改善──> [completed] (locked)
--
-- 設計：
--   - status 從 'draft'/'submitted' 擴成 'draft'/'awaiting_follow_up'/'completed'
--   - 舊 'submitted' 視為「已完成」backfill 為 'completed'
--   - follow_up_user_id：獸醫指派的「追蹤者」（陪同人員），FK 到 users
--   - follow_up_submitted_at：追蹤者完成追蹤的時間
--
-- GLP：completed 後 service 層禁止修改（unless admin 走「修正紀錄」流程，本 PR 不做）。

-- ── 1. 拓寬 status 允許值 ──────────────────────────────

ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT IF EXISTS vet_patrol_reports_status_check;

-- 暫先允許四種值（draft/awaiting_follow_up/completed + 舊 submitted）
-- 跑完 backfill 後再縮回三種
ALTER TABLE vet_patrol_reports
    ADD CONSTRAINT vet_patrol_reports_status_check_temp
    CHECK (status IN ('draft', 'awaiting_follow_up', 'completed', 'submitted'));

-- ── 2. backfill 'submitted' → 'completed' ──────────────────────────────

UPDATE vet_patrol_reports
SET status = 'completed'
WHERE status = 'submitted';

-- 縮回三狀態
ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT vet_patrol_reports_status_check_temp;
ALTER TABLE vet_patrol_reports
    ADD CONSTRAINT vet_patrol_reports_status_check
    CHECK (status IN ('draft', 'awaiting_follow_up', 'completed'));

-- ── 3. 新增追蹤者欄位 ──────────────────────────────

ALTER TABLE vet_patrol_reports
    ADD COLUMN IF NOT EXISTS follow_up_user_id UUID REFERENCES users(id);

ALTER TABLE vet_patrol_reports
    ADD COLUMN IF NOT EXISTS follow_up_submitted_at TIMESTAMPTZ;

-- backfill：completed 的舊報告，follow_up_submitted_at 用 submitted_at
UPDATE vet_patrol_reports
SET follow_up_submitted_at = submitted_at
WHERE status = 'completed' AND follow_up_submitted_at IS NULL;

-- 列表頁 filter「我待追蹤」用：找指派給我且還沒完成的
CREATE INDEX IF NOT EXISTS idx_vet_patrol_reports_follow_up_pending
    ON vet_patrol_reports(follow_up_user_id)
    WHERE status = 'awaiting_follow_up' AND deleted_at IS NULL;
