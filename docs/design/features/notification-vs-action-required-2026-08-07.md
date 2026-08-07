# 通知（鈴鐺）／待處理（驚嘆號）分家設計

- 日期：2026-08-07（GMT+8）
- 觸發：使用者回報「已完成的巡場報告仍出現在待處理」，並指出代理人確認、請假批准與巡場報告
  全混在同一串，要求把「需要簽核／做出反應的」與「單純告知的」拆成兩個入口
- 狀態：**PR A（根因修復 + 對帳安全網）已實作待審；PR B / C 設計待實作**

---

## 1. 使用者已裁定的四件事

| 決策點 | 定案 |
|---|---|
| 待處理納入標準 | 只收「指派給我本人 + 需我做出動作 + 系統能判定完成」的事項 |
| 消失條件 | **只能由系統偵測「動作已完成」自動消失**，使用者不可手動已讀掉、不可略過 |
| 資料放法 | 沿用 `notifications` 表，加 `kind` 欄位（`info` / `action`），API 加 `?kind=` 篩選，前端拆兩個入口 |
| 存量殘留 | 修 bug + 一次性資料修補（上 prod 前先列筆數確認） |

UI：通知＝鈴鐺，待處理＝驚嘆號，兩者都在頁面上方。

---

## 2. 現況

系統**已經有**待處理的雛形，但沒有獨立入口：

- `notifications.priority`：`0`＝一般、`1`＝緊急置頂（`models/notification.rs:63-65`）
- 建立：`NotificationService::create_pinned_notification()`（`services/notification/crud.rs:166`）
- 解除：`NotificationService::resolve_pinned_notifications(entity_type, entity_id)`
  （`crud.rs:182`）——把 `priority` 降回 0 **並**標記已讀
- 排序：`ORDER BY priority DESC, created_at DESC`（`crud.rs:63`）
- 前端：同一個鈴鐺下拉，置頂項多一個黃色「待處理」標籤
  （`NotificationDropdown.tsx:214`，i18n key `common.actionRequired`）

**目前全系統只有 2 處建立置頂待辦**：
1. 巡場報告指派追蹤者（`handlers/animal/vet_patrol.rs:88`）
2. 採購單未入庫提醒（`services/notification/erp.rs:121`）

**只有 2 處解除**：
1. 追蹤改善完成（`handlers/animal/vet_patrol.rs:202`）
2. GRN 核准入庫（`services/document/workflow.rs:482`）

使用者提到的「代理人確認、請假批准」目前**完全不是**置頂待辦，混在一般通知裡。

---

## 3. 確認的根因（有 prod DB 證據，非推測）

### 3-1 現象
截圖中 2026-07-09 巡場報告狀態為「已完成」，但許芮蓁的通知仍顯示「待處理」。

### 3-2 靜態分析的死路
全 repo `SET status = 'completed'` 只出現在一處
（`services/animal/vet_patrol.rs:1370`，`complete_followup`），而該路徑**確實**有接解除 hook。
所以「完成了卻沒解除」在程式碼上說不通——必須查資料。

### 3-3 查 prod DB 得到的真相

```
-- 該則置頂通知綁的報告
id           = 687524ef-e2e0-4f19-8997-ae30cdbf1579
patrol_date  = 2026-07-09
status       = draft
follow_up_user_id = NULL
deleted_at   = 2026-07-13 03:28:38 UTC  ← 已軟刪除
```

實際發生的事：

1. 2026-07-09 12:05 獸醫 `kmofcc` 建報告 `687524ef`，送出給 `museum1925`（許芮蓁）追蹤
   → 建立置頂通知 `f5536e34`
2. 獸醫後來把它 **retract**（收回成 draft，`follow_up_user_id` 清空），再 **soft delete** 整份報告
3. 獸醫另建 `bb2e147b`（同樣是 2026-07-09 這場），走完流程到 `completed`
   → 截圖清單上「已完成」的是這一份
4. `f5536e34` 綁的是**已被刪掉的** `687524ef`，**永遠不會有人對它呼叫 `complete_followup`**
   → 置頂狀態永久卡死

### 3-4 根因一句話

> **置頂待辦的解除只掛在「正常完成」這一條 happy path 上；
> 「撤回 / 刪除 / 取消 / 作廢」這些同樣讓待辦失效的路徑一條都沒接。**

具體缺口：
- `retract_vet_patrol_report`（`handlers/animal/vet_patrol.rs:315`）— 未解除
- `delete_vet_patrol_report`（同檔 `:301`）— 未解除
- 採購單取消 / 作廢 / 關單 — 未解除（只有 GRN 核准會解除）

### 3-5 這不是孤例

同樣模式的第二個實例：通知 `fea1bd01`（2026-06-23）→ 報告 `67025f62`，
一樣是 `draft` + `deleted_at` 已設 + `follow_up_user_id` NULL。

