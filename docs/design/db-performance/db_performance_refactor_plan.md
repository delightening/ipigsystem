# 資料庫效能重構計劃（為規模主動優化）

> 受眾：專案負責人 + 未來的自己（半技術）。
> 更新：2026-06-25。**決策方向：為規模主動優化，不是等瓶頸出現才修**（2026-06-25 使用者裁定）。
> 但仍守三鐵律：**量測驅動、風險分級、跨階段必停**。本輪只完善計畫，尚未改 code。
> 證據基礎：對暫時 PostgreSQL 16（套用全 104 migration）灌 5,000 與 **50,000** 隻動物兩種規模實測。
> 搭配：`docs/design/db-performance/db_er_diagram.html`、`docs/design/db-performance/perf_baseline.md`。

---

## 0. 指導原則

1. **打真正的瓶頸，不做漂亮但低值的事。** 實測排序決定優先級，不靠直覺。
2. **規模殺手是「查詢寫法」，不是「缺索引」也不是「表的數量」。** 動物子表的 JOIN 欄位早已有索引；瓶頸在 OFFSET 深分頁、無界 COUNT、前置萬用字元。
3. **不破壞 API / 前端契約者優先。** 同樣效益下，選風險最低的做法（例：兩段式改寫 > keyset 換 UI）。
4. **每項都要有可量測的驗收標準**（before/after 數字），改完在暫時叢集（50k 資料）重測。
5. **跨階段必停**：每個工作項目（W1…）做完停下回報，不自動 push / merge / 進下一項。
6. schema 結構變更（W6）預設不做，條件式啟動。

---

## 1. 規模實測結論（5k → 50k，這是優先級的證據）

同一組查詢在兩種規模的實測（`EXPLAIN ANALYZE`，暫時叢集）：

| 查詢 | 5k | 50k | 擴展級別 | 判讀 |
|---|---:|---:|---|---|
| 詳情 `get_by_id`（PK） | 0.09ms | 0.04ms | **O(log n)** | 永遠快，免處理 |
| 列表第 1 頁（LIMIT 50） | ~35ms* | 9.2ms | **≈O(1)** | planner 在大表自動改走子表索引；免處理 |
| 分頁 COUNT（無篩選） | 0.79ms | 4.7ms | **O(n)** | Index Only Scan，線性成長 |
| 篩選搜尋 COUNT（`ILIKE '%x%'`） | — | 6.9ms | **O(n)** | 全表 Seq Scan（前置萬用字元 + 無 LIMIT 不能短路）|
| **深分頁 第 200 頁（OFFSET 9950）** | （不存在） | **🔴 867ms** | **O(offset)×enrich** | 對被丟棄的 9,950 列也跑昂貴 enrich + JIT |
| └ 同頁改**兩段式**後 | — | **✅ 11.7ms** | O(offset) on slim index | **74× 改善，不動 API/前端** |

> *5k 列表 35ms 是因為 planner 當時選擇把 `animal_observations`（80k）整表雜湊掃；50k 時整表（800k）太貴，planner 自動改成每列走 `idx_animal_observations_animal_id` 索引點查 → 反而剩 9.2ms。第 1 頁不是問題。

**三個會隨「動物數」惡化的真瓶頸**：
- 🔴 **深分頁 O(offset)×enrich**（867ms @ 第 200 頁）→ 兩段式已證明可解。
- 🟠 **篩選搜尋 COUNT 全表掃**（O(n)，500k≈70ms）→ trgm 索引 + total 處理。
- 🟠 **無篩選分頁 COUNT**（O(n)，500k≈47ms）→ 快取 / 約略。

**不隨動物數惡化、但隨「總操作量」惡化的表**：`user_activity_logs`（每次 mutation 都寫，數年將達千萬列；已分區，但 audit 列表 / 全表掃須注意）。

**結論：原先圈的 Phase 1（FK 索引）對「動物規模」幫助最小**（動物子表已有索引，缺的 32 個在 stock_ledger / 財會等與動物數無關的表）。**優先級翻轉如 §2。**

---

## 2. 翻轉後的優先順序（依實測 ROI）

