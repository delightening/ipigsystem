# 補登歷史變更申請（Amendment Import Backfill）施工計畫

> 立案：2026-06-01　／　定位：approved-protocol-import（P1–P5 / #533–#537）家族延伸
> 受眾：專案負責人 + 維護者（半技術）

---

## 1. 背景與目標

補登匯入的舊計劃（`import_approved`）目前進系統後是 `status=APPROVED`，可以正常開**新的** live 變更申請。但舊計劃在紙本世界裡**以前就已經核准過的歷史變更**（變更第 1 號、第 2 號…），系統沒有地方補登。

**目標**：在計劃詳情頁的「變更」分頁，讓**計劃負責人（Study Director）**把歷史變更申請補登進系統，平行 P1–P5 的補登 pattern——跳過 live 審查、回填原始日期、支援院外審查委員、不產生 live 電子簽章、直接落在終態 `EFFECTIVE`。後續系統開的新 live 變更自動接續編號。

### 成功標準（acceptance）

- [ ] SD 在 imported 計劃的變更分頁，能新增一筆歷史變更（標題、內容、MAJOR/MINOR、原始送件/分類/核准/生效日期）
- [ ] 能補登該歷史變更的審查文件（委員意見 + 決定，支援院外委員填姓名）
- [ ] 補登完成後該變更落 `EFFECTIVE`，`effective_from` = 原始生效日，**無** live 電子簽章，帶「補登/紙本歷史」標記
- [ ] 編號自動接續：歷史變更佔 R01、R02…，之後 live 新變更自動從 R0(N+1) 起
- [ ] 全程 audit log（HMAC chain），actor = SD/admin
- [ ] 整合測試覆蓋：建立 → 補登審查 → 落 EFFECTIVE → 編號接續 → 權限拒絕（非 SD/非 imported）

---

## 2. 範圍 / 非範圍

### 範圍
- amendments 表加歷史標記欄 + migration
- `amendment_review_assignments` 支援院外委員（nullable reviewer_id + name）
- 後端：新增 backfill service/handler 一組（平行 `import_approved` / `record_import_reviews`）
- 前端：AmendmentsTab 加「補登歷史變更」入口（SD/admin only）+ 補登表單

### 非範圍（明確排除）
- 不改正常 live 變更流程（DRAFT→提交→分類→審查→核准→生效）任何既有行為
- 不補登變更的「附件」檔案（沿用既有 attachment 上傳，非本計畫）
- 不做歷史變更的「事後編輯狀態機」——採 draft→finalize 一次定稿（見 §6 workflow）
- 不動 historical-records（PR #514/#515）archive 表——兩者無關

---

## 3. 已定案決策（使用者已拍板）

| 項目 | 決定 |
|---|---|
| 補登深度 | 完整：平行 P2，連分類 + 委員審查意見/決定都能補登 |
| 編號 | 直接照紙本填 R01/R02（格式本就一致），**不加原始編號欄**；後續 live 自動接 R0(N+1) |
| 終態 | 落 `EFFECTIVE`，`effective_from` 回填原始生效日 |
| 簽章 | 不產生 live 電子簽章，標記「補登/紙本歷史」 |
| 權限 | **計劃負責人（Study Director, `study_director_user_id`）+ admin** |
| 入口位置 | 計劃詳情頁的「變更」分頁（`AmendmentsTab.tsx`） |

---

## 4. 決策（已裁定 2026-06-01，均選 A，已落地 PR #544）

### D1. 補登的 gate：限「imported 計劃」還是「任何 APPROVED 計劃」？

| 選項 | 做法 | 代價 |
|---|---|---|
| **A（推薦）限 imported 計劃** | protocols 加永久標記 `imported_at`（`import_approved` 時寫入）；既有 prod imports 用 audit log（`PROTOCOL_IMPORT_APPROVED` 事件）回填 | 多一個欄位 + 一段資料回填 SQL；語意最乾淨（只有紙本來源計劃能補歷史變更） |
| B 任何 APPROVED 計劃 | 不加標記，純靠 SD/admin 權限 + audit + `is_historical` 守住 | 簡單，但理論上 SD 可在「系統內正常計劃」上補假歷史變更（風險低：SD 可信 + 全程 audit） |

