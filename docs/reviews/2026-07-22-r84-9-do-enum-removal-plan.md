# R84-9 規劃書：移除 `DocType::DO` 單據類型

> 狀態：**規劃中，尚未執行**。等使用者審核選項後再動手。
> 撰寫：2026-07-22。追蹤：`docs/TODO.md` R84-9、`docs/spec/modules/ERP流程.md` §6.4。
> 前提事實：DO（銷貨出庫）自 2026-07-21（#1005）起被封鎖新建；prod 查證 `documents`／`stock_ledger` 皆 **0 筆 DO**。

---

## 1. 為什麼這不是「一行 SQL」

PostgreSQL 的 enum 型別**不支援** `ALTER TYPE ... DROP VALUE`。要把 `'DO'` 從 `doc_type` enum 拿掉，只能「建新型別 → 把用到的欄位轉成新型別 → 刪舊型別」整套重建。而 `doc_type` 這個 enum 被 **2 個核心表的欄位**、**數個 view**、以及**約 15 處程式碼**（含多處直接寫死 `'DO'` 字串的 SQL）依賴，牽一髮動全身。

`doc_type` enum 現值（`001_enums.sql:11`）：
```
('PO', 'GRN', 'PR', 'SO', 'DO', 'SR', 'TR', 'STK', 'ADJ', 'RM', 'RTN')
```
（註：`'RM'` 退料單同樣是死值——前端隱藏、後端 `process_single_line` 無分支。若要重建型別，可考慮一併處理，見 §6。）

---

## 2. 影響範圍盤點

### 2.1 使用 `doc_type` 型別的欄位（共 2）
- `documents.doc_type`（`009_erp_stock.sql:159`）
- `stock_ledger.doc_type`（`009_erp_stock.sql:236`）

### 2.2 依賴這兩欄的 view（ALTER COLUMN TYPE 前**必須先 DROP**，之後重建）
已知：`v_purchase_order_receipt_status`、`v_grn_line_unshelved`、`v_low_stock_alerts`、`v_inventory_summary`、`v_expiry_alerts`（`009`／`131`）。
⚠️ **不要硬記這份清單**——後續 migration 可能新增。執行時用下方探測 SQL 拿「當下實際」的完整依賴清單：

```sql
-- 列出所有依賴 documents.doc_type 或 stock_ledger.doc_type 欄位的 view/rule
SELECT DISTINCT v.oid::regclass AS dependent_view
FROM pg_depend d
JOIN pg_rewrite r ON r.oid = d.objid
JOIN pg_class v ON v.oid = r.ev_class
JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
WHERE d.refobjid IN ('documents'::regclass, 'stock_ledger'::regclass)
  AND a.attname = 'doc_type'
  AND v.relkind IN ('v','m');
```

### 2.3 程式碼引用 `DocType::DO` / `'DO'`（都要清）
- `backend/src/models/document.rs`：enum variant、`prefix()`、`affects_stock()`、`requires_batch_expiry()`、`requires_shelf()` 的 match arm，+ 2 個測試（`:450`、`:465`）
- `backend/src/services/accounting.rs:162,327`：`post_sales` 的 `SO | DO` match、label
- `backend/src/repositories/accounting.rs:179`：SQL `doc_type IN ('DO', 'SR', 'RTN')`
- `backend/src/services/document/crud.rs:214,221,460,1080`：**DO 封鎖特例**、`SO | DO` match、測試
- `backend/src/services/document/workflow.rs:98`：`SO | DO` match
- `backend/src/services/notification/erp.rs:25,171,270`：label、SQL `doc_type IN ('DO', 'SO')`
- `backend/src/services/report.rs:371,583,631`：3 處 SQL `IN (... 'DO' ...)`
- 前端 `frontend/src/types/erp.ts` 的 `DocType` union 含 `'DO'`（+ 相關 label map）

> **關鍵風險**：SQL 裡的 `doc_type IN ('DO', ...)`，`'DO'` 會被 cast 成 `doc_type` enum。**enum 一旦沒有 `'DO'`，這些 SQL 會在執行期直接報錯**（`invalid input value for enum doc_type: "DO"`）。所以這些 SQL 的 `'DO'` 移除是**強制**、且必須與 enum 重建同批上線，否則報表/通知/會計查詢會炸。

---

## 3. 兩個選項（請先擇一）

