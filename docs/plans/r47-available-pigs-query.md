# R47 — 可用豬隻快速查詢（庫存盤點）Design Doc

> **立案**：2026-05-13 / **規格定稿**：2026-05-13 / **作者**：vet + Claude
> **branch**：`feature/r47-available-pigs-query`
> **預估**：~7h、1 個 PR

## 1. 動機

規劃新 protocol 時，vet 需快速回答：**「手上現有可用豬，符合年紀 + 體重區間的有幾頭、公母比例如何、品種分佈為何」**。
目前動物列表頁缺月齡 / 體重區間 filter，也沒有統計列；每次都得手動撈資料 + 數頭數 — 痛點。

## 2. 規格定稿

### 2.1 「可用豬隻」定義

| AnimalStatus | 是否可用 | 條件 |
|--------------|---------|------|
| `Unassigned`（未分配） | ✅ 永遠可用 | — |
| `Completed`（實驗完成存活） | ✅ 永遠可用 | — |
| `InExperiment`（實驗中） | ⚠️ 條件可用 | 僅當 `include_breeding=true` 且該豬 protocol_no=`'000'` |
| `Euthanized` / `SuddenDeath` / `Transferred` | ❌ 排除 | — |

同時必須 `deleted_at IS NULL`，且**最近一筆體重 measured_at >= NOW() - 40 days**。

### 2.2 動物 ↔ 計畫關聯

```
animals.iacuc_no = protocols.iacuc_no  (隱式關聯，無 FK constraint)
```

- 純庫存豬：`animals.iacuc_no IS NULL` → LEFT JOIN 結果 protocol 端全 NULL
- 在計畫中：`animals.iacuc_no = protocols.iacuc_no`
- 「飼養計畫」識別：`protocols.protocol_no = '000'`（硬編，不過度設計）

### 2.3 「包含飼養計畫 000」toggle

- 預設 **off**：只列 `Unassigned + Completed`
- **on**：額外納入 `InExperiment` AND `protocol_no='000'` 的豬
- 其他 protocol_no（023、045...）的 InExperiment 豬永遠視為佔用，**toggle 不會把這些拉進來**

### 2.4 Filter 參數

| Filter | 型別 | 必填 | 備註 |
|--------|------|------|------|
| `sex` | `male` / `female` / `null` (all) | ✗ | 對應 `animal_gender` enum |
| `age_months_min` | i32 | ✗ | 含端點，`>=` |
| `age_months_max` | i32 | ✗ | 含端點，`<=` |
| `weight_min` | Decimal | ✗ | 含端點，`>=` |
| `weight_max` | Decimal | ✗ | 含端點，`<=` |
| `include_breeding` | bool（default false） | ✗ | 是否加飼養計畫 000 |
| `export` | `xlsx` / `null` | ✗ | 為 xlsx 時切到 Excel 路徑 |
| `page` / `per_page` | 數字 | ✗ | 分頁，預設 20/page |

### 2.5 API 回應結構（JSON 模式）

```json
{
  "animals": [
    {
      "id": "uuid",
      "ear_tag": "P001",
      "animal_no": "M001",
      "breed": "minipig",
      "gender": "male",
      "birth_date": "2024-01-15",
      "age_months": 28,
      "latest_weight_kg": "32.5",
      "weight_measured_at": "2026-05-08",
      "pen_location": "A-3",
      "pen_id": "uuid"
    }
  ],
  "summary": {
    "total": 20,
    "male": 12,
    "female": 8,
    "by_breed": { "Minipig": 12, "White": 5, "LYD": 3, "Other": 0 },
    "excluded_weight_expired": 3
  },
  "pagination": { "page": 1, "per_page": 20, "total": 20 }
}
```

- `age_months` 在 backend 算好給前端（避免前端時區誤差）
- `excluded_weight_expired`：用相同 filter 但**不要求**體重 ≤ 40 天的 count，減去主結果 count 得出
- breed key 用 enum 顯示名（含 LYD 大寫）

### 2.6 Excel 9 欄

| # | 欄位 | DB 來源 | 格式 |
|---|------|--------|------|
| 1 | 品種 | `animals.breed` | display name |
| 2 | 耳號 | `animals.ear_tag` | string |
| 3 | 性別 | `animals.gender` | 公/母 |
| 4 | 出生日 | `animals.birth_date` | yyyy-MM-dd |
| 5 | 月齡 | 計算欄位 | int |
| 6 | 最近體重(kg) | `weight_records.weight_kg` | decimal 1 位 |
| 7 | 量測日 | `weight_records.measured_at` | yyyy-MM-dd |
| 8 | 棟舍 | `pens.building` (via pen_id) 或 `pen_location` substring | string |
| 9 | 欄位 | `pens.code` 或 `pen_location` | string |

