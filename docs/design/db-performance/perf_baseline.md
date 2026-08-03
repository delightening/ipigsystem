# 資料庫效能 Baseline（Phase 0）

> 對應計劃：`docs/design/db_performance_refactor_plan.md` 的 Phase 0。
> 目的：在改任何索引/查詢**之前**留下可比對的數字。產出日期：2026-06-24。
> **本輪不改任何 code、不加任何索引。** 做完即停，待裁定才進 Phase 1。

---

## ⚠️ 最重要結論（先看這個）

**在本系統的真實規模下（單一場區、累計數千隻動物、非百萬級），目前資料庫沒有明顯瓶頸。** 灌入代表性合成資料後，所有熱查詢實測都在 **sub-2ms**（動物列表主查詢 35ms 為唯一例外，成本在計算欄位而非缺索引）。

實測也**修正了診斷階段的幾個假設**（猜測 vs 量測的差異）：

| 診斷階段的假設 | Phase 0 實測 | 修正 |
|---|---|---|
| `stock_ledger` 依 product_id 查 = Seq Scan | 已有複合索引 `idx_stock_ledger_warehouse_product(warehouse_id, product_id)`，planner 用整段索引掃（570 buffers, 1.4ms） | 補單欄索引仍有益（變 tight seek），但**不是「Seq→Index」戲劇性改善**，效益較預期小 |
| AI 儀表板 4 連發全表 COUNT 是 HIGH 瓶頸 | `animals` 已走 Index Only Scan、`protocols` 僅 500 列 → 全段 1.66ms | 現規模下**非瓶頸**；隨資料成長才需處理 |
| 動物列表 `pen_location ILIKE '%%'` 走 seq scan 很慢 | 5000 動物 + LIMIT 50 下，planner walk PK + filter 即 0.95ms | 前置萬用字元在**現規模 + 有 LIMIT** 時成本低；風險在無 LIMIT 的 COUNT / 罕見關鍵字 / 大表 |

**這正是「量測驅動、跨階段必停」的價值**：避免為 sub-2ms 的查詢做高風險優化。Phase 1 的 FK 索引現階段是「**為寫入子表 + 未來成長預留**」，而非「解決當前慢查詢」。**建議：把 Phase 1 視為低優先 / 條件式，除非預期資料量將大幅成長，或 prod 上 `pg_stat_statements` 顯示真實熱點與此 dev baseline 不同。**

---

## 1. 量測環境

| 項目 | 內容 |
|---|---|
| 叢集 | `postgres:16-alpine` 暫時容器（port 5455 + tmpfs），與 prod（5432）完全隔離，**不碰正式資料** |
| schema | `backend/migrations` 全部 104 個 migration 套用後的真實結構 |
| 既有索引 | 769 個（migration 030 等已建不少熱路徑索引） |

### 啟用 pg_stat_statements 的設定與步驟

`shared_preload_libraries` 必須在**啟動時**載入（`ALTER SYSTEM` + `restart` 對 tmpfs 容器無效，會被 wipe）。本 baseline 用啟動參數：

```bash
docker run -d --name ipig-erd-tmp \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=*** -e POSTGRES_DB=ipig_erd \
  --tmpfs /var/lib/postgresql/data -p 127.0.0.1:5455:5432 \
  postgres:16-alpine \
  -c shared_preload_libraries=pg_stat_statements \
  -c pg_stat_statements.track=all \
  -c track_io_timing=on
# 之後：
psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"   # migration 012 其實已建
```

> **prod / dev 永久叢集**的對應做法：在 `postgresql.conf`（或 docker-compose 的 `command:`）設 `shared_preload_libraries='pg_stat_statements'` 並重啟一次；extension 由 migration 012 建立。`track_io_timing=on` 讓 `EXPLAIN (BUFFERS)` 有 I/O 時間。

### 合成資料規模（代表性，灌入 dev 隔離叢集）

| 表 | 列數 |
|---|---|
| animals | 5,000 |
| animal_weights | 100,000 |
| animal_observations | 80,000 |
| animal_surgeries | 10,000 |
| stock_ledger | 200,000 |
| products | 2,000 |
| protocols | 500 |
| users | 200（+ migration seed）|
| documents / warehouses / species / animal_sources | 1,000 / 20 / 5 / 10 |