| | **選項 A：完整移除 enum 值** | **選項 B：只清死碼、保留 enum 值（建議先評估）** |
|---|---|---|
| 做什麼 | §2 全部：型別重建 migration + 清所有程式碼/SQL 的 DO | 清掉 Rust `DocType::DO` 相關死碼與 SQL 的 `'DO'`，但**不動 DB enum**（`'DO'` 值留著、無害、0 筆使用） |
| DB 風險 | 高：對 `documents`+`stock_ledger` 兩核心表 ACCESS EXCLUSIVE 鎖、drop/recreate 多個 view、cast 失敗風險 | **無 DB schema 變更** |
| 得到什麼 | enum 帳面乾淨、無 `'DO'` | 無死碼（90% 的乾淨度），enum 保留一個無害未用值 |
| 風險/效益比 | 低（動核心表換掉一個沒人用的標籤） | 高（幾乎零風險拿到主要好處） |

**我的建議**：以這個單機 prod、DO 已 0 筆且已封鎖新建的現況，**選項 B 的風險/效益比明顯較好**——死碼清掉、SQL 不再引用 `'DO'`，enum 留一個無害未用值，完全不必動核心表。選項 A 的型別重建，是「為了拿掉一個沒人用的標籤，對兩張最核心的表動外科手術」。

但你要的是「分步 migration 規劃」，所以 §4 完整給出**選項 A** 的每步 SQL 與風險；若你認同選項 B，§4 的 migration 段可整段跳過，只做「程式碼清理」那部分。

---

## 4. 選項 A：分步執行計畫

### 前置 P0：再次驗證 prod 0 筆 DO（migration 內也會再擋一次）
```sql
SELECT count(*) FROM documents   WHERE doc_type = 'DO';   -- 應為 0
SELECT count(*) FROM stock_ledger WHERE doc_type = 'DO';  -- 應為 0
```
> 風險：只要有 1 筆 DO，§4.2 的 `USING ...::text::doc_type` cast 會失敗、整個 migration abort（不會靜默壞資料，但會擋下部署）。

### 步驟 1（先行 PR，程式碼清理，**此時 enum 仍有 DO**）
把 §2.3 所有 `DocType::DO` / `'DO'` 移除：
- Rust：刪 `DocType::DO` variant 與各 match arm；`post_sales` 的 `SO | DO` 改 `SO`；`crud.rs` 移除 DO 封鎖特例（DO 已無法建、變成不可能路徑）；刪 2 個 DO 測試。
- SQL 字串：`report.rs`／`accounting.rs`（repo）／`notification/erp.rs` 的 `IN (... 'DO' ...)` 拿掉 `'DO'`。
- 前端：`DocType` union 拿掉 `'DO'` + label map。
- ⚠️ RULES_BACKEND §9：若有 `query!` 巨集需重建 `.sqlx` 快取（本專案相關查詢多為 runtime `query()`，仍請確認）。
- 驗收：`cargo check --tests` + `cargo test` + `clippy` 全綠；前端 `tsc`+`eslint`。此 PR **不動 DB**，enum 仍含 DO，故安全。

> 為何先清程式碼：清完後「沒有任何地方會 encode/查詢 DO」，§4.2 的型別重建才安全。sqlx enum 以名稱對應，Rust 移除 DO variant 而 DB 暫留 DO 值不影響（0 筆、永不 encode）。

### 步驟 2（第二 PR，型別重建 migration `NNN_drop_do_from_doc_type.sql`）
以單一 transaction 執行：
```sql
-- (a) 前置守衛：有 DO 就 abort，錯誤訊息明確
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM documents WHERE doc_type = 'DO')
     OR EXISTS (SELECT 1 FROM stock_ledger WHERE doc_type = 'DO') THEN
    RAISE EXCEPTION 'R84-9 abort: 仍有 DO 單據，無法移除 enum 值';
  END IF;
END $$;

-- (b) 舊型別改名
ALTER TYPE doc_type RENAME TO doc_type_old;

-- (c) 建新型別（無 DO）
CREATE TYPE doc_type AS ENUM ('PO','GRN','PR','SO','SR','TR','STK','ADJ','RM','RTN');

-- (d) DROP 所有依賴 view（用 §2.2 探測 SQL 拿到的實際清單；下為已知範例）
DROP VIEW IF EXISTS v_purchase_order_receipt_status CASCADE;
DROP VIEW IF EXISTS v_grn_line_unshelved CASCADE;
DROP VIEW IF EXISTS v_low_stock_alerts CASCADE;
DROP VIEW IF EXISTS v_inventory_summary CASCADE;
DROP VIEW IF EXISTS v_expiry_alerts CASCADE;

-- (e) 兩欄轉新型別
ALTER TABLE documents
  ALTER COLUMN doc_type TYPE doc_type USING doc_type::text::doc_type;
ALTER TABLE stock_ledger
  ALTER COLUMN doc_type TYPE doc_type USING doc_type::text::doc_type;

-- (f) 重建 view（把 009/131 等 migration 的 view 定義原樣搬過來——
--     ⚠️ 必須逐字對齊現況定義，含後續 migration 對 view 的改動）

-- (g) 刪舊型別
DROP TYPE doc_type_old;
```
- **對稱 down**（`migration-down-guard` 要求）：反向重建含 DO 的舊 enum、swap 回、重建 view。標 `data loss on down` 註記；prod forward-only。

