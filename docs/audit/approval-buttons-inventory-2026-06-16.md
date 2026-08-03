# 「核准」按鈕運作邏輯盤點報告

> **日期：** 2026-06-16
> **範圍：** 系統內所有「核准 / 審查決議」按鈕的運作邏輯（前端按鈕 → API 端點 → 權限 → service 狀態轉換 / 交易 / 樂觀鎖 / audit / 電子簽章 / 通知）
> **產出對應：** 本報告為盤點結果；後續改善項已立案於 `docs/TODO.md` § R71。
> **方法：** 4 路並行 codebase 盤點（Protocol/Amendment、ERP/設備、GLP/PI/動物欄位修正、前端 UI）+ 關鍵發現逐項回讀程式碼驗證。所有結論均引用 `檔案:行號`。

---

## §0 摘要（TL;DR）

本次盤點涵蓋 **9 類 IN-SCOPE 核准動作**（排除使用者指定的 5 個流程，見 §8）。整體結論：

- **核准動作在合規防護上「兩極化」**：GLP 變更請求、ERP 單據核准、設備維護驗收（含簽章）做得最完整（tx + `FOR UPDATE` + in-tx audit + ActorContext）；但**動物欄位修正、PI 帳號邀請、設備閒置申請**三個核准動作幾乎沒有防護（無交易、無 audit、無併發守衛），且都用 `is_admin()` 硬編碼權限而非 permission key。
- **最高風險 gap**：**動物欄位修正核准會直接改動物 identity 級欄位（耳號 / 出生日期 / 性別 / 品種），卻完全無 audit log、無交易原子性** — 對 GLP/21 CFR §11 追溯是明確缺口。
- **前端 UX 三套權限機制混用**（`hasPermission` token / role 字串比對 / 完全無前端 gate），且僅「設備維護驗收」具二級認證（簽章+密碼），其餘高風險決議（Protocol 核准、單據最終核准）皆無。
- **發現一個前端缺口**：Amendment 決議端點（`/amendments/:id/decision`、`/status`）後端存在，但前端無任何按鈕呼叫（見 §9）。

---

## §1 範圍與假設

### 排除（使用者指定，不在本次盤點）
GLP 受控文件 approve（`/admin/documents/:id/approve`）、HR 請假 / 加班核准、動物移轉核准、設備報廢核准、安樂死核准/申訴。完整列於 §8。

### 重要假設：採「流程層級」排除，非「子系統層級」
使用者排除的是**特定 5 個流程**。因此本盤點將下列「與排除流程相鄰但不同」的核准動作**納入範圍**：

| 納入 | 理由（與排除項區隔） |
|---|---|
| GLP **變更請求**核准 | 排除的是 GLP **受控文件** approve，change-request 為另一端點 |
| 設備**閒置 / 維護審查** | 排除的是設備**報廢**，閒置/維護為不同流程 |
| 動物**欄位修正**審查 | 排除的是動物**移轉**，欄位修正為不同流程 |

> ⚠️ 若上述任一項實際上應比照其相鄰流程一併排除，請告知，將自盤點移除並調整 R71 立案。

---

## §2 IN-SCOPE 核准動作後端總表