> 我推薦 **A**。需要你裁定，因為它牽涉 schema + 對既有 prod 資料做一次回填。

### D2. 補登 workflow 形狀：draft→finalize 兩段 vs 一次到位

| 選項 | 做法 | 代價 |
|---|---|---|
| **A（推薦）draft→finalize** | 建立時 `status=DRAFT, is_historical=true`（可編輯、可重補審查）→ SD 確認 → finalize 直接 DRAFT→EFFECTIVE（專屬路徑，繞過泛型 transition guard，比照 `mark_effective`） | 多一個 finalize 端點；但與 P1（import→finalize）一致、避免刪終態紀錄 |
| B 一次到位 | 單一端點一個 tx 建立 + 補審查 + 落 EFFECTIVE；改錯只能刪除重來 | 端點少；但刪 EFFECTIVE 歷史紀錄不漂亮（即使 historical 無簽章） |

> 我推薦 **A**（與既有 import_pending→finalize pattern 一致，codebase 慣例）。

> **Decision (2026-06-01)**：D1 = A（限 imported 計劃；`imported_at` 於 `import_approved`
> 寫入 + `PROTOCOL_IMPORT_APPROVED` audit log 回填）；D2 = A（draft→finalize，create 為
> `status=DRAFT, is_historical=true`，finalize 走 DRAFT→EFFECTIVE 專屬路徑）。已落地。

---

## 5. 資料模型 / Migration

### 087_amendment_import_backfill.sql

```sql
-- amendments：歷史補登標記
ALTER TABLE amendments
  ADD COLUMN is_historical BOOLEAN NOT NULL DEFAULT false;
-- is_historical=true：補登歷史變更。語意：
--   * 跳過 live 審查，可由 DRAFT 直接 finalize 到 EFFECTIVE
--   * approved_signature_id / rejected_signature_id 維持 NULL（紙本核准，無 live 簽章）
--   * 前端顯示「補登/紙本歷史」badge
COMMENT ON COLUMN amendments.is_historical IS '補登歷史變更（紙本核准回溯），跳過 live 審查與簽章';

-- amendment 的原始日期：submitted_at / classified_at / effective_from 既有欄位直接回填即可，不新增。

-- protocols：永久 imported 標記（D1-A）
ALTER TABLE protocols
  ADD COLUMN imported_at TIMESTAMPTZ NULL;
COMMENT ON COLUMN protocols.imported_at IS 'import_approved 建立時間；非 NULL = 補登匯入計劃（永久標記，與暫態 import_pending 區分）';

-- 既有 prod imports 回填 imported_at（取最早一筆 PROTOCOL_IMPORT_APPROVED audit 事件時間）
UPDATE protocols p SET imported_at = sub.ts
FROM (
  SELECT (entity->>'id')::uuid AS protocol_id, MIN(created_at) AS ts
  FROM user_activity_logs
  WHERE event_type = 'PROTOCOL_IMPORT_APPROVED'
  GROUP BY entity->>'id'
) sub
WHERE p.id = sub.protocol_id AND p.imported_at IS NULL;
-- 註：audit entity JSON 欄位實際結構動工時以 services/audit.rs AuditEntity 為準調整。
```

### 088_amendment_external_reviewers.sql（比照 085）

```sql
-- 院外歷史審查委員：reviewer_id 改 nullable + 加 reviewer_name
ALTER TABLE amendment_review_assignments
  ALTER COLUMN reviewer_id DROP NOT NULL,
  ADD COLUMN reviewer_name TEXT NULL;

ALTER TABLE amendment_review_assignments
  ADD CONSTRAINT chk_amendment_reviewer_identity
  CHECK (reviewer_id IS NOT NULL OR NULLIF(BTRIM(reviewer_name), '') IS NOT NULL);

-- 注意：既有 UNIQUE(amendment_id, reviewer_id) 在 reviewer_id NULL 時不阻擋重複院外同名委員，
-- 與 085 review_comments 處理一致（補登為全量取代語意，重複由 service 控制）。
```

