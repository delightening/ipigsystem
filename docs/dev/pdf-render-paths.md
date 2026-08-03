# PDF 匯出端點 → 渲染路徑總覽

> ⚠️ **過時文件（2026-05-30 標註）**：本文件描述的是已下線的 `pdf-service`
> （gotenberg + Word/Excel COM daemon）架構。**Word/Excel COM daemon（`services/word-convert/`）
> 已移除，不再使用**；現行唯一 PDF 服務為 `services/print-pdf`（FastAPI + WeasyPrint，
> HTML→PDF，無任何 daemon 依賴）。下方所有 daemon / `WORD_CONVERT_URL` / `EXCEL_CONVERT_URL` /
> 9100/9101 port / daemon-only 503 與 `/daemon-health` pre-check 內容**僅為歷史記錄**，
> 不反映現況。最新渲染路徑見 `services/print-pdf/README.md`。
>
> 最後更新：2026-05-13（R45 final — GLP daemon-only / 非 GLP HTML 收斂）
> 範圍：pdf-service 全部 `/render-*` 端點 + 對應 backend handler + fail-safe 層覆蓋狀況

## R45 final 路由原則

```text
GLP 文件（5 個）— Word/Excel COM daemon ONLY，失敗 → HTTP 503
  ├─ aup_protocol / review_reply / review_result / vet_patrol_report (docx)
  │    → Word COM daemon (host:9100) → PDF
  └─ vet_patrol_template (xlsx)
       → Excel COM daemon (host:9101) → PDF

非 GLP 文件（5 個）— HTML/Chromium 主路徑
  ├─ warehouse / audit_log / blood_test / medical_record / surgery
  │    → Jinja2 HTML → Gotenberg Chromium → PDF
  └─ project_medical（批次 zip）
       → 並行 N × HTML → Chromium tab pool (concurrent=4)
       → pypdf merge → PDF

fallback 規則
  ├─ GLP：fail-fast，HTTP 503 + 前端 daemon-health pre-check + email admin
  └─ 非 GLP：HTML 失敗 → docx (docxtpl) → Word daemon → Gotenberg LibreOffice (多層)
```

## Fail-safe 三層說明

| 層 | 內容 | 目的 |
|---|---|---|
| **L1** | daemon 回 404 / 非 PDF / 5xx / 連線錯誤 → 自動 fallback Gotenberg | 使用者永遠拿得到檔；401/403 仍 fail-loud 避免遮罩 auth 設定錯誤 |
| **L2** | response 帶 `X-PDF-Renderer` header（`excel_daemon` / `word_daemon` / `gotenberg_fallback` / `gotenberg_only`） | 讓 backend / 前端知道實際走哪條路 |
| **L3** | 前端讀 header，`gotenberg_fallback` 時 toast「使用備援渲染器，格式可能略有差異」 | 降級時使用者知情，不被無聲品質下降 |

## 端點 × 路由矩陣（R45 final）

| # | pdf-service 端點 | 模板 | 分類 | format=pdf 路徑 | format=docx/xlsx | Fallback |
|---|---|---|:-:|---|---|---|
| 1 | `/render/{doc_type}` | (legacy) | n/a | (無 caller，待刪) | n/a | n/a |
| 2 | `/render-docx/{type}` | 多 | wrapper | 走對應業務端點 | docxtpl 直接回 | n/a |
| 3 | `/render-xlsx/{type}` | 多 | wrapper | 同上 | xlsx 直接回 | n/a |
| 4 | `/render-aup/from-working-content` | aup_protocol.docx | 🔒 **GLP** | Word daemon ONLY → fail-fast 503 | docxtpl | **無** |
| 5 | `/render-review-reply/from-review-data` | review_reply.docx | 🔒 **GLP** | Word daemon ONLY | docxtpl | **無** |
| 6 | `/render-review-result/from-review-data` | review_result.docx | 🔒 **GLP** | Word daemon ONLY | docxtpl | **無** |
| 7 | `/render-vet-patrol-report/from-report-data` | vet_patrol.docx | 🔒 **GLP** | Word daemon ONLY | docxtpl | **無** |
| 8 | `/render-vet-patrol/from-animals` | vet_patrol_template.xlsx | 🔒 **GLP** | Excel daemon ONLY | xlsx 直接 | **無** |
| 9 | `/render-warehouse/from-report-data` | warehouse.docx | 非 GLP | **HTML/Chromium** | docxtpl | HTML 失敗 → docx → Word → Gotenberg |
| 10 | `/render-audit-log/from-export-data` | audit_log.docx | 非 GLP | **HTML/Chromium** | docxtpl | 同上 |
| 11 | `/render-blood-test/from-blood-test-data` | blood_test.docx | 非 GLP | **HTML/Chromium** | docxtpl | 同上 |
| 12 | `/render-medical-record/from-animal-data` | medical_record.docx | 非 GLP | **HTML/Chromium** | docxtpl | 同上 |
| 13 | `/render-project-medical/from-project-data` | medical_record.docx (zip)| 非 GLP | **並行 HTML/Chromium** + pypdf merge | n/a | 每隻獨立 fallback |
| 14 | `/render-surgery/from-surgery-data` | surgery.docx | 非 GLP | **HTML/Chromium** | docxtpl | 同上 |
| 15 | `/daemon-health` | n/a | infra | 探測 word + excel + gotenberg 狀態 | n/a | 回 200/503 |

