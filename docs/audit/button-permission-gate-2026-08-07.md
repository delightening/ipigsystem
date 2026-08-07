# 全站按鈕權限閘稽核報告

- 日期：2026-08-07（GMT+8）
- 觸發：使用者指出 `animals/reservation-planning` 的操作按鈕對無權限者仍顯示，要求全域徹查
- 定案規則（本次使用者裁定）：
  1. **無權限 → 完全隱藏按鈕**（不用 disabled + tooltip）
  2. **判準一律用 permission code**，禁用 role 硬判
  3. 先出報告，由使用者決定修哪些、怎麼切 PR

---

## 0. 一句話結論

**後端授權是紮實的，問題全在前端。**
後端 56 個 handler 檔共 396 處 `require_permission!`，加上 service 層的擁有權檢查（如
`access::require_protocol_related_access`、巡場報告依 status 分派），抽查未發現「可寫入但完全無授權檢查」
的端點。因此本次發現的**不是安全漏洞，是 UX 缺陷**：使用者看得到按鈕、按下去吃 403。

但有兩個副作用值得認真看待：

- **誤導性最強的是稽核 / 簽核類按鈕**（安樂死同意、簽章作廢、審查委員指派）。使用者以為自己有職權，
  按下去才發現沒有，對合規流程是壞的訊號。
- **403 會餵給封鎖計數器**。既有已知問題：`response_logger` 對所有 403 無差別計數
  （見記憶 `idor-403-counter-coarse`），讓使用者持續點沒權限的按鈕，等於讓他們自己撞 IP 封鎖。
  這條把「純 UX 問題」升級成「會咬人的 UX 問題」。

---

## 1. 方法與涵蓋範圍

**已掃範圍（完整）**
- 後端：`backend/src/handlers/**/*.rs` 全部 56 檔，抽出 `pub async fn` ↔ `require_permission!` 對應表。
- 前端：`frontend/src/pages/**` + `frontend/src/components/**` 中**所有**發出
  `api.post/put/patch/delete` 的檔案，共 **117 檔**，逐檔統計
  「權限判斷次數（`hasPermission` / `RequirePermission` / `isAdmin()` / `hasRole`）」
  對「按鈕與選單項數（`<Button` / `DropdownMenuItem`）」。
- 路由：`frontend/src/App.tsx` 全部路由的 `RequirePermission` / `AdminRoute` / `DashboardRoute` 覆蓋。

**已手動讀碼驗證**：本報告 P0 全部項目、P1 的 ERP 與 AUP 代表項目、
`RequirePermission.tsx`、`DashboardRoute.tsx`、`stores/auth.ts::hasPermission`、
`services/protocol/comment.rs::resolve_comment`、`handlers/animal/vet_patrol.rs::update_vet_patrol_report`。

**未涵蓋 / 本報告不做結論的部分（誠實揭露）**
- 純 hook 檔（`use*Mutations.ts`，本身無按鈕）只確認「有無自帶閘」，**未逐一追它的所有呼叫端**。
  少數 hook 可能被某個有閘的元件呼叫而實際安全。修的時候閘要下在按鈕上、不下在 hook 上，
  所以這不影響修法，但會影響「還有幾顆漏網」的精確計數。
- **未做執行期驗證**——沒有實際用各角色帳號登入點過每顆按鈕。本報告是靜態分析。
- E2E / 單元測試對「按鈕可見性」的覆蓋率未評估。

---

## 2. 統計

| 項目 | 數 |
|---|---|
| 後端 handler 檔 | 56 |
| 後端 `require_permission!` 處 | 396 |
| 前端會發 mutation 的 UI 檔 | 117 |
| 其中**完全沒有任何權限判斷** | **73** |
| 其中有權限判斷 | 21（其餘 23 檔為純 API wrapper / 自助功能） |

73 檔裡扣掉「本來就不需要閘」的（自助改密碼、2FA、個人顯示偏好、忘記密碼、自己的通知），
**實際需要補閘的約 55 檔**。

---

## 3. P0 — 任何登入者都看得到，且動作有實質後果

這些頁面的**路由層完全沒有權限閘**（`App.tsx` 只包 `ProtectedRoute`＝登入即可），
所以按鈕層是唯一防線，而按鈕層是空的。

### 3-1 實驗動物子紀錄（`/animals/:id`，路由無閘）

`AnimalDetailTabContent.tsx` 把各 tab 直接 lazy-load 渲染，**沒有傳任何 `canEdit` / `readOnly` prop**。
以下元件內權限判斷次數皆為 **0**：

