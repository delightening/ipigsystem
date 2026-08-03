# 通知路由顯示 vs 實際發送行為 — 一致性稽核

> **稽核日期**：2026-06-26　**稽核者**：Claude（逐檔讀碼驗證）　**受眾**：專案負責人 + 維護者
> **結論**：**不相符**。27 個「可設定事件」中僅約 11 個真正按路由表發站內通知；email 管道設定大多無效；另有 4~5 個設備事件實作正確卻不在 UI。

---

## 0. TL;DR

| 類別 | 數量 | 意義 |
|---|---|---|
| ✅ 站內通知確實走路由表 | ~11 | 行為與顯示大致相符（多數仍忽略 email channel） |
| ⚠️ 部分走路由 / email 失效或脫鉤 | ~7 | 顯示說會寄 email，實際不寄或走別條路 |
| ❌ 死路由（設了等於白設） | 8 | 收件人寫死、不查路由表；其中 `animal_sudden_death` 完全不發通知 |
| ➕ 隱形路由（實作正確卻不在 UI） | 4~5 | 設備事件，admin 在路由頁看不到、無法設定 |

三類系統性落差：
1. **死路由**：UI 可設定，程式卻硬寫收件人、不查路由表。
2. **隱形路由**：程式正確查路由，UI 卻沒列出該事件。
3. **管道脫鉤**：路由頁的 `email`/`both` 設定多被忽略；低庫存/效期 email 走排程器獨立路徑，與路由表完全無關。

---

## 1. 「通知路由顯示」的定義來源（三層，彼此一致）

| 層 | 位置 | 內容 |
|---|---|---|
| 後端可設定事件清單 | `backend/src/services/notification/routing.rs:157` `list_available_event_types()` | 27 個事件，5 分組（AUP/修正案/動物/ERP/HR） |
| 前端事件中文對照 | `frontend/src/types/notification.ts:159` `eventTypeNames` | 26 項（無設備） |
| DB 內建規則 seed | `backend/migrations/003_notifications.sql:83-125` | 26 列（含設備、不含 `leave_approved`/`overtime_approved` 等） |
| 管道選項 | `notification.ts:190` `channelNames` | `in_app` / `email` / `both` |
| 路由解析中樞 | `notification/helpers.rs:87` `get_recipients_by_event()`、`:113` `is_email_enabled_for_event()` | 動態 JOIN routing→roles→user_roles→users |

> 路由頁 CRUD：`handlers/notification_routing.rs`；前端 `pages/admin/NotificationRoutingPage.tsx`。
> 三層定義本身對得上；**落差全在「實際 notify 呼叫是否查這份表」**。

---

## 2. 逐事件總評表（27 個宣告事件）

判定欄：✅ 站內走路由｜⚠️ 部分/管道失效｜❌ 死路由

### AUP 計畫審查
| 事件 | 判定 | 實際行為 | 證據 |
|---|---|---|---|
| `protocol_submitted` | ✅ | 走路由發站內（忽略 channel） | `protocol.rs:24,33` |
| `protocol_vet_review` | ✅ | 狀態映射→走路由（站內） | `protocol.rs:212,222` |
| `protocol_under_review` | ✅ | 走路由站內 + **email 開關有效**（委員指派） | `protocol.rs:121` `is_email_enabled_for_event` |
| `protocol_resubmitted` | ✅ | 狀態映射→走路由（站內） | `protocol.rs:214` |
| `protocol_approved` | ⚠️ | 走路由發站內，但 seed `both` 的 **email 不寄**（channel 被忽略） | `protocol.rs:215,222`（用 `_channel`） |
| `protocol_rejected` | ⚠️ | 同上 | `protocol.rs:216` |
| `review_comment_created` | ✅ | 走路由（站內） | `protocol.rs:347` |
| `all_reviews_completed` | ✅ | 走路由（站內） | `protocol.rs:401` |
| `all_comments_resolved` | ✅ | 走路由（站內） | `protocol.rs:445` |