| 工作 | 項目 | 實測 / 預期效益 | 風險 | 動到範圍 |
|---|---|---|---|---|
| **W1** | 動物列表 `list()` 改**兩段式分頁** | **867ms → 11.7ms（74×）** | 低 | 僅 `services/animal/core/query.rs`；API/前端不動 |
| **W2** | 篩選搜尋 COUNT：`pen_location` 補 trgm + total 策略 | 全表掃 → BitmapOr / O(1) | 低 | 加索引 + 微調 SQL |
| **W3** | 兩段式套用到其他「大表 + 每列 enrich」列表 | 同類 10–70× | 中 | 各列表 query（見 §3.W3 清單）|
| **W4** | Phase 1 FK 索引 Tier 1（非動物大表） | 邊際（為非動物表 / 寫入 / FK 完整性）| 低 | 一個 migration |
| **W5** | `user_activity_logs` 千萬列情境驗證 + audit 列表優化 | 待測 | 中 | audit 查詢 |
| **W6** | schema 結構（keyset 換 UI / 物化視圖 / 分區檢視）| 條件式 | 高 | 跨層；預設不做 |

---

## 3. 各工作項目詳述

### W1 — 動物列表兩段式分頁改寫（最高優先，已證明）

**問題**：`services/animal/core/query.rs:149` 的 `list()` 對「本頁 + 被 OFFSET 丟棄的所有列」都計算 LATERAL（最近體重、vet_recommendation）+ EXISTS（abnormal / on_medication）。第 200 頁 = 1 萬列 × enrich = 867ms（含 JIT 310ms）。

**做法（不改 API、不改前端、結果集等價）**：先用瘦查詢取本頁 id，再只對這 50 筆 enrich。
```sql
WITH pageids AS (
  SELECT id FROM animals p
  WHERE p.deleted_at IS NULL /* + push_animal_filters */
  ORDER BY <sort> LIMIT $per_page OFFSET $offset
)
SELECT ... /* 原本的 LATERAL / EXISTS / JOIN，全部 */
FROM pageids
JOIN animals p ON p.id = pageids.id
LEFT JOIN ...                       -- source / species / vet_recommendations / latest_weight
ORDER BY <sort>;                    -- 第二段要重排（pageids 已定序，但 JOIN 會打散）
```
**注意事項**：
- `<sort>` 兩段都要一致（含 `NULLS LAST, p.id` tiebreak）。**白名單排序欄若是 `lw.weight`（latest_weight）這種「enrich 出來的欄位」**，第一段瘦查詢拿不到 → 此情況退回單段或把 weight 也納入第一段子查詢。需逐一處理排序分支。
- `push_animal_filters` 的 keyword `ILIKE` 與 `is_on_medication` EXISTS 仍在第一段 WHERE（否則分頁列數不對）。
- COUNT 查詢（`query.rs:138`）不變（見 W2）。

**驗收標準（在 50k 暫時叢集）**：
- 任意頁（含第 200 頁）full 查詢 < 20ms（目前第 200 頁 867ms）。
- 結果集與現版**逐列等價**（同 id 順序、同欄位值）→ 寫對照測試。
- `cargo test --all-targets` 全綠（動到 service/handler 路徑）。
- 一個 commit，做完停下回報。

### W2 — 篩選搜尋 COUNT + total 策略

**問題**：
- 篩選搜尋的 total：`COUNT(*) ... WHERE ear_tag ILIKE '%x%' OR pen_location ILIKE '%x%'` → 全表 Seq Scan（50k=6.9ms，O(n)）。`ear_tag` 已有 `idx_animals_ear_tag_trgm`，但 `pen_location` 無 → OR 兩側無法都走索引。
- 無篩選 total：Index Only Scan 全索引（O(n)）。

**做法**：
1. 補 `pen_location` trgm 索引 → 兩側皆 trgm，planner 可 BitmapOr（選擇性高時才有效）。
   ```sql
   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_animals_pen_location_trgm
     ON animals USING gin (pen_location gin_trgm_ops);
   ```
2. total 策略（擇一，待裁定）：
   - (a) 無篩選時用約略計數（`reltuples`）顯示「約 N 筆」；
   - (b) 前端不顯示精確 total，改「下一頁是否存在」（撈 per_page+1）；
   - (c) 維持精確 COUNT，靠 trgm 索引壓低（選擇性高才夠）。

**驗收**：篩選搜尋 COUNT 在 50k 由 Seq Scan → Bitmap Index Scan（選擇性高的關鍵字）；或改方案後不再 O(n) 全表。

### W3 — 兩段式套用到其他大表列表（已盤點，結論：無需再改）

盤點候選 list 查詢是否有「每列 enrich（子查詢 / LATERAL / EXISTS）+ offset 分頁」的放大病：

