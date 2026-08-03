# 動物試驗申請須知 + 須知簽署 — 實作設計

> 緣由：盤點舊計劃書匯入時發現系統缺口（見 [legacy-protocol-import-investigation.md](./legacy-protocol-import-investigation.md) §b、[protocol-application-flow.html](./protocol-application-flow.html) 落差表第 1 列）。實體歸檔每個計劃都有 `2-申請須知簽名檔`，系統卻無對應結構。
>
> 已裁定（2026-06-11）：
> 1. 須知本質 = **全院共用一份 + 版次制**（如「2019年9月修訂版」）
> 2. 申請人簽署 = **手寫電子簽章**（複用現有 `electronic_signatures` / signature_bridge 機制）
> 3. 流程位置：客戶填計劃書 → **簽申請須知** → 送出 → 執秘收件
>
> 本文件為設計，尚未實作。實作前需使用者對本設計 sign-off（schema + API contract = 高風險）。

---

## 1. 資料模型

### 1.1 新表 `application_notices`（須知版本，全院共用）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `version_label` | TEXT | NOT NULL UNIQUE | 版次標籤，例「2019年9月修訂版」 |
| `title` | TEXT | NOT NULL | 須知標題（動物試驗申請須知） |
| `content` | TEXT | NOT NULL | 須知正文（markdown），顯示給申請人閱讀 |
| `attachment_id` | UUID | NULL FK→attachments | 選填：原始 PDF/docx 留底 |
| `effective_from` | DATE | NOT NULL | 生效日 |
| `is_active` | BOOLEAN | NOT NULL DEFAULT false | 當前生效版本（唯一一筆 true） |
| `created_by` | UUID | NOT NULL FK→users | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

- **唯一生效版本**：partial unique index `WHERE is_active` 確保同時只有一筆 active。
- 切換版本走「停用舊 + 啟用新」transaction。

#### 須知版本歷史 seed（使用者提供，2026-06-11）

| 版次 | 生效日 effective_from | 備註 |
|---|---|---|
| A | 2020-12-15 | |
| B | 2023-04-12 | |
| C | 2024-11-26 | |
| D | 2025-09-15 | 當前生效（is_active=true） |

> 109/110 歸檔另見更早的「2018年5月修訂版」「2019年9月修訂版」紙本——若早於版次 A，匯入時對應「pre-A」歷史版本（需使用者確認是否補登為版次表第 0 列）。匯入舊計劃時依其送件日對應當時生效版本。

### 1.2 新表 `protocol_notice_acknowledgements`（申請人簽署紀錄）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | |
| `protocol_id` | UUID | NOT NULL FK→protocols, UNIQUE | 一計劃一筆（重簽 = upsert） |
| `notice_id` | UUID | NOT NULL FK→application_notices | 簽署的是哪個版本 |
| `signer_id` | UUID | NOT NULL FK→users | 簽署人（申請人/PI） |
| `signature_id` | UUID | NULL FK→electronic_signatures | 手寫電子簽章（匯入舊計劃可空，改掛紙本 attachment，見 §5.2） |
| `notice_attachment_id` | UUID | NULL FK→attachments | 匯入舊計劃的紙本須知簽名掃描（方案 A） |
| `acknowledged_at` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

- `UNIQUE(protocol_id)`：每計劃一筆；若須知改版或退回重送需重簽 → 覆蓋（先 invalidate 舊簽章再建新）。

### 1.3 複用 `electronic_signatures`（不改既有 schema）

簽署須知時建立一筆：
- `entity_type = 'protocol_notice_ack'`
- `entity_id = protocol_id`（字串）
- `signer_id = 申請人`
- `signature_type = 'CONFIRM'`、`meaning = 'ACKNOWLEDGE'`（新 enum 值，§5.1 定稿）
- `handwriting_svg` / `stroke_data` / `signature_method = 'handwriting'`
- `content_hash` = hash(protocol_id + notice version_label + signer)

