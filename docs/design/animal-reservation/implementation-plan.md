# 動物預約與試驗規劃 — 分階段實作計畫

> 設計來源：memory `animal-reservation-planning`、mockup `reservation-planning-mockup.html`（v2）。
> ⚠️ Phase 0 為 **schema migration（高風險，不可逆）**，需使用者明確簽核後才執行。（已簽核 2026-07-01）

## 決策摘要
- 按試驗分組（已核准 `protocols`／規劃中新表 `planned_experiments`）。
- 兩段式：**預約**（earmark 未分配動物）→ **正式分配**（進實驗中，狀態轉 `in_experiment`、預約自動清）。兩類試驗一致。
- 搜尋（體重/週齡/性別）+ 多選批次配對到缺口。
- 需求：已核准讀 protocol 動物數量欄；規劃中讀 `demand_count`。
- 缺口 = 需求 −（已分配 + 已預約）。備註可改、體重唯讀。權限：執行秘書 + 管理員。

---

## Phase 0 — Schema migration ⚠️（已簽核，本 PR）
`backend/migrations/117_animal_reservation_planning.sql`（原 115，因與 HR 分支 migration 115/116 撞號改號）
1. 新表 `planned_experiments(id, unit, description, demand_count, protocol_id?→protocols, created_by, created_at, updated_at)`。
2. `animals` 加 `reserved_protocol_id?` / `reserved_planned_experiment_id?`（ON DELETE SET NULL）+ CHECK `num_nonnulls(...) <= 1`（二擇一）。
3. 索引：兩個 reserved 部分索引 + planned_experiments.protocol_id。
- DDL 已對 prod 現行 schema `BEGIN…ROLLBACK` 驗證通過。實際套用於 api 下次啟動（sqlx::migrate!）。
- **待確認（後續 Phase）**：protocol「申請動物數量」欄實際位置、`執行秘書` 角色代碼。

## Phase 1 — 後端：planned_experiments CRUD
- model DTO + repository + service + handlers + routes（`GET/POST /planned-experiments`、`PUT/DELETE /planned-experiments/:id`）。權限：秘書+管理員。Service-driven audit。

## Phase 2 — 後端：預約 + 正式分配 + 搜尋
- `POST /planned-experiments/:id/reserve` + `POST /protocols/:id/reserve`（body `{animal_ids:[]}`，批次；校驗未分配）。
- unreserve；正式分配重用既有 `POST /animals/batch/assign` 並清空 reservation。
- 搜尋：`GET /animals/reservable?weight_min&weight_max&age_weeks_min&age_weeks_max&gender`（只回未分配未預約符合者）。

## Phase 3 — 後端：規劃分組查詢
- `GET /reservation-planning`：union（已核准 protocols + planned_experiments），各帶 demand / reserved_count / assigned_count / 動物 rows。

## Phase 4 — 前端：規劃頁
- 新頁（sidebar 入口 + 權限 gate）：分組表 + summary + 新增預定試驗 + 搜尋配對 modal（多選批次）+ 兩段式操作 + 備註 inline + 體重唯讀。RWD 走 `/system_table_chats`。

## 排程
- 一 Phase 一 PR。Phase 0（本 PR，schema）最先，merge 後停下確認 pattern 再 Phase 1。