> 規模依「單一場區研究豬、逐隻照顧、系統營運數年累積」估算。animals 量級刻意設在數千（符合本場真實量），其餘子表按每隻多筆紀錄放大。

---

## 2. Top SQL by total_exec_time（pg_stat_statements）

工作負載：每條熱查詢跑 40 次後擷取。

| total_ms | calls | mean_ms | **max_ms** | stddev_ms | 查詢（截斷） |
|---:|---:|---:|---:|---:|---|
| 29.2 | 40 | 0.730 | 1.758 | 0.310 | `SELECT * FROM stock_ledger WHERE product_id IN (...)` |
| 14.7 | 40 | 0.369 | 0.480 | 0.042 | `... animals ... ear_tag ILIKE $2 OR pen_location ILIKE ...` |
| 9.1 | 40 | 0.228 | 0.349 | 0.033 | `SELECT (count animals), (count protocols)` 儀表板 |
| 7.8 | 40 | 0.196 | 0.305 | 0.028 | `SELECT count(*) FROM animals WHERE deleted_at IS NULL` 分頁 COUNT |
| 2.5 | 40 | 0.061 | 0.172 | 0.031 | `animal_weights ... ORDER BY measure_date DESC LIMIT 1` |
| 1.8 | 40 | 0.046 | 0.163 | 0.024 | 動物列表 JOIN |

> **關於 p95**：`pg_stat_statements` **不提供百分位數**，只有 `mean / min / max / stddev`。上表以 `max_ms`（最差單次）+ `stddev` 作為尾延遲代理。真正的 API p95 需在應用層（Axum middleware / Prometheus histogram，本專案已有 `middleware/response_logger.rs` + Grafana）量測——**建議在 prod 上對熱路徑 API 加 histogram 後讀 p95**，這比 dev 合成資料更貼近真實使用者體驗。

---

## 3. EXPLAIN (ANALYZE, BUFFERS) — 加索引前數字

### ① 動物列表主查詢（`services/animal/core/query.rs:149`，無 filter, LIMIT 50）
- **Execution Time: 35.5 ms**（最慢的熱查詢）
- 動物本體 + JOIN + LATERAL 體重查詢都走索引（`animals_pkey` backward、`idx_animal_weights_animal_id` bitmap、`animal_sources/species` PK + Memoize）——這部分快。
- **成本集中在兩個計算欄位**（一次性 hashed subplan，非缺索引）：
  - `has_abnormal_record`：`Seq Scan on animal_observations` filter `record_type='abnormal'`，掃 80,000 列、**8.8 ms**
  - `is_on_medication`：`Seq Scan on animal_observations` filter `NOT no_medication_needed`，掃 80,000 列、**6.7 ms**
- **加索引前**：上述為 Seq Scan。隨 `animal_observations` 成長而線性變慢。
- **改善方向（Phase 3，非 Phase 1）**：partial index `animal_observations(animal_id) WHERE record_type='abnormal'` 與 `WHERE no_medication_needed=false`，或把計算欄改為實體化/觸發維護。

### ② 動物列表 keyword 搜尋（`pen_location ILIKE '%Q1%'`）
- **Execution Time: 0.95 ms**
- 計畫：`Index Scan Backward using animals_pkey` + Filter（`ear_tag ILIKE OR pen_location ILIKE`），Rows Removed 682。
- **加索引前**：未用 trgm（LIMIT 50 + 常見關鍵字下，walk PK 即夠快）。trgm 索引的效益在**罕見關鍵字 / 無 LIMIT 的 COUNT / 表變大**時才顯著。

### ③ 動物列表分頁 COUNT
- **Execution Time: 0.79 ms** — 已走 `Index Only Scan using idx_animals_active`（Heap Fetches: 0）。已最佳化，無需處理。

### ④ 動物詳情 `get_by_id`（`query.rs:306`，PK）
- **Execution Time: 0.086 ms** — `Index Scan using animals_pkey`。極快。
- 次要：`experiment_assigned_by_name` 子查詢對 `users`（201 列）Seq Scan，0.03ms，可忽略。