> ✅ 已實作（PR-B step 1，migration 099）：新增 `signature_meaning` enum 值 `ACKNOWLEDGE`。HMAC 不受影響（meaning 不在簽章 HMAC input，見 §5.1）。

---

## 2. API

### 2.1 申請人側
- `GET /api/v1/application-notices/active` — 取當前生效須知（正文 + 版本），填表時顯示。
- `POST /api/v1/protocols/{id}/acknowledge-notice` — 申請人簽署
  - 入：`{ handwriting_svg, stroke_data }`
  - 行為（同 tx）：建 electronic_signature → upsert protocol_notice_acknowledgements（綁當前 active notice）→ audit
  - 守衛：只有該計劃 **PI 或 SD（`study_director_user_id`）** 可簽；計劃須為 DRAFT。（2026-06-12 改：原設計為 PI/CO_EDITOR，見 §5.4）

### 2.2 提交驗證（核心）
- `submit()`（`backend/src/services/protocol/status.rs:529`）DRAFT→SUBMITTED 前新增檢查：
  - 存在 `protocol_notice_acknowledgements` 且 `notice_id` = 當前 active notice 且簽章 `is_valid`
  - 否則 `AppError::BadRequest("尚未簽署最新版動物試驗申請須知")`
- 前端 `validation.ts` 同步加阻擋（送出鈕 disabled + 提示）。
- **此驗證只作用於「正常流程新計劃」**（DRAFT→SUBMITTED，簽章走電子手寫、`signature_id` 必填）。
  **匯入舊計劃不適用**：`import_approved` 直接以 APPROVED 進系統、**繞過 state machine（不呼叫 `submit()`）**，故其 legacy ack 僅為歷史紀錄，不需滿足此檢查（coderabbit review 一致性釐清）。
- `is_valid` 判定：正常流程 = 電子簽章 `is_valid=true`；legacy（匯入）= `signature_id IS NULL` 但 `notice_attachment_id IS NOT NULL`（紙本掃描）視為有效歷史簽署。

### 2.3 Admin 須知版本登記（比照 protocol_template_versions）
- `GET /api/v1/application-notices` — 版本列表
- `POST /api/v1/application-notices` — 新增版本
- `POST /api/v1/application-notices/{id}/activate` — 設為生效（停用其他）
- 權限：`aup.application_notice.manage`（新增）或 admin。

### 2.4 匯入路徑承接（舊計劃）
- `ImportApprovedProtocolRequest` 加選填（**PR-E 才動 DTO**，PR-A schema 已可承接）：`notice_version_label`、`acknowledged_at`、`notice_attachment_id`。
- 匯入舊計劃時：紙本須知簽名檔（PDF）上傳為 attachment，記錄歷史 acknowledgement（無電子簽章；`signature_id` 為 nullable，不偽造電子簽章）。
- **`signer_id` 來源（NOT NULL）**：匯入時填該計劃 `pi_user_id`；外部 PI 無系統帳號時填匯入者本人（與 `import_approved` 既有 `pi_user_id` fallback 一致）。
- `notice_version_label` 依舊計劃送件日對應 §1.1 當時生效版次（找不到對應版次 → 由匯入者於工具選定）。
- ✅ 已定稿（方案 A，§5.2）：signature_id nullable + 紙本掃描 attachment + acknowledged_at，不偽造電子簽章。

---

## 3. 前端
- **填表流程**：protocol-edit 新增「申請須知」段落 → 顯示 active 須知正文 → 手寫簽名板（複用既有簽章元件）→ 簽署後標記已完成。
- **送出阻擋**：未簽 → 送出鈕 disabled + 提示。
- **Admin 頁**：須知版本登記分頁（比照計畫書範本版本登記 #539）。

---

## 4. 實作切分（建議 PR 粒度）

