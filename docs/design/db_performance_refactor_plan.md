# 資料庫效能重構計劃（Plan & 說明）

> 狀態：**計劃階段，尚未動任何 code / schema**。本文件供討論與裁定，核准後才依階段執行。
> 產出日期：2026-06-24　·　對應分支：`claude/intelligent-bell-ayy1of`
> 診斷依據：在環境內以 PG16 套用全部 104 個 migration 後 introspect 真實 schema + 子代理掃描後端程式碼。

---

## 0. 一句話結論

**效能瓶頸不在「表太多」，而在「索引缺失」與「查詢寫法」。** 因此本計劃刻意**先不動 schema 結構**，把高效益、低風險、可逆的索引與查詢修復排在前面；schema 結構性調整（合併/拆表）列為最後且條件式階段，等量測證明特定表是瓶頸才針對性地做。

---

## 1. 現況診斷摘要

| 指標 | 數值 | 說明 |
|---|---|---|
| 邏輯表 | 168（182 含分區子表） | 14 領域，每領域均 ~12 張，正規化粒度健康 |
| 表對表外鍵 | 276 | — |
| 既有索引 | 787 | 並非沒做索引，但 FK 子欄位系統性遺漏 |
| **缺索引的 FK 欄位** | **341** | 🔴 最大系統性漏洞 |
| ├ 指向 `users` 的審計欄位 | 199 | 多數**不需要**索引（很少反查） |
| └ 業務 JOIN 關聯 | **142** | ✅ Phase 1 真正要處理的對象 |

**三類效能問題**（依影響面排序）：

1. 🔴 **缺索引 FK**（系統性）：Postgres 不自動為 FK 子欄位建索引 → JOIN、`ON DELETE` 連動、FK 完整性檢查全表掃描。
2. 🟠 **N+1 查詢**（熱路徑）：通知服務雙層迴圈、protocol 審查指派、QA SOP 關聯子查詢。
3. 🟠 **SQL 反模式**：儀表板多個全表 `COUNT(*)`、動物搜尋 `ILIKE '%kw%'`（前置萬用字元索引失效）、`LOWER(TRIM())` 包欄位。

---

## 2. 重構原則（為什麼這樣排）

- **動最少、效益最大優先**：加索引 / 改查詢寫法 → 不改 schema 結構就能拿到「效能數字改善」。
- **可逆優先**：索引可 `DROP`，N+1 修復是純後端 code，皆可回退；schema 結構改動不可逆，最後做。
- **不為了減表數而合併表**：寬表會造成 NULL 欄位爆炸、鎖競爭、寫入放大，是反效果。168 張表對 14 領域的系統屬正常偏精簡（對照：SAP S/4HANA ~90,000 表、Dynamics ~6,000、Odoo 數百–上千；本系統 ERP 領域僅 22 張）。
- **量測驅動**：每階段前後都要有數字，否則「效能改善 X%」無法驗收。

---

## 3. 分階段計劃

### Phase 0 — 建立 Baseline（前提，必做）

| 項目 | 內容 |
|---|---|
| 目標 | 取得「改善前」的可量測數字，作為所有階段的驗收基準 |
| 做法 | 啟用 `pg_stat_statements`；對熱路徑 API（動物列表/詳情、protocol 審查、儀表板、庫存）量測 p95 latency 與 top SQL by total_time |
| 產出 | `docs/design/perf_baseline.md`（量測快照） |
| 風險 | 無（唯讀觀測） |
| 驗收 | 有一份可重現的 baseline 數字表 |

> ⚠️ 注意：診斷用的暫時 DB 是空的，無法提供真實 row count。Phase 0 必須在**有代表性資料量**的環境（staging 或 dev 灌測試資料）量測，否則索引效益無法量化。

---

### Phase 1 — 補 FK 索引 🔴（最大效益 / 低風險 / 不改結構）

**原則**：不是 341 個全加。只加在**業務 JOIN 關聯（142 個）中、屬高交易量表**的欄位。指向 `users` 的審計欄位（如 `created_by`）除非實際會反查，否則跳過——加了只增加寫入成本。

**執行方式**：一律 `CREATE INDEX CONCURRENTLY`（不鎖表），分批上線，每批用 Phase 0 量測驗證效益。每個 up migration 配對 `migrations/down/` 對稱 `DROP INDEX`。