---

## 4. 存量盤點（prod 實查，2026-08-07）

`SELECT related_entity_type, count(*) FROM notifications WHERE priority > 0 GROUP BY 1`

| entity_type | 置頂筆數 | 判定 |
|---|---|---|
| `vet_patrol_reports` | 3 | **2 筆孤兒**（報告已軟刪）＋ **1 筆合法**（`5726a1fc`，2026-08-07 建立，status=`awaiting_acknowledgement`） |
| `document` | 4 | **4 筆孤兒**：收件人是已刪除帳號（`deleted_*@deleted.local`），且 `related_entity_id` 已 join 不到任何 `documents` 列 |

**需要修補：6 筆。需要保留：1 筆。**

`document` 那 4 筆因收件人帳號已刪，實際上沒有人看得到，但仍應一併清乾淨，
避免日後對帳工具把它們一直算成「未完成待辦」。

---

## 5. 目標設計

### 5-1 資料模型

新增 migration：

```sql
ALTER TABLE notifications
  ADD COLUMN kind TEXT NOT NULL DEFAULT 'info'
  CHECK (kind IN ('info', 'action'));

-- 既有置頂列即為待辦
UPDATE notifications SET kind = 'action' WHERE priority > 0;

CREATE INDEX idx_notifications_user_kind_unresolved
  ON notifications (user_id, kind, created_at DESC)
  WHERE kind = 'action' AND priority > 0;
```

**`kind` 與 `priority` 的分工**（兩者都保留，語意不同）：
- `kind = 'action'`：**這則通知的性質**是待辦。一旦是待辦，永遠是待辦（歷史事實，不變）。
- `priority > 0`：**這則待辦還沒完成**。完成後降 0，從驚嘆號清單消失，但仍留在鈴鐺歷史裡。

這樣「待處理」清單 = `kind='action' AND priority>0`，
而使用者事後仍能在鈴鐺裡回顧「我當初處理過哪些事」。

### 5-2 API

| 端點 | 改動 |
|---|---|
| `GET /notifications` | 加 `?kind=info\|action`；不帶＝全部（維持既有行為，不破壞舊前端） |
| `GET /notifications/unread-count` | 維持原義（鈴鐺用） |
| `GET /notifications/action-required-count` | **新增**，回 `kind='action' AND priority>0` 的筆數（驚嘆號用） |
| `POST /notifications/read` / `read-all` | **必須排除 `kind='action' AND priority>0` 的列**——否則「全部已讀」會把待辦清掉，違反「只能由系統偵測完成自動消失」 |

> ⚠️ `read-all` 這條是關鍵。現況 `resolve_pinned_notifications` 同時設 `is_read=true`，
> 而 `mark all read` 目前會無差別標記所有列。查 prod 發現 3 筆 vet_patrol 置頂列
> **`is_read` 全部是 `true` 但 `priority` 仍是 1**——證明使用者早就按過「全部已讀」，
> 只是前端用 `priority` 而非 `is_read` 決定黃標，才沒被掩蓋過去。分家後必須把這條堵死。

### 5-3 待處理的納入範圍

依裁定標準（**指派給我本人 + 需我動作 + 系統能判定完成**）逐項套用：

**✅ 納入（建議首批）**

| 事項 | 觸發 | 完成訊號 |
|---|---|---|
| 巡場追蹤改善待填 | `submit_for_followup` | `complete_followup`（已有） |
| 採購單未入庫 | 排程 `po_pending_receipt` | GRN 核准（已有） |
| **職務代理人待確認** | `leave_proxy_assigned`（`services/notification/hr.rs:96`） | 代理人確認或退回 |
| **請假 / 加班待審核** | `leave_submitted` / `overtime_submitted` | 該審核者核准或駁回 |
| **單據待審核** | `document_submitted`（採購／銷貨／調整／移轉） | 該審核者核准或駁回 |
| **審查指派** | `review_assignment` | 該委員送出審查意見 |
| **修正案待審** | `amendment_submitted` | 審查決定記錄 |
| **安樂死單待審** | `euthanasia_order_created` | 同意或申訴結案 |

**❌ 不納入（留在鈴鐺）**

低庫存預警、效期預警、月報、`leave_approved` / `overtime_approved`（結果通知，無需動作）、
`protocol_approved` / `protocol_rejected`、`all_comments_resolved`、`animal_abnormal_record`
（是告知不是指派）、站內信（無明確完成訊號，使用者已裁定不納入）。

> ⚠️ 「請假待審核」有一個歧異要確認：一張假單的審核鏈是
> 單位主管 → 負責人（`DIRECTOR`）。**中間任一關核准後，前一關的待辦要不要消失？**
> 我的認定是「該關核准 → 該關的待辦消失，下一關才產生新待辦」，
> 但這需要逐關產生／解除，不是一次發給所有審核者。列 §8 待確認。