| 候選 | 位置 | 是否有每列 enrich | 處置 |
|---|---|---|---|
| stock_ledger 列表 | `services/stock/ledger.rs:509-560` | ❌ 扁平 JOIN（w/p/d/loc 全 by id） | 不改 |
| audit 列表 | `services/audit.rs:1335-1353` | ❌ 扁平 SELECT（`ORDER BY created_at DESC` + OFFSET） | 不改 |
| messages 列表 | `services/messaging/message.rs` | ❌ EXISTS 僅 helper 檢查，非 list 投影 | 不改 |
| AI 動物查詢 | `repositories/ai.rs:162-203` | ❌ 扁平 SELECT（病在 `ear_tag ILIKE '%%'` + COUNT，非 enrich） | 走 W2/trgm，非兩段式 |

**結論**：兩段式（W1）是**動物列表專屬**——只有它有 LATERAL（最近體重 / vet_rec）+ EXISTS（abnormal / on_med）的每列 enrich 被 OFFSET 放大。其他大表列表都是扁平 JOIN/SELECT，OFFSET 不放大昂貴 enrich，**硬套兩段式為低值改動（違反外科手術原則），不做。**

**轉介的真正 follow-up（非兩段式）**：
- `stock_ledger` `ORDER BY sl.trx_date DESC` **無支援索引** → 200k+ 時排序整個 filtered set。考慮加 `stock_ledger(trx_date DESC)`（或含 warehouse_id 複合）→ 併入 W4 評估。
- `user_activity_logs` 列表 + COUNT（千萬列）：created_at 已為分區鍵；需驗證**分區修剪**（§7.5）+ COUNT 策略（W2 同類）。

### W4 — Phase 1 FK 索引 sweep（重新定位為收尾，非開場）

32 個無索引業務 JOIN FK（完整見 §5）。**對「動物規模」幫助小**，價值在非動物大表 / 寫入子表 / FK 完整性。建議只做 Tier 1：
```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stock_ledger_product_id               ON stock_ledger(product_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_storage_location_inventory_product_id  ON storage_location_inventory(product_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inventory_snapshots_product_id         ON inventory_snapshots(product_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_journal_entry_lines_account_id         ON journal_entry_lines(account_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_roles_role_id                     ON user_roles(role_id);
```
> ⚠️ **stock_ledger.product_id 已有複合索引 `(warehouse_id, product_id)` 可用**（實測非 Seq Scan，但需掃較大範圍）；專屬單欄索引使之變 tight seek，效益中等而非戲劇性。Tier 2/3 完整清單見 §5，延後到量測證明需要再上。

**執行限制（必讀）**：`CREATE INDEX CONCURRENTLY` 不能在 transaction 內，而 `sqlx::migrate!` 每個 migration 包 transaction（現有 104 migration 無一用 CONCURRENTLY 印證）。→ **雙軌**：
1. prod 用 `psql` 手動跑 CONCURRENTLY（無停機）；
2. 同時提交**非並行** `CREATE INDEX IF NOT EXISTS` migration（prod 已建 → no-op；新 DB / 測試正常建）；
3. 每個配對 `migrations/down/NNN_*.sql` 的 `DROP INDEX IF EXISTS`。

### W5 — user_activity_logs 千萬列情境（待裁定是否先測）

audit 日誌隨**操作量**長（非動物數），數年可達千萬列。建議灌千萬列實測 audit 列表查詢與 `WHERE hmac_version IS NULL`（`audit_log.rs:23`）等，再決定 partial index / 兩段式 / 分區策略。

### W6 — schema 結構（條件式，預設不做）

只在 W1–W5 後仍有特定瓶頸才逐項 surface tradeoff、等裁定：
- 若深分頁 11.7ms 仍嫌慢、且 UI 可接受「載入更多」→ 改 **keyset/cursor 分頁**（O(1)，但失去任意跳頁）。
- 高頻彙總（庫存 / 到期）→ 物化視圖 / 維護計數欄（如 `pens.current_count` 已是此模式）。
- 大日誌表分區修剪檢視。
- **不為了減表數而合併表。**

---

## 4. 執行紀律 / 停機規則（對齊 CLAUDE.md）

- **PR 測試標準**：W1/W3/W5 動 handler/service → `cargo test --all-targets` 全綠（需本地起測試 Postgres）；W2/W4 純索引 / SQL → 最小 lib 測試 + 暫時叢集量測。
- **跨工作必停**：每個 W 做完停下回報，不自動 push / merge / 進下一項。
- **不可逆操作必經明確同意**：prod 上 `CREATE INDEX CONCURRENTLY`、merge PR、push、prod 設定變更（如為 W5 在 prod 開 pg_stat_statements 需重啟）。
- **量測未達驗收必停**：改完在 50k 叢集量不到預期改善（或結果集不等價）→ 停下查因，不硬上。
- dev DB migrate 自動 OK。