#### Tier 1 — 動物紀錄子表（動物詳情頁熱路徑，最高優先）

動物詳情頁要一次撈出該動物的血檢/觀察/手術/體重…，這些表全部缺 `animal_id` 索引：

```
CREATE INDEX CONCURRENTLY ix_animal_blood_tests_animal_id        ON animal_blood_tests(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_observations_animal_id       ON animal_observations(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_surgeries_animal_id          ON animal_surgeries(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_weights_animal_id            ON animal_weights(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_vaccinations_animal_id       ON animal_vaccinations(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_transfers_animal_id          ON animal_transfers(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_sacrifices_animal_id         ON animal_sacrifices(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_pathology_reports_animal_id  ON animal_pathology_reports(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_sudden_deaths_animal_id      ON animal_sudden_deaths(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_vet_advices_animal_id        ON animal_vet_advices(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_vet_advice_records_animal_id ON animal_vet_advice_records(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_field_corrections_animal_id  ON animal_field_correction_requests(animal_id);
CREATE INDEX CONCURRENTLY ix_euthanasia_orders_animal_id         ON euthanasia_orders(animal_id);
CREATE INDEX CONCURRENTLY ix_euthanasia_byproduct_animal_id      ON euthanasia_byproduct_samples(animal_id);
CREATE INDEX CONCURRENTLY ix_animal_blood_test_items_blood_id    ON animal_blood_test_items(blood_test_id);
CREATE INDEX CONCURRENTLY ix_animals_pen_id                      ON animals(pen_id);
CREATE INDEX CONCURRENTLY ix_animals_source_id                   ON animals(source_id);
```

#### Tier 2 — ERP / 庫存 / 會計（append 量大）

```
-- 庫存帳（高頻寫入 + 報表 JOIN）
CREATE INDEX CONCURRENTLY ix_stock_ledger_doc_id            ON stock_ledger(doc_id);
CREATE INDEX CONCURRENTLY ix_stock_ledger_line_id           ON stock_ledger(line_id);
CREATE INDEX CONCURRENTLY ix_stock_ledger_warehouse_id      ON stock_ledger(warehouse_id);
CREATE INDEX CONCURRENTLY ix_stock_ledger_storage_loc_id    ON stock_ledger(storage_location_id);
-- 單據明細
CREATE INDEX CONCURRENTLY ix_document_lines_document_id     ON document_lines(document_id);
CREATE INDEX CONCURRENTLY ix_document_lines_product_id      ON document_lines(product_id);
CREATE INDEX CONCURRENTLY ix_document_lines_storage_loc_id  ON document_lines(storage_location_id);
-- 單據主檔
CREATE INDEX CONCURRENTLY ix_documents_warehouse_id         ON documents(warehouse_id);
CREATE INDEX CONCURRENTLY ix_documents_partner_id           ON documents(partner_id);
CREATE INDEX CONCURRENTLY ix_documents_protocol_id          ON documents(protocol_id);
-- 會計分錄
CREATE INDEX CONCURRENTLY ix_journal_lines_entry_id         ON journal_entry_lines(journal_entry_id);
CREATE INDEX CONCURRENTLY ix_journal_lines_account_id       ON journal_entry_lines(account_id);
```

#### Tier 3 — Protocol / Amendment 審查工作流

```
CREATE INDEX CONCURRENTLY ix_amendments_protocol_id              ON amendments(protocol_id);
CREATE INDEX CONCURRENTLY ix_amendment_review_assign_amend_id    ON amendment_review_assignments(amendment_id);
CREATE INDEX CONCURRENTLY ix_amendment_versions_amend_id         ON amendment_versions(amendment_id);
CREATE INDEX CONCURRENTLY ix_amendment_status_history_amend_id   ON amendment_status_history(amendment_id);
CREATE INDEX CONCURRENTLY ix_review_assignments_protocol_id      ON review_assignments(protocol_id);
CREATE INDEX CONCURRENTLY ix_review_comments_protocol_id         ON review_comments(protocol_id);
CREATE INDEX CONCURRENTLY ix_review_comments_version_id          ON review_comments(protocol_version_id);
CREATE INDEX CONCURRENTLY ix_protocol_activities_protocol_id     ON protocol_activities(protocol_id);
CREATE INDEX CONCURRENTLY ix_protocol_versions_protocol_id       ON protocol_versions(protocol_id);
```