| # | 核准動作 | 端點 | 權限 | tx + FOR UPDATE | 樂觀鎖/409 | in-tx Audit | 電子簽章 | 通知 | Anon 拒絕 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | AUP/Protocol 審查決議 | `POST /protocols/:id/status` | `aup.protocol.change_status`（+delete 用 delete perm） | ✅ tx+FOR UPDATE | ❌（version 欄閒置） | ✅ `PROTOCOL_APPROVE` 等 | ❌（另端點，見 #2） | ✅ PI/委員/獸醫 | ⚠️ 靠 handler 層 |
| 2 | Protocol 審查核准簽章 | `POST /signatures/protocol/:id` | 角色 chair/staff | ❌ pool（非 tx） | — | ❌ 不寫 user_activity_logs | ✅ 本體即簽章 | ❌ | 靠 handler |
| 3 | Amendment 審查決議（核准/退回） | `POST /amendments/:id/decision` | `aup.amendment.approve` + DB reviewer 雙層 | ✅ tx+FOR UPDATE | ✅ status-guard→409 | ❌ 僅 status_history+簽章表 | ✅ 終態自動簽 | ❌ | ⚠️ 裸 Uuid |
| 4 | Amendment 泛型狀態變更 | `POST /amendments/:id/status` | `aup.protocol.change_status`（跨域 key） | ✅ tx+FOR UPDATE | ✅ | ❌ 且 history 寫在 tx **外** | ❌ | ✅ | ⚠️ 裸 Uuid |
| 5 | Amendment 標記生效 | `POST /amendments/:id/effective` | `aup.protocol.change_status` | ✅ tx+FOR UPDATE+CAS | ✅ CAS→409 | ✅ `AMENDMENT_EFFECTIVE` | ❌（核准時已簽） | ✅ | ✅ `require_user()` |
| 6 | ERP 單據核准（倉管） | `POST /documents/:id/approve` | `erp.document.approve` + 角色 WAREHOUSE_MANAGER | ✅ tx+FOR UPDATE | ❌（靠 status 守衛） | ✅ `DOC_APPROVE`/`DOC_WM_APPROVE` | ❌ | ✅ 建立者 | ✅ `require_user()` |
| 7 | ERP 單據最終核准（admin） | `POST /documents/:id/admin-approve` | `erp.document.approve` + `is_admin()` | ✅ tx+FOR UPDATE | ❌ | ✅ `DOC_ADMIN_APPROVE` | ❌ | ✅ | ✅ `require_user()` |
| 8 | GLP 變更請求核准 | `POST /admin/change-requests/:id/approve` | `change.request.approve` | ✅ tx+FOR UPDATE | ❌（無 version 欄） | ✅ `APPROVE`(GLP) | ✅ `sign_record_tx` | ❌ | ✅ `require_user()` |
| 9 | PI 帳號邀請核准寄送 | `POST /pi-account-invites/:id/approve-send` | `is_admin()` 硬編碼 | ❌ **無 tx** | ❌ | ❌ **無 audit** | ❌ | ✅ email（reset link） | ❌ 未用 ActorContext |
| 10 | 設備閒置申請核准 | `POST /equipment-idle-requests/:id/approve` | `equipment.idle.approve` | ❌ **無 tx/無 FOR UPDATE** | ❌ | ❌ **無 audit** | ❌ | ✅ 站內（申請人） | ❌ 未用 ActorContext |
| 11 | 設備維護驗收 | `POST /equipment-maintenance/:id/review` | `equipment.maintenance.review`/`equipment.manage` | ✅ tx+FOR UPDATE | ❌ | ✅ `MAINTENANCE_REVIEW_APPROVE/REJECT` | ❌（另端點 #12） | ❌ **無通知** | ✅ `require_user()` |
| 12 | 設備維護驗收簽章 | `POST /signatures/maintenance/:id/reviewer` | `equipment.maintenance.review`/`equipment.manage` | ✅ tx+FOR UPDATE | ✅ 已簽→409 | ✅ `MAINTENANCE_REVIEWER_SIGNATURE` | ✅ `sign_record_tx` | ❌ | ✅ `require_user()` |
| 13 | 動物欄位修正審查 | `POST /animals/animal-field-corrections/:id/review` | `is_admin()` 硬編碼 | ❌ **無 tx/無 FOR UPDATE** | ❌ | ❌ **無 audit** | ❌ | ❌ **無通知** | ❌ 未用 ActorContext |

> **GLP 結案報告 / 管理審查**：經查 `study_report` 與 `management_review` **目前無獨立核准/簽署動作**，僅 create/update（見 §4-F）。`management_review` 有 `approved_at` 欄位（`migrations/016_glp_compliance.sql:249`）卻無核准入口與守衛，列為 §7 立案項。

---

## §3 各動作運作邏輯詳述

### A. AUP/Protocol 審查決議（#1, #2）
- **狀態機**：`models/protocol.rs:92-106 can_change_status_to`（終態 egress 白名單）；entry guard 散落於 `services/protocol/status.rs`。核准守衛：APPROVED/APPROVED_WITH_CONDITIONS 必須 from `UNDER_REVIEW` 且**所有 primary reviewer 皆已發表意見**（`status.rs:166-225`）。
- **Handler/Service**：`handlers/protocol/crud.rs:309 change_protocol_status` → `services/protocol/status.rs:24 change_status_tx`（pool wrapper `:685`）。
- **Audit**：✅ in-tx `log_activity_tx`（`status.rs:325`），event_type 動態（`PROTOCOL_APPROVE` / `_CONDITIONAL` / `PROTOCOL_REJECT`，`history.rs:24-58`）+ 時間軸 `protocol_activities`。
- **簽章**：❌ 與狀態機**解耦** — 核准（#1）不寫簽章，簽章走獨立端點 #2（`handlers/signature/protocol_review.rs:35`）。pool 版 `sign_internal`（`services/signature/mod.rs:368-393`）**僅 INSERT `electronic_signatures`，不寫 `user_activity_logs`/HMAC chain**（已回讀驗證）。
- **gap**：(a) 無不變式保證「APPROVED 必有簽章」；(b) `Protocol.version`（`protocol.rs:124`）樂觀鎖欄位閒置未用。