| 元件 | 使用者看得到的按鈕 | 後端實際要求 |
|---|---|---|
| `components/animal/ObservationsTab.tsx` | 新增 / 編輯 / 刪除 / 複製 觀察紀錄 | `animal.record.create` `.edit` `.delete` `.copy` |
| `components/animal/SurgeriesTab.tsx` | 新增 / 編輯 / 刪除 / 複製 手術紀錄、PDF 匯出（13 顆） | `animal.record.*` / `animal.export.surgery` |
| `components/animal/WeightsTab.tsx` + `ManualWeightEntry.tsx` | 新增 / 編輯 / 刪除 體重 | `animal.record.create` `.edit` `.delete` |
| `components/animal/VaccinationsTab.tsx` | 新增 / 編輯 / 刪除 疫苗接種 | `animal.record.create` `.edit` `.delete` |
| `components/animal/PathologyTab.tsx` | 上傳 / 更新 病理報告 | `animal.pathology.upload` |
| `components/animal/QuickEditAnimalDialog.tsx` | 快速編輯動物 | `animal.animal.edit` |
| `pages/animals/components/AnimalHeaderCard.tsx` | 變更欄舍（`PUT /animals/:id`） | `animal.animal.edit` |
| `components/animal/ImportDialog.tsx` | 匯入動物 / 匯入體重 | `animal.animal.import` |
| `components/animal/ExportDialog.tsx` | 匯出病歷 | `animal.export.medical` |

### 3-2 動物「不可逆 / 合規」動作（同樣路由無閘）

| 元件 | 按鈕 | 後端實際要求 | 為什麼特別嚴重 |
|---|---|---|---|
| `components/animal/EuthanasiaOrderDialog.tsx` | 開立安樂死單 | `animal.record.create` | 開單即進入安樂死流程 |
| `components/animal/EuthanasiaPendingPanel.tsx` | **同意安樂死**（先建 `APPROVE` 簽章再 `POST /euthanasia/orders/:id/approve`）、提出申訴 | 後端擋 | 這是簽章動作。讓沒有簽署權的人看到「同意」鈕，是合規上最不該出現的畫面 |
| `components/animal/EmergencyMedicationDialog.tsx` | 緊急給藥 | `animal.record.emergency` | 獨立於一般 record 權限的高風險動作 |
| `pages/animals/AnimalSourcesPage.tsx`（`/animal-sources` 路由無閘） | 新增 / 編輯 / 刪除 來源 | `animal.source.manage`（讀取另需 `animal.animal.view_all`） | 沒有 `view_all` 的人連清單都載不出來，卻看得到「新增」 |

### 3-3 動物預約與試驗規劃（使用者原始回報項）

`/animals/reservation-planning`，路由閘 = `animal.info.assign`（**含唯讀查詢**）。

| 位置 | 按鈕 | 現況 |
|---|---|---|
| `ReservationPlanningPage.tsx:38` | 新增預定試驗 | 無按鈕層閘 |
| `ReservationPlanningGroupCard.tsx:92` | 搜尋配對（→ 批次預約） | 無按鈕層閘 |
| `ReservationPlanningGroupCard.tsx:168` | 正式分配進實驗 | 無按鈕層閘 |
| `ReservationPlanningGroupCard.tsx:172` | 解除預約 | 無按鈕層閘 |
| `EditableRemarkCell`（每一列） | 備註 inline 編輯 | 無按鈕層閘 |

**這頁的問題和其他頁相反**：不是「按鈕該藏沒藏」，是**讀寫共用同一個權限**，
導致 SD / 試驗工作人員**連頁面都進不來**。修法見 §6。

### 3-4 ERP 主檔與倉儲（`/warehouses`、`/inventory/*`、`/products/:id`、`/partners` 路由皆無閘）

| 元件 | 按鈕 | 後端實際要求 |
|---|---|---|
| `components/warehouse/WarehouseActionHeader.tsx` | 匯入倉庫 / 匯出倉庫 / 新增倉庫 / 刪除倉庫（9 顆） | `erp.warehouse.create` `.delete` `.view` |
| `components/warehouse/WarehouseImportDialog.tsx` | 執行匯入 | `erp.warehouse.create` |
| `components/warehouse/WarehouseInactiveDialog.tsx` | 停用倉庫 | `erp.warehouse.edit` |
| `pages/inventory/WarehouseLayoutPage.tsx` | 儲位版面編輯（3 個 mutation） | `erp.storage.edit` |
| `pages/inventory/components/AssignToShelfDialog.tsx` | 分配到儲位 | `erp.storage.inventory.edit` |
| `pages/master/ProductDetailPage.tsx` | 產品編輯 / 狀態切換等（5 顆） | `erp.product.edit` |
| `components/partner/PartnerImportDialog.tsx` | 匯入夥伴 | `erp.partner.create` |

### 3-5 AUP 計畫書（`/protocols`、`/protocols/:id` 路由無閘）