## GLP fail-fast 行為（R45 final）

```
GLP 匯出 → format=pdf
   ↓
Word/Excel daemon
   ├─ 200 OK → PDF（X-PDF-Renderer: word_daemon | excel_daemon）
   └─ daemon 失敗 → HTTP 503
       └─ 前端：「PDF daemon 服務未上線，已自動通知管理員」
       └─ Backend：outbox enqueue email channel → admin（30 min rate-limit）
```

**前端保護**：4 個 GLP 匯出按鈕進場 ping `/api/daemon-health`（TanStack Query 30s cache），未上線時 disable + tooltip。`useDaemonHealth` hook 統一管理。

## 非 GLP HTML 性能（R45 Phase 4 實測）

| 場景 | 之前（daemon sequential）| 現在（HTML parallel）| 提升 |
|---|---:|---:|---:|
| 單隻 medical_record | ~6s | ~1s | **6×** |
| 8 隻 zip 批次 | ~50s | **7.5s** | **6.7×** |
| 30 隻 zip 批次 | ~3 分鐘（估計）| ~25-30s（推算）| **6-7×** |

並行控制：`asyncio.Semaphore(4)` — Chromium tab pool 不爆 + 記憶體穩定。

## 字體支援（Gotenberg image, ipig-gotenberg-cjk:8）

| 字體 | 用途 | 授權狀態 |
|---|---|---|
| 標楷體 (kaiu.ttf) | 中文標題 + body | Windows 隨附 |
| Times New Roman (×4 style) | docx default English body | Windows 隨附 |
| Arial (×4 style) | xlsx 數字 + 部分標題 | Windows 隨附 |
| Segoe UI Symbol | ☑ ☐ ☐ etc. | Windows 隨附 |
| Noto CJK + Arphic uMing/uKai + Liberation | fallback | 開源 |

→ daemon 路徑與 Gotenberg fallback 路徑使用同字體集，視覺差異 < 5%。

## pdf-service ↔ backend handler 對照

| pdf-service 端點 | backend handler | 業務功能 |
|---|---|---|
| `/render-aup/from-working-content` | `protocol/pdf_export.rs:164` | AUP 計畫書 PDF |
| `/render-project-medical/from-project-data` | `animal/pdf_export.rs:223`, `import_export.rs:128` | 全試驗豬病歷 zip 匯出 |
| `/render-medical-record/from-animal-data` | `animal/pdf_export.rs:84`, `import_export.rs:76` | 單豬病歷表 PDF |
| `/render-review-reply/from-review-data` | `protocol/pdf_export.rs:108` | 審查意見回覆表 |
| `/render-review-result/from-review-data` | `protocol/pdf_export.rs:69` | 審核結果 PDF |
| `/render-surgery/from-surgery-data` | `animal/pdf_export.rs:157` | 手術紀錄表 |
| `/render-blood-test/from-blood-test-data` | `animal/pdf_export.rs:529` | 血液檢查紀錄 |
| `/render-audit-log/from-export-data` | `audit.rs:122` | 操作日誌 PDF |
| `/render-warehouse/from-report-data` | `warehouse.rs:164` | 倉庫現況報表 |
| **`/render-vet-patrol/from-animals`** | **`animal/pdf_export.rs:634`** | **欄位狀態表（demo path）** |
| `/render-vet-patrol-report/from-report-data` | `animal/pdf_export.rs:478` | 獸醫巡場報告 |
| `/render/{doc_type}` (legacy HTML) | _無 caller，REGISTRY 空殼_ | — |

## 覆蓋率總結

| 層 | 覆蓋數 | 比例 |
|---|---|---|
| **L1 fail-safe**（daemon 失效自動 Gotenberg） | 14 / 14 daemon 端點 | **100%** |
| **L2 X-PDF-Renderer header** | 14 / 14 | **100%** |
| **L3 fallback toast** | 10 / 10 PDF download caller | **100%** |

## 實作細節

### pdf-service（`pdf-service/app/main.py`）
所有 endpoint 統一用 `_pdf_headers(filename)` 組 Response headers — 自動帶上 `Content-Disposition` + 可選的 `X-PDF-Renderer`。

