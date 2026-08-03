# Admin 駁回通道 + 計劃排序沉底 + 軟刪除 — 設計

> 緣由：清理兩筆誤送審計畫（APIG-115011 / APIG-115014，SUBMITTED 非匯入）時，發現預審階段缺「駁回」出口，且被駁回計劃無沉底/軟刪。決定做成正式可複用流程。
>
> 使用者裁定（2026-06-12，auq）：
> 1. 駁回入口 = **SUBMITTED + PRE_REVIEW，僅 admin**
> 2. 「我的計劃」排序 = **REJECTED + CLOSED 沉底**
> 3. **要** admin 軟刪除按鈕（被駁回計劃可隱藏）

## 1. 現況

| 項目 | 現況 | 檔案 |
|---|---|---|
| 狀態機允許 SUBMITTED/PRE_REVIEW→REJECTED | ✅ 已允許（`_` 分支，REJECTED 非 Suspended/Closed） | `models/protocol.rs::can_change_status_to` |
| change_status 權限 | 只查 `aup.protocol.change_status`，**非 admin 專用** | `handlers/protocol/crud.rs:272` |
| 前端轉移選項 | 純查 `allowedTransitions[status]`，未依角色 | `constants.ts:24` / `useProtocolDetail.ts:84` |
| 我的計劃排序 | `ORDER BY created_at DESC`，已濾 `status!='DELETED'` | `services/protocol/my_protocols.rs:59` |
| 軟刪除 | DELETED 狀態存在（列表會濾掉），但 change_status→DELETED 僅允許從 DRAFT/補件；REJECTED 是終態無法軟刪；無專屬按鈕 | `status.rs:48` |

## 2. 設計決策

### 2.1 駁回（admin 專用，重用 change_status）
- **重用泛型 `change_status`**（非新端點）→ 沿用既有 audit + 通知 PI 邏輯，DRY。
- 在 `change_status_tx` 新增 admin 子守衛：
  - 當 `to_status == REJECTED` 且 `from ∈ {SUBMITTED, PRE_REVIEW}` → 要求 actor 為 **admin**（`actor.as_user().is_admin()`；System actor 放行供 bin），否則 `Forbidden`。
  - **UNDER_REVIEW → REJECTED（委員會審後否決）不受影響**，維持既有 `aup.protocol.change_status` 權限即可。
- **remark 必填**：駁回時無 remark → `Validation` 錯誤（留稽核理由）。
- 前端：`useProtocolDetail` 在 `isAdmin && status ∈ {SUBMITTED, PRE_REVIEW}` 時把 `REJECTED` 注入 `availableTransitions`（靜態表不動，依角色擴充）。

### 2.2 排序沉底
- `my_protocols.rs` ORDER BY 改：
  ```sql
  ORDER BY (p.status IN ('REJECTED','CLOSED')) ASC, p.created_at DESC
  ```
  終態（已否決/已結案）沉底，活躍計劃在上，組內維持新→舊。

### 2.3 軟刪除（dedicated admin 端點，不鬆動終態鎖）
- **不**透過泛型 change_status（避免鬆動 CSO-r2 #2 的終態 egress 鎖）。
- 新增專屬端點：`POST /api/v1/protocols/{id}/soft-delete`
  - admin only（`current_user.is_admin()`）。
  - 允許來源狀態：**REJECTED**（本次需求）。其他狀態回 `BusinessRule`。
  - 行為：`UPDATE protocols SET status='DELETED'`（同 tx 寫 audit `PROTOCOL_SOFT_DELETED`）。
  - 列表既有 `status != 'DELETED'` 過濾 → 自動從「我的計劃」隱藏。
  - 權限沿用 `aup.protocol.delete`（admin 已有）。
- 前端：`status == REJECTED && isAdmin` 顯示「軟刪除」按鈕 + 二次確認 dialog + i18n。

## 3. 實作切分

| PR | 範圍 | 測試標準 |
|---|---|---|
| **PR-1（後端）** | change_status admin 駁回守衛 + remark 必填；soft-delete 端點/service/route/權限；my_protocols 排序 | `cargo test --all-targets`（動 handler/service，需 Postgres） |
| **PR-2（前端）** | availableTransitions 角色注入；軟刪除按鈕 + 確認 dialog + mutation + i18n（zh-TW master + en） | tsc + eslint |

> 跨 PR 邊界必停。PR-1 綠燈 + commit 後停下確認。

## 4. 收尾
- 部署後，兩筆誤送審計畫由 admin 在 UI 直接「駁回」→ 不再需要 token / 自簽。
