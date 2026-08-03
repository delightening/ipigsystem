# 進銷存系統規格 (iPig ERP)

> **模組**：庫存、採購、領用管理
> **版本**：7.1
> **最後更新**：2026-07-22（修正「銷貨出庫（DO）」相關錯誤敘述，詳見 §5.1；完整系統設計與現況缺口見 [`ERP流程.md`](./ERP流程.md)）

---

## 1. 系統目的

iPig ERP 負責管理系統中所有物資的進銷存作業：

- 飼料、藥品、器材、耗材的採購與入庫
- 庫存盤點與調撥
- 成本追蹤與報表
- 交易夥伴（供應商 / 內部或外部領用對象）分類管理
- **血液檢查費用追蹤報表**

> **重要 1**：本系統**不管理動物**，動物屬於動物管理系統。
>
> **重要 2（2026-07-22 修正）**：本公司**沒有對外銷貨業務**，ERP 裡的「銷貨單（SO）」實際上是**內部耗材領用**——出庫只記「庫存減列」＋「成本轉列」，**不產生應收帳款、不認列營業收入**。舊版規格（v7.0）描述的「SO 銷貨單 → DO 銷貨出庫」兩段式流程、以及暗示對外收費的用語已經過時且不準確，本版更正。詳見 §5.1。

---

## 2. 角色權限

| 角色 | 權限 |
|------|------|
| SYSTEM_ADMIN | 全權管理 |
| WAREHOUSE_MANAGER | 入庫/出庫/盤點/調撥/採購/報表 |
| ADMIN_STAFF | 基礎操作（查詢、建立領用單） |
| EXPERIMENT_STAFF | 建立領用單、唯讀查詢庫存 |

> 僅限內部人員（`is_internal = true`）存取

---

## 3. 核心資料模型

### 3.1 產品主檔 (products)

| 欄位 | 類型 | 說明 |
|------|------|------|
| id | UUID | 主鍵 |
| sku | VARCHAR(50) | 產品編碼（唯一，系統自動生成） |
| name | VARCHAR(200) | 產品名稱 |
| category_code | CHAR(3) | SKU 類別代碼 |
| subcategory_code | CHAR(3) | SKU 子類別代碼 |
| base_uom | VARCHAR(20) | 基本單位 |
| pack_unit | VARCHAR(20) | 包裝單位 |
| pack_qty | INTEGER | 包裝量 |
| track_batch | BOOLEAN | 追蹤批號 |
| track_expiry | BOOLEAN | 追蹤效期 |
| safety_stock | DECIMAL | 安全庫存量 |
| reorder_point | DECIMAL | 補貨點 |

### 3.2 庫存流水 (stock_ledger)

| 欄位 | 類型 | 說明 |
|------|------|------|
| id | UUID | 主鍵 |
| product_id | UUID | FK → products.id |
| warehouse_id | UUID | FK → warehouses.id |
| direction | ENUM | in / out / adjust |
| qty | DECIMAL | 異動數量 |
| unit_cost | DECIMAL | 單位成本 |
| batch_no | VARCHAR(50) | 批號 |
| expiry_date | DATE | 效期 |
| doc_type | VARCHAR(20) | 來源單據類型 |
| doc_no | VARCHAR(50) | 來源單據編號 |

### 3.3 夥伴 (partners)

| 欄位 | 類型 | 說明 |
|------|------|------|
| id | UUID | 主鍵 |
| type | partner_type | 供應商/客戶 |
| customer_category | customer_category | 客戶分類（internal/external/research/other） |
| name | VARCHAR(200) | 名稱 |
| contact_name | VARCHAR(100) | 聯絡人 |
| tax_id | VARCHAR(20) | 統一編號 |

---

## 4. SKU 編碼規則

**格式**：`[類別代碼]-[子類別代碼]-[流水號]`（11 字元）

**範例**：`MED-ANT-001`（藥品-抗生素-第 001 號）

### 4.1 主類別

| 代碼 | 類別 |
|------|------|
| MED | 藥品 |
| MSP | 醫材 |
| FED | 飼料 |
| EQP | 器材 |
| CON | 耗材 |
| CHM | 化學品 |
| OTH | 其他 |

---

## 5. 單據類型

| 代碼 | 類型 | 說明 |
|------|------|------|
| PO | 採購單 | Purchase Order |
| GRN | 採購入庫 | Goods Receipt Note |
| PR | 採購退貨 | Purchase Return |
| SO | 領用單（原稱「銷貨單」） | 核准即**一段式**扣庫存＋轉列成本（Sales Order 命名為歷史沿用；成本價從 stock_ledger 加權平均成本取得），**不記應收/收入** |
| SR | 銷貨退貨 | Sales Return。⚠️ **業務上不存在**（2026-07-23 使用者裁定）：ERP 出庫全是「實驗完成後記錄消耗」、沒有價金，因此不會有退貨退款。目前仍可新建且 `post_sr` 會沖銷收入／應收，屬潛在地雷，追蹤於 `TODO.md` R84-13 |
| TR | 調撥單 | Transfer |
| STK | 盤點單 | Stock Take |
| ADJ | 調整單 | Adjustment |
| RTN | 退貨單 | Return |

