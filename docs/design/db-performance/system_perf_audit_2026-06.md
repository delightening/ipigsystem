# 全系統效能排查報告（2026-06）

> 範圍：DB / Infra+Postgres / Backend handler / 前端 / 並發負載，五層。
> 方法：量測驅動（非猜測）。日期：2026-06-26。
> 前置作業（已落地 prod）：#794 DB 效能（兩段式分頁 / trgm / FK 索引 / pg_stat_statements 可觀測性）、#797 寫入路徑 N+1（document 明細 + 動物匯入）。本報告涵蓋這兩者**之外**的全系統排查。

---

## 0. 總結論（先看這個）

**現 prod 規模下（單一場區、153 隻動物、輕流量），系統效能健康——熱查詢 sub-60ms、讀路徑並發無瓶頸、無鎖競爭。以下發現多為「優化機會 / scale 預備」，非當前 bug。**

最值得做的（依 ROI）：
1. 🟠 **`/protocols` 後端過濾**（詳情頁最慢呼叫 47ms / DB 14.7ms，傳全部計畫再前端 filter）
2. 🟡 **PG 針對 SSD 調校**（`random_page_cost=4`→1.1 等，config-only，影響 plan 選擇）
3. 🟢 **前端小修**（`metrics/vitals` 雙打、shell 呼叫去重、`utils` bundle 拆重函式庫）

---

## 1. 方法（四個真相來源）

| 來源 | 用途 | 本次狀態 |
|---|---|---|
| prod `pg_stat_statements`（W0 開啟） | 真實查詢時間 | ✅ 已讀（瀏覽 + 負載後累積）|
| prod 真實 session（browse handoff 登入） | 前端真實熱頁量測 | ✅ 動物列表/詳情實測 |
| 合成負載（curl 並發 conc10/20/40） | 連線池 / 鎖競爭 | ✅ 讀路徑實測 |
| 程式碼 / 設定 inspection | 反模式 / config | ✅ PG 設定 / bundle |

> ⚠️ prod 流量輕 + stats 會被部署 reset → 真實數據要持續累積（期間少部署）才更具代表性；本報告數字為「瀏覽 + 負載」期間樣本。

---

## 2. 各層發現

### 2.1 DB（多數於 #794/#797 已處理）
- 熱讀路徑（動物列表/詳情）已修兩段式 + 索引；寫入 N+1（document/匯入）已修。
- 本次 pg_stat 複查：**DB 端無慢查詢**，SELECT 全 <22ms（除一次性 `maintenance_vacuum_analyze` 145ms）。
- 剩餘 backlog（R78）：W2 total 策略、分區修剪驗證、autovacuum、sort 白名單複合索引——現規模未觸發。

### 2.2 Infra + Postgres 🟡（config-only 機會）
PG 跑近原廠預設，**未針對所在 2GB 容器 + SSD 調校**：

| 設定 | 現值 | 建議 | 理由 |
|---|---|---|---|
| `random_page_cost` | **4**（HDD 預設）| **1.1** | SSD;現值高估索引成本 → planner 偏 seq scan（影響 plan 選擇，最關鍵）|
| `shared_buffers` | 128MB | ~512MB | 只用 2GB 的 6% |
| `work_mem` | 4MB | 16-32MB | 大排序/雜湊 spill 磁碟（注意 ×連線）|
| `effective_io_concurrency` | 1 | 200 | SSD 可並行 |

- `print-pdf` idle 記憶體 **386/512MB（75%）**：render 尖峰需盯（已知必須序列化）。
- ⚠️ 調 PG 需重啟 db → reset pg_stat_statements。建議「養數據幾天 → 再一次調」。

### 2.3 Backend handler 🟠
- **`log_activity`（audit 寫）mean 5.9ms × 每次 mutation**：寫放大主因（business 寫 + audit + HMAC chain + 16 索引）。現規模可接受;寫密集批次會累積。
- **`/protocols` 列表 DB 14.7ms**：回傳全部計畫（前端再 filter）→ 後端 `?status=approved` 過濾可減 DB + 網路 + 序列化。
- 前端看到的 `events` 58ms 未進 DB 慢查榜 → 主要是網路/序列化，非 DB。

