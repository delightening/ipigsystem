# 設計提案：新增「已轉出院外」終態（departed）

> 狀態：**未來 backlog（純假設需求，無時程）**。本文僅記錄方向與草案，**尚未施作**。
> 關聯：GitHub issue #180（移除 `transferred` 中間態的較大重構）。
> 產出脈絡：豬隻狀態說明討論（2026-07，見 `docs/design/animal-status-explanations.html`）。

## 1. 背景與問題

`AnimalStatus` enum 目前把兩個正交維度塞進同一欄位：

| 維度 | 內容 | 現況表達 |
|---|---|---|
| 生命週期／實驗階段 | 未分配 → 實驗中 → 實驗完成 → 死亡 | enum 主要在管這個 ✅ |
| 實體在場／位置 | 在場 / 離場 | 無獨立表達 ❌ |

具體語意缺口：**外部轉讓（external）完成時**，`complete_transfer` 會清空 `pen_location` / `pen_id`（動物實體離院），但狀態卻設回 `in_experiment`（`backend/src/services/animal/transfer.rs` 步驟 5）。結果是「已離院的豬顯示為實驗中」，看不出牠已不在場。

## 2. 現況事實（釐清，避免誤解）

- **目前實際只有 internal 轉讓**（院內計劃間互轉），動物一律留在場內。
- **external（轉出院外）歷史上從未真正發生**，屬純假設需求、無時程。
- **單一場地**為主，無多院區／跨棟規劃。

→ 因此**不採**「在場/離場」正交維度（過度設計）；未來若 external 真要用，採**最小侵入的專屬終態**。

## 3. 決策：方案 A —— 新增專屬終態 `departed`

新增一個動物狀態 `departed`（顯示名暫定「已轉出院外」），比照 `euthanized` / `sudden_death` 為**終點狀態**：

- `is_terminal()` → `true`
- `is_active_in_facility()` → `false`
- 不可再轉出任何狀態
- 徽章色：建議 `neutral`（灰）或 `purple`，與死亡終態（紅）區隔——動物未死，只是離院。

### 被否決的替代方案

- **方案 B（在場/離場正交維度）**：語意最乾淨，但單一場地 + 純假設需求下屬過度設計，擱置。
- **維持現況**：external 完成顯示「實驗中」的語意缺口無解，僅靠說明文案 band-aid。

## 4. 草案（實作時再細化，屬必問紅線）

> 以下為方向草案。真正動工前須依 `RULES_BACKEND.md` §9 走 migration 選號，並就 API contract / 狀態機改動停下 surface tradeoff。

### 4.1 Schema migration（草案）

```sql
-- 新增 enum 值（Postgres enum 只能 ADD，無法就地移除）
ALTER TYPE animal_status ADD VALUE IF NOT EXISTS 'departed';
```

### 4.2 狀態機（`backend/src/models/animal/enums.rs`）

- `display_name`：`Departed => "已轉出院外"`
- `is_terminal`：加入 `Departed`
- `is_active_in_facility`：`Departed` 落在「非在場」（`is_terminal` 已涵蓋）
- `can_transition_to`：`external` 轉讓完成的目標由 `Completed → Departed`（取代目前的 `→ InExperiment`）

### 4.3 轉讓流程（`transfer.rs` 步驟 5 `complete_transfer`）

- `is_external == true` 時：`status = 'departed'`（而非 `in_experiment`），維持清空 `pen_location` / `pen_id`。
- `is_external == false`（internal）：維持現況 `→ in_experiment`，不受影響。

### 4.4 pen count 影響

`current_count` 的 recalc 條件目前為
`status NOT IN ('euthanized', 'sudden_death', 'transferred')`。
新增 `departed` 後，**須一併排除**（離院不計欄舍在養數）：
`status NOT IN ('euthanized', 'sudden_death', 'transferred', 'departed')`。
需全面盤點所有出現此條件的 SQL（`transfer.rs`、pen repo、動物查詢等）並一致更新。

### 4.5 前端影響

- `frontend/src/types/animal.ts`：`AnimalStatus` union + `animalStatusNames` / `allAnimalStatusNames` 加 `departed`。
- 狀態色：`constants.ts` 的 `statusColors` / `detailStatusColors` 補 `departed`。
- i18n：`animals.statusLabels.departed` + `animals.statusHelp.departed`（本次已建好 statusHelp 骨架，屆時補一段即可）。
- 篩選頁籤：`AnimalFilters.tsx` tabs 補 `departed`。
- `EXCLUDED_STATUSES`（`lib/api/animal.ts`）視語意決定是否納入。

## 5. 非目標（本提案不含）

- 不做「在場/離場」正交維度。
- 不處理多院區／跨棟搬遷（無規劃）。
- 不改 internal 轉讓行為。

## 6. 觸發條件

當 external（轉出院外）從「純假設」變成**有具體時程的需求**時，再啟動本提案；屆時先出正式 migration + 影響盤點給使用者審，不直接動 code。
