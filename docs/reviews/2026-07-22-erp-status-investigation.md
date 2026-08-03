# ERP 現況調查（2026-07-22）

> 背景：使用者純討論性提問「調查 ERP 現況」，五個問題：庫存是否會負值／每筆進銷貨是否記錄品項+批號+來源去向單據／UI 是否容易查詢／漏掉什麼／應符合什麼規範但沒做。
> 本輪**不動 code**，純調查+回報。追蹤輪次：`docs/TODO.md` §R84。
>
> 調查方法：4 個並行唯讀 Explore agent（庫存負值邏輯 / 批號單據追溯 schema / 前端庫存查詢 UI / ERP 模組全貌，皆 sonnet），
> 指揮官另對 §1 最關鍵的透支漏洞判斷親自讀碼（`backend/src/services/stock/ledger.rs`）複驗，非單憑 agent 結論轉述。

## 0. 系統定位

ipig_system 是**實驗動物 CRO（受託研究機構）管理平台**，核心是 IACUC 計畫書 + 動物個體照護紀錄，深度對齊 GLP / 21 CFR Part 11（HMAC-chain audit trail）。ERP 進銷存是其中一個**支援性子系統**（`README.md:13,22`、`DESIGN.md:10,15`）。這個定位決定了 §5 的規範判準——不是一般製造業 ERP，而是要滿足 GLP 受試物質帳（test article accountability）與管制藥品簿冊。

## 1. 倉儲是否會出現負值？

**判定：正常單一操作不會，但有一個已驗證的透支漏洞，且 DB 層完全沒有最後防線。**

做得好的部分：
- 出庫前 `check_stock_available` 用 `SELECT ... FOR UPDATE` 鎖快照列，不足即拒（`backend/src/services/stock/ledger.rs:631-665`）。
- 儲位扣帳用原子條件 `UPDATE ... WHERE on_hand_qty >= $3`（`ledger.rs:522-540`）。
- 跨單並發用 `pg_advisory_xact_lock` 按 (倉,品) 排序取鎖，防死鎖也防跨單並發透支（`ledger.rs:37-46`）。
- 盤點差異走正規 ADJ 流程，無繞過檢查的後門。

已驗證的問題：
- **同一張單據內兩行同品項可透支（確定性重現，非低機率 race）**：每行的庫存檢查都讀 `inventory_snapshots`，但快照要等**整張單全部行處理完才重算一次**（`ledger.rs:48-54` `process_document`：先逐行 `process_single_line` 全跑完，才逐 (倉,品) 呼叫 `update_inventory_snapshot`）。庫存 100，一張 SO 開兩行各扣 60 → 兩行檢查都看到 100、都通過 → 快照重算後變 -20。建單時沒有「同品項不得重複開行」的檢查。若兩行落在同一儲位，儲位層的原子扣帳會攔住第二行；但 warehouse-only（無儲位）或分散在不同儲位時攔不住。**無測試覆蓋此情境**（已掃過 `backend/tests/`，僅有跨單/跨倉不足的測試，無同單多行同品項測試）。
- **DB 層完全沒有 `CHECK (qty >= 0)`**：`inventory_snapshots.on_hand_qty_base`、`storage_location_inventory.on_hand_qty`、`document_lines.qty` 皆無約束（`backend/migrations/009_erp_stock.sql:204,222,258`），全部 136 個 migration 都沒補。唯一相關的 `line_shelf_allocations.qty > 0`（`131_grn_shelf_allocation.sql:35`）是另一張表，非庫存量表本身。應用層一旦失守（如上述漏洞），DB 會照單全收負值。

## 2. 每筆進出貨是否記錄品項＋批號＋來源/去向單據？

**判定：部分。單據參照完整，批號追溯不完整。**