### 5-4 必須補齊的解除 hook（根因修復）

原則從「完成時解除」改成 **「待辦不再適用時解除」**。凡是讓實體離開「等我動作」狀態的
路徑都要接，不只 happy path：

| 實體 | 需接解除的路徑 | 現況 |
|---|---|---|
| 巡場報告 | `complete_followup` | ✅ 已有 |
| 巡場報告 | `retract_vet_patrol_report` | ✅ **PR A 已補**（本次事故主因） |
| 巡場報告 | `delete_vet_patrol_report` | ✅ **PR A 已補**（本次事故主因） |
| 巡場報告 | `discard_vet_patrol_draft` | ✅ PR A 已補（防禦性） |
| 採購單 | GRN 核准 | ✅ 已有 |
| 採購單 | 取消 / 作廢 / 關單 | ✅ 非缺口（經查證，見 §6-bis 補充發現） |
| 請假 / 加班 | 核准 / 駁回 / 申請人撤回 | ❌ 缺（尚未是待辦） |
| 代理人 | 確認 / 退回 / 假單被撤回 | ❌ 缺（尚未是待辦） |
| 單據 | 核准 / 駁回 / 作廢 | ❌ 缺（尚未是待辦） |
| 修正案 | 審查決定 / 撤回 | ❌ 缺（尚未是待辦） |
| 安樂死單 | 同意 / 申訴結案 / 撤單 | ❌ 缺（尚未是待辦） |

**實作建議**：不要在每個 handler 手動呼叫。改在 service 層的「狀態轉換」單一出口統一處理
（例如各 service 的 `transition_status()` 內，凡轉入終態就呼叫
`resolve_pinned_notifications(entity_type, id)`）。手動逐處呼叫正是這次漏掉兩條路徑的原因。

### 5-5 前端

- `NotificationDropdown.tsx` 拆成兩個元件：`NotificationBell`（`kind=info`）、
  `ActionRequiredButton`（`kind=action` + `priority>0`，驚嘆號圖示）
- 驚嘆號的紅點數字用新的 `action-required-count` 端點
- 待處理項目**不提供**「標為已讀」；點擊只做導頁
- 待處理為 0 時：圖示仍在但無紅點（維持版面穩定），下拉顯示「目前沒有待處理事項」
- `common.actionRequired` i18n key 沿用，另加 `common.actionRequiredEmpty` 等

---

## 6. 存量修補

`resolve_pinned_notifications` 的既有語意（`priority→0` + `is_read=true`）正好適用，
一次性腳本可直接重用同一條 UPDATE：

```sql
-- 巡場：報告已軟刪或已完成，但通知仍置頂
UPDATE notifications n
SET priority = 0, is_read = true, read_at = COALESCE(n.read_at, NOW())
WHERE n.priority > 0
  AND n.related_entity_type = 'vet_patrol_reports'
  AND EXISTS (
    SELECT 1 FROM vet_patrol_reports r
    WHERE r.id = n.related_entity_id
      AND (r.deleted_at IS NOT NULL OR r.status = 'completed')
  );

-- 孤兒：related_entity_id 已 join 不到任何實體
UPDATE notifications n
SET priority = 0, is_read = true, read_at = COALESCE(n.read_at, NOW())
WHERE n.priority > 0
  AND n.related_entity_type = 'document'
  AND NOT EXISTS (SELECT 1 FROM documents d WHERE d.id = n.related_entity_id);
```

**預期影響：6 列**（vet_patrol 2 + document 4）。
**必須不動：1 列**（`ef46b84d` → 報告 `5726a1fc`，status=`awaiting_acknowledgement`，合法待辦）。

執行前先跑對應的 `SELECT` 版本核對筆數是否為 6，數字對不上就停下回報。

---

## 6-bis. PR A 實作內容（已完成，本分支）

使用者 2026-08-07 裁定：PR A 先單獨走、多關簽核採逐關產生逐關解除、對帳安全網要做。
本分支已完成 PR A：

**根因修復** — `handlers/animal/vet_patrol.rs`
- 抽出 `resolve_followup_pin()` 共用 helper，取代原本只在 `complete_followup` 內聯的那段
- 補接三條先前遺漏的終態路徑：`retract_vet_patrol_report`、`delete_vet_patrol_report`、
  `discard_vet_patrol_draft`（最後一條為防禦性補位）

**對帳安全網** — `services/notification/reconcile.rs`（新檔）
- `NotificationService::reconcile_pinned_notifications(dry_run)`：
  降級「置頂中、但關聯實體已不存在 / 已刪 / 已在終態」的通知