### 步驟 3：部署與驗收
- CI `cargo test`（乾淨 DB 跑全部 migration）必綠——這是型別重建能過的關鍵驗證。
- prod 部署：app 啟動 `sqlx::migrate!` 自動跑；**建議在低流量時段**（(e)/(f) 期間對兩表 ACCESS EXCLUSIVE 鎖）。部署後健檢：報表中心、庫存流水、通知、GRN 待上架頁（依賴那幾個 view）逐一開一次確認未壞。

---

## 5. 風險點總表（選項 A）

| # | 風險 | 影響 | 緩解 |
|---|---|---|---|
| 1 | 有 DO 殘留列 → cast 失敗 | migration abort、部署卡住 | 前置守衛 (a) + 部署前再查 |
| 2 | 漏 DROP 某個依賴 view | `ALTER COLUMN TYPE` 報「used by a view」而失敗 | 用 §2.2 pg_depend 探測 SQL 拿完整清單，別硬記 |
| 3 | view 重建定義與現況不符 | 報表/查詢行為悄悄改變 | 從**最新** migration 抓 view 定義逐字對齊，非只看 009 |
| 4 | SQL `'DO'` 未清乾淨就上 enum | 執行期 `invalid input value for enum` | 步驟 1（清碼）**先**於步驟 2（換 enum）合併上線 |
| 5 | 核心表鎖 | 部署瞬間 `documents`/`stock_ledger` 短暫鎖 | 低流量時段部署；單機 prod 影響小 |
| 6 | `.sqlx` 快取／prepared plan 過期 | 舊連線快取計畫失效 | 部署重啟 api 重連即解 |
| 7 | down 不可逆風險 | 回退複雜 | prod forward-only；down 僅 dev/staging |

---

## 6. 「順便」決策：RM 要不要一起移除？

`'RM'`（退料單）同屬死值。若做選項 A 的型別重建，**多拿掉 RM 幾乎零額外成本**（新 enum 少列一個值即可），但需要：
- prod 先查證 `documents`/`stock_ledger` 皆 0 筆 RM；
- 清 RM 的程式碼引用（另有數處）。

**建議**：這是獨立決策，先確認你要不要一起做，我再把 RM 納入盤點。不建議在沒查證前擅自綁進來。

---

## 7. 驗收方式（無論選 A/B）
- 程式碼：`cargo test --all-targets` + `clippy` 全綠、前端 `tsc`+`eslint`。
- （選項 A）CI 乾淨 DB 跑完 migration 綠 = 型別重建可行的權威證明。
- 部署後手動 smoke：報表中心、庫存流水、通知、GRN 待上架頁各開一次。

---

## 8. 決議（2026-07-22 使用者裁示）

1. **採選項 B**：只清死碼、**保留 enum 值 `'DO'`**（無害未用），不動 DB 型別、不碰核心表。
2. **`RM` 一起處理**：比照 B——清 RM 的死碼與 SQL 引用、保留 enum 值；但**執行前需先查證 prod `documents`/`stock_ledger` 皆 0 筆 RM**。
3. **交由 local（可測環境）執行**：兩項都寫進 `docs/TODO.md` backlog（R84-9 更新為 B 方案、新增 **R84-12** RM 清理），由能實跑後端測試的環境動手，不在遠端 sandbox 改 code。
   > 訂正（2026-07-23）：RM 清理的追蹤編號為 **R84-12**，非 R84-11。R84-11 已由「批號對帳分級」（#1034）佔用；`docs/TODO.md` 一直是正確的 R84-12，僅本規劃書 §8 初版誤植 R84-11，已更正對齊。

> 由於選 B，§4 的型別重建 migration（步驟 2）**整段不執行**；只做步驟 1 的「程式碼清理」部分（但 enum 值保留，故 SQL 的 `'DO'`／`'RM'` 移除是「不再引用」而非「因 enum 消失而被迫改」——風險更低）。