```python
def _pdf_headers(filename: str) -> dict[str, str]:
    return {
        "Content-Disposition": _content_disposition(filename),
        **_renderer_headers(),  # 讀 _renderer_path contextvar
    }
```

`_renderer_path` ContextVar 由 `_docx_to_pdf_word_first` / `_xlsx_to_pdf_excel_first` / 直走 Gotenberg 的路徑 `.set()`。

### backend（`backend/src/services/pdf_service_client.rs` + `utils/http.rs`）
所有 `render_*` method 回傳 `Result<(Vec<u8>, Option<String>)>`，handler 用統一的：

```rust
let (bytes, renderer) = state.pdf_service.render_xxx(...).await?;
crate::utils::http::file_response_with_renderer(
    bytes, "application/pdf", &filename, false, renderer,
).map_err(AppError::Internal)
```

### 前端（`frontend/src/hooks/usePdfFallbackToast.ts`）
共用 hook：

```ts
const notifyIfFallback = usePdfFallbackToast()
const res = await api.get(url, { responseType: 'blob' })
notifyIfFallback(res)  // 'gotenberg_fallback' 時 toast 一次
```

已接通的 caller：
- `AnimalPenReport.tsx`（欄位狀態表）
- `VetPatrolReportDialog.tsx` / `VetPatrolReportListPage.tsx`（巡場報告）
- `BloodTestTab.tsx`（血液檢查）
- `SurgeriesTab.tsx`（手術紀錄）
- `CommentsTab.tsx`（審查意見回覆 + 審核結果）
- `useProtocolPdfExport.ts`（AUP 計畫書）
- `useAuditLogExport.ts`（操作日誌）
- `WarehouseReportPage.tsx`（倉庫報表）
- `ExportDialog.tsx`（病歷批次匯出）

---

## 未來路徑（park，不在當前 scope）

### HTML + Gotenberg Chromium（取代 daemon 的長期方向）

當前 daemon 路徑痛點：`threads=1` 序列化、Windows 鎖定、批次匯出慢。長期可遷往：

```text
backend → pdf-service → Jinja2 render HTML → Gotenberg /forms/chromium/convert/html → PDF
```

**為何快**：Chromium 在 container 常駐、無冷啟動、天然並行（多 tab）。單次 ~300-800ms vs daemon 3-8s。

**為何之前沒走**：Gotenberg image 缺中文字型。已透過 `ipig-gotenberg-cjk:8`（Noto CJK + 標楷體 kaiu.ttf，見 `services/gotenberg/Dockerfile`）補齊，技術阻礙解除。

**遷移成本（10 個 docx template）**：
- 🟢 簡單（audit_log / warehouse / blood_test / vet_patrol / audit_log_skeleton）：純表格，HTML/CSS 半天/張
- 🟡 中（medical_record / surgery / review_reply / review_result）：多區塊、嵌圖
- 🔴 高（aup_protocol）：IRB 公文版面挑剔，最後評估或保留 docx

**先決條件**：本次「字體裝進 Gotenberg + daemon 退役」驗證成功後再啟動。

### unoserver（park）

LibreOffice 常駐 daemon，跨平台。如未來 Gotenberg LibreOffice 路徑仍嫌慢可換。
解的是「LibreOffice 每次冷啟動 2-3s」，但 Chromium 路徑直接繞過，所以優先序低於 HTML 遷移。

### Word/Excel COM multi-process pool（park）

如最終保留 daemon（aup_protocol 走 docx），可開多個 Word.exe 各自 STA 解 `threads=1` 瓶頸。
但若 HTML 路徑成功取代大部分匯出，daemon 只剩 1 張表服務，此優化 ROI 下降。

---

## 已知部署設定關鍵

| env | 值 | 說明 |
|---|---|---|
| `WORD_CONVERT_URL` | `http://host.docker.internal:9100` | Word-only daemon（`ENABLED_OFFICE_APP=word`） |
| `EXCEL_CONVERT_URL` | `http://host.docker.internal:9101` | Excel-only daemon（`ENABLED_OFFICE_APP=excel`） |
| `WORD_CONVERT_TOKEN_FILE` | `/run/secrets/word_convert_token` | 與 host daemon 共用同一份 token 檔 |
| `DOCX_CONVERTER_TIMEOUT` | `30` (秒) | backend → pdf-service 60s 內必須失敗或 fallback，留時間給 Gotenberg |

**⚠️ 部署陷阱**（本次 demo 踩到的）：若 `EXCEL_CONVERT_URL` 未設，pdf-service 會把 xlsx 轉檔送到 `WORD_CONVERT_URL=:9100`，但 9100 是 Word-only daemon 無 `/convert-xlsx` 路由 → 404。L1 已修為自動 fallback Gotenberg，但**仍應正確設定 `EXCEL_CONVERT_URL`** 才能拿到 Excel-fidelity PDF。