檔名：`available_pigs_{YYYYMMDD_HHMMSS}.xlsx`。Header bold + 凍結首列。

## 3. 實作拆解（4 backend + 4 frontend = 8 task）

### Backend (R47-1 ~ R47-4)

**R47-1: Query 函式（核心）**

`backend/src/services/animal/core/query.rs::list_available_pigs(pool, filter) -> Result<(Vec<AvailablePigRow>, Summary)>`

SQL 框架：

```sql
WITH latest_weight AS (
  SELECT DISTINCT ON (animal_id)
    animal_id, weight_kg, measured_at
  FROM weight_records
  WHERE measured_at >= NOW() - INTERVAL '40 days'
  ORDER BY animal_id, measured_at DESC
)
SELECT
  a.id, a.ear_tag, a.animal_no, a.breed, a.gender,
  a.birth_date, a.pen_location, a.pen_id,
  EXTRACT(YEAR FROM AGE(a.birth_date))::int * 12
    + EXTRACT(MONTH FROM AGE(a.birth_date))::int AS age_months,
  lw.weight_kg AS latest_weight_kg,
  lw.measured_at AS weight_measured_at
FROM animals a
LEFT JOIN protocols p ON a.iacuc_no = p.iacuc_no
INNER JOIN latest_weight lw ON lw.animal_id = a.id
WHERE a.deleted_at IS NULL
  AND a.birth_date IS NOT NULL
  AND (
    a.status IN ('unassigned', 'completed')
    OR (
      a.status = 'in_experiment'
      AND $include_breeding
      AND p.protocol_no = '000'
    )
  )
  AND ($sex IS NULL OR a.gender = $sex)
  AND ($age_min IS NULL OR <age_months_expr> >= $age_min)
  AND ($age_max IS NULL OR <age_months_expr> <= $age_max)
  AND ($weight_min IS NULL OR lw.weight_kg >= $weight_min)
  AND ($weight_max IS NULL OR lw.weight_kg <= $weight_max)
ORDER BY a.ear_tag
LIMIT $per_page OFFSET $offset;
```

注意：
- `birth_date IS NULL` 的豬無法算月齡 → 直接排除（在 summary `excluded_no_birthdate` 額外算？— **暫不做，本期只算過期體重排除**）
- `latest_weight` CTE 用 `DISTINCT ON` 取每豬最新一筆 ≤ 40 天的 weight
- `INNER JOIN latest_weight` 自動排除沒新鮮體重的豬
- `excluded_weight_expired`: 同 query 改 `LEFT JOIN` 改成 `LEFT JOIN`（含 NULL）但取 count，減去主 count 得出 — 或寫第二 query 用 `LEFT JOIN` 但 status filter 相同，count 後減去

Summary 計算：
```sql
-- 同 filter 但不要求新鮮體重，count 後減主結果即得排除數
SELECT
  COUNT(*) AS total_all,
  COUNT(*) FILTER (WHERE a.gender = 'male') AS male,
  ...
```
或在 Rust 端對主 list aggregate（list 已 pagination 不準）。**最終**：summary 必須走獨立 aggregate query 不分頁，避免 pagination 後 summary 不對。

**R47-2: Service + handler**

- `services/animal/core/query.rs::list_available_pigs` 是 service 函式（authorization 在 handler 端）
- `handlers/animal/animal_core.rs::list_available_pigs(state, query)`：
  - parse query params
  - 若 `export=xlsx` → 呼叫 R47-3 path、回 `Response<Bytes>` with `Content-Disposition`
  - 否則回 JSON `{ animals, summary, pagination }`
- Route：`GET /api/animals/available`，加在 `routes/mod.rs` animal routes 區
- 權限：沿用 `require_permission!("animal.read")` 既有 macro

**R47-3: Excel export**

- 新檔 `services/animal/excel_export.rs`（reusable）或 inline in handler
- 用 `rust_xlsxwriter`（已升 0.95 via PR #366）
- 共 9 欄、header bold、freeze pane 1 列
- 回 `bytes::Bytes`

**R47-4: 統計回應結構 + tests**

- Rust types：`AvailablePigRow`、`AvailablePigSummary`、`AvailablePigListResponse`
- Unit tests in `services/animal/core/query.rs`：
  - 純庫存 + Completed 預設都列入
  - include_breeding=true 加上 InExperiment+000
  - InExperiment + 其他 protocol 永遠排除
  - sex / age / weight filter
  - 體重 > 40 天的不列入主結果但計入 excluded_weight_expired
  - Euthanized / SuddenDeath / Transferred 永遠排除