### ⑤ stock_ledger 依 product_id（ERP Tier 1 候選）
- **Execution Time: 1.39 ms**，570 buffers。
- 計畫：`Index Scan using idx_stock_ledger_warehouse_product`，`Index Cond: (product_id = ...)`。
- **重要**：product_id 是該複合索引的**第二欄**，planner 仍能用但需掃較大範圍（cost 3776）。**加專屬 `idx_stock_ledger_product_id` 後預期變 tight seek**（buffers 與 cost 大降），但因已有可用索引，**並非從 Seq Scan 起步**。

### ⑥ AI 儀表板 4 連發 COUNT（`repositories/ai.rs:119-122`）
- **Execution Time: 1.66 ms**
- `animals` 兩個 COUNT 都走 `Index Only Scan`（`idx_animals_pen_id`、`idx_animals_status_deleted_created`，Heap Fetches: 0）。
- `protocols` 兩個 COUNT 走 Seq Scan，但只 500 列（9 buffers），微不足道。
- **加索引前**：現規模非瓶頸。隨 animals/protocols 大幅成長才需快取或約略計數。

---

## 4. 既有索引盤點（意外發現，schema 其實已相當有索引）

baseline 計畫執行時觀察到以下既存索引（非本輪新增）：
`animals_pkey`、`idx_animals_active`、`idx_animals_status_deleted_created`、`idx_animals_pen_id`、`idx_animals_ear_tag_trgm`、`idx_animal_weights_animal_id`、`idx_animal_observations_animal_id`、`idx_animal_surgeries_animal_id`、`idx_stock_ledger_warehouse_product`、`idx_user_protocols_*` 等。

→ 動物/庫存熱路徑的主要 JOIN 欄位**多已有索引**。Phase 1 的 32 個「無索引業務 FK」多落在**較少查詢的子表 / 反向查找**，這與 baseline「現規模無瓶頸」一致。

---

## 5. 規模壓測：5k → 50k（2026-06-25 補充）

把同一組查詢灌到 **50,000 隻動物**（10×，子表等比：1M 體重 / 800k 觀察 / 100k 手術）重測，看哪些查詢隨規模惡化：

| 查詢 | 5k | 50k | 擴展級別 | 判讀 |
|---|---:|---:|---|---|
| 詳情 `get_by_id`（PK） | 0.09ms | 0.04ms | O(log n) | 永遠快 |
| 列表第 1 頁 | ~35ms* | 9.2ms | ≈O(1) | planner 自動改走子表索引，免處理 |
| 分頁 COUNT（無篩選） | 0.79ms | 4.7ms | O(n) | Index Only Scan 線性 |
| 篩選搜尋 COUNT（`ILIKE '%x%'`）| — | 6.9ms | O(n) | 全表 Seq Scan（前置萬用字元 + 無 LIMIT）|
| **深分頁 第 200 頁（OFFSET 9950）** | （不存在）| **🔴 867ms** | O(offset)×enrich | 對被丟棄的 9,950 列也跑 enrich + JIT |
| └ 改**兩段式**後 | — | **✅ 11.7ms** | — | **74×，不動 API/前端** |

> *5k 列表 35ms 是 planner 當時雜湊整表掃 observation；50k 時整表太貴改走索引點查，反而剩 9.2ms。

**真瓶頸（隨動物數惡化）**：深分頁 O(offset)×enrich（867ms）> 篩選 COUNT 全表掃 > 無篩選 COUNT。
**FK 索引對「動物規模」幫助最小**（動物子表已有索引）。

## 6. 結論與下一步

- ✅ Phase 0 baseline + 50k 規模壓測完成。
- **決策（2026-06-25）：為規模主動優化。** 詳細執行計畫見 `db_performance_refactor_plan.md`（已依實測 ROI 翻轉優先序）：
  1. **W1** 動物列表兩段式分頁（867ms→11.7ms，已證明）— 最高優先。
  2. **W2** 篩選 COUNT trgm + total 策略。
  3. **W3** 兩段式套用其他大表列表（stock_ledger / audit / messages / ai.rs）。
  4. **W4** FK 索引 Tier 1 sweep（收尾）。
  5. **W5/W6** 條件式（audit 千萬列、keyset/物化視圖）。
- 仍建議擇期在 **prod** 開 `pg_stat_statements` 跑一週，用真實流量校準 dev 合成 baseline（最準）。
