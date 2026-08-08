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

-- 回填。只看 priority 是不夠的：那樣**只認得得出「現在還沒完成」的待辦**，
-- 已經完成而降回 0 的舊待辦會被永久寫成 'info'，與上面「kind 是歷史事實」的
-- 不變量自相矛盾 —— 分家後鈴鐺歷史裡就再也標不出「這件我當初處理過」。
--
-- 這些舊列還有一個可靠訊號：**建立時的標題格式**。系統只有兩處產生置頂待辦
-- （erp.rs 採購未入庫、vet_patrol.rs 巡場追蹤），兩者的標題都是固定 format!，
-- 而歷史列的標題已經凍結、不會再變。
--
-- ⚠️ 這與 crud.rs 的 RESOLVE_PINNED_SQL 刻意「不比對標題」並不衝突：
-- 那是**執行期**的解除路徑，未來文案調整或多語系會讓 LIKE 失效而漏解除；
-- 這裡是**一次性回填既有列**，比對的是已經寫死在資料裡的歷史字串。
--
-- 2026-08-07 對 prod 實查（全表 1252 列）：
--   採購未入庫  174 列（4 未完成、170 已完成）
--   巡場追蹤      8 列（1 未完成、  7 已完成）
--   其餘       1070 列，未完成 0 —— 證實這兩個 pattern 涵蓋了全部現存置頂列。
-- 即多回收 177 列的歷史待辦身分，而非讓它們沉入 'info'。
--
-- 仍保留 priority > 0 這一支當安全網：萬一有本文件未涵蓋的置頂列，
-- 寧可標成 action（最多在鈴鐺多一個「已完成」徽章），也不要漏掉待處理清單。
UPDATE notifications
SET kind = 'action'
WHERE priority > 0
   OR (related_entity_type = 'document'
       AND title LIKE '[iPig] 採購單未入庫提醒%')
   OR (related_entity_type = 'vet_patrol_reports'
       AND title LIKE '[巡場報告]%需您填寫追蹤改善');

-- 「待處理」清單的查詢索引。partial index：只索引未完成的待辦，
-- 而那在 prod 上是個位數（2026-08-07 實查全系統 7 筆），索引極小。
CREATE INDEX IF NOT EXISTS idx_notifications_action_pending
    ON notifications (user_id, created_at DESC)
    WHERE kind = 'action' AND priority > 0;
