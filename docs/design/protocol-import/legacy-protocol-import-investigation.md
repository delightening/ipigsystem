# 舊計劃書匯入（legacy protocol import）— 系統現況調查

> 背景：使用者手上有一批歷年紙本/電子歸檔的動物試驗計劃書（`Downloads\計劃書匯入\PIG-109`、`PIG-110`，民國 109–110 年 / 2020–2021，約 54 個計劃資料夾），要整理後匯入系統。匯入前先盤點系統現況：protocols schema 吃什麼、有沒有「申請須知」概念、既有流程圖。
>
> 調查日期：2026-06-11。本文件只記錄**調查結論**，不含實作。後續改善與流程圖更新另開檔。

---

## (a) protocols schema 與既有 approved-protocol-import 吃什麼

### 結論：系統「已核准計劃匯入」功能成熟，且已支援審查時間軸與院外審查者

**入口**：`POST /api/v1/protocols/import-approved`
- Handler：`backend/src/handlers/protocol/crud.rs:52`
- Service：`backend/src/services/protocol/core.rs:184` `import_approved()`
- 權限：`aup.protocol.import_approved` 或 admin

**輸入型別** `ImportApprovedProtocolRequest`（`backend/src/models/protocol.rs:477`）：

| 欄位 | 必填 | 說明 |
|---|---|---|
| `title` | ✅ | 計劃書標題 |
| `pi_user_id` | 選填 | PI（None = 外部 PI，需在 working_content 提供姓名） |
| `iacuc_no` | ✅ | IACUC 核准編號（例 PIG-110001），會計接點、UNIQUE 防重複匯入 |
| `application_no` | 選填 | 申請編號（例 APIG-109033） |
| `study_director_user_id` | ✅ | 計劃負責人 / SD（內部員工） |
| `working_content` | 選填 | 計劃內容 JSON |
| `start_date` / `end_date` | 選填 | 計劃起迄日 |
| `submitted_at` | 選填 | 原始申請日 |
| `pre_review_at` | 選填 | 執秘行政預審日 |
| `vet_review_at` | 選填 | 獸醫師審查日 |
| `committee_first_review_at` | 選填 | 委員第一次審查日 |
| `revision_required_at` | 選填 | 補件/修訂退回日 |
| `committee_second_review_at` | 選填 | 委員第二次審查日 |
| `approved_at` | 選填 | 原始核准日 |
| `remark` | 選填 | 匯入備註 |

**匯入時自動發生**（同一 transaction）：
1. 建 `protocols`（status=APPROVED、`import_pending=true`、`imported_at=NOW()`）
2. 建 PI 關聯 `user_protocols(PI)`
3. 自動建會計客戶夥伴 `partners(code=iacuc_no, type=customer)`
4. **Backfill 審查時間軸** → `protocol_activities`（逐筆里程碑，remark 標 `[歷史匯入]`，`backend/src/services/protocol/history.rs:217`）
5. Audit `PROTOCOL_IMPORT_APPROVED`

**後續補登工作流**：
- `PUT /api/v1/protocols/{id}` — import_pending 期間可直接編輯 working_content（不走 amendment）
- `POST /api/v1/protocols/{id}/finalize-import` — 建 v1 版本快照 + 清 import_pending 旗標
- `POST /api/v1/protocols/{id}/import-reviews` — **補登審查意見**，支援院外審查者：
  - `ImportReviewComment { reviewer_id?, reviewer_name?, content, reply?, section_no? }`（`backend/src/models/protocol.rs:562`）
  - 含執秘意見、委員一審/二審意見、獸醫評比；**有 reply 欄（申請人回覆）與 section_no（對應計劃書項次）**
- `DELETE /api/v1/protocols/{id}/imported` — admin 刪誤匯（需無下游資料）

### 相關資料表
- `protocols`（主表，`backend/migrations/007_aup_protocol.sql:10`）
- `protocol_versions`（版本快照）
- `protocol_status_history`（狀態歷程）
- `protocol_activities`（時間軸，27 種 activity_type）
- `review_comments`（審查意見，支援 reviewer_name 院外 + section_no + review_stage，`085_import_external_reviewers.sql`）
- `vet_review_assignments`（獸醫審查，支援 vet_name 院外）
- `user_protocols`（PI / CLIENT / CO_EDITOR）
- `amendments`（修正案）

### Protocol status（16 值）
`DRAFT → SUBMITTED → PRE_REVIEW → VET_REVIEW → UNDER_REVIEW →(REVISION_REQUIRED → RESUBMITTED)→ APPROVED / APPROVED_WITH_CONDITIONS → CLOSED / SUSPENDED`；另 `REJECTED / DEFERRED / DELETED`。終態：REJECTED, CLOSED, DELETED。