### 修正案
| 事件 | 判定 | 實際行為 | 證據 |
|---|---|---|---|
| `amendment_submitted` | ✅ | 走路由（站內） | `amendment.rs:22` |
| `amendment_decision_recorded` | ❌ | **死路由**：狀態映射只產生 submitted/approved/rejected，永不產生此事件 | `amendment.rs:87-92` |
| `amendment_approved` | ⚠️ | 走路由站內，seed `both` 的 email 不寄 | `amendment.rs:89,96` |
| `amendment_rejected` | ⚠️ | 同上 | `amendment.rs:90` |

### 動物健康
| 事件 | 判定 | 實際行為 | 證據 |
|---|---|---|---|
| `emergency_medication` | ❌ | **死路由**：硬寫「全部 VET + 該計畫 PI」 | `animal.rs:152-183` |
| `animal_abnormal_record` | ⚠️ | 走路由站內，seed `both` 的 **email 不寄**（忽略 channel） | `animal.rs:235,250` |
| `vet_recommendation_created` | ❌ | **死路由**：硬寫 PI/COEDITOR，且 `COEDITOR` 角色**已廢除**；email 只看 `is_urgent` 硬邏輯 | `animal.rs:29-45,97` |
| `animal_sudden_death` | ❌ | **死路由 + 完全不發通知**：猝死登記 handler 無任何 notify 呼叫 | `handlers/animal/sudden_death.rs:30-45` |
| `euthanasia_order_created` | ❌ | **死路由**：安樂死通知全硬寫 pi/vet/chair user_id | `euthanasia.rs:15-97` |

### ERP 進銷存
| 事件 | 判定 | 實際行為 | 證據 |
|---|---|---|---|
| `document_submitted` | ✅ | 走路由（站內，忽略 channel） | `erp.rs:22,38` |
| `po_pending_receipt` | ✅ | 走路由（站內，daily 批次） | `erp.rs:85` |
| `low_stock_alert` | ⚠️ | 站內走路由（含 PURCHASING）；**email 走排程器獨立路徑、不看路由表**（見 §3） | `alert.rs:104` / `scheduler.rs:933,938` |
| `expiry_alert` | ⚠️ | 同上 | `alert.rs:178` / `scheduler.rs:996,1001` |

### HR 人事
| 事件 | 判定 | 實際行為 | 證據 |
|---|---|---|---|
| `leave_submitted` | ✅ | 走路由（站內） | `hr.rs:23` |
| `overtime_submitted` | ✅ | 走路由（站內） | `hr.rs:124` |
| `leave_approved` | ❌ | **死路由**：硬寫「申請人本人」 | `hr.rs:180` |
| `leave_cancelled` | ❌ | **死路由**：硬寫「曾核准此假單的經手人」 | `hr.rs:63-74` |
| `overtime_approved` | ❌ | **死路由**：硬寫「申請人本人」 | `hr.rs:214` |

### 隱形路由（程式有、UI 無 — 不在上述 27 個之列）
| 事件 | 判定 | 實際行為 | 證據 |
|---|---|---|---|
| `equipment_overdue` | ➕ | **實作最正確**：走路由 + 依 channel 分流站內/email | `equipment.rs:72` |
| `equipment_unrepairable` | ➕ | 同上 | `equipment.rs:124` |
| `equipment_maintenance_review` | ➕ | 同上（seed 在 `013_maintenance_review.sql`） | `equipment.rs:170` |
| `equipment_disposal` | ➕ | 同上（`should_send_in_app`/`should_send_email` 正確） | `equipment.rs:204-235` |

> UI 缺口：`list_available_event_types()` 與 `eventTypeNames` 皆無設備分組 → 路由頁無法新增/編輯；但 `list_notification_routing()` 會撈出這些 DB 列，前端因無中文對照而顯示原始代碼字串。

---

## 3. 重點落差詳述

### 落差 1：死路由（8 個）
admin 在路由頁可設收件角色與管道，但程式碼把收件人寫死或根本不發 → **改設定無任何效果**。
- 完全不發：`animal_sudden_death`。
- 硬寫收件人：`emergency_medication`、`vet_recommendation_created`、`euthanasia_order_created`、`leave_approved`、`leave_cancelled`、`overtime_approved`。
- 映射不產生：`amendment_decision_recorded`。
- 附帶 bug：`vet_recommendation_created` 查的 `up.role IN ('PI','COEDITOR')`，而 `COEDITOR` 角色已於先前重構廢除（`helpers.rs:11-13` 註解自承「CO_EDITOR 角色拆除後…」）→ 該條件等同只剩 PI。