| # | 範圍 | 測試標準 |
|---|---|---|
| PR-A | migration（2 新表 + index）+ models + repository | `cargo test --lib` |
| PR-B | service（acknowledge + submit 驗證）+ handler + 權限 | `cargo test --all-targets`（動 handler/service，需 Postgres） |
| PR-C | Admin 須知版本登記 API + 前端分頁 | tsc + eslint |
| PR-D | 填表簽署前端 + 送出阻擋 | tsc + eslint |
| PR-E | import-approved 承接須知（選填欄位 + 紙本 attachment） | `cargo test --all-targets` |

> 跨 PR 邊界必停（CLAUDE.md 執行紀律）。PR-A 完成先停一次確認 schema。

---

## 5. 設計決策（2026-06-11 已定稿）
1. **`signature_meaning` 新增 `ACKNOWLEDGE`**（不 reuse CONFIRM）。意義最精準、合規報表可按 meaning 撈須知同意簽章。
   - ✅ **HMAC 風險已釐清（2026-06-12，PR-B step 1）**：簽章 HMAC canonical input（`services/signature/mod.rs::signature_canonical_input`）為 `signer_id : content_hash : timestamp : hash_input`，**不含 `meaning`**，故新增 `ACKNOWLEDGE` enum 值**不影響**既有/新簽章 HMAC。原「需處理 HMAC 版本」顧慮為過度保守。實作 = `migration 099 ALTER TYPE ADD VALUE`（比照 024）+ `SignatureMeaning::Acknowledge` variant。
2. **匯入舊計劃須知簽名 = 方案 A**：`protocol_notice_acknowledgements.signature_id` 改 **nullable**；舊計劃只掛紙本掃描 PDF（attachment）+ `acknowledged_at`，不偽造電子簽章。
3. **須知正文 = markdown 正文 + PDF 留底**：`application_notices.content` 存 markdown 供線上閱讀；`attachment_id` 存原始 PDF 正本。
4. **`content` 維持 NOT NULL（2026-06-12 裁定，方案 A）**：匯入舊計劃需登記「當時生效的歷史版次」，但 2018/2019 等舊版可能只有紙本 PDF 掃描、無 markdown 正文。決定**不**改 nullable，而是歷史版次以 `attachment_id` 掛 PDF 正本 + `content` 填佔位文字（如「（紙本版本，詳見附件 PDF）」）。理由：登記簿每筆線上閱讀皆有值、schema 與顯示/送審讀取邏輯最簡單。PR-E 匯入歷史版次時依此填佔位。

> 連帶調整：§1.2 表 `signature_id` 由 NOT NULL 改 **nullable**（容納方案 A 匯入舊簽名）；§1.3 簽章 `meaning` 由 `CONFIRM` 改 **`ACKNOWLEDGE`**（新 enum 值）。

### 5.4 須知簽署人改為 SD / PI（2026-06-12 裁定）

原 §2.1 守衛為「PI / CO_EDITOR 可簽」；改為 **PI 或 SD（`study_director_user_id`）可簽**。連帶：

1. **簽署守衛**（`POST /acknowledge-notice`）：`actor` 須為該計劃 PI 或 SD，否則 `Forbidden`。
2. **送審驗證**（`submit()`，`status.rs:529`）：DRAFT→SUBMITTED 前須存在「對當前 active 須知」的有效 acknowledgement（不變）。
3. **staff 新增計劃的擁有者建模 = 只設 SD，不建 CoEditor**：
   - 建立時 `study_director_user_id = 該 staff`；**不**在 `user_protocols` 寫 CO_EDITOR 列（避免同一人雙關聯、避免對自己發 `COEDITOR_ASSIGNED` 的 audit 噪音）。
   - 為此須**擴充 `access::can_edit_protocol`**：SD 對自己負責的計劃取得編輯權（目前 SD 只在 import_pending 路徑被認 → 擴充到一般 DRAFT 編輯 + 須知簽署）。CoEditor 語意保留給「額外協作者」。
4. **影響範圍**：`services/access.rs::can_edit_protocol` + 新增 `can_sign_notice`（PI 或 SD）；建立計劃流程填入 SD；前端送出阻擋提示文案不變。