**已從程式碼移除的死值（2026-07-23，R84-9／R84-12）**：

| 代碼 | 狀態 |
|---|---|
| ~~DO~~ 銷貨出庫 | Rust `DocType` 已移除；帶 `"doc_type":"DO"` 的請求在**反序列化階段**即回 422。原因見 §5.1 |
| ~~RM~~ 退料單 | 同上。前端一直隱藏、後端 `process_single_line` 從未有對應分支，是純死值 |

⚠️ **DB 的 `doc_type` enum 仍保留 `'DO'` / `'RM'` 兩個值**（規劃書 `docs/reviews/2026-07-22-r84-9-do-enum-removal-plan.md` §8 使用者裁定的**選項 B**）：只清死碼、不對 `documents` / `stock_ledger` 兩張核心表做型別重建。執行前已查證 prod 兩表的 DO / RM 皆 0 筆。sqlx 若真解碼到這兩個值會報錯——在「0 筆既有資料 + 已封鎖新建」前提下屬不可能路徑，且報錯優於靜默誤判成別的型別。

### 5.1 為什麼沒有「銷貨出庫（DO）」單

**業務事實（2026-07-22 使用者確認）**：本公司沒有對外銷貨業務，所有出庫都是**內部耗材領用**——庫存離開倉庫絕大多數情況下是被計畫（IACUC study/protocol）使用掉，不是賣給客戶；少數「無計畫外部對象領用」例外見下方說明，但同樣不是真正的銷貨。因此不需要「銷貨單（SO）先開立 → 銷貨出庫（DO）實際出庫」這種為了配合「先立應收帳款、後扣庫存」而設計的兩段式流程。

**程式碼現況（已落地，非本輪新決定）**：
- SO 自 2026-07-20（`#1004`，migration 136）起改為**一段式**：核准時逐行照「該行儲位所屬倉」直接扣庫存＋過帳，不再依賴 DO 才出庫。
- 2026-07-21（`#1005`）進一步封鎖 DO **新建**：`crud.rs` 明確拒絕 `doc_type == DO` 的建立請求，理由是「SO＋DO 並用會對同一筆領用雙扣庫存、雙認金額」。
- **2026-07-23（R84-9）死碼已清除**：`DocType::DO` 連同該封鎖特例一併從 Rust 移除（特例在 variant 不存在後成為不可能路徑）。守護的不變式沒有消失、而是**前移了一層**——原本在 service 層擋，現在在反序列化階段就擋，測試移至 `models/document.rs::deprecated_doc_types_are_rejected_at_deserialization`。
- 會計過帳（`backend/src/services/accounting.rs`）明訂：SO **一律**只記「借：銷貨成本／貸：存貨」（成本轉列），即使單據行帶了單價也不記應收帳款（1200）、不記銷貨收入（4100）——因為根本沒有真實對外收入需要認列。
- ⚠️ **修正（2026-07-22，查證後推翻原判斷）**：原本以為 1200/4100 這兩個科目只是「舊 DO 單相容用、可以移除」，但實際查證發現**兩者都仍被其他現行功能結構性依賴，與 DO 是否有歷史資料無關**：① `POST /accounting/ar-receipts`（`AccountingService::create_ar_receipt`）是獨立於 SO/DO 之外、目前仍可呼叫的「記錄客戶收款」功能，寫死依賴科目 1200；② `post_sr`（SR 銷貨退貨過帳，`DocType::SR`）目前**未被封鎖新建**（不像 DO 那樣禁止建立），核准時會同時過帳 1200 與 4100。**結論：1200/4100 不能移除**，`docs/TODO.md` R84-10 已依此結論結案，不再是「需查證」的待辦。
- 少數「無計畫外部對象領用」（`protocol_id = None`，例如提供樣本給合作機構）仍可用 SO 開立，但**會計處理相同**——一樣只記成本轉列，不因為對象是外部單位就認列收入；若該對象需要正式發票/收款，走系統外流程（財務系統外處理，見 `ERP流程.md` §7）。

**交易夥伴（`partners`）的 `customer_category`（internal/external/research/other）欄位**：這是對「領用對象」的分類標籤（供報表篩選用，見領用明細報表），**不是**「是否認列收入」的判斷依據——不論分類為何，SO 一律不記收入。現行 SO 的主要領用對象是 IACUC 計畫（`protocol_id`），而非手動建立的客戶主檔；`documents.partner_id` 目前多數 SO 為 NULL。

---

## 6. 報表模組