#### Tier 4 — 設備 / HR / 訊息 / 巡檢（次熱）

```
CREATE INDEX CONCURRENTLY ix_equipment_calibrations_equip_id    ON equipment_calibrations(equipment_id);
CREATE INDEX CONCURRENTLY ix_equipment_maint_equip_id           ON equipment_maintenance_records(equipment_id);
CREATE INDEX CONCURRENTLY ix_equipment_status_logs_equip_id     ON equipment_status_logs(equipment_id);
CREATE INDEX CONCURRENTLY ix_leave_approvals_request_id         ON leave_approvals(leave_request_id);
CREATE INDEX CONCURRENTLY ix_comp_time_overtime_id              ON comp_time_balances(overtime_record_id);
CREATE INDEX CONCURRENTLY ix_messages_thread_id                 ON messages(thread_id);
CREATE INDEX CONCURRENTLY ix_msg_participants_thread_id         ON message_thread_participants(thread_id);
CREATE INDEX CONCURRENTLY ix_vet_patrol_entries_report_id       ON vet_patrol_entries(report_id);
CREATE INDEX CONCURRENTLY ix_vet_patrol_entries_animal_id       ON vet_patrol_entries(animal_id);
CREATE INDEX CONCURRENTLY ix_vet_patrol_entry_animals_entry_id  ON vet_patrol_entry_animals(entry_id);
```

| 風險 | 低（`CONCURRENTLY` 不鎖表；可 `DROP` 回退） |
|---|---|
| 成本 | 每個索引增加對應表的寫入成本與儲存，故只選熱表，不全加 |
| 驗收 | 對應 API 的 p95 latency vs Phase 0 baseline 下降；`EXPLAIN` 由 Seq Scan 轉 Index Scan |

> **待 Phase 0 量測後**：從 142 個業務 FK 中可能再篩掉低流量者，或補上未列出的複合索引（如 `(animal_id, created_at DESC)` 支援詳情頁排序）。上方清單為「高信心子集」，非最終定案。

---

### Phase 2 — 修 N+1 查詢 🟠（高效益 / 低風險 / 純後端 code）

| # | 位置 | 問題 | 建議修法 |
|---|---|---|---|
| 1 | `services/notification/erp.rs:111-135` | 雙層迴圈（PO 數 × 收件者）逐筆 `create_notification` INSERT，可達 50+ 條 SQL | 收集後 multi-row `INSERT ... VALUES (...),(...)` 一次寫入 |
| 2 | `services/notification/erp.rs:210-246` | 同上（手術缺銷貨稽核，計畫數 × 人數） | 同上 |
| 3 | `services/protocol/status.rs:360-362` | 迴圈內逐個 `assign_primary_reviewer_tx` INSERT | `INSERT ... SELECT` 或 multi-row VALUES（注意 transaction / FOR UPDATE 鎖） |
| 4 | `services/notification/protocol.rs:313-327 / 357-371 / 401-415` | 迴圈內逐人 `create_notification` | 批次化 `create_notification`（新增 bulk 版本） |
| 5 | `repositories/qa_plan.rs:400,433` | 每行觸發關聯子查詢 `COUNT(*) FROM qa_sop_acknowledgments` | 改 `COUNT(*) OVER (PARTITION BY sop_id)` 視窗函式或 LEFT JOIN 聚合一次取回 |

> 參考既有正確範例：`services/user.rs:261-297` 已用「預載 + HashMap 合併」避免 N+1，新修法可比照其 pattern。

| 風險 | 低（純 Rust 邏輯，有整合測試覆蓋的路徑需先跑綠） |
|---|---|
| 驗收 | 同一操作的 SQL 條數由 N（或 N×M）降為 1–2；對應 endpoint latency 下降 |

---

### Phase 3 — SQL 反模式修正 🟠（中高效益 / 低–中風險）