### B. 變更申請 Amendment 決議（#3, #4, #5）
- **狀態機**：`models/amendment.rs:102-128 can_transition_to`（集中白名單，比 protocol 易讀）+ `is_terminal`。
- **決議（#3）**：`handlers/amendment.rs:271 record_amendment_decision` → `services/amendment/workflow.rs:530 record_decision`。各 reviewer decision 聚合：全 APPROVE→APPROVED / 任一 REJECT→REJECTED / 任一 REVISION→REVISION_REQUIRED（`workflow.rs:642-684`）。終態自動建簽章 + 回填 FK（`insert_decision_signature_tx` `workflow.rs:52`），HMAC-SHA256 v2。
- **gap（#3）**：⚠️ **僅寫 `amendment_status_history` + 簽章表，未寫 `user_activity_logs`/HMAC chain** — 最核心的核准/否決決議反而缺全域 audit（對比 #5 mark_effective ✅ 與 #1 protocol ✅）。REVISION 分支 history actor 用 `SYSTEM_USER_ID` 而非觸發者（`workflow.rs:656`）→ actor 歸因失真。
- **gap（#4）**：⚠️ `record_status_change` 在 `tx.commit()` **之後**才用 pool 寫 history（`workflow.rs:756→758`）→「狀態已變、歷程遺失」窗口；且用 `aup.protocol.change_status`（跨域 key）。
- **#5 mark_effective**：B 組中最完整（in-tx history + `log_activity_tx` + CAS→409 + `require_user()`）。
- **附帶**：`classify_amendment`（Minor 分類即終態 ADMIN_APPROVED + 自動簽章，`workflow.rs:304-361`）同 #3 缺全域 audit chain。

### C. ERP 單據核准（#6, #7）
- **依單據類型大量分支**（`services/document/workflow.rs:234-422`）：`affects_stock()` → `StockService::process_document`；PO → 自動建 GRN 草稿（額外 `DOC_CREATE`）；GRN → 超量入庫守衛 `ensure_no_over_receipt`；STK → 自動產生待審 ADJ。大金額 ADJ 走兩段式（WM `wm_approved` → admin 最終核准 #7）。
- **防護完整**：tx + `FOR UPDATE` + in-tx audit + `require_user()`。會計過帳用巢狀 SAVEPOINT 隔離（失敗不阻擋核准）。
- **觀察**：`erp.document.approve` permission 之外又硬檢查 `ROLE_WAREHOUSE_MANAGER`（`document.rs:214`），permission 與角色雙閘重疊，語意應文件化。

### D. GLP 變更請求核准（#8）
- `handlers/glp_compliance.rs:296 approve_change_request` → `services/glp_compliance.rs:762`。`submitted`/`under_review`→`approved`。tx + `FOR UPDATE` + in-tx audit（`event_type="APPROVE"`）+ `sign_record_tx`（`record_type="change_request"`，強制驗密碼）+ `require_user()`。SoD：泛型 `update_change_request` 擋下直接設 `approved`（`:719-728`）。**防護完整**。
- **觀察**：無 version 樂觀鎖（`ChangeRequest` 無 version 欄），靠 FOR UPDATE + 狀態機防重複；屬風格不一致，非漏洞。

### E. 設備閒置 / 維護審查（#10, #11, #12）
- **維護驗收（#11/#12）防護完整**：tx + `FOR UPDATE` + in-tx audit；#12 簽章端點具 `sign_record_tx` + 「已簽→Conflict 409」冪等守衛 + 二級認證（簽章+密碼）。**唯一缺口**：#11 驗收結果**無通知**（對比閒置核准有通知申請人）。
- **設備閒置核准（#10）是明顯離群者**（`services/equipment.rs:1847-1979`）：⚠️ **無 tx、無 FOR UPDATE、無 audit、未用 ActorContext**。SELECT→UPDATE idle_request→UPDATE equipment→INSERT status_log 全部對 pool 各自 execute（非原子）。與**同一檔案**的維護驗收（防護齊全）強烈對比，疑為未隨 Service-driven audit 遷移完成之舊碼。