| 元件 | 按鈕 | 後端實際要求 |
|---|---|---|
| `components/protocol/ReviewersTab.tsx` | 指派審查委員 | `aup.review.assign` |
| `components/protocol/VetReviewForm.tsx` | 儲存獸醫審查表 | 後端硬檢 `ROLE_VET` or admin |
| `components/protocol/CommentsTab.tsx` | 新增意見 / 標記已解決 / 回覆（6 顆） | `aup.review.comment` / service 層計畫關聯檢查 |
| `components/protocol/AttachmentsTab.tsx` | 上傳 / 刪除附件 | 後端擋 |
| `components/protocol/HistoricalAmendmentDialog.tsx` | 建立歷史修正案（3 個 mutation） | 後端擋 |
| `pages/protocols/components/ProtocolListTab.tsx` | 送審 / 狀態變更 / 複製等（7 顆） | `aup.protocol.change_status` `.delete` / 擁有權 |
| `pages/protocols/.../import-review/ChairmanLetterUpload.tsx` | 上傳主席同意函 | `aup.protocol.import_approved` |

> `VetReviewForm` 是雙重問題：**後端也用 role 硬判**（`handlers/protocol/crud.rs:621`
> `has_role(ROLE_VET)`）。依「禁 role 硬判」原則，前後端應一起改成 permission code。

---

## 4. P1 — 路由層有閘但比動作粗，或閘只覆蓋部分按鈕

| 位置 | 狀況 |
|---|---|
| `pages/animals/VetPatrolReportListPage.tsx` | 路由閘 `animal.record.view`（唯讀等級），但頁面有編輯 / 刪除 / PDF；元件內僅 2 處判斷，未覆蓋全部 |
| `pages/master/ProductsPage.tsx` | 2 處判斷 vs 4 顆按鈕 + 3 個 mutation，覆蓋不完整 |
| `pages/admin/QASopPage.tsx` | 路由閘 `qau.sop.view`（唯讀），頁面 6 顆按鈕含寫入，僅 2 處判斷 |
| `components/protocol/AmendmentsTab.tsx` | 3 處判斷 vs 10 顆按鈕，需逐顆確認 |
| `pages/documents/DocumentDetailPage.tsx` | 6 處判斷 vs 13 顆按鈕，需逐顆確認 |
| `pages/protocols/.../NoticeAcknowledgementCard.tsx` | 無判斷；`acknowledge_notice` 後端走擁有權而非 permission，需確認前端是否該對非當事人隱藏 |
| `pages/reports/components/ApAgingTab.tsx`、`ArAgingTab.tsx` | 無判斷；建立付款 / 收款需 `erp.document.create` |
| `pages/messaging/MessagingPage.tsx` | 路由閘 `messaging.send`，但頁內 6 個 mutation 未逐一判斷 |

---

## 5. P2 — admin 專屬頁，風險低但仍違反新規則

以下都在 `AdminRoute` 底下（僅 `admin` / `SYSTEM_ADMIN` 可達），按鈕沒閘的實際影響小，
但若日後把某頁開放給非 admin 角色，會立刻變成 P0：

`pages/admin/components/BatchCreatePenDialog.tsx`、`DataExportImportCard.tsx`、
`InvalidateSignatureDialog.tsx`（簽章作廢）、`MaintenanceReviewDialog.tsx`、`SystemSettingsCards.tsx`、
`pages/admin/NotificationRouting/hooks/useNotificationRouting.ts`。

---

## 6. `reservation-planning` 權限重設計（使用者已裁定）

### 裁定內容

| 對象 | 檢視 | 操作 |
|---|---|---|
| 執行秘書 `IACUC_STAFF` | ✅ | ✅ |
| 試驗工作人員 `EXPERIMENT_STAFF`（**全體**；SD 由此名單指派而來） | ✅ | ❌ |
| 研究主持人 `STUDY_DIRECTOR` | ✅ | ❌ |
| 負責人 `DIRECTOR` | ✅ | ❌ |
| `admin` / `SYSTEM_ADMIN` | ✅（bypass） | ✅（bypass） |
| 獸醫 `VET` | ❌ | ❌ |
| 計畫主持人 `PI` | ❌ | ❌ |

「操作」＝ 新增預定試驗、批次預約、正式分配、解除預約、**以及每一列的備註 inline 編輯**。

### 需要的改動

1. **新增權限** `animal.planning.view`（migration + `startup/permissions.rs` 角色授權）。
   授予 `IACUC_STAFF`、`EXPERIMENT_STAFF`、`STUDY_DIRECTOR`、`DIRECTOR`。
