# 修復計畫：PR #0-200 code review（adversarial-verified findings）

> 建立日期：2026-06-08 ｜ 來源：`code-review-0-100-report.md` + `code-review-100-200-report.md` + 2026-06-08 逆向驗證
> 範圍：僅含**驗證為「確認需修」的 11 項**（已剔除 3 誤報、降級 5 項可接受）。原則：先報告後修、外科手術式變更、先紅後綠。

## 確認需修清單（11 項）

| # | Finding | 類別 | 嚴重度 |
|---|---|---|---|
| 1 | #55 IACUC 審查者匿名僅前端，PI 可從 API 讀真名/email | security | 🟠High |
| 2 | #138 dashboard get_vet_comments 跨計畫 IDOR | security | 🟠High |
| 3 | #179 approve_transfer 無轉入 PI 角色/自核守衛（SoD） | security | 🟠High |
| 4 | #179 transfer 步驟 2-5 狀態檢查在 tx 外、無 status WHERE（race） | correctness | 🟡Med |
| 5 | #174/#176 vet_advice CRUD 無 audit | compliance | 🟠High |
| 6 | #182 care_record create/update 無 audit | compliance | 🟠High |
| 7 | #167 equipment approve_disposal/restore 無 audit + 非 tx | compliance | 🟠High |
| 8 | #197 storage_location update/transfer 無 audit | compliance | 🟡Med |
| 9 | #63/#97 facility 模組全 mutation 零 audit | compliance | 🟡Med |
| 10 | #93 equipment 校正/報廢 CRUD 無 audit | compliance | 🟢Low |
| 11 | #56 進銷貨報表 COGS 算法（月度未沖 SR + 按類別 cogs=0） | money | 🟡Med |

---

## 建議拆 PR（5 個）

| PR | 涵蓋 | 風險 | 測試層級 | 需裁定 |
|---|---|---|---|---|
| **A — 存取控制/IDOR/SoD** | #55 / #138 / #179-SoD / #179-race | 中（authz + 狀態機） | `--all-targets`（整合：IDOR 回歸） | 否 |
| **B — 動物/醫療 audit 補登** | #174/#176 vet_advice / #182 care_record | 中（SDD 遷移） | `--all-targets` | 否 |
| **C — ERP/資產 audit 補登 + 原子性** | #167 equipment 報廢/恢復（+tx）/ #197 storage_location / #93 calibration | 中 | `--all-targets` | 否 |
| **D — facility 模組 audit 補登** | #63/#97（25+ mutations） | 中（量大、機械式） | `--all-targets` | 否 |
| **E — 進銷貨 COGS 修正** | #56 | 中（財務算法） | `--lib`（report SQL）+ 手驗 | **是** |

---

## PR A — 存取控制 / IDOR / SoD（security，最高優先）

### A1 #55 審查者匿名（後端裁剪）
- `services/protocol/comment.rs::get_comments`（或 handler `list_review_comments`）依 viewer 角色裁剪：viewer 非 IACUC_STAFF/CHAIR/REVIEWER/VET/admin 時，回傳前清空 `reviewer_name`/`reviewer_email`（或以伺服器端穩定代號「審查者 A/B/C」取代）。
- **驗收**：以 PI 身分呼叫 review-comments 端點 → 回應不含審查者真名/email；以 IACUC_STAFF → 含真名。整合測試。

### A2 #138 dashboard get_vet_comments boundary
- `handlers/animal/dashboard.rs::get_vet_comments`：對非 `view_all` 使用者取 `access::accessible_protocol_ids`，SQL 加 `WHERE p.protocol_id = ANY($boundary)`（空集合回空），比照 `report_protocol_boundary`。
- **驗收**：非 view_all PI 只看到自己計畫的 vet comments；admin 看全部。整合測試。

### A3 #179 approve_transfer SoD（狀態機層）
- `services/animal/transfer.rs::approve`（或 handler）：加「轉入 PI 角色」檢查（非僅 `animal.record.create`）+ 防 `initiated_by == approver` 自核。對齊 signature-signing-authority 模型（VET + 轉出/入 PI）。
- **驗收**：非轉入 PI 不能 approve；發起人不能自核。

### A4 #179 transfer 步驟 2-5 race
- 步驟 2-5 的 `before` 讀取移入 tx + `FOR UPDATE`；UPDATE 加 `AND status = '<expected>'` 並檢 rows_affected==0 → Conflict。
- **驗收**：並發 approve/complete 只成功一次（整合或 service 測試）。

---

