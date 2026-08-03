# SOP 文件簽署 + 訓練考試 — 實作設計

> 緣由：員工教育訓練盤點時確認系統缺口——目前 `training_records` 僅為「訓練完成」的扁平登錄（手動填 user / course_name / completed_at），**無 SOP 內容、無閱讀確認、無簽署綁定、無考試**。本設計補上完整的「SOP 建立 → 員工閱讀 → 電子簽署 → 考試及格 → 訓練完成」閉環。
>
> 已裁定（2026-06-15，使用者 AskUserQuestion）：
> 1. 本任務先**產設計規格**，定案後再開實作 PR（schema + API contract = 高風險）。
> 2. SOP 內容 = **上傳檔案（PDF/Word）** 線上閱讀（不在系統內 rich-text 編寫）。
> 3. 簽署 = **複用既有電子簽章**（`electronic_signatures` + signature_bridge 手寫，`meaning = ACKNOWLEDGE`，21 CFR Part 11）。
> 4. 改版處理 = **改版即失效，全員重新閱讀 → 簽署 → 考試**。
> 5. 考試及格 = **固定 80%**，**無限重試**，自動計分。
> 6. 資料落點 = **新增專用表**，完成時同步寫一筆既有 `training_records`（統一「訓練完成」總覽）。
> 7. 定期重訓 = 每份 SOP 可設定**重訓週期欄位**（預設 3 年，建議區間 3–5 年），到期失效需重做。
>
> 本文件為設計，尚未實作。實作前需使用者對本設計 sign-off。
>
> **既有對照先例**：[application-notice-acknowledgement-design.md](./application-notice-acknowledgement-design.md)（申請須知簽署）——本設計沿用其「版次制 + ACKNOWLEDGE 電子簽章 + 上傳檔案留底」模式，並多加一層**考試引擎**。

---

## 0. 名詞定義

| 名詞 | 定義 |
|---|---|
| **SOP 主檔**（`sop_documents`） | 一份 SOP 的恆定識別（跨版本），如「動物房進出標準作業程序」。 |
| **SOP 版本**（`sop_versions`） | 某 SOP 的某一版內容（上傳的 PDF/Word），有版次標籤與生效日；同一 SOP 同時只有一個生效版本。 |
| **考卷**（`sop_exams`） | 綁定某 SOP 版本的一份考題集（題目存 DB），及格分數預設 80%。 |
| **指派**（`sop_assignments`） | 指定哪些員工需完成此 SOP 訓練。 |
| **簽署**（`sop_acknowledgements`） | 員工對某 SOP 版本的「我已閱讀並理解」電子簽章紀錄。 |
| **考試嘗試**（`sop_exam_attempts`） | 員工的一次作答；無限重試 = 多筆。 |
| **訓練完成**（`sop_training_completions`） | 對某 SOP 版本同時滿足「有效簽署 + 考試及格」的彙整結果；同步寫一筆 `training_records`。 |

---

## 1. 整體流程

```text
[QA/管理者]
  建立 SOP 主檔
      └─► 上傳版本內容（PDF/Word）+ 設生效（停用舊版）
              └─► 建考卷（題目 + 80% 及格）
                      └─► 指派員工
                                                  [員工]
                                                    閱讀 SOP（線上檢視/下載 PDF）
                                                        └─► 電子簽署確認（手寫簽名，meaning=ACKNOWLEDGE）
                                                                └─► 作答考試（無限重試，至 ≥80%）
                                                                        └─► 系統判定「訓練完成」
                                                                              → 寫 sop_training_completions
                                                                              → 同步寫 training_records（統一總覽）
```

**完成判定（核心規則）**：對某員工 + 某 SOP 的**當前生效版本**，當且僅當同時存在
1. `sop_acknowledgements`（簽章 `is_valid = true`），且
2. `sop_exam_attempts` 中至少一筆 `passed = true`

→ 建立 `sop_training_completions`（`completed_at = max(簽署時間, 通過時間)`，`expires_at = completed_at + 重訓週期`），並同步 upsert 一筆 `training_records`。