### F. GLP 結案報告 / 管理審查（無核准動作）
- `study_report`：僅 create/update（`services/glp_compliance.rs:1168/1205`）。`update` 明確擋下把 status 設 `approved`/`signed`（`:1221-1228`），但程式碼自承「**目前尚無正式 `sign_study_report` 流程**，先止血」（`:1218-1220`）。
- `management_review`：僅 create/update（`:433/467`）。⚠️ **比 study_report 更鬆** — `update` 的 `status = COALESCE($4, status)`（`:484`）**無任何發布狀態守衛**，持 `glp.management_review.manage` 者可經泛型 PUT 直接設 status 並寫 `approved_at`，繞過任何簽核。

### G. PI 帳號邀請核准寄送 / 動物欄位修正審查（#9, #13）
- **PI 邀請（#9）**：`handlers/protocol/pi_provision.rs:101`。⚠️ **無 service 層**（業務邏輯 + raw SQL 直接寫 handler，違反分層）；無 tx、無 audit；`is_admin()` 硬編碼權限。寄送 password-reset token 給外部 PI 屬敏感動作卻零 audit。並發兩 admin 可各寄一封（無冪等）。
- **動物欄位修正（#13）**：`services/animal/field_correction.rs:147 review` →（核准）`apply_correction:207` 直接 UPDATE `animals` 的 `ear_tag`/`birth_date`/`gender`/`breed`（已回讀驗證 `:207-260`）。⚠️ **無 tx（改動物與標記申請分兩次 execute，非原子）、無 FOR UPDATE、無 audit、無通知**；`is_admin()` 硬編碼權限。**改 identity 級欄位卻無任何追溯紀錄 — 本次盤點合規風險最高項**。

---

## §4 前端按鈕總表

| # | 按鈕（流程） | 位置 | 權限 gate（前端） | 確認 | 二級認證 | 防連點(isPending) | i18n |
|---|---|---|---|---|---|---|---|
| 1 | 變更狀態（Protocol 決議） | `ProtocolDetailHeader.tsx:91`→`StatusChangeDialog.tsx` | role 字串比對 | Select 對話框（退回強制備註） | ❌ | ✅ | ✅ |
| 2 | 標記生效（Amendment） | `components/protocol/AmendmentsTab.tsx:304` | `hasPermission('aup.protocol.change_status')` | ✅ ConfirmDialog | ❌ | ✅ | 部分 |
| 3 | 倉庫核准 / 最終核准（ERP） | `pages/documents/DocumentDetailPage.tsx:384/394` | role 比對（WM / admin） | ❌（駁回才填原因） | ❌ | ✅ | ❌ 硬編碼 |
| 4 | 核准（GLP 變更請求） | `pages/admin/ChangeControlPage.tsx:180` | `hasPermission('change.request.approve')` | ❌ | ❌ | ❌ **可連點** | ❌ 硬編碼 |
| 5 | 核准寄送（PI 邀請） | `pages/protocols/components/PiAccountInvitesTab.tsx:88` | ❌ **無前端 gate** | ✅ ConfirmDialog | ❌ | ✅ | ❌ 硬編碼 |
| 6 | 核准/駁回（設備閒置） | `pages/admin/components/IdleTabContent.tsx:91` | `hasPermission('equipment.idle.approve')` | ❌ | ❌ | ❌ **icon 鈕可連點** | aria 有 |
| 7 | 驗收通過/退回（設備維護） | `MaintenanceReviewDialog.tsx:157` | `hasPermission('equipment.maintenance.review')` | ✅ Dialog | ✅ **簽章+密碼** | ✅ | ✅ |
| 8 | 批准/拒絕（動物欄位修正） | `pages/admin/AnimalFieldCorrectionsPage.tsx:181` | ❌ **無前端 gate** | ❌（拒絕才填原因，選填） | ❌ | ✅ | ❌ 硬編碼 |

> **設備閒置駁回**固定送 `rejection_reason: '駁回'`（`EquipmentPage.tsx:321`），未提供填寫 UI。

---

## §5 跨流程一致性發現（彙總）