| 報表 | 頁面元件 | 說明 |
|------|----------|------|
| 庫存現況 | `StockOnHandReportPage` | 即時庫存 |
| 庫存流水 | `StockLedgerReportPage` | 異動明細 |
| 採購明細 | `PurchaseLinesReportPage` | 採購分析 |
| 領用明細 | `SalesLinesReportPage` | 內部耗材領用分析（元件/API 名稱沿用歷史「銷貨」命名，非真實對外銷貨） |
| 成本摘要 | `CostSummaryReportPage` | 成本統計 |
| **血液檢查費用** | `BloodTestCostReportPage` | 專案+日期+實驗室篩選 |

所有報表支援 CSV 匯出。

---

## 7. API 端點

### 7.1 產品管理

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/products` | 產品列表 |
| POST | `/products` | 新增產品（SKU 自動生成） |
| GET | `/products/:id` | 產品詳情 |
| PUT | `/products/:id` | 更新產品 |
| PATCH | `/products/:id/status` | 變更狀態 |

### 7.2 庫存管理

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/inventory/on-hand` | 庫存現況 |
| GET | `/inventory/expiring` | 即將到期品項 |
| GET | `/stock-ledger` | 庫存流水 |

### 7.3 單據管理

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/documents` | 單據列表 |
| POST | `/documents` | 建立單據 |
| GET | `/documents/:id` | 單據詳情 |
| PUT | `/documents/:id` | 編輯單據 |
| POST | `/documents/:id/submit` | 送審 |
| POST | `/documents/:id/approve` | 核准（大金額 ADJ：倉庫管理員核准後進入 `wm_approved`） |
| POST | `/documents/:id/admin-approve` | ADMIN 最終核准（大金額 ADJ；**沖銷單不走此路**） |
| POST | `/documents/:id/admin-reject` | ADMIN 駁回，退回草稿 |
| POST | `/documents/:id/cancel` | 作廢 |
| POST | `/documents/:id/reverse` | **R84-5 發起沖銷**：對已核准單據建立沖銷草稿（倉管/ADMIN），此階段不動庫存 |
| POST | `/documents/:id/reverse-approve` | **R84-5 核准沖銷**：ADMIN 最終核准，執行庫存與會計的反向鏡射；發起人不得自行核准 |
| GET | `/inventory/lot-movements` | **R84-6 批號生命週期追溯**：時間軸 + 數量對帳（跨倉彙總） |

### 7.4 報表

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/reports/stock-on-hand` | 庫存現況報表 |
| GET | `/reports/stock-ledger` | 異動報表 |
| GET | `/reports/purchase-lines` | 採購明細 |
| GET | `/reports/sales-lines` | 領用明細（路由沿用歷史「sales」命名） |
| GET | `/reports/cost-summary` | 成本分析 |
| GET | `/reports/blood-test-cost` | 血檢成本報表 |
| GET | `/reports/purchase-sales-monthly` | 進銷貨月報 |
| GET | `/reports/purchase-sales-by-partner` | 進銷貨彙總（依夥伴） |
| GET | `/reports/purchase-sales-by-category` | 進銷貨彙總（依產品類別） |

---

## 8. GLP 合規要點

| 要求 | 實作方式 | 現況 |
|------|----------|------|
| 可追溯性 | stock_ledger 記錄每筆異動，`doc_type/doc_id/doc_no` 皆 `NOT NULL` | ✅ 每筆異動保證連回某張單；⚠️ 連回單據裡「哪一行明細」（`line_id`）與「批號完整生命週期」仍有缺口，詳見 `ERP流程.md` §6 |
| 批號管理 | batch_no 欄位 | 🔶 可為 NULL、無獨立批號實體、部分單據類型不強制，詳見 `ERP流程.md` §6 |
| 效期管理 | expiry_date + 系統提醒 | ✅ 已有欄位與預警；出庫是否強制 FEFO 待查證 |
| 數據完整性 | 僅新增不修改，調整用 adjust | ✅ |

> 完整現況盤點（含尚未補強的缺口與計畫）見 [`ERP流程.md`](./ERP流程.md) §6、`docs/TODO.md` §R84。

---

## 9. 前端路由

| 路由 | 頁面 |
|------|------|
| `/products` | 產品列表 |
| `/products/new` | 新增產品 |
| `/products/:id` | 產品詳情 |
| `/inventory` | 庫存現況 |
| `/stock-ledger` | 庫存流水 |
| `/documents` | 單據列表 |
| `/warehouses` | 倉庫管理 |
| `/partners` | 供應商/客戶管理 |

---

## 10. 相關文件

- [`ERP流程.md`](./ERP流程.md) - 白話完整流程說明（給非工程師看）＋ 現況缺口與補強計畫
- [通知系統](./NOTIFICATION_SYSTEM.md) - 低庫存/效期提醒
- [動物管理](./ANIMAL_MANAGEMENT.md) - 血液檢查費用關聯
