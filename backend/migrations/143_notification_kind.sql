-- 143: 通知分家 —— 新增 kind 欄位區分「一般通知」與「待辦」
--
-- 背景：系統原本只用 `priority`（0=一般 / 1=置頂）表達「這是待辦」，兩者混在同一個
-- 鈴鐺下拉裡。使用者要求拆成兩個入口：鈴鐺＝通知、驚嘆號＝待處理。
--
-- 為什麼需要 `kind` 而不是繼續只用 `priority`：兩者語意不同，缺一不可。
--
--   kind = 'action'  →  這則通知的**性質**是待辦（歷史事實，一旦是就永遠是）
--   priority > 0     →  這則待辦**還沒完成**（完成後降 0）
--
-- 於是「待處理」清單 = `kind='action' AND priority>0`，而使用者事後仍能在鈴鐺歷史裡
-- 回顧「我當初處理過哪些事」—— 只用 priority 的話，完成後那則就與一般通知無從區分。
--
-- 詳見 docs/design/features/notification-vs-action-required-2026-08-07.md §5-1。

ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'info';

-- CHECK 而非 enum：待辦種類日後可能擴充（見設計文件 §5-3 規劃的 8 類），
-- TEXT + CHECK 比 ALTER TYPE 容易演進，且本欄基數只有 2、不影響查詢計畫。
ALTER TABLE notifications
    DROP CONSTRAINT IF EXISTS chk_notifications_kind;
ALTER TABLE notifications
    ADD CONSTRAINT chk_notifications_kind CHECK (kind IN ('info', 'action'));

-- 既有的置頂列即為待辦。priority>0 是本次之前唯一的「待辦」判準，
-- 故以它回填 kind；已完成而降回 0 的舊待辦無從辨識，只能留在 'info'
-- （不影響「待處理」清單正確性 —— 那些本來就不該出現在清單上）。
UPDATE notifications SET kind = 'action' WHERE priority > 0;

-- 「待處理」清單的查詢索引。partial index：只索引未完成的待辦，
-- 而那在 prod 上是個位數（2026-08-07 實查全系統 7 筆），索引極小。
CREATE INDEX IF NOT EXISTS idx_notifications_action_pending
    ON notifications (user_id, created_at DESC)
    WHERE kind = 'action' AND priority > 0;