- ✅ **單據面**：`stock_ledger` 的 `doc_type / doc_id / doc_no` 皆 `NOT NULL`（`009_erp_stock.sql:236-238`）——每筆異動**結構上保證**連得回單據。⚠️ 訂正：`line_id`（`:239`）本身**沒有** `NOT NULL`，僅是可為 NULL 的 FK，故「連回哪一張單」有保證，但「連回單據裡的哪一行明細」不保證。GRN 也有 `documents.source_doc_id` 鏈回 PO（`009_erp_stock.sql:166`，供 `v_purchase_order_receipt_status` 使用）。
- ❌ **批號面**三個弱點：
  1. `batch_no VARCHAR(50)` 可為 NULL（`009_erp_stock.sql:243-244`），**沒有獨立 lots/batches 資料表**——同批號靠字串比對，不是關聯鍵（有 FK）。
  2. 批號只在 `products.track_batch = true` 時才強制，而 `track_batch` **預設 false**（`009_erp_stock.sql:77`）；`requires_batch_expiry()` 強制名單只涵蓋 `GRN|DO|SO|ADJ|STK`（`backend/src/models/document.rs:75-80`，校驗於 `backend/src/services/document/crud.rs:251-274`）——**採購退貨（PR）、調撥（TR）、銷貨退貨（SR/RTN）即使品項 `track_batch=true` 也不擋批號**。
  3. **出庫沒有 FIFO/FEFO 自動配批**（已用關鍵字搜過 `ledger.rs`，無命中），批號靠人手輸入單據行，輸錯即斷鏈。
- ❌ **去向查詢**：後端沒有任何 traceability API（如 `/lots/{id}/movements`），只有 `/inventory/ledger`（含 `batch_no` filter，`ledger.rs:667-735`）與 `/inventory/on-hand`、`/inventory/unassigned*`（`backend/src/routes/erp.rs:191-206`）。要回答「這批貨去了哪些單」只能自己拿 `product_id + batch_no` 去 ledger 查詢結果手動比對。
- **孤兒案例**：`DocType::RM`（報廢）在 `process_single_line` 的 match 中**沒有對應分支**（`ledger.rs:64-73` 落入 `_ => {}`）——若真的建立 RM 單會完全不寫 `stock_ledger`。實務報廢改走 ADJ（`backend/src/services/document/workflow.rs:141`），RM 是死的 enum 值，非活躍風險但屬程式碼異味。
- 歷史期初補帳（`migrations/070_r62_baseline_ledger_backfill.sql:12-96`）用合成單號 `ADJ-BASELINE-*`，屬合理但需知悉的追溯邊界案例。

## 3. UI 上是否容易查詢？

**判定：查「現在有多少」容易；查「從哪來、去哪了」困難。**

- ✅ `InventoryPage`（`frontend/src/pages/inventory/InventoryPage.tsx`）功能齊全：關鍵字/倉庫貨架樹狀/批號/效期預警/低庫存篩選（`:29-34,154-174`）、可排序、展開列看批號明細（`InventoryRow.tsx:299-306`）、一鍵跳到該品項流水（`InventoryRow.tsx:233-240`）。單據詳情頁（`DocumentDetailPage.tsx:571,595,623-626`）也會顯示各明細行批號與效期。
- ❌ 五個硬傷：
  1. **流水/報表裡的單號全是純文字、不可點擊**（`StockLedgerReportPage.tsx:249`、`StockLedgerPage.tsx:130`、`PurchaseLinesReportPage.tsx:243`、`SalesLinesReportPage.tsx:218` 均無 `<Link>` 到 `/documents/:id`）——想看那張單得再去 DocumentsPage 手動搜尋單號，這是追溯體驗最大的斷點。
  2. `StockLedgerReportPage` **不能直接輸入品項或批號查詢**（`:180-205` 只有日期區間+倉庫下拉，無品項搜尋框、無批號篩選），只能從 InventoryPage drill-down 帶 URL 參數進去。`StockLedgerPage`（簡版）完全無篩選，只有全量清單+CSV 匯出。
  3. **沒有批號追溯視圖**（一個批號從進貨→上架→出庫的完整鏈）；唯一接近的功能是 `WarehouseDetailTabs.tsx:345-414` 的「未分配庫存反查來源 GRN」，且只在倉庫詳情頁單向查詢，非通用批號生命週期追溯。
  4. `InventoryPage`、`StockLedgerPage`、`StockLedgerReportPage`、`PurchaseLinesReportPage`、`SalesLinesReportPage` **均未見分頁機制**，資料量成長後全量載入（僅確認前端 UI 層未帶分頁參數，未實測後端 API 是否支援）。
  5. 產品詳情頁的庫存快照（`ProductInventorySnapshot.tsx:58-76`）只按倉庫/儲位加總，**不顯示批號**，要看批號仍須跳去 InventoryPage 展開列。