1. **合規防護兩極化**：#3/#9/#10/#13（amendment 決議、PI 邀請、設備閒置、動物欄位修正）在 audit / 交易原子性 / 併發守衛上明顯落後同類動作（ERP、GLP change request、維護驗收）。
2. **權限機制三套混用**：後端 `require_permission!(token)`（多數）vs `is_admin()` 硬編碼（#9 #13 #7-admin）；前端 `hasPermission` vs role 字串比對 vs 無 gate（#5 #8）。
3. **電子簽章覆蓋不均**：僅 #2(protocol)、#8(change request)、#12(maintenance) 有簽章；Protocol 核准（#1）與簽章解耦、無強制耦合。
4. **二級認證僅 #11/#12（維護驗收）有**；其餘高風險決議（Protocol 核准、單據最終核准）皆無。
5. **樂觀鎖一律缺席**：全部動作無 `version`/409 樂觀鎖，採「tx + FOR UPDATE + status 守衛」悲觀鎖派（一致設計取向，非個別 bug）；唯 #10 連 tx/FOR UPDATE 都沒有。
6. **交易完整性例外**：#4（amendment 狀態）history 寫在 tx 外；#9/#10/#13 完全無 tx。
7. **i18n 硬編碼**：#3 #4 #5 #8 的按鈕/toast 為硬編碼中文，未走 `t()`。
8. **前端防連點 gap**：#4（ChangeControlPage 核准鈕）、#6（IdleTabContent icon 鈕）無 `isPending` disable。

---

## §6 Gap → R71 立案對照

詳見 `docs/TODO.md` § R71。優先序：

| 優先 | Gap | R71 |
|---|---|---|
| 🔴 高（合規/資安） | 動物欄位修正核准：改 identity 欄位無 audit + 無交易原子性 + is_admin 硬編碼 | R71-1 |
| 🔴 高 | PI 邀請核准寄送：無 audit + 無 tx + 邏輯混 handler（raw SQL） | R71-2 |
| 🔴 高 | 設備閒置核准：無 tx/FOR UPDATE/audit/ActorContext | R71-3 |
| 🟠 中高 | Amendment 決議（#3）+ classify 缺全域 audit chain（user_activity_logs/HMAC） | R71-4 |
| 🟠 中 | Amendment 泛型狀態（#4）history 寫在 tx 外 | R71-5 |
| 🟠 中 | GLP management_review 無核准守衛（有 approved_at 無 RELEASE_STATUSES 守衛）；study/management 無正式簽署流程 | R71-6 |
| 🟡 中 | Protocol 核准與電子簽章無強制耦合（無「已核准必有簽章」不變式） | R71-7 |
| 🟡 低 | 前端權限 gate 機制統一（hasPermission vs role vs 無 gate）+ #5/#8 補前端 gate | R71-8 |
| 🟡 低 | 前端防連點：#4/#6 補 `isPending` disable | R71-9 |
| 🟡 低 | 前端核准鈕補確認對話框（Protocol/ERP/GLP/idle/animal）+ #6 駁回補填原因 UI | R71-10 |
| 🟡 低 | i18n：#3/#4/#5/#8 按鈕與 toast 去硬編碼 | R71-11 |
| 🔵 待確認 | Amendment 決議端點（`/decision`,`/status`）前端無 UI 呼叫 — 確認決議是否經他路徑或缺漏 | R71-12 |

> 二級認證是否擴及 Protocol 核准 / 單據最終核准、樂觀鎖是否補上，屬**產品/合規決策**，未逕自立案為實作項，於 R71 備註待拍板。

---

## §7 排除清單（使用者指定，未盤點）

| 流程 | 端點 | 備註 |
|---|---|---|
| GLP 受控文件 approve | `POST /admin/documents/:id/approve` → `approve_controlled_document` | — |
| HR 請假核准 | `POST /hr/leaves/:id/approve` → `approve_leave` | — |
| HR 加班核准 | `POST /hr/overtime/:id/approve` → `approve_overtime` | — |
| 動物移轉核准 | `POST /transfers/:id/approve` → `approve_transfer` | 含 transfer 簽章流程 |
| 設備報廢核准 | `POST /equipment-disposals/:id/approve` → `approve_disposal` | 含 `POST /signatures/disposal/:id/approver` |
| 安樂死核准 / 申訴 | `POST /euthanasia/orders/:id/approve`、`POST /euthanasia/appeals/:id/decide` | — |

> 若「以後核准」指全系統所有核准（含上列 5 個），需另開一輪盤點。

---

## §8 待確認 / 邊界項

1. **§1 流程層級排除假設**：GLP 變更請求 / 設備閒置·維護 / 動物欄位修正是否應比照相鄰排除項一併排除？（目前納入）
2. **Amendment 決議前端 UI**（R71-12）：後端 `record_amendment_decision`、`change_amendment_status` 存在，前端零呼叫端。需確認審查決議是否經其他 UI 路徑（如共用 protocol 審查介面）或尚未實作。
3. **GLP study_report / management_review 簽署流程**：程式碼自承為已知 follow-up（`services/glp_compliance.rs:1218-1220`）。