**順序**：依使用者陳述採「閱讀 → 簽署 → 考試」。簽署語意為「我已閱讀並理解本 SOP」；考試為理解度驗證。若考試未過，簽署仍保留，completion 不成立，待考過即補齊完成。

**簽章作廢時的連動（合規）**：completion 綁定一筆有效簽章；若該 `electronic_signature` 後續被作廢（`is_valid = false`，如管理者撤銷），則對應 `sop_training_completions` **標記失效（保留列、不刪）**，連動的 `training_records` 一併標記失效（`expires_at` 設為作廢時刻或加失效註記）。**不級聯刪除**——21 CFR Part 11 / GLP 要求完整稽核軌跡，失效僅改狀態並留 audit。員工須重新簽署（+ 視需要重考）才能恢復完成。

**並發與冪等**：completion 之建立與「最後一筆通過 attempt 的寫入」**同一 transaction**。`sop_training_completions` 的 `UNIQUE(sop_version_id, user_id)` 為最後防線——並發重複交卷造成的唯一鍵衝突視為**冪等成功**（回傳既有 completion，不報錯）。鎖定策略見 §3.6（attempt_no）與 §3.8。

---

## 2. 改版即失效 + 定期重訓

| 觸發 | 行為 |
|---|---|
| **SOP 改版**（啟用新版本） | completion 綁 `sop_version_id`。新版啟用後，員工對「當前生效版本」無 completion → 系統視為**未完成/已失效**，需對新版重新閱讀 → 簽署 → 考試。舊版 completion 保留為歷史紀錄（不刪）。 |
| **重訓週期到期** | `sop_training_completions.expires_at < now()` → 視為失效，需重做。週期 = `sop_documents.retrain_interval_months`（預設 36，建議 36–60）。 |
| **到期前提醒** | 排程（複用既有 `services/scheduler.rs` + `notifications`）於到期前 N 日通知員工與 QA。**僅檢查當前 active 版本的 completion 到期**（與「completion 只認 active 版本」一致；舊版 completion 之 `expires_at` 不觸發提醒）。查詢收件者 Email 時須過濾 `is_active = true AND deleted_at IS NULL`（不通知已停用/刪除帳號）；待處理項目以 `ORDER BY expires_at` + `LIMIT` 分批，避免一次載入過多。 |

> 改版「失效」採**綁版本的隱式失效**（completion 只認當前 active 版本），非批次 UPDATE 既有列——零資料變更、可追溯、與既有 application-notice「綁 active notice」一致。

---

## 3. 資料模型（新表）

> 對齊既有風格：snake_case、UUID PK、`created_at TIMESTAMPTZ DEFAULT NOW()`、FK 明確。簽章複用 `electronic_signatures`，**不改其 schema**。

### 3.1 `sop_documents`（SOP 主檔，跨版本恆定）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `code` | TEXT | NOT NULL UNIQUE | SOP 編號，如 `SOP-AN-001` |
| `title` | TEXT | NOT NULL | SOP 名稱 |
| `category` | TEXT | NULL | 分類（動物/品保/器材…），供篩選 |
| `retrain_interval_months` | INT | NOT NULL DEFAULT 36 | 重訓週期（月），建議 36–60；NULL 視為僅改版失效（見 §備註） |
| `is_retired` | BOOLEAN | NOT NULL DEFAULT false | 整份 SOP 停用（不再指派/受訓） |
| `created_by` | UUID | NOT NULL FK→users | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

> 備註：若某 SOP 不設定期重訓，可保留 `retrain_interval_months` 但業務上以「永不到期」處理——為避免 NULL 分支複雜化，**預設一律有值（36）**；如未來確需「只改版不定期」，再評估改 nullable（列入 §9 未決）。

### 3.2 `sop_versions`（SOP 版本 = 上傳檔案）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `sop_id` | UUID | NOT NULL FK→sop_documents | |
| `version_label` | TEXT | NOT NULL | 版次標籤，如「2026 第 1 版」 |
| `attachment_id` | UUID | NOT NULL FK→attachments | 上傳的 SOP 正本（PDF/Word） |
| `summary` | TEXT | NULL | 選填重點摘要，列表顯示用 |
| `effective_from` | DATE | NOT NULL | 生效日 |
| `is_active` | BOOLEAN | NOT NULL DEFAULT false | 當前生效版本（每 SOP 唯一一筆 true） |
| `created_by` | UUID | NOT NULL FK→users | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