| # | 位置 | 問題 | 建議修法 |
|---|---|---|---|
| 1 | `repositories/ai.rs:119-125` | 儀表板 7 個全表 `COUNT(*)` | 改用 `pg_class.reltuples` 估算，或加 WHERE 過濾，或快取 |
| 2 | `repositories/ai.rs:165,176-203` | 動物搜尋 `ear_tag ILIKE '%' \|\| $2 \|\| '%'` 前置萬用字元 → 索引失效 | 改右前綴 `$2 \|\| '%'`，或建 `pg_trgm` GIN 索引支援模糊搜尋 |
| 3 | `repositories/product.rs:38-72` | `LOWER(TRIM(name))` 函式包欄位 → 索引失效 | 加 generated column 或表達式索引 `((lower(trim(name))))`，或應用層 normalize |
| 4 | `repositories/glp_compliance.rs` 多處 | 硬編碼 `LIMIT 200` 無真正分頁 | 改 keyset / offset 分頁參數 |

| 風險 | 中（改查詢語意需確認結果集不變，建議先寫對照測試） |
|---|---|
| 驗收 | 對應查詢 `EXPLAIN ANALYZE` 執行時間下降；功能回歸測試綠 |

---

### Phase 4 — Schema 結構調整 ⚪（條件式，預設不做）

**只有在 Phase 0–3 完成後，量測仍指出「特定某張表」是瓶頸時才進行**，且針對該表個案處理、逐案 surface tradeoff 等裁定。可能的候選議題（待數據佐證，現在**不預設要做**）：

- `user_activity_logs` 分區邊界目前到 2028Q4，需排程自動建立後續分區。
- 是否將極少查詢的審計欄位（199 個 user-FK）改為不設 FK 約束以降低寫入檢查成本（**合規影響大，需 GLP 端確認**）。
- 動物管理領域 33 表中是否有可合併的稀疏子表（需確認查詢樣態，多半不建議）。

| 風險 | 🔴 高（不可逆、動 API contract / GLP 合規路徑） |
|---|---|
| 規則 | 每個 schema 變更獨立 PR、獨立裁定、附 `migrations/down/` 對稱回退、更新 `docs/glp/traceability-matrix.md` |

---

## 4. 風險控管與停機點

- **跨 Phase 必停**：每個 Phase 完成、量測驗證後停下回報，不自動進下一個 Phase。
- **不可逆操作必經明確同意**：staging/production migration、schema 結構變更、移除 FK 約束。
- **Phase 1 分批**：索引不要一次全上，每批（Tier）上線後量測再續。
- **合規不可砍**：HMAC audit chain、簽章、權限檢查、紀錄鎖定 trigger 一律不在效能重構中觸碰。

---

## 5. 各階段驗收標準（對齊「效能數字改善」）

| Phase | 驗收標準 |
|---|---|
| 0 | 產出可重現的 baseline 數字表（p95 latency + top SQL） |
| 1 | 熱路徑 API p95 下降；目標 SQL `EXPLAIN` 由 Seq Scan → Index Scan |
| 2 | 目標操作 SQL 條數由 N/N×M → 1–2；endpoint latency 下降 |
| 3 | 目標查詢 `EXPLAIN ANALYZE` 時間下降；功能回歸綠 |
| 4 | 針對個案表的指定指標改善，且合規/契約無回歸 |

---

## 6. 本計劃刻意「不做」的事（scope 邊界）

- ❌ 為了減少表數而合併表（反效果，且非效能來源）。
- ❌ 一次性全系統 schema 重設計（不可逆、風險最高、效益最低）。
- ❌ 把 341 個缺索引 FK 無差別全加索引（過度索引傷寫入）。
- ❌ 在效能重構中順手改合規/簽章/稽核邏輯（surgical changes 原則）。

---

## 7. 建議的下一步

1. 你核准本計劃的**階段順序與 scope 邊界**。
2. 我先做 **Phase 0**：確認量測環境（staging？dev 灌測試資料？）→ 產 baseline。
3. Baseline 出來後，從 **Phase 1 Tier 1** 開始（動物詳情頁索引，效益最直觀），分批驗證。

> 需要你裁定的兩點：(a) Phase 0 量測要在哪個環境跑？(b) Phase 1 索引清單是否同意「審計用 user-FK 預設不加、只加業務 JOIN FK」這個取捨？