---

## 5. 診斷附錄

### 5.1 SQL 反模式（repositories，已 Read 覆核行號）
- **HIGH**：`ai.rs:176–203` 前置萬用字元 `ear_tag ILIKE '%%'`（10 變體）；`ai.rs:162-165` 分頁全表 COUNT + 前置萬用字元；`ai.rs:119-122` 儀表板 4 連發全表 COUNT。
- **MEDIUM**：`query.rs:66-72`（pen_location ILIKE，見 W2）；`query.rs:138-144`（分頁 COUNT）；`product.rs:328`（`format!("%{kw}%")`）；`qa_plan.rs:400,433`（每列子查詢 COUNT → 改 LEFT JOIN GROUP BY）；`audit_log.rs:23`（partial index）。
- **LOW**：`hr.rs:52-63`（函式包欄位）；`pen.rs:23`、`equipment.rs:121`。

### 5.2 N+1（services/handlers，覆核後重新分級）
- ❌ 非 N+1：`update.rs:175`（迴圈最多 2 圈：old/new pen）；`facility.rs:772`（刻意逐筆 #649）。
- 🟡 MEDIUM（寫路徑，受輸入筆數限制）：`blood_test.rs:253-274` 逐筆 INSERT 血檢項目 → 多列 VALUES；`grn.rs:434-441` 逐 PO 重算。
- 🟢 LOW：`blood_test.rs:941-985`（受 active panel 數限制）；`invitation.rs:113`、`protocol/history.rs:242`。
- **重點**：無無界讀取型 N+1；熱讀路徑（動物列表）已用 LATERAL/EXISTS 一次撈，問題在 OFFSET 放大（W1 解）。

### 5.3 無索引 FK（160 個）
- 指向 `users` 審計欄 **128 個**：預設不加（只在寫入填值 / PK 反查 users，依 `created_by` 篩選罕見；整批加拖慢寫入）。日後有「某人經手紀錄」報表需求再單獨加。
- 業務 JOIN **32 個**（W4 對象，分 Tier）：
  - **Tier 1**：stock_ledger.product_id、storage_location_inventory.product_id、inventory_snapshots.product_id、journal_entry_lines.account_id、user_roles.role_id
  - **Tier 2**：expiry_monthly_snapshots(product_id, warehouse_id)、ap_payments.journal_entry_id、ar_receipts.journal_entry_id、blood_test_panel_items.template_id、qa_non_conformances.related_inspection_id、qa_schedule_items.related_inspection_id、report_history.scheduled_report_id、chart_of_accounts.parent_id、role_permissions.permission_id
  - **Tier 3**：electronic_signatures 反向 ×8、calendar_sync_conflicts ×3、notification_routing.role_code、environment_monitoring_points.zone_id（R21 parked）、animals.source_id、pdf_artifacts.attachment_id、application_notices.attachment_id、protocol_notice_acknowledgements.notice_attachment_id

---

## 6. 建議執行順序（一項一停）

0. **W0**（prod 可觀測性）— **應最先做**：先能看見才能優化（見 §7.4）。
1. **W1**（動物列表兩段式）— 最高 ROI、低風險、已證明、不破壞契約。
2. **W7**（動物詳情頁前端瀑布）— 使用者最有感（見 §7.1）。
3. **W2**（COUNT 策略）— 與 W1 同屬動物列表頁。
4. **W3**（盤點其他大表列表 → 逐一套用）。
5. **W8**（寫路徑成本量測）— 上萬隻前確認寫入不是瓶頸（見 §7.2）。
6. **W4**（FK 索引 Tier 1 sweep）— 收尾。
7. **W5 / W6** — 條件式，待前面量測結果決定。

---

## 7. 尚未涵蓋的面向（2026-06-25 實地查證補充）

> 原範圍（N+1 / ER / 建索引）只覆蓋「讀路徑 + 結構」。以下為補查項目，標明已查證 vs 待查。