## PR B — 動物/醫療 audit 補登（compliance）

### B1 #174/#176 vet_advice CRUD → SDD audit
- `VetAdviceRecordService::create/update/delete` 改 SDD 簽名 `(pool, actor, ...)` + tx 內 `log_activity_tx`，event_type `VET_ADVICE_RECORD_CREATE/UPDATE/DELETE`，before snapshot 走 FOR UPDATE。handler 傳 actor。
### B2 #182 care_record create/update → SDD audit
- `CareRecordService::create/update` 收 actor + `log_activity_tx`（`CARE_RECORD_CREATE/UPDATE`），清掉 update 內的 TODO。
- **驗收**：create/update/delete 後 `user_activity_logs` 有對應 HMAC-chained 紀錄含正確 actor + before/after diff。整合測試。

---

## PR C — ERP/資產 audit 補登 + 原子性（compliance）

### C1 #167 equipment approve_disposal / restore_equipment
- 兩條改 `pool.begin()` + `SELECT ... FOR UPDATE` + 狀態守衛（`AND status=...`）+ 同 tx `log_activity_tx`（`DISPOSAL_APPROVE`/`DISPOSAL_RESTORE`），比照 `sign_disposal_approver_tx`。
### C2 #197 storage_location update_inventory_item / transfer_inventory
- 兩函式收 `&ActorContext`、tx 內 FOR UPDATE 取 before、同 tx 寫 `STORAGE_INVENTORY_UPDATE/TRANSFER`，比照 `create_inventory_item`。
### C3 #93 equipment calibration/disposal CRUD（Low）
- `create/update/delete_calibration` + `create_disposal` 補 `log_activity_tx`。
- **驗收**：上述 mutation 後有 HMAC-chained audit；整合測試覆蓋 disposal approve + storage update。

---

## PR D — facility 模組 audit 補登（compliance，量大）

- `services/facility.rs` 全部 building/zone/pen/department/species 的 create/update/delete（25+ mutations）比照 animal/equipment 接 Service-driven audit（收 actor + `log_activity_tx`，event_type `FACILITY_*_CREATE/UPDATE/DELETE`）。handler 傳 actor。
- 機械式但量大，建議獨立 PR；可分 commit（building/zone/pen/dept/species）。
- **驗收**：每類 mutation 後有 audit；抽樣整合測試。

---

## PR E — 進銷貨 COGS 修正（money）⚠️ 需裁定

- **#56-1 月度 COGS**：`report.rs::cogs_monthly` 改 `SUM(debit_amount) - SUM(credit_amount)`（5200 淨額），以正確沖減 SR 銷貨退貨貸方。（此項算法明確，可直接做。）
- **#56-2 按類別 COGS**：`purchase_sales_by_category` 目前 `cogs_amount=0`、`gross_profit=sales_amount`。兩個方向：
  - **(a) 計算真實 COGS**：從 stock_ledger 加權平均成本或 journal 5200 按品類歸集 → 真毛利。較準但較複雜，需定義成本來源。
  - **(b) 標示 N/A**：移除誤導的 `gross_profit=sales`，按類別只報銷貨額、毛利欄標「不適用（請看月度損益）」。最小、不誤導。
  - **→ 請裁定 (a) 或 (b)**；另確認月度 net-cogs 公式 (#56-1) 認可。

---

## 不修（驗證後降級 / 誤報，僅記錄）

- 🟡 #91 AI「read」scope（admin-only、by-design）→ 建議只在 docs/DESIGN 註明「AI key = 全域唯讀」。
- 🟡 #72 weight import actor=System（audit 有寫、僅誤標）/ #48 終態 pen_id（cosmetic）/ HMAC chain 排序（單 instance 罕見）/ #168 role is_system（admin+簽章+audit）/ DateTextInput（後端擋下）→ 低優先，可入 backlog 或不處理。
- 🟡 #61 SO/DO 計畫歸屬 → **請確認是否為「倉管可代任意活躍計畫開銷貨」的預期工作流**；是則不修。
- ❌ #91 AI is_internal / #194 DB_ROLLBACK runbook / #158 verifier TZ → 誤報，不處理。

## Self-check

- [x] 僅納入逆向驗證「確認需修」項；誤報/可接受已剔除。
- [x] 多解處（#56-2）已標「需裁定」，未 silent pick。
- [x] 每個 PR 列驗收（先紅後綠 / 整合回歸）。
- [x] audit 補登一律 in-tx + 正確 actor + before/after，對齊既有 R26 SDD pattern。