2. **後端拆閘**（`handlers/planned_experiment.rs`，現況全部共用 `PERM = "animal.info.assign"`）：
   - 讀取 → `animal.planning.view`：`list_planned_experiments`、`get_planned_experiment`、
     `get_reservation_planning`、`list_reservable_animals`
   - 寫入 → 維持 `animal.info.assign`：`create` / `update` / `delete_planned_experiment`、
     `reserve_animals`、`unreserve_animals`、`update_animal_remark`
3. **路由閘放寬**（`App.tsx:519`）：`animal.info.assign` → `animal.planning.view`
4. **按鈕層補閘**（一律 `hasPermission('animal.info.assign')`，無權限完全不渲染）：
   `ReservationPlanningPage.tsx:38`、`ReservationPlanningGroupCard.tsx:92 / 168 / 172`、
   `EditableRemarkCell`（無權限時退成純文字，**不是** disabled 輸入框）。

### 一併確認的既有問題

`components/auth/DashboardRoute.tsx:6` 的 `DASHBOARD_ROLES` **不含** `IACUC_STAFF`、`PI`、
`STUDY_DIRECTOR`、`DIRECTOR`。這幾個角色若無任何 `erp.*` 權限，進 `/dashboard` 會被踢到 `/my-projects`。
`reservation-planning` 路由不在 `DashboardRoute` 底下，本次改動不受影響，
但這是既有的 role 硬判，與「禁 role 硬判」原則衝突 → 列後續項。

---

## 7. 制度層面的三個根因（不修這些，補完閘還會再長回來）

### 7-1 沒有共用的「動作閘」元件
現況每個地方各自寫 `hasPermission('...') && <Button>`，字串手寫、容易漏、也沒有統一測試點。
建議加一個 `<Can permission="x.y.z">` 包裝元件（無權限回傳 `null`，正好符合「完全隱藏」規則），
並用 ESLint rule 或 CI 靜態檢查禁止「同檔內有 mutation 但無 `<Can>` / `hasPermission`」。

### 7-2 前後端權限字串沒有單一真相源
前端手寫字串、後端 `require_permission!` 手寫字串，兩邊靠人眼對齊。
建議由後端 permission seed 產生 TS 常數（例如 `PERMISSIONS.ANIMAL_RECORD_CREATE`），前端只能用常數。
如此「前端閘比後端鬆 / 字串打錯」在 `tsc` 階段就會被抓到。

### 7-3 GUEST 全通行與「完全隱藏」規則衝突
- `stores/auth.ts:260`：`if (user.roles.includes('GUEST')) return true`
- `components/auth/RequirePermission.tsx:46`：`if (isGuest && !guestBlock) return true`

這是 demo 模式的刻意設計（見 `GUEST_DEMO_ARCHITECTURE.md`），**不是 bug**。
但補閘時要確認 guest demo 的畫面不會因此變空，否則 demo 會退化。
建議：補閘一律走 `hasPermission()`（它自帶 guest 短路），不要繞過它自己判角色。

---

## 8. 建議的修法順序

一次改 55 檔的 diff 沒人審得動，且依 `merge-when-green-no-bot` 常設授權會直接自動合進 prod。建議切開：

| PR | 範圍 | 理由 |
|---|---|---|
| 1 | `<Can>` 元件 + permission TS 常數產生（§7-1、§7-2） | 先有工具，後面每支 PR 都短 |
| 2 | `reservation-planning` 權限拆分（§6） | 使用者原始需求，獨立可驗證，含 migration |
| 3 | 動物模組 P0（§3-1、§3-2） | 影響面最大、最常用 |
| 4 | ERP P0（§3-4） | |
| 5 | AUP P0（§3-5）+ `VetReviewForm` 前後端去 role 硬判 | 含後端改動，需單獨審 |
| 6 | P1 逐顆確認（§4） | |
| 7 | P2 + `DASHBOARD_ROLES` 去 role 硬判（§5、§6 末） | 低風險，可最後 |

PR 2 含 migration，取號前照 `RULES_BACKEND.md` §9 查 `origin/main` + prod。

---

## 9. 待使用者決定

1. 上表 PR 切分是否接受？要不要用 `integration/button-permission-gate` 長期分支收攏
   （§7-1 的 `<Can>` 一落地，後面每支 PR 都會碰到同一批檔案，容易衝突）。
2. §7-1 / §7-2 的制度改動要不要做？只補閘不做這兩項，之後新功能還是會漏。
3. P1 那 8 項要逐顆確認——先展開成逐顆清單給你看，還是直接進 PR 6 邊做邊判？
4. 補閘後「使用者看不到按鈕、也不知道該找誰」的問題要不要處理？（例如頁面底部一行
   「部分功能需執行秘書權限」的說明文字，而非在每顆按鈕上做 tooltip。）