### 7.0 ⚠️ Meta 結論：prod 現在太小，看不到 scale 問題
prod DB 啟動才 ~2 天、真實資料僅數百～數千列。實測發現 **450/770 個索引近 2 天 idx_scan=0**，但這**不是**索引沒用——是表太小，planner 直接 seq scan（連 `idx_animals_ear_tag_trgm`、`idx_animal_weights_animal_id` 等我們在 50k 測試明確看到被用的索引都顯示 0）。
**推論：prod 的統計（idx_scan / pg_stat_statements）現階段無法驅動 scale 優化；只能靠合成 50k 測試的投影。** 這反而強化「主動為規模優化」的正確性——等 prod 數字說話就太晚了。

### 7.1 動物詳情頁前端請求瀑布（W7，已查證 🔴）
`useAnimalDetailQueries.ts`：預設 `timeline` tab 一次發 **~10 支 API**，且有問題：
- **兩層瀑布**：`animal-data-boundary` 先回 → observations / surgeries / weights / sacrifice 才靠其 `afterParam` 出發（非並行，多一個 round-trip 延遲）。
- **過量抓取**：`approved-protocols` 直接 `GET /protocols`（全部計畫）再前端 filter；計畫變多時等同 AI 儀表板的全表抓取。
- ✅ 做得好：其他 tab 用 `enabled` lazy gate，不會預載。
**方向**：(a) `data-boundary` 併進 animal 主回應消除瀑布；(b) `/protocols?status=approved` 後端過濾取代全抓；(c) timeline 預設可考慮合併 endpoint。**驗收**：詳情頁 API 數 10→≤4、消除瀑布層。

### 7.2 寫路徑成本（W8，部分查證 🟠）
- 暫時叢集共 **32 個觸發器**，集中在 `user_activity_logs`（各分區 2 個，migration 041 不可變守衛）+ `electronic_signatures` + `animal_blood_test_items`。
- 每次 mutation = 業務寫入 + `user_activity_logs` 寫入 + HMAC chain 計算 + 觸發器。**上萬隻動物的營運寫入量下，寫放大未量測。**
- **待做**：在 50k 叢集量單筆 mutation 的端到端寫延遲（含 audit + HMAC + trigger），確認寫入不是隱藏瓶頸。

### 7.3 死索引盤點（已查證，結論：現階段不可行 ❄️）
450/770 索引近 2 天 0-scan，但**總大小僅 9.8MB**，且因小表 seq scan 而非真死索引（見 §7.0）。**現在刪除有害（會砍掉 scale 後需要的索引）。**
**待做**：prod 累積 ≥1 個月統計 + 資料量上來後再盤，排除當季 `user_activity_logs` 分區與 PK/UNIQUE 約束索引。

### 7.4 prod 可觀測性（W0，已查證 🔴 應最先做）
實測 prod 設定：
- `shared_preload_libraries =` **空** → pg_stat_statements **未載入**（extension 在 catalog 但沒 preload）→ **零查詢統計**。
- `log_min_duration_statement = -1` → **慢查詢 log 關閉**。
- `jit = on`、`jit_above_cost = 100000`（預設）→ 我們實測 867ms query 的 **310ms JIT 過載在 prod 是活的**。
- `track_io_timing = off`、`work_mem = 4MB`、`max_connections = 100`。
**建議（W0，需重啟 postgres 一次，要明確同意）**：
1. compose 加 `-c shared_preload_libraries=pg_stat_statements`（extension 已建）。
2. `log_min_duration_statement = 500`（記錄 >0.5s 查詢）。
3. 評估 OLTP 短查詢調 `jit_above_cost` 上調或 `jit=off`（消除 310ms 過載）。
4. `track_io_timing = on`（EXPLAIN BUFFERS 才有 I/O 時間）。

### 7.5 其他已知、本輪未查（待裁定是否納入）
- **並發 / 負載測試**：全部是單 query EXPLAIN，未測吞吐 / 鎖競爭（真實瓶頸常在此；已知 WeasyPrint 必須序列化即此類）。
- **連線池**：sqlx `PgPool` max_connections vs PG `max_connections=100` 是否匹配。
- **配合 sort 的複合索引**：列表 sort 白名單（status / gender / entry_date…）部分欄缺索引 → 大表全表排序。
- **權限 N+1**：`services/access.rs` 可見範圍是否逐列查。
- **分區修剪驗證**：`user_activity_logs` / `ai_query_logs` 查詢是否帶分區鍵。
- **autovacuum / 統計新鮮度**：高寫入 audit 表 stats 過時 → 爛計畫。
- **前端大列表渲染**：動物列表渲染數千列是否需虛擬化（前端效能，非 DB）。