---

## (b) 系統有沒有「申請須知 / 須知簽名」概念

### 結論：**完全沒有**。這是確定的缺口。

實體歸檔裡每個計劃都有 `2-申請須知簽名檔\`（申請人簽署聲明已閱讀並同意「動物試驗申請須知」）。系統目前無對應結構：

| 檢查項 | 結果 | 位置 |
|---|---|---|
| protocols 表欄位（如 guideline_acknowledged_at） | ✗ 無 | `backend/src/models/protocol.rs` |
| 資料庫 migration | ✗ 無 | `backend/migrations/` |
| 提交驗證（submit 流程檢查須知同意） | ✗ 無 | `backend/src/services/protocol/status.rs:529` |
| 前端提交驗證 | ✗ 無 | `frontend/src/pages/protocols/protocol-edit/validation.ts` |
| 須知文件本身的版本管理 / 上傳 / 顯示 | ✗ 無 | — |

**注意區分（避免誤判已支援）**：
- 電子簽章系統（`signature_bridge` / `043_signature_meaning.sql`：APPROVE/REVIEW/WITNESS/AUTHOR/CONFIRM…）→ 是**審核階段簽章**（委員核准計畫），不是申請人的須知同意。
- `protocol_template_versions` → 是**計畫書範本**版本登記，不是「申請須知」。
- `063_vet_patrol_acknowledgement.sql` → 是**獸醫巡場報告**的「確認收到」，不同模組。

**若要補上「申請須知簽名」需要**：
1. 須知文件版本表（如 `application_notice_versions`）
2. 申請人須知同意/簽名關聯（protocol 級欄位或關聯表）
3. submit 流程前加「須知同意」驗證
4. 須知文件的版本管理與顯示

---

## (c) 現有流程圖與設計文件清單

### Protocol 申請/審查相關設計文件（docs/）

| 檔案 | 用途 | 含流程圖 |
|---|---|---|
| `docs/design/protocol-draft.md` | 完整計畫書範例 + 必填檢核清單（10 個 Section） | — |
| `docs/design/protocol-form-fields-spec.md` | 計畫書填寫表單完整欄位規格（436 行，欄位真相來源） | — |
| `docs/design/protocol-data.json` | 預填表單資料 JSON 範本 | — |
| `docs/design/aup-official-form-AD-04-01-01F.md` | 官方表單 AD-04-01-01F §4 原文（措辭真相來源） | — |
| `docs/design/aup-pdf-output-requirements.md` | AUP 計畫書 PDF 輸出 8 項修復需求 | — |
| `docs/design/aup-print-parity-audit.md` | 表單↔列印 PDF 全表歧異稽核（62 筆） | — |
| `docs/design/aup-print-label-worksheet.md` | 列印標籤措辭決策表（C 類，待使用者逐項決策） | — |
| `docs/design/per-protocol-consumable-cost-report.md` | 計畫耗材成本報表設計 | — |
| `docs/spec/modules/AUP.md` | AUP 提交與審查系統規格 | — |
| `docs/spec/modules/AUP_SYSTEM.md` | AUP 審查系統規格（含狀態機 13 態） | Markdown 狀態圖 |
| `docs/spec/architecture/SYSTEM_RELATIONSHIPS.md` | 全系統模組依賴 | Mermaid graph TD |
| `docs/design/euthanasia-sacrifice-flow.html` | 犧牲/安樂死/byproduct 流程示意圖 | HTML + CSS |

### 流程圖格式慣例
1. **Mermaid**（主要）— `SYSTEM_RELATIONSHIPS.md`、`AUP_SYSTEM.md`
2. **自訂 HTML + CSS**（深色主題 Lane 佈局）— `euthanasia-sacrifice-flow.html`
3. Markdown 表格 + 狀態機文字描述

> 後續若要新增「Protocol 申請審查流程圖」，建議沿用 Mermaid（概念圖）或自訂 HTML（詳細操作流）。

---

## 對「舊計劃書匯入」任務的啟示（待裁定，不在本文件實作）

1. 既有 `import-approved` + `import-reviews` 已能承接：計劃本體、PI/SD、APIG/IACUC 編號、審查里程碑時間軸、委員意見+申請人回覆。**收件證明裡的審查過程（哪位委員說什麼、客戶回覆什麼）可灌入 `import-reviews`**。
2. **缺口**：申請須知簽名（2-申請須知簽名檔）目前無處可放 → 需決定是否補功能，或匯入時暫忽略。
3. 申請表本體有 xlsx / docx / pdf 多版本、多日期（1125→1204→1209…）→ 需定「取哪一版為準」規則（通常取核准前最後一版）。
