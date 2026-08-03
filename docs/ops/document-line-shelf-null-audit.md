# 單據明細 storage_location_id NULL Audit

> **⚠️ 2026-07-16 更新**：GRN（採購入庫）已改「軟擋」——`DocType::requires_shelf()` 移除 GRN，
> 改為 `shelf_soft_expected()`（缺儲位可核准、事後分配上架、未上架期間提醒）。本文件下方以
> `doc_type IN ('GRN', 'DO', 'SO', 'ADJ', 'STK')` 為前提的審計 SQL 中，**GRN 的 NULL 儲位已是
> 預期設計、非違規**；追溯改用 view `v_grn_line_unshelved` 與 `line_shelf_allocations`
> （migration 131）。下方硬擋審計現僅適用 DO/SO/ADJ/STK/SR/RTN。
>
> **用途**：在 `requires_shelf()` 規則的後端必填驗證落地後，盤點既有資料中違反此規則的歷史單據，作為「是否加 DB NOT NULL constraint」與「是否需要資料修護」的決策依據。
> **時機**：Backlog 3 落地後第一次跑（disclosure → 2026-05-19 後）。
> **執行者**：DBA / on-call SRE，需 prod DB 唯讀權限。
> **下一步**：依結果決定 Backlog 3 follow-up（加 NOT NULL migration / 資料修護 / 維持現狀）。

---

## 1. Audit SQL（唯讀）

連 prod DB 後執行：

```sql
-- (a) 違反規則的歷史 line 數，依 doc_type 分組
SELECT
    d.doc_type,
    d.status,
    count(*) AS lines_missing_shelf,
    min(d.doc_date) AS earliest_doc_date,
    max(d.doc_date) AS latest_doc_date
FROM document_lines dl
JOIN documents d ON dl.document_id = d.id
WHERE dl.storage_location_id IS NULL
  AND d.doc_type IN ('DO', 'SO', 'ADJ', 'STK', 'SR', 'RTN')
GROUP BY d.doc_type, d.status
ORDER BY d.doc_type, d.status;

-- (b) 違反規則的 line 在哪些單據（樣本，最多 50 筆）
SELECT
    d.doc_no,
    d.doc_type,
    d.status,
    d.doc_date,
    dl.line_no,
    dl.product_id,
    dl.qty,
    d.warehouse_id,
    d.created_by,
    d.created_at
FROM document_lines dl
JOIN documents d ON dl.document_id = d.id
WHERE dl.storage_location_id IS NULL
  AND d.doc_type IN ('DO', 'SO', 'ADJ', 'STK', 'SR', 'RTN')
ORDER BY d.created_at DESC
LIMIT 50;

-- (c) 是否有現役（非 cancelled）的違規「單據」？（決定修護迫切性）
-- 用 DISTINCT 是因為一張單可能有多條違規 line，這裡要的是「幾張單」而非「幾行」。
SELECT count(DISTINCT d.id) AS active_violation_docs
FROM document_lines dl
JOIN documents d ON dl.document_id = d.id
WHERE dl.storage_location_id IS NULL
  AND d.doc_type IN ('DO', 'SO', 'ADJ', 'STK', 'SR', 'RTN')
  AND d.status <> 'cancelled';
```

## 2. 決策樹

| (a) 違規 line 數 | (c) 現役違規單據數 | 建議行動 |
|---|---|---|
| **0** | **0** | 可選擇進一步以 **trigger** 強制（見 §3 方案 B）；或維持 application 層（方案 A） |
| **>0 但 <100，皆 cancelled** | **0** | 維持 application 層即可；若想加 trigger 需先確認 backfill 策略對 cancelled 單據是否例外 |
| **>0，含 draft / submitted / approved** | **>0** | **暫不加 DB 層強制**。先資料修護：(i) 通知 owner 補儲位 (ii) 對無法補的歷史單據加 ops note + 保留 (iii) trigger 推遲到修護後 |

## 3. 可落地的 DB 層強制方案（若 (a)=0）

PostgreSQL `CHECK` constraint 設計上**不允許 subquery、不可參考其他資料表**（[官方文件](https://www.postgresql.org/docs/current/ddl-constraints.html)：CHECK 條件須 immutable、僅依賴當前列）。因此「依 `documents.doc_type` 判斷 `document_lines.storage_location_id` 是否必填」**無法用 CHECK 表達**。

可行選項：

| 方案 | 機制 | Trade-off |
|---|---|---|
| **A. 維持 application 層** | 本 PR 已落地：`services/document/crud.rs` create/update 必經 `requires_shelf()` 檢查 | 簡單；繞過 service 層的程式（如直接 SQL）無保護 |
| **B. PostgreSQL trigger** | `CREATE TRIGGER` BEFORE INSERT/UPDATE ON `document_lines`，JOIN `documents` 取 `doc_type` 後決定 raise exception | DB 層強制；但增加 DB 維護面 + migration 複雜度 + trigger 不會被 pg_dump 自動還原 |
| **C. Schema 重構** | 拆 `document_lines` 為「PO/PR 用」+「其他 doc_type 用」兩張表，後者 `storage_location_id NOT NULL` | 最徹底但範圍大；歷史資料需 migrate |

**目前建議**：採用方案 A（本 PR），除非 ops 強烈要求 DB 層強制。若日後選 B/C，可基於本文件決策樹的數字決定遷移成本可承受程度。

## 4. 落地後 telemetry

加 service 層 validation 後，可在 Prometheus 加 metric：

```rust
// 在 AppError::ValidationWithCode 進入 IntoResponse 時 increment counter
// label: error_code="doc.line.shelf_required"
```

追蹤新增單據被擋下的頻率，若 > 0 表示前端 / 外部 API 用戶端仍嘗試送 NULL，需 follow up。