### 2.4 前端 🟠🟢（W7 驗證成功）
- ✅ **W7 修復 prod 驗證**：詳情頁 observations/surgeries/weights **各只抓一次**（雙重抓取已消除）。
- 🟠 **`/protocols` over-fetch**：詳情頁最慢呼叫（47ms），抓全部計畫前端 filter。
- 🟡 **`metrics/vitals` 每頁雙打**；**~10 個 shell/全域呼叫每次導航重打**（me、nav_order、各 badge、auth/refresh、config-warnings、alerts、pdf-health、heartbeat）→ 部分可加長 staleTime / 合併。
- 🟡 **`utils` bundle 282KB（解壓,eager 載入 shell）**：疑似重函式庫（匯出/圖表/pdf）沒做 route-level lazy。
- 🟢 動物列表預設 by-pen 視圖渲染全部在欄動物（116 隻 / 1054 DOM 節點,現規模 OK,隨欄位數成長不分頁——facility 大幅成長才需注意）;`animals` + `by-pen` 同載 + 4 個 facility 下拉分開打。
- ⚠️ 詳情頁 data-boundary → obs/surg/weights 仍 2 層序列（W7 消雙抓但序列依賴在;徹底解需把 boundary 併入 animal 回應）。

### 2.5 並發 / 負載 🟢
GET /animals 合成負載（200 req × conc 10/20/40）:

| conc | p50 | p95 | p99 | max | 峰值 active DB 連線 |
|---|---|---|---|---|---|
| 10 | 13ms | 30ms | 41ms | 42ms | 2 |
| 20 | 9ms | 13ms | 15ms | 16ms | 2 |
| 40 | 10ms | 15ms | 24ms | 38ms | 2 |

- **p95 在 conc40 仍 15ms、峰值只 2 條 DB 連線 → 無 pool 飽和、無鎖競爭**。pool=10 對讀有大量餘裕。
- （throughput 28-35 req/s 為測試框架 process-spawn 上限,非 server;p95 才是可靠訊號。）
- 未測：寫密集並發、大資料量下的並發（讀健康,寫路徑因 audit 序列化值得未來測）。

---

## 3. 可動修復清單（依 ROI，給「再修 code」階段）

| # | 項目 | 層 | 改動 | 風險 | 效益 |
|---|---|---|---|---|---|
| P1 | `/protocols` 後端加 `status` 過濾 + 前端改用 | Backend+FE | 小 | 低 | 詳情頁最慢呼叫 47ms↓、減傳輸 |
| P2 | `metrics/vitals` 雙打修掉 | FE | 小 | 低 | 每頁少 1 呼叫 |
| P3 | shell/全域呼叫加長 staleTime / 合併（config-warnings、nav_order 等少變的） | FE | 小-中 | 低 | 每次導航少數個呼叫 |
| P4 | `utils` bundle 分析 + 重函式庫 route-level lazy | FE | 中 | 低 | 首屏 JS↓ |
| P5 | PG 調校（random_page_cost / shared_buffers / work_mem / eff_io_concurrency） | Infra | config + 重啟 | 低-中 | plan 品質、SSD 充分利用。**需擇期（reset stats）** |
| P6（條件式） | 詳情頁 data-boundary 併入 animal 回應消序列 | FE+BE | 中 | 低 | 詳情頁少 1 round-trip |
| P7（條件式） | by-pen 視圖 facility 大幅成長後的渲染策略 | FE | 中 | — | 規模觸發才做 |

> 寫放大（log_activity）+ audit 2 個 jsonb GIN 拔除：屬 R78 backlog，需更長 prod 觀測，不在本輪 quick win。

---

## 4. 建議執行順序（再修 code 階段）
1. **P1 + P2 + P3**（前端/後端 quick win,同一 PR,純 code 無 migration）→ 走 CI → 部署。
2. **P4**（bundle 分析,可能獨立 PR）。
3. **P5**（PG 調校）擇期單獨做（會 reset pg_stat,挑「已養夠數據」時機）。
4. P6/P7 條件式。