- `UNIQUE(sop_id, version_label)`。
- **唯一生效版本**：partial unique index `ON sop_versions(sop_id) WHERE is_active`。
- 啟用新版走「停用舊 + 啟用新」transaction（比照 application-notice activate）。transaction 內先以 `SELECT ... FOR UPDATE` 鎖定該 SOP 的版本列，再驗證/切換 `is_active`，避免並發啟用造成 TOCTOU 競態（partial unique index 為最後防線）。

### 3.3 `sop_exams` + `sop_exam_questions`（考卷與題庫）

`sop_exams`：

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `sop_version_id` | UUID | NOT NULL FK→sop_versions, UNIQUE | 一版本一份考卷（改版可換題） |
| `pass_score_pct` | INT | NOT NULL DEFAULT 80 | 及格百分比 |
| `created_by` | UUID | NOT NULL FK→users | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

`sop_exam_questions`：

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `exam_id` | UUID | NOT NULL FK→sop_exams | |
| `seq` | INT | NOT NULL | 題序 |
| `question_type` | TEXT | NOT NULL | `true_false` / `single_choice` |
| `stem` | TEXT | NOT NULL | 題幹 |
| `options` | JSONB | NULL | 選擇題選項陣列（是非題為 NULL） |
| `correct_answer` | JSONB | NOT NULL | 正解（是非：`true`/`false`；單選：選項 key） |
| `points` | INT | NOT NULL DEFAULT 1 | 配分 |

> 題型僅自動可判定者（是非 / 單選）；簡答需人工評分、與「無限重試自動判定」衝突，**不採**。

### 3.4 `sop_assignments`（指派）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `sop_id` | UUID | NOT NULL FK→sop_documents | 指派在主檔層（跨版本） |
| `user_id` | UUID | NOT NULL FK→users | |
| `assigned_by` | UUID | NOT NULL FK→users | |
| `assigned_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

- `UNIQUE(sop_id, user_id)`。

### 3.5 `sop_acknowledgements`（閱讀 + 簽署，比照 protocol_notice_acknowledgements）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `sop_version_id` | UUID | NOT NULL FK→sop_versions | 簽的是哪一版 |
| `user_id` | UUID | NOT NULL FK→users | 簽署人 |
| `signature_id` | UUID | NOT NULL FK→electronic_signatures | 手寫電子簽章 |
| `acknowledged_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

- `UNIQUE(sop_version_id, user_id)`：每人每版一筆；改版需對新版重簽（新列）。
- 複用 `electronic_signatures`：`entity_type = 'sop_acknowledgement'`、`entity_id = sop_version_id`、`signature_type = 'CONFIRM'`、`meaning = 'ACKNOWLEDGE'`、`signature_method = 'handwriting'`、`content_hash = hash(sop_version_id + version_label + signer_id)`。
- **HMAC 不受影響**：簽章 HMAC canonical input 不含 `meaning`（見 application-notice §5.1）。