> ⚠️ 動工時先確認 `imported_at` 回填 SQL 對得上 `user_activity_logs` 的實際 JSON 結構（entity 欄位格式）。

---

## 6. 後端 service / handler

### 檔案佈局（平行 protocol import）

```
services/amendment/
  import_backfill.rs   ← 新增：create_historical / finalize_historical / record_historical_reviews
models/amendment.rs    ← 新增 request DTO（平行 ImportReviewsRequest 家族）
handlers/amendment.rs  ← 新增 3 個 handler
routes/protocol.rs     ← 註冊 3 條路由
```

### Service 函式（`AmendmentService`）

| 函式 | 對應 protocol import | 行為 |
|---|---|---|
| `create_historical(pool, actor, req)` | `import_approved` | 驗 SD/admin + 計劃 imported（D1）→ 產生編號（MAX+1）→ INSERT `status=DRAFT, is_historical=true, amendment_type=MAJOR/MINOR`，回填 submitted_at/classified_at → status_history → audit |
| `record_historical_reviews(pool, actor, amendment_id, req)` | `record_import_reviews` | FOR UPDATE 鎖 amendment + 驗 is_historical + DRAFT → 全量取代 `amendment_review_assignments`（DELETE 再 INSERT，支援院外 name fallback）→ audit |
| `finalize_historical(pool, actor, amendment_id, req)` | `finalize_import` | FOR UPDATE + 驗 is_historical + DRAFT → DRAFT→EFFECTIVE（專屬路徑，繞泛型 guard）→ 寫 effective_from → version snapshot → status_history → audit `AMENDMENT_IMPORT_FINALIZED` |

### 關鍵守衛（沿用既有合規 pattern）
- Service 層拒絕 `ActorContext::Anonymous`（CLAUDE.md §ActorContext 規範 2）
- 權限：`study_director_user_id == actor_user_id || is_admin`，否則 `AppError::Forbidden`（中文訊息，對齊 amendment 模組 i18n）
- gate：protocol `imported_at IS NOT NULL`（D1-A），否則 `BusinessRule`
- `is_historical` 變更不得進入泛型 `change_status` / `record_decision` / `mark_effective` 路徑；live 變更（`is_historical=false`）不得進 backfill 路徑——雙向互斥檢查
- 終態 EFFECTIVE 後不可再 backfill 審查（DRAFT-only gate 自然擋住）
- 全程 `log_activity_tx`（HMAC chain），actor = User(SD/admin)

### 編號（§3 已定案，落地細節）
- 沿用 `generate_amendment_no`（`COALESCE(MAX(revision_number),0)+1`），backfill 不需特例
- imported 計劃剛進系統時無 live 變更 → backfill 依序建立得 R01、R02…；之後 live 自動 R0(N+1)
- 邊界：若已有 live 變更才回頭 backfill，會排到後面號（順序顛倒）。**前端提示「建議先補登歷史變更再開新變更」**；不做硬性阻擋（避免過度設計）

---

## 7. 前端

### 入口（`components/protocol/AmendmentsTab.tsx`）
- 計劃 `imported_at != null` 且使用者為 SD/admin → 顯示「補登歷史變更」按鈕（與既有「建立變更」並列，視覺區分：補登用次要樣式 + 「補登」字樣）
- 列表中 `is_historical=true` 的列加 badge「補登／紙本歷史」（沿用既有 status badge 樣式，token 化色彩，不硬編色）

### 補登表單（新元件 `HistoricalAmendmentDialog.tsx`）
- 第一段：標題、變更內容、MAJOR/MINOR、原始送件日 / 分類日 / 生效日
- 第二段（平行 P2）：委員審查意見列表（每位委員：系統帳號 or 院外姓名、決定 APPROVE/REJECT/REVISION、意見、決定日）
- 送出 → create_historical → record_historical_reviews → finalize_historical（前端串三步，或後端提供 one-shot wrapper——動工時依 D2 定）

### API（`lib/api/protocol.ts` 或 amendment 區）
- `createHistoricalAmendment` / `recordHistoricalAmendmentReviews` / `finalizeHistoricalAmendment`
- 沿用 TanStack Query mutation + `getApiErrorMessage`（禁 Zod，R58）