## 4. 漏掉的部分（按風險排序）

1. **紅單/沖銷（reversal）沒有實作**——已核准單據作廢時系統報錯提示「Use reversal instead」（`workflow.rs:708`），但全庫**找不到 reversal 的任何實作**。等於已核准的錯單只能用 ADJ 硬調，而 ADJ 又不強制批號，錯一次追溯鏈就斷一次。這是單據生命週期的斷頭路，優先度最高。
2. 同單多行同品項透支漏洞 ＋ DB 無 CHECK 防線（見 §1）。
3. 批號無實體、無 FIFO/FEFO、退貨調撥不強制批號（見 §2）。
4. UI 追溯斷點：單號不可點、無追溯視圖、無分頁（見 §3）。
5. **SoD 未強制**：requester ≠ approver 只靠 HMAC 稽核鏈補償，非程式碼守衛（`docs/TODO.md` R80-6 既有裁定：倉庫實際單人，硬守衛會卡死審批，接受風險——本輪重申此風險仍是開放項，非新發現）。
6. 單據狀態機只有 Draft/Submitted/Approved/Cancelled（`document.rs:109-114`），approve 即過帳，無獨立 posted 狀態——單人操作可接受，但「核准」與「庫存生效」永遠不可分離。
7. 未結案 TODO 提醒：R53-13（byproduct 財務簽核 gate）、R62-2（storage_location_inventory 歷史回填待跑 prod）、R81-9（請購單字眼正名，純文件）。
8. 系統無報價單、無發票（invoice）單據類型（`models/document.rs` 的 `DocType` 未見對應值）；⚠️ 不確定是否在系統外處理，需使用者確認。

## 5. 應符合的規範（按定位判準，非一般製造業 ERP 判準）

- **GLP 受試物質帳（test article accountability）**——OECD GLP 原則與 TFDA 非臨床試驗優良操作規範要求受試物**逐批**記錄接收/使用/剩餘/銷毀，且要能對帳（收到量＝用掉＋剩下＋銷毀）。這正是系統最弱的一環：批號非強制、無批號實體、無雙向追溯 API。**列為「應該做而沒做」的第一名**——建議至少讓 GLP 試驗相關品項全面 `track_batch = true`，並把 PR/TR/SR 納入 `requires_batch_expiry` 強制名單。
- **管制藥品管理條例**——麻醉/安樂死用藥（ketamine、pentobarbital 等）依法要有專用簿冊逐筆記錄與定期申報，盤點差異須說明；負庫存在簿冊上是不可能的物理狀態，因此 §1 的 DB CHECK 防線對這類品項不是 nice-to-have。⚠️ 不確定：管制藥品簿冊是否已在系統外（紙本/食藥署系統）另行處理，若是，ERP 至少要能與其對帳。
- **21 CFR Part 11 / 電子簽章**——Part 11 是否適用取決於對應的 predicate rule（FDA 官方立場：僅在其他法規要求以電子方式留存/傳輸紀錄時才適用，非獨立標準）；本系統已具備的是**支援性控制**——audit trail 與 e-signature（HMAC chain 是強項，優於一般 ERP），這保證了「若適用 Part 11，控制基礎已具備」，但不等於「已完整符合 Part 11」，適用範圍需依實際受哪些法規要求判定，未逐條核對。
- **效期管理（FEFO）**——GLP 要求試劑/受試物於效期內使用；系統有 expiry 欄位與預警。⚠️ 出庫時是否有 FEFO 強制或拒扣過期批號的校驗邏輯，本輪**未查到對應程式碼**（已查過 `ledger.rs`、`crud.rs` 的出庫/驗證路徑無命中），但也不能排除是遺漏未讀到——判定為「待查證」而非「確定沒有」，需另行確認。
- **商業會計法／存貨計價**——加權平均為合法計價方式，此面向無問題。⚠️ 若 SO 對應真實銷售行為，統一發票開立需有對應流程；系統無 invoice 單據，推測在外部處理，請確認（同 §4-8）。