### 3.6 `sop_exam_attempts`（考試嘗試，無限重試 + 作答歷史）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `exam_id` | UUID | NOT NULL FK→sop_exams | |
| `user_id` | UUID | NOT NULL FK→users | |
| `attempt_no` | INT | NOT NULL | 第幾次（同 user+exam 遞增） |
| `answers` | JSONB | NOT NULL | 作答內容（question_id → 答案） |
| `score_pct` | NUMERIC(5,2) | NOT NULL | 得分百分比 |
| `passed` | BOOLEAN | NOT NULL | `score_pct >= pass_score_pct` |
| `started_at` | TIMESTAMPTZ | NULL | 開始作答 |
| `submitted_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | 交卷 |

- `UNIQUE(exam_id, user_id, attempt_no)`。
- 保留所有嘗試（GLP 可追溯）；嘗試不可竄改（audit log 記錄）。
- **`attempt_no` 並發安全**：同一 `(exam_id, user_id)` 交卷時，於 transaction 內以 `SELECT COALESCE(MAX(attempt_no),0)+1 ... FOR UPDATE`（鎖該 user+exam 既有列）計算下一序號，避免並發兩筆算到同值撞唯一鍵；若仍撞鍵則重試一次。不採全域 sequence（序號須對每人每卷獨立連續）。

### 3.7 `sop_training_completions`（完成彙整）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `sop_version_id` | UUID | NOT NULL FK→sop_versions | |
| `user_id` | UUID | NOT NULL FK→users | |
| `acknowledgement_id` | UUID | NOT NULL FK→sop_acknowledgements | |
| `exam_attempt_id` | UUID | NOT NULL FK→sop_exam_attempts | 通過的那次 |
| `completed_at` | TIMESTAMPTZ | NOT NULL | max(簽署時間, 通過時間) |
| `expires_at` | TIMESTAMPTZ | NULL | completed_at + retrain_interval_months |
| `training_record_id` | UUID | NULL FK→training_records | 同步寫入的總覽紀錄 |

- `UNIQUE(sop_version_id, user_id)`。
- 建立時同步 upsert `training_records`（`course_name = SOP title + 版次`、`completed_at`、`expires_at`、`notes = 'SOP 訓練（自動）'`）。
- **型別轉換注意**：`training_records.completed_at` / `expires_at` 為 `NaiveDate`，本表為 `TIMESTAMPTZ`。同步時須以**系統設定時區**（非 UTC）做 `TIMESTAMPTZ → 當地日期` 轉換，避免 UTC 跨日造成日期少一天；轉換邏輯收斂於單一 helper，勿散落。
- **去重鍵與權威來源**：`sop_training_completions` 為權威，`training_records` 為衍生鏡像。`training_records` 現無唯一約束、且 `course_name`（= SOP title + 版次）含**可變**的 `title`，故**不可**用 `(user_id, course_name)` 當去重鍵。同步以 completion 持有的 `training_record_id` 反向連結做 upsert（首次建立則寫回 `training_record_id`）；`course_name` 僅供顯示，非鍵。
- **交易邊界**：completion 與 `training_records` upsert **同一 transaction**；鏡像寫入失敗 → 整筆 rollback（completion 不獨立存在），確保兩表一致。

### 3.8 FK 刪除政策、保留與邊界規則

- **資料保留（GLP 不級聯刪除）**：`sop_assignments` / `sop_acknowledgements` / `sop_exam_attempts` / `sop_training_completions` 對 `users` 的 FK 採 **`ON DELETE RESTRICT`/保留**，不隨使用者刪除而級聯刪。本系統使用者採**軟刪除**（`deleted_at`），訓練與簽署紀錄須長期保存（GLP 一般要求 5–10 年）以維稽核軌跡。
- **`is_retired = true`（整份 SOP 停用）效果**：(a) **不可**再新增指派；(b) 既有 completion **不追溯失效**（保留歷史）；(c) 前端列表標示「已停用」並隱藏於待辦；(d) 不再觸發重訓提醒。
- **啟用版本須先有考卷（guard）**：`UNIQUE(sop_version_id)` 只保證至多一份考卷、不保證存在。**啟用版本前 service 層須驗證該版已有 `sop_exams` 且題目數 ≥1**，否則拒絕（`AppError::BadRequest`），避免員工「可簽署但無考卷可考、永遠無法完成」。

---

## 4. 角色與權限

> 沿用既有 `training.*` 命名風格，新增 `sop.*` 權限（種子於 migration，比照 `startup/permissions.rs`）。

| 權限 | 授予角色（建議） | 能力 |
|---|---|---|
| `sop.manage` | QA / QAU / 系統管理員 | 建立/編輯 SOP 主檔、上傳版本、啟用版本、建題、指派 |
| `sop.view_all` | QA / QAU / 主管 | 查看**所有人**的 SOP 訓練狀態總覽 |
| （受訓行為，免特別權限） | 所有登入員工 | 對**被指派給自己**的 SOP：閱讀、簽署、考試、查自己紀錄 |

- 員工只能操作被指派給自己的 SOP（守衛：`sop_assignments` 存在該 user）。
- 既有 `training.view / training.manage` 維持用於 `training_records` 總覽。

---

## 5. API 草案

### 5.1 管理側（`sop.manage`）
- `POST /api/v1/sops` — 建 SOP 主檔（code/title/category/retrain_interval_months）
- `GET /api/v1/sops` — SOP 列表
- `POST /api/v1/sops/{id}/versions` — 上傳版本（multipart：檔案 → attachment + version_label + effective_from）
- `POST /api/v1/sops/{id}/versions/{vid}/activate` — 啟用版本（停用舊，transaction）
- `PUT /api/v1/sops/versions/{vid}/exam` — 建/改考卷（pass_score_pct + 題目陣列）
- `POST /api/v1/sops/{id}/assignments` — 指派員工（user_ids[]）
- `GET /api/v1/sops/{id}/status` — 該 SOP 全員完成狀態（`sop.view_all`）

### 5.2 員工側
- `GET /api/v1/sops/assigned` — 我被指派的 SOP（含狀態：待閱讀/待簽署/待考試/已完成/已過期）
- `GET /api/v1/sops/versions/{vid}` — 取版本內容（含 attachment 下載連結）
- `POST /api/v1/sops/versions/{vid}/acknowledge` — 簽署
  - 入：`{ handwriting_svg, stroke_data }`
  - 行為（**同一 tx**，比照 `protocol_notice_acknowledgements` 編排）：`INSERT electronic_signatures`（`entity_type='sop_acknowledgement'`、`entity_id=vid`、`meaning='ACKNOWLEDGE'`）取得 `signature_id` → upsert `sop_acknowledgements`（綁該 `signature_id`）→ 嘗試判定 completion → audit。FK 僅保證 `signature_id` 存在；**service 須額外驗證**該簽章的 `entity_type='sop_acknowledgement'` 且 `entity_id=vid`（防錯掛他單簽章）。
  - 守衛：該 SOP 已指派給本人，且 `vid` 為當前 active 版本
  - 回：`{ acknowledged_at, signer_id, signature_id }`
- `GET /api/v1/sops/versions/{vid}/exam` — 取題（**不含正解**）。回：`{ exam_id, pass_score_pct, questions: [{ id, seq, question_type, stem, options }] }`
- `POST /api/v1/sops/versions/{vid}/exam/attempts` — 交卷
  - 入：`{ answers }`（`question_id → 答案`）
  - **提交驗證（計分前）**：所有 `question_id` 須屬該 exam 當前題目；每題答案格式須符其 `question_type`（`true_false` 為布林、`single_choice` 為合法選項 key）。任一不符 → `400 BadRequest`（不寫 attempt，保稽核乾淨）。
  - 行為（**同一 tx**）：後端計分 → 寫 `sop_exam_attempts`（attempt_no 見 §3.6 鎖定）→ 若 `passed` 且已簽署 → 建 completion + 同步 training_records → audit
  - 回：`{ attempt_no, score_pct, passed, pass_score_pct, submitted_at }`（未過可再呼叫，無次數限制）
- **錯誤碼約定**：`403` 未指派 / 無權；`404` SOP 或版本不存在；`409` 簽署對非 active 版本、或重複完成（冪等回既有 completion）；`400` 提交驗證失敗。

> 計分一律在**後端**（不信任前端），正解不下發到瀏覽器。

---

## 6. 前端草案

- **員工「我的訓練」頁**：SOP 卡片列表（待辦 / 已完成 / 已過期分頁）→ 點入：
  1. 閱讀區（PDF 內嵌檢視 / 下載）
  2. 手寫簽名板（**複用既有簽章元件**）→ 簽署
  3. 考試作答（是非 / 單選）→ 交卷顯示分數；未過「再考一次」
- **QA/Admin SOP 管理頁**：版本登記（比照計畫書範本版本登記）、題庫編輯、指派、全員狀態儀表。
- 遵循 `DESIGN.md`：CSS variable token、復用 `components/ui/`；新增表格前先走 `/system_table_chats`。

---

## 7. 合規對應

| 要求 | 本設計對應 |
|---|---|
| GLP 人員訓練紀錄可追溯 | `sop_training_completions` + `training_records` + 全程 audit |
| 21 CFR Part 11 電子簽章 | 複用 `electronic_signatures`（手寫 + HMAC 稽核鏈），`meaning = ACKNOWLEDGE` |
| 改版控管 | 版次制 + 唯一生效版本 + 改版即失效全員重做 |
| 訓練有效性驗證 | 考試 80% 及格（自動計分、無限重試、作答歷史留存） |

**稽核事件（PR-A 設計 schema 時即預留 hook，複用既有 audit 機制）**：須記錄 SOP 建立/編輯、版本上傳/啟用、考卷建立/修改、指派/取消指派、簽署、簽章作廢、考試交卷（每次 attempt）、completion 建立/失效。每筆記錄 actor、動作、資源 ID、前後狀態、時間（沿用既有 `user_activity_logs` 欄位與 HMAC 鏈）。保留期比照訓練紀錄（GLP 5–10 年）。檢視權限：`sop.view_all` + 既有稽核檢視角色。

---

## 8. 實作切分（建議 PR 粒度，跨 PR 邊界必停）

| # | 範圍 | 測試標準 |
|---|---|---|
| PR-A | migration（7 新表 + index + `sop.*` 權限種子）+ models + repository | `cargo test --lib` |
| PR-B | SOP 主檔/版本/啟用 service + handler + 權限 | `cargo test --all-targets`（需 Postgres） |
| PR-C | 考卷/題庫 + 考試 attempt 計分（後端計分）service + handler | `cargo test --all-targets` |
| PR-D | 簽署 acknowledge（複用簽章）+ completion 判定 + 同步 training_records | `cargo test --all-targets` |
| PR-E | 指派 + 全員狀態總覽 API | `cargo test --all-targets` |
| PR-F | 前端員工受訓流程（閱讀 / 簽署 / 考試） | tsc + eslint |
| PR-G | 前端 QA/Admin 管理頁（版本/題庫/指派/儀表） | tsc + eslint |
| PR-H | 改版失效 + 定期重訓到期排程提醒（scheduler + notifications） | `cargo test --all-targets` |

> PR-A 完成先停一次確認 schema（CLAUDE.md 執行紀律：schema = 高風險）。

---

## 9. 未決 / 待確認

1. **重訓週期具體值**：使用者傾向「3–5 年」（含問號）。本設計設為 per-SOP 欄位、預設 36 月。若要全院統一固定值，請指定。
2. **`retrain_interval_months` 是否允許「永不到期」**：目前一律有值（預設 36）。若需「只改版失效、不定期重訓」選項，需改 nullable + 完成判定分支。
3. **題庫建立者 / 抽題策略**：目前為每版固定全題作答（不隨機抽題）。若題庫大需「隨機抽 N 題」，再擴充 `sop_exams.draw_count`。
4. **考試前是否強制閱讀達成條件**（如捲動到底 / 最短停留）：目前僅以「已簽署」作為閱讀證明，未強制閱讀行為偵測。
5. **指派粒度**：目前為逐人指派（`sop_assignments`）。若需「依角色/部門批次指派」，可加指派來源欄位或群組指派。

---

## 10. 設計決策（2026-06-15 已定稿）

1. **新增專用表，不塞既有 `training_records`**：training_records 為扁平登錄，放不下版本/簽署/作答/重試歷史；新表結構清楚、可追溯，完成時再同步一筆 training_records 維持統一總覽。
2. **簽署複用既有電子簽章**（`meaning = ACKNOWLEDGE`，已於 migration 099 存在）：合規、有 HMAC 稽核鏈，且 HMAC 不含 meaning，無相容性風險。
3. **SOP 內容 = 上傳檔案**：以 `attachments` 留底（PDF/Word），版本表掛 `attachment_id`；不做系統內 rich-text 編輯（降低範圍與維護成本）。
4. **改版即失效採綁版本隱式失效**：completion 只認當前 active 版本，零批次資料變更、可追溯。
5. **考試後端計分、正解不下發**：防作弊；80% 固定及格、無限重試、保留全部 attempt。