### 型別（`types/amendment.ts`）
- `Amendment` 加 `is_historical: boolean`
- 新增 request 型別（hand-rolled，不引 Zod）

---

## 8. 權限與合規對齊

| 面向 | 處理 |
|---|---|
| 21 CFR §11 簽章 | 歷史變更為紙本核准，**不偽造 live 電子簽章**；approved/rejected_signature_id 留 NULL，audit log 記錄「誰在何時補登」作為系統內非否認紀錄。與 import_approved 不產生 live 核准簽章一致 |
| HMAC audit chain | backfill 三動作皆走 `log_activity_tx`；actor = User(SD/admin)，非 Anonymous |
| 狀態機完整性 | DRAFT→EFFECTIVE 僅限 `is_historical=true` 的專屬 finalize 路徑；泛型 guard（CSO #3 終態不可退）不受影響 |
| i18n | 所有 audit / error 訊息用中文（對齊 amendment 模組既有規範，memory: vet_patrol / amendment 中文化） |

---

## 9. 測試策略（handler 層 → 須整合測試全綠）

> 本 PR 動到 handlers/routes → 依 CLAUDE.md「動 handler 層必 `cargo test --all-targets` 全綠（需本地 Postgres）」

- 整合測試（`tests/`）：
  - SD 對 imported 計劃 create_historical → 200 + status=DRAFT + is_historical
  - record_historical_reviews 院外委員（無帳號填姓名）→ 寫入成功；缺 id+name → 400
  - finalize_historical → status=EFFECTIVE + effective_from = 回填日 + signature_id 仍 NULL
  - 編號接續：backfill R01/R02 後開 live 變更 → R03
  - 權限：非 SD 非 admin → 403；非 imported 計劃 → 422/BusinessRule
  - 互斥：對 live 變更呼叫 backfill 端點 → 拒絕；對 historical 呼叫 live decision → 拒絕
- 前端：`tsc` + `eslint` 零警告（memory: 不跑 prod build / vite dev）

---

## 10. PR 切分（每 PR 跨邊界必停，依 CLAUDE.md 執行紀律）

| PR | 內容 | 測試門檻 |
|---|---|---|
| **P6-1** | migration 087 + 088 + models DTO + `imported_at` 寫入 `import_approved` | `cargo check --tests` 綠 |
| **P6-2** | service `create_historical` + `finalize_historical` + handler/route + 整合測試 | `cargo test --all-targets` 全綠 |
| **P6-3** | service `record_historical_reviews`（院外委員）+ 整合測試 | `cargo test --all-targets` 全綠 |
| **P6-4** | 前端 AmendmentsTab 入口 + HistoricalAmendmentDialog + API + 型別 | `tsc` + `eslint` 綠 |
| **P6-5** | 文件（PROGRESS §9 / TODO 新 R 條目 / amendment-sop.md 補歷史補登段） | `cargo check` 綠 |

> 每個 PR 完成測試 + commit 後**停**，不自動 push / 不自動開下一個。

---

## 11. 風險

| 風險 | 緩解 |
|---|---|
| `imported_at` 回填 SQL 對不上 audit JSON 結構 | 動工前先讀 `services/audit.rs` AuditEntity 實際序列化；回填失敗不致命（既有 imports 暫無法補登，可手動補 imported_at） |
| 編號順序顛倒（先開 live 才 backfill） | 前端軟提示，不硬擋；極少發生（imported 計劃剛進系統通常無 live 變更） |
| DRAFT→EFFECTIVE 繞 guard 被誤用到 live 變更 | service 強制 `is_historical=true` 才走此路徑；雙向互斥測試覆蓋 |
| 院外委員 UNIQUE 失效（reviewer_id NULL） | 與 085 一致，全量取代語意，service 控重複 |

---

## 12. 待你確認

1. **D1**：補登 gate 限 imported 計劃（推薦 A）還是任何 APPROVED？
2. **D2**：workflow 採 draft→finalize 兩段（推薦 A）還是一次到位？
3. 沒意見 → 我照兩個 A 開工，從 **P6-1（migration + models）** 起，做完停。
