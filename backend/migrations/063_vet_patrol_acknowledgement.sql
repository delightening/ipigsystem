-- R39++ 三階段巡場報告流程：插入「待確認收到」階段
--
-- 流程：
--   [draft] ─獸醫送出─▶ [awaiting_acknowledgement] ─追蹤者按「確認收到」─▶
--     [awaiting_follow_up] ─追蹤者填回覆 + 按「確認完成」─▶ [completed] (locked)
--
-- 改動：
--   - status 拓寬：新增 'awaiting_acknowledgement'
--   - 新欄位 acknowledged_at / acknowledged_by_id：記追蹤者按「確認收到」的時間 + 是誰按的
--   - backfill：既有 awaiting_follow_up 視為已確認（acknowledged_at = submitted_at,
--     acknowledged_by_id = follow_up_user_id），避免舊資料卡在中間狀態回到「待確認」
--
-- GLP：completed 後仍不可改；新增 awaiting_acknowledgement 狀態下 service 層
-- 同樣禁止追蹤者填 follow_up 內容（必須先 acknowledge 才能填）。

-- ── 1. 拓寬 status check ──────────────────────────────

ALTER TABLE vet_patrol_reports
    DROP CONSTRAINT IF EXISTS vet_patrol_reports_status_check;

ALTER TABLE vet_patrol_reports
    ADD CONSTRAINT vet_patrol_reports_status_check
    CHECK (status IN ('draft', 'awaiting_acknowledgement', 'awaiting_follow_up', 'completed'));

-- ── 2. 新增欄位 ──────────────────────────────

ALTER TABLE vet_patrol_reports
    ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS acknowledged_by_id UUID REFERENCES users(id);

-- ── 3. backfill：既有 awaiting_follow_up 視為已確認 ──────────────────────────────

UPDATE vet_patrol_reports
SET acknowledged_at = COALESCE(submitted_at, updated_at),
    acknowledged_by_id = follow_up_user_id
WHERE status = 'awaiting_follow_up'
  AND acknowledged_at IS NULL;

-- ── 4. 索引：列表頁「待我確認」 ──────────────────────────────

CREATE INDEX IF NOT EXISTS idx_vet_patrol_reports_pending_ack
    ON vet_patrol_reports(follow_up_user_id)
    WHERE status = 'awaiting_acknowledgement' AND deleted_at IS NULL;