> ⚠️ 設計取捨待裁定：`leave_approved`/`cancelled`/`overtime_approved` 收件人=申請人/經手人，語意上**本就該寫死**；但路由頁仍把它們列為可設定事件，會誤導 admin。屬「UI 該不該顯示」問題，非「行為錯誤」。

### 落差 2：隱形路由（設備 4~5 個）
設備家族是全系統**唯一**同時做對「查路由收件人」與「依 channel 發 email/站內」的實作，卻被排除在 UI 可設定清單外。修法成本低（補進 `list_available_event_types()` + `eventTypeNames`）。

### 落差 3：管道(channel) 脫鉤
- **多數忽略 channel**：seed 設 `both` 的 `protocol_approved/rejected`、`amendment_approved/rejected`、`animal_abnormal_record` 等，對應 notify 用 `_channel` 只發站內 → **email 從不寄**。路由頁顯示「兩者」是假象。
- **低庫存/效期 email 完全脫鉤路由**（最矛盾）：
  - 站內：`send_low_stock_notifications()` → `get_recipients_by_event("low_stock_alert")`（含 admin+WAREHOUSE_MANAGER+PURCHASING），忽略 channel。
  - email：排程器 `fetch_stock_email_recipients()` → **寫死角色** `('SYSTEM_ADMIN','WAREHOUSE_MANAGER')` ＋ 每人 `notification_settings.email_low_stock` 旗標，**完全不查 routing**（`scheduler.rs:1011-1034`）。
  - 後果：(a) seed channel 是 `in_app`（路由頁顯示「不寄 email」），實際卻照寄 email → **直接矛盾**；(b) 站內含 PURCHASING、email 不含 → **兩管道收件人不一致**；(c) 路由表 channel 對 email 毫無作用。
- **真正讓 email channel 生效的只有**：設備家族 + 委員指派 `protocol_under_review`（`is_email_enabled_for_event` 當開關）。

---

## 4. 修復建議（分級，皆屬高風險 / 待裁定方向）

> 全部牽涉行為改變或 UI 契約，依 CLAUDE.md「高風險分流」需逐項確認後再動。

### A. 顯示層誠實化（低風險、可逆、見效快）
- A1. 把死路由事件從路由頁**隱藏**，或加標註「固定收件人，不受路由設定影響」。
- A2. 把設備 4 事件**補進** `list_available_event_types()` + `eventTypeNames`，讓 UI 與實作對齊。
- A3. 對「channel 被忽略」的事件，UI 暫時**鎖死 channel = `in_app`**（移除 email/both 選項），避免誤導；或在管道欄標「email 尚未支援」。

### B. 行為層補齊（中高風險，逐事件決定）
- B1. 死路由事件改走 `get_recipients_by_event()`（語意合理者除外，如自我通知類）。
- B2. 忽略 channel 的 notify 改用 `should_send_in_app`/`should_send_email` 分流（比照 `equipment.rs`）。
- B3. 低庫存/效期：統一 email 收件人來源 — 改由 routing 表 channel 驅動，移除 `fetch_stock_email_recipients` 的寫死角色（或反向：明確定義「routing 管站內、個人設定管 email」並同步 UI 文案）。
- B4. 修 `vet_recommendation_created` 的 `COEDITOR` 殘留（角色已廢）。

### C. 最小止血（若只想先處理一項）
- 低庫存/效期 email 與路由脫鉤（落差 3 第二點）最矛盾且影響實際寄信對象，建議優先。

---

## 5. 驗證方法備註
- 本報告以**逐檔讀原始碼**為準。先前並行的探查代理彙整有兩處與程式碼矛盾（誤稱 `emergency_medication`、`leave_cancelled` 走路由表），已採親讀結論修正。
- 未實際啟動系統觀察 runtime 行為；判定基於靜態程式路徑。如需 runtime 佐證，可在 dev 環境設一條 email channel 路由規則後觸發對應事件、檢查 outbox 是否入列。