### Frontend (R47-5 ~ R47-8)

**R47-5: Advanced filter panel**

- `pages/animals/AnimalsPage.tsx` 上方加折疊式 `<Collapsible>`（用既有 shadcn 元件）
- 折疊按鈕：「進階篩選」+ chevron
- 內容：
  - 性別 RadioGroup：全部 / 公 / 母
  - 月齡：兩個 Number input min~max
  - 體重(kg)：兩個 Number input min~max
  - Toggle：`包含飼養計畫 000 中的豬`（預設 off）
- 套用按鈕（或 onChange debounce 300ms）

**R47-6: 統計列**

- 表格 header 上方加 `<div>` chip 區：
  - chip 1：`符合 N 頭　♂ 12　♀ 8`
  - chip 2：`Minipig 12 / White 5 / LYD 3`（Other 為 0 不顯示）
- chip 用既有 `Badge` 元件
- summary 過期提示小字：`另有 N 頭因體重資料 > 40 天未列入`（N>0 才顯示）

**R47-7: 匯出 Excel 按鈕**

- filter panel 旁邊放「匯出 Excel」按鈕（icon: `FileDown`）
- onClick: 取目前 filter state、組 query string、`window.location.href = '/api/animals/available?...&export=xlsx'`
- 或用 fetch + blob + a.download（既有 download helper 沿用）

**R47-8: 過期體重提示**

- 已併入 R47-6 統計列下方小字
- 視覺：text-muted-foreground text-xs

## 4. 任務排序 + 預估

```
R47-1 query 函式 + tests  ──── 2h ┐
R47-4 types + summary ──── 0.5h  │ backend
R47-2 handler + route ──── 0.5h  │ 並行 OK
R47-3 xlsx export ──── 1h ───────┘
                          ↓
R47-5 filter panel ──── 1h ──────┐
R47-6 統計列 chip ──── 0.5h     │ frontend
R47-7 export 按鈕 ──── 0.5h    │ 並行 OK
R47-8 過期提示 ──── 0.5h ──────┘
                          ↓
e2e + manual QA ──── 0.5h
```

合計 ~7h，1 個 PR 可做完。

## 5. 風險與停機規則

- **不可逆風險**：低 — 新增 query / endpoint / UI 元件，不改既有 schema、不改 mutation
- **migration**：無
- **commit 粒度**：依 CLAUDE.md，PR 內 3-15 commit、單 commit < 500 lines
  - commit 1: R47-1 query 函式 + tests（service 層）
  - commit 2: R47-2 + R47-4 handler + types + route
  - commit 3: R47-3 xlsx export
  - commit 4: R47-5~8 frontend
  - commit 5: e2e + 文件

## 6. 順帶發現（不在本任務動）

`backend/src/services/access.rs:218-224` `get_animal_protocol_id` 函式寫：
```rust
sqlx::query_scalar("SELECT protocol_id FROM animals WHERE id = $1")
```
但 `animals` 表沒有 `protocol_id` 欄位（實際關聯走 `iacuc_no`）。被呼叫到會 SQL error。

**處置**：列入 R-backlog 獨立追蹤，**不在 R47 動手**（surgical changes 原則）。

## 7. 驗收標準

- [ ] backend tests: 6 個 unit test 全綠（見 R47-4）
- [ ] cargo clippy --all-targets -- -D warnings -A deprecated 綠
- [ ] frontend tsc + lint 綠
- [ ] 動物列表頁 advanced filter 可開合、6 種條件可篩
- [ ] 統計列即時更新（debounce 300ms）
- [ ] 切換 include_breeding toggle 後結果正確變動
- [ ] Excel 匯出檔開啟可讀、9 欄齊備、檔名含 timestamp
- [ ] 把某豬最近體重改成 41 天前 → 該豬從結果消失、excluded count +1
- [ ] Euthanized/SuddenDeath/Transferred 豬永遠不出現

## 8. PR description 範本

```
feat(R47): 可用豬隻快速查詢 + Excel 匯出

支援按性別 / 月齡區間 / 體重區間 filter，附「包含飼養計畫 000」toggle。
統計列顯示總數 / 公母 / 品種分佈；體重 > 40 天的豬自動排除並提示。

- backend: list_available_pigs query 函式 + handler + xlsx export
- frontend: advanced filter panel + 統計列 + 匯出按鈕

依 docs/plans/r47-available-pigs-query.md 規格落地。
```