- 保守原則：認不得的 `related_entity_type` 一律不動，只在報告中列出
- 兩個呼叫端共用同一份邏輯：一次性修補 bin，與日後的定期排程

**一次性修補工具** — `bin/reconcile_pinned_notifications.rs`（新檔），支援 `--dry-run`

**定期排程** — `services/scheduler.rs`
- 每日 03:50 UTC（台灣 11:50），排在其他 GC 作業之後
- 對帳有命中時記 `warn` 而非 `info`：命中代表某條終態路徑漏接了解除 hook，
  對帳只是止血，真正該修的是漏掉的那條路徑——不要讓它靜靜地每天清、沒人發現

**回歸測試** — `tests/notification_pinned_reconcile.rs`（新檔，4 例，全 `#[serial]`）
- 軟刪 / 已完成 → 必須降級
- **在途待辦 → 絕不可降級**（比前者重要：誤清真正待辦的傷害大得多）
- dry-run 不得寫入

**驗證結果**
- `cargo check --tests` / `clippy -W clippy::unwrap_used` / `fmt --check`：0 error 0 warning
- 新測試 4 passed；既有 `vet_patrol_core` + 2 支 notification 測試 33 passed（exit 0）
- 對 prod DB 跑 dry-run 查詢：**命中 6 筆**（巡場 2 + 單據 4），
  合法在途待辦 1 筆（`ef46b84d`，2026-08-07，`awaiting_acknowledgement`）**正確未被命中**

**尚未執行**：僅剩 prod 的實際資料修補（需先 merge 部署後再跑 bin）。
排程已隨 `SchedulerService::start()` 在應用啟動時掛載，部署後即生效。

**補充發現**：採購單（PO）那條路徑經查**沒有**同類 bug——
`pending_pos` 的唯一出口就是「存在已核准的 GRN」，而該處已接解除 hook。
prod 上那 4 筆 `document` 置頂列是單據與收件人都被硬刪後留下的歷史垃圾，
不是 hook 漏接。§5-4 表中「採購單 / 取消作廢」一列據此修正為非缺口。

---

## 7. 我對「只能自動消失」這個決定的一點保留（已由對帳安全網補上）

你選的是「只能由系統偵測完成自動消失，不可手動略過」。我照這個做。

但這次事故正好暴露它的代價：**待辦的正確性 100% 取決於 hook 覆蓋率**，
而 hook 是手寫的、每加一條新的終態路徑就多一次漏接機會。這次漏的兩條
（retract / delete）不是罕見路徑——獸醫改個日期重開一份報告就會走到。
一旦漏接，使用者**沒有任何自救手段**，只能等我進 DB 修。

§5-4 的「集中在狀態轉換出口」能大幅降低漏接率，但降不到零。

建議補一層安全網（**不改變你的裁定**，使用者仍然不能手動略過）：
一支定期對帳作業，把「置頂中、但關聯實體已不存在或已在終態」的列自動降級並記 log。
這正是你當初沒選的第三個選項，但根因確認後我認為它從「nice to have」變成「結構上需要」。
**使用者 2026-08-07 裁定：要做，每日一次。** 已隨 PR A 完整落地：
邏輯在 `services/notification/reconcile.rs`，排程在 `services/scheduler.rs`
（每日 03:50 UTC，由 `SchedulerService::start()` 掛載）。

---

## 8. 已定案與待決

### 已定案（2026-08-07，使用者裁定）

| 問題 | 裁定 |
|---|---|
| 實作切分 | **PR A 先單獨走**（已完成，見 §6-bis）；PR B（`kind` + 雙入口）、PR C（其餘 6 類轉待辦）後續 |
| 多關簽核（單位主管 → 負責人） | **逐關產生、逐關解除**——每個人的清單永遠只顯示「現在輪到我」 |
| 定期對帳安全網 | **要做**，**每日一次**（邏輯 + 排程皆已隨 PR A 落地，每日 03:50 UTC） |

「逐關」對 PR C 的實作含意：**不能**在送審時一次發給整條審核鏈，
必須在每次關卡轉換時各做一次「解除前一關 + 建立下一關」。
§5-4 建議的 `transition_status()` 單一出口設計正好承載這件事。

### 待你決定

1. §5-3 的納入清單（8 項）是否就是你要的範圍？有沒有要加或拿掉的？
2. PR B 的前端要不要先做 HTML 預覽（兩個圖示的版面、紅點樣式、空狀態），
   照慣例讓你先看畫面再改 code？

---

## 9. 相關

- 巡場報告另有一支 session 在動（worktree `wt-ab9f1d48`，分支 `fix/vet-patrol-report-readability`）。
  本設計若動到 `handlers/animal/vet_patrol.rs` 需留意衝突。
- 通知路由統一化的既有規劃見 `docs/design/features/notification-routing-unification-feasibility-2026-06-26.md`。