## 6. 檢查過但沒有問題的範圍（四路彙整）

- GRN 入庫／SR、RTN 退貨入庫（純加值路徑，`ledger.rs:78-114,332-367`）。
- `assign_unassigned` 分配儲位（有 FOR UPDATE 鎖 + FIFO 上限驗證，`services/stock/inventory.rs:596-793`）。
- 所有 `get_on_hand*` 查詢皆唯讀；`reconcile_storage_inventory.rs` 為 read-only 對帳工具，不寫 DB。
- Stocktake（STK）核准後自動產生的 ADJ 差異單，完整走 `process_adjustment`/`check_stock_available`，未繞過檢查（`workflow.rs:765-914`）。
- `documents`/`document_lines`/`warehouses`/`partners`/`storage_locations` 的 FK 完整性。
- InventoryPage 的即時庫存查詢（關鍵字/倉庫貨架/批號/效期/低庫存篩選、排序、展開批號明細）功能齊全可用。
- DocumentDetailPage 明細行顯示批號與效期，功能正常。
- backend/src/routes/ 全部模組已核對 router 掛載（`routes/mod.rs`），ERP 主要單據類型（DocType/DocStatus enum）、會計 handler、供應商/客戶主檔、單位換算已定位。

## 7. 不確定處彙總

- 同單多行同品項透支路徑僅為程式碼推理＋人工複驗，**未實跑整合測試觸發**，信心中等。
- `storage_location_inventory` 上架分配（`line_shelf_allocations`）是否補上批號級來源明細，未深入細查。
- `DocType::RM` 是否已完全停用或前端仍可能建立此類單據，需再確認建單白名單。
- 前端「無分頁」結論僅限 UI 層，未實測後端 API 是否支援分頁參數。
- `WarehouseReportPage.tsx`、`DocumentsPage.tsx` 列表頁篩選細節未逐行讀完。
- 出庫時效期（FEFO）校驗邏輯未查到對應程式碼，需另行確認是否存在。
- 管制藥品簿冊、發票開立是否在系統外處理，需使用者確認。

## 8. 建議後續派工優先序（供 TODO §R84 排程參考）

| 優先序 | 項目 | 對應章節 | 性質 |
|---|---|---|---|
| 1 | 同單同品項透支：補檢查（建單/核准階段擋重複品項，或逐行即時重算快照）＋補整合測試 | §1 | 中風險小改，紅→修→綠 |
| 2 | `inventory_snapshots` / `storage_location_inventory` 補 `CHECK (>= 0)` migration | §1 | DB 約束，需評估既有髒資料 |
| 3 | GLP 試驗相關品項批號強制化：`track_batch` 盤點現況 + PR/TR/SR 納入 `requires_batch_expiry` | §2、§5 | 需與使用者確認品項範圍，中風險 |
| 4 | 流水/報表單號改可點擊連結（`StockLedgerReportPage`/`StockLedgerPage`/`PurchaseLinesReportPage`/`SalesLinesReportPage`） | §3 | 純前端 UI，低風險高回報 |
| 5 | Reversal（紅單/沖銷）機制設計 | §4-1 | 架構決策，需使用者參與 surface tradeoff |
| 6 | 批號追溯視圖（forward/backward traceability 頁面 + API） | §2、§3 | 中大型功能，需先定範圍 |
| 7 | 出庫 FEFO/效期校驗查證（R84-7） | §5、§7 | 純查證，先確認現況再決定是否要修 |
| 8 | 管制藥品簿冊／發票對帳查證（R84-8） | §4-8、§5、§7 | 需使用者先確認系統外流程現況，非單純技術任務 |

> 排序原則：先消風險（1-2）→ 對齊 GLP 合規（3）→ 低成本高體驗提升（4）→ 需要架構決策的大項放最後（5-6）→ 查證類排最後（7-8，因需先有查證結果才知道要不要排進技術待辦）。
