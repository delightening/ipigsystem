# R32-1 — PDF 生成現況盤點 + 校正後計畫

**建立日期**：2026-04-30
**任務**：R32-1（盤點 PDF 生成入口 + 列現況痛點清單）
**目的**：為 R32-2 ~ R32-15 提供事實基礎

---

## 1. 既有 PDF 生成路徑：4 條，**全部不盡人意**

> R32 立項根本原因 = 4 條路徑沒有一條讓使用者滿意。

### 1.1 路徑 A：後端 `printpdf` 手刻（1,236 行）

| 項目 | 細節 |
|---|---|
| 程式碼 | `backend/src/services/pdf/service.rs`（1,236 行）+ `context.rs`（214 行）+ `mod.rs`（5 行）= **1,455 行** |
| Handler | `backend/src/handlers/protocol/export.rs`（觀察其後端 `/protocols/:id/export-pdf` 走此路徑）|
| 用於 | Protocol AUP 計畫書 v1（舊版）|
| 機制 | 純 Rust + `printpdf` crate + `lopdf` crate，手寫 Op 操作（`Op::ShowText` / `Op::DrawPolygon`）|
| **痛點** | (1) `render_paragraph` 用 `chars.chunks(45)` **硬切字元**（中英寬度估算粗糙）<br>(2) `render_table_row` 用 `text.chars().take(max_chars - 1) + "…"` **硬截斷儲存格**（違反 memory `no-table-truncate`）<br>(3) 無 widow/orphan 控制、無 section header 跨頁綁定、無 page header/footer/頁碼<br>(4) 1,236 行手刻 = maintain 災難（每加一個欄位都要手算座標） |

### 1.2 路徑 B：前端 `html2canvas` + `jsPDF` fallback

| 項目 | 細節 |
|---|---|
| 程式碼 | `frontend/src/components/protocol/content-sections/useProtocolPdfExport.ts`（165 行）|
| 用於 | Protocol fallback（路徑 A 失敗時前端兜底）|
| 機制 | `html2canvas` 把 React DOM 拍成 canvas → `jsPDF.addImage()` 塞圖片 |
| **痛點** | (1) **文字變圖片** — 無法 Ctrl+F、無法 OCR、無法被 GLP 稽核工具解析（重大合規風險）<br>(2) 檔案巨大（1-2 MB / 頁）<br>(3) 放大字級會糊<br>(4) 用 `<section>` boundary 切頁，但若單一 section > 1 頁仍會硬切表格中間 |

### 1.3 路徑 C：後端 → Gotenberg `/forms/chromium/convert/html`

| 項目 | 細節 |
|---|---|
| 程式碼 | `backend/src/services/gotenberg.rs::GotenbergClient::html_to_pdf()`（151 行）|
| Handler | `backend/src/handlers/protocol/pdf_export.rs`（743 行，AUP 計畫書 v2 + 審核結果 + 審查意見回覆）<br>`backend/src/handlers/animal/pdf_export.rs`（523 行）|
| 用於 | Protocol export-pdf-v2 / animal medical / project medical / vet patrol（透過 multipart 上傳完整 HTML 字串）|
| 機制 | Rust 後端**自己拼 HTML 字串**（含內嵌 CSS）→ multipart upload 給 `gotenberg/gotenberg:8` container → 內建 Chromium 印 PDF |
| **痛點** | (1) HTML 字串在 Rust 端 **format!() 拼字串**（脆弱、無 type safety）<br>(2) 模板與 React view **不同步**（雙份維護）— web 改了 PDF 沒跟著動<br>(3) 樣式 inline 在字串裡（無法重用 `frontend/src/styles/`）<br>(4) `format!()` 大量 SQL injection 等級風險（雖然 Gotenberg 不執行 JS 但 XSS 仍可能影響輸出）|

### 1.4 路徑 D：後端 → FastAPI `pdf-service` → Jinja2 → Gotenberg

| 項目 | 細節 |
|---|---|
| 程式碼 | `backend/src/services/pdf_service_client.rs`（76 行）<br>`pdf-service/app/main.py`（50 行）+ `renderer.py`（50 行）+ `doc_types.py`（29 行）+ `schemas/blood_test.py` + `templates/blood_test.html`（60 行）|
| 用於 | **僅** `blood_test`（動物驗血報告）|
| 機制 | Rust 送 JSON payload → FastAPI 用 Pydantic 驗證 → Jinja2 渲染 HTML → 內部 multipart 給 gotenberg → 回 PDF |
| **痛點** | (1) **三層架構** Rust → Python → Jinja2 → Gotenberg，每層都是 maintain 點<br>(2) **三份 schema** 重複定義：Rust models + Python Pydantic + Jinja2 templates 用的欄位<br>(3) Jinja2 模板 **再次與 React view 不同步**（同 1.3 痛點 2）<br>(4) Python 容器是運維負擔（多一個語言、多一套依賴 / CVE 監控） |

---

## 2. 入口統計（前端按鈕 → 後端 endpoint）

| 前端入口 | 走哪條路徑 | Endpoint | LoC |
|---|---|---|---|
| `useProtocolPdfExport.ts::exportFromBackend` | C | `POST /protocols/:id/export-pdf-v2` | 165 |
| `useProtocolPdfExport.ts::exportFromClient` | B（fallback）| 無（純前端）| 同上 |
| `useAuditLogExport.ts::handleExportPDF` | ? 未深入查 | TBD | 158 |
| `AnimalPenReport.tsx::exportPDFMutation` | C | `GET /animals/export-pen-report` + `window.print()` | 177 |
| `VetPatrolReportDialog.tsx` | C | `POST /vet-patrol-reports/:id/export-pdf` | — |
| `WarehouseReportPage.tsx` | 純 `window.print()` | 無後端 | 251 |
| Animal blood test | D | `POST /animals/:id/export-blood-test-pdf` → pdf-service `/render/blood_test` | 523 |
| Animal medical export | C | `POST /animals/:id/export-pdf` | 523 |
| Project medical export | C | `POST /projects/:iacuc_no/export-pdf` | 同上 |

**程式碼總量**：4 條路徑 + handler + 前端 hooks ≈ **3,442 行**（不含模板）。

---

## 3. 為什麼**全部不盡人意**

| 路徑 | 共同根因 |
|---|---|
| A printpdf 手刻 | 排版引擎太底層，手刻不可能達到 CSS Paged Media 等級 |
| B html2canvas | 文字變圖片，違背「文件可搜尋」原則 |
| **C Gotenberg + Rust-format-HTML** | **不複用 React view**，雙份維護；HTML 字串拼接脆弱 |
| **D pdf-service Jinja2** | **不複用 React view**，三份維護（Rust + Python + Jinja2）；多一個 service |

**路徑 C 與 D 的共同病根** = 「PDF 用一套 HTML，Web 用另一套 React」**內容雙軌**。每次需求改動要兩邊同步，現實上一定 drift，使用者收到的 PDF 與 web 看到的不一致是必然結果。

---

## 4. R32 校正後的策略：**React view 為單一真實內容來源**

### 4.1 核心理念

**不要再寫 PDF 專用模板**（Jinja2 / Rust HTML 拼接 / printpdf 手刻通通不要）。**React view 就是 PDF 內容**，透過：
- 階段 1：CSS Paged Media（`@page` + `@media print` + `?print=1`）讓使用者 Ctrl+P 直接印
- 階段 2：headless Chromium 載入 `?print=1` URL → 後端產 PDF

這樣**內容只有一份**：React component。Web 看什麼，PDF 就印什麼。

### 4.2 既有基礎設施複用 / 砍除矩陣

| 元件 | 動作 |
|---|---|
| `gotenberg/gotenberg:8` container | ✅ **複用**（它就是業界標準 headless Chromium for PDF） |
| Gotenberg `/forms/chromium/convert/url` endpoint | ✅ **新用**（餵 React 內部 URL，比現有 `convert/html` 路徑乾淨） |
| `services/gotenberg.rs::GotenbergClient::html_to_pdf()` | ✅ **複用** + 新增 `url_to_pdf(url, headers)` 方法 |
| `services/pdf_service_client.rs` (76 行) | ❌ **砍** — 改成「Rust 直接呼 Gotenberg URL 模式」 |
| `pdf-service/` 整個 Python container | ❌ **砍** — 與 Jinja2 模板一起進垃圾桶 |
| `pdf-service/app/templates/blood_test.html` | ❌ **砍** — blood test 改成 React view + `?print=1` |
| `services/pdf/service.rs` 1,236 行 printpdf | ❌ **砍** + 移除 `printpdf` / `lopdf` Cargo 依賴 |
| `useProtocolPdfExport.ts::exportFromClient` html2canvas | ❌ **砍** + 移除 `html2canvas` / `jspdf` npm 依賴 |
| `handlers/protocol/pdf_export.rs` (743 行) | 🔄 **重寫** — 改成「呼 Gotenberg URL 模式 + 帶 service token」（預期降到 ~150 行）|
| `handlers/animal/pdf_export.rs` (523 行) | 🔄 同上（預期降到 ~120 行）|

**預估砍 / 重寫總量**：~3,442 行 → ~500 行（含新 service token + GLP 存證）。

### 4.3 校正後的任務清單（修正 R32-10 ~ R32-15）

| # | 原計畫 | 修正後 |
|---|---|---|
| R32-10 | 新建 chrome service container | ❌ **刪除** — 已有 gotenberg container |
| R32-11 | 引入 chromiumoxide crate | ❌ **刪除** — 已有 GotenbergClient（只需擴 url_to_pdf）|
| R32-10' | **新增**：擴充 `GotenbergClient::url_to_pdf(url, extra_headers)` | 用既有 `gotenberg/gotenberg:8` 的 `/forms/chromium/convert/url` endpoint |
| R32-12 | Service token 機制 | ✅ **保留**（一樣需要） |
| R32-13 | 4 個 v3 endpoint | ✅ **保留** — 流程：產生 service token → Gotenberg fetch React URL with `Authorization: Bearer` extra header → 回 PDF |
| R32-14 | GLP 存證 schema migration | ✅ **保留** |
| R32-15 | 砍舊路徑 | ✅ **保留並擴大** — 額外砍 pdf-service / Jinja2 templates / Python container |

### 4.4 階段 2 工程量重估

- 原估：3-4 週全職（含建新 chrome container + chromiumoxide 學習成本）
- **修正後：~2-2.5 週全職**（buffer 包含：service token 安全測試 + GLP schema migration 相容性 + 4 個 v3 endpoint 整合測試矩陣 + 砍舊路徑後的 regression 測試）

### 4.5 ⚠️ Gotenberg 中文字型必須自建 image（**Critical**）

`gotenberg/gotenberg:8` 預設**沒有**中日韓字型 → 直接餵中文 React URL 會印出**全部方框**。必須自建 image：

```dockerfile
FROM gotenberg/gotenberg:8
USER root
COPY ./fonts/*.ttf /usr/local/share/fonts/
COPY ./fonts/*.otf /usr/local/share/fonts/
RUN fc-cache -fv
USER gotenberg
```

需準備字型檔（GLP 規範）：
- **DFKaiShu-SB-Estd-BF**（標楷體）— 中文正文
- **Times New Roman**（含 Bold variant）— 英文正文
- 後備字型：Noto Sans TC / PMingLiU（缺字 fallback）

`docker-compose.yml` 改 `gotenberg` service 的 `image:` → `build: ./services/gotenberg-zh/`。
**新任務 R32-10b** 加入階段 2。

---

## 5. 階段 1 不變

階段 1（R32-1 ~ R32-9）**完全不變** — print stylesheet + `?print=1` 原本就是為了讓 React view 能直接被列印 / 被 Chromium 正確抓取。是階段 2 的前置條件。

階段 1 完成後，使用者按 Ctrl+P 就能取得排版正確的 PDF，**完全跳過全部 4 條既有路徑**。

---

## 6. 與 R32 風險規則對齊

- ✅ R32-1 盤點完成（本文件）
- ✅ 發現意料外路徑（Gotenberg / pdf-service）→ 已 surface 並修正計畫
- ⏭ 下一步等使用者確認校正方向後啟動 R32-2（print stylesheet baseline）

---

## 7. 待使用者確認

- [ ] 校正後的「複用 Gotenberg 基礎設施 + 砍 pdf-service Jinja2」方向是否同意
- [ ] 階段 2 砍 `pdf-service/` 整個 Python container 是否同意（運維簡化但需確認 blood test 沒其他依賴）
- [ ] R32-10 / R32-11 改成 R32-10'（擴 GotenbergClient）是否同意

---

## 8. 目標版型 — `templates/` 既有 PDF 範例（**最重要的修正**）

> 使用者指出「現在產出的格式不像 `templates/AUP 動物試驗計畫書範例.pdf`」。所以**目標格式不是 R32-2 我隨意設計的 print stylesheet**，是這份具體 GLP 表單版型。**且現在輸出 PDF 功能會報錯**。

### 8.1 `templates/` 目錄盤點（5 份範例 + 1 份 Word 原稿）

| 檔案 | 對應 R32-D3 範圍 | 頁數 |
|---|---|---|
| `AUP 動物試驗計畫書範例.pdf` | (1) Protocol AUP 計畫書 | 18 頁 |
| `實驗豬隻病歷總表範例.pdf` | (2) 病歷資料 | 2 頁 |
| `動物欄位巡視報告範例.pdf` | (vet patrol) | 1 頁 |
| `審查意見回覆表範例.pdf` | (review reply) | 3 頁 |
| `審核結果範例.pdf` | (review result) | 4 頁 |
| `AD-04-01-01F動物試驗研究計畫書.docx` | AUP Word 原稿 | — |

> **未涵蓋**：R32-D3 的「(3) 手術資料彙整」與「(4) Audit log」沒有現成範例 — R32-2 設計時需另外定義或請使用者提供。

### 8.2 AUP 計畫書版型規格（從 PDF 反推）

| 維度 | 規格 |
|---|---|
| **頁面尺寸** | A4 (210×297mm = 595×842pt) |
| **頁邊距** | L≈12.7mm / R≈14.5mm / T≈25mm（含 header）/ B≈25mm（含 footer） |
| **字型** | 中文：**DFKaiShu-SB-Estd-BF（標楷體）**；英文：**Times New Roman PS**；少量 PMingLiU 細明體 / Calibri |
| **字級** | 主章節標題 16pt；正文 + 副標題 13pt；表格內容 10pt；header/footer 12pt |
| **章節編號** | `1`, `1.1`, `1.1.1` 三層；標題格式 `{號} {中文} ({English})` |
| **Page header**（每頁固定）| 左：「文件編號 AD-04-01-01E」；右：「頁次/總頁數 N of 18」 |
| **Page footer**（每頁固定）| 左：「版權為豬博士動物科技股份有限公司所有，禁止任何未經授權的使用」；右：「All Rights Reserved © DrPIG. Unauthorized use in any form is prohibited.」 |
| **封面**（page 1） | 整頁圖片（image 占 (1,1)-(594,841)）— 公司 logo + 計畫名稱 + 編號 |
| **目錄**（page 2） | 章節標題 + 頁碼，dot leader 連線 |
| **Form 元件** | `□` (unchecked) / `■` (checked) checkbox 字元；中英對照欄位描述 |
| **表格** | 簡單 grid（無底色/無 zebra），多列高（中英文雙語並列） |
| **整體風格** | 純文字、黑白印刷友善、無色彩裝飾、密集資訊 |

### 8.3 與 R32-2 print stylesheet 設計的衝擊

我先前在 R32-2 假設：「@page A4 margin 20mm + 隱藏 nav/sidebar + status badge 保留色彩」。但**目標版型不是這樣**：

| 我先前 R32-2 假設 | 目標版型實際要求 |
|---|---|
| margin 20mm 全邊 | L 12.7mm / R 14.5mm（更窄）/ T+B ≈ 25mm（含 header/footer 帶狀區） |
| status badge 保留顏色 | **黑白印刷**（無色彩裝飾） |
| 字型沿用 web 字型（系統字 + Noto Sans TC）| **必須是標楷體 + Times New Roman**（GLP 文件規範） |
| 沒設計 page header/footer | **必須有**：左右兩欄固定文件編號 + 頁碼 + 版權聲明 |
| 沒設計封面 / 目錄 | **必須有**：圖片封面（page 1）+ 目錄（page 2，含 dot leader）|
| 沒考慮中英對照 | **正文必須中英雙語並列**（章節標題 / 表單欄位 / 表格欄位） |
| 中英混排靠 `word-break: keep-all` | 字型混排（標楷體中文 + Times 英文）需明確 `font-family` 切換 |

### 8.4 `templates/from ipig/` 既有系統匯出範例（2026-04-30 使用者提供）

**新發現**：使用者提供 `templates/from ipig/` 目錄，內含現有系統實際匯出的 docx 樣本。涵蓋 R32-D3 4 種報表中**「病歷觀察」+「手術紀錄」共 3 類**：

| 範例 docx | 結構 | 對應 R32 任務 |
|---|---|---|
| `001-實驗豬隻病歷總表-2026-04-30.docx` | A4 直式，3 表（基本資訊 4-col + 疫苗驅蟲 3-col 5-row + 體重觀察 3-col 24-row）| R32-5 病歷總表 |
| `001-實驗觀察試驗紀錄-*.docx` × 7 | **A4 橫式**，4 表（基本資訊 5-col + 事件紀錄 4-col + 11-col 疼痛骨架 + **15-col 詳細疼痛評估**）| R32-5 觀察紀錄 |
| `001-手術紀錄表-*.docx` × 6 | **直橫混合 multi-section**：直式（手術記錄表 11×7 + 生理數值 13×6 + 術後觀察 5×2）+ 橫式（**58-row × 15-col 術後追蹤疼痛評估**） | R32-6 手術紀錄 |

**關鍵格式特徵**：
- 全部 page margin **L/R/T/B = 12.7mm**（與 AUP 一致 → 確認 GLP 文件規範）
- A4，但**直橫混用**：觀察紀錄純橫式；手術紀錄**單一文件直橫切換**
- 表格密度高（11~15 col 為常態）；CSS 必須**完整展開**（`overflow: visible`）禁止 truncate
- 多筆事件以「日期排序」串接（每天上下午各一筆 × N 天 = 50+ 列）

### 8.5 校正後 R32-2 / R32-4 ~ R32-7 任務改寫

| 原 R32-2 | 改寫 |
|---|---|
| Print stylesheet baseline | 改為 **「GLP 文件版型 print stylesheet」**：A4、字型（標楷體 + Times）、章節 16/13/10pt 三層、`@page` header/footer 固定區塊（CSS Paged Media `@top-left` `@top-right` `@bottom-left` `@bottom-right`）、純黑白、`@page :first` 處理封面、**支援 portrait / landscape 動態切換**（CSS named pages：`@page landscape { size: A4 landscape }` + element-level `page: landscape`） |
| R32-4 Protocol print 樣式 | 對照 `templates/AUP 動物試驗計畫書範例.pdf` 1:1 復刻；產出 `frontend/src/components/protocol/print/ProtocolPrintLayout.tsx`（包含目錄、章節、表格、checkbox、簽名欄位）|
| R32-5 病歷 print 樣式 | 對照 `templates/實驗豬隻病歷總表範例.pdf`（直式總表）+ `templates/from ipig/001-實驗觀察試驗紀錄-*.docx`（**橫式觀察紀錄**含 11-col 疼痛骨架 + 15-col 詳細疼痛評估表）。橫式版型用 named page `@page observation { size: A4 landscape }` |
| R32-6 手術彙整 print 樣式 | 對照 `templates/from ipig/001-手術紀錄表-*.docx`（**單一文件混用直橫向 multi-section**）：直式（基本資訊 + 術前 + 生理數值 6-col 13-row + 術後）+ 橫式（58-row × 15-col 術後追蹤疼痛評估）。**最複雜的版型**，需 CSS named page transition |
| R32-7 Audit log print 樣式 | **本計畫提案（GLP 21 CFR §11 對齊）**：A4 直式 / header「文件編號 + 頁次/總頁數」/ 報表標題（雙語）/ 篩選條件區塊（時間範圍 / actor / event_type / resource_type / 產出時間 / 產出人）/ 主體 **6-col 表格**（時間 / Actor / Event Type / Resource Type / Resource ID / 摘要）/ **表尾 HMAC Chain 完整性驗證結果**（§11.10(c) 要求列印物可證明資料未被竄改：「✅ 通過 (verified to row #N)」+ 本報表 HMAC hash）/ 統一 GLP footer。**HMAC 設計複用**既有 R30-7 / R26-6 `user_activity_logs.hmac_version` + `services/audit.rs::verify_chain_rows`，本任務只負責**讀取 + 顯示**驗證結果，不重新設計 HMAC chain |

### 8.6 R32-1b 取消

使用者於 2026-04-30 確認「沒有報錯了」→ R32-1b（修現有 PDF export 報錯）任務取消。

### 8.7 階段 2 額外任務（PR #289 bot review 反饋採納）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| **R32-10b** | **自建 Gotenberg image（中文字型）** | `services/gotenberg-zh/Dockerfile`：`FROM gotenberg/gotenberg:8` + COPY 標楷體 + Times New Roman + Noto Sans TC fallback + `fc-cache -fv`；`docker-compose.yml` `gotenberg` service 改 `build:`；驗收：餵中文 URL 產出 PDF 中文不變方框 | [ ] |
| **R32-7b** | **遷移 `useAuditLogExport.ts`** | 分析現況實作 → 砍 client-side CSV/PDF 邏輯（若有）→ 改呼新後端 `/api/v1/audit-log/export-pdf-v3`（走 R32-13 流程）→ 配合 R32-7 新 audit log 版型 | [ ] |
| **R32-9b** | **GLP 合規性驗證任務（必加驗收標準）** | 階段 2 staging 驗證除技術接受標準（R32-9 列）外，加 GLP 合規維度：(a) PDF 內嵌字型完整性（`pdfinfo` / `pdffonts` 檢查）；(b) PDF metadata（`/Title /Author /CreationDate /Producer` 含產出來源 + 用戶）；(c) PDF/A-1b 或 PDF/A-3b 長期保存格式合規性（GLP 20 年保留期需要）；(d) 文件結構完整性（`pdfa.bfo.com` 或 veraPDF 線上 validator）；(e) HMAC chain 驗證結果與 audit_log 一致；(f) 由 QA 或合規負責人實際試列印一輪 | [ ] |

---

## 9. R32 計畫校正 v3（2026-05-03，最終決策）

> 使用者於 2026-05-03 對話中確認三件事，**整個策略從 HTML→PDF 轉向 docx template fill**：
> 1. **Web ↔ PDF 同源不在乎** — 接受雙軌維護
> 2. **使用 Python service**（沿用 `pdf-service` container，不再砍）
> 3. **Web 顯示走 Hybrid** — 維持現有原生 UI + 加「預覽 PDF」按鈕，**不**模仿 Word 版型

### 9.1 為何根本性轉向

§4 校正計畫（Gotenberg + CSS Paged Media）建立在「React view 為單一真實內容來源」的假設上。使用者三題回應推翻此假設：

- Q1「需要即時頁碼計算 + 自訂分頁演算法」→ CSS Paged Media 在邊角分頁狀況不穩；Word 是 word processor 本職
- Q3「直接用填入 word 的方法閃開字型問題」→ 若走 docx，OS 字型 + Word 渲染原生支援，**完全閃開字型授權問題**
- 「Web ↔ PDF 同源不在乎」→ docx 雙軌維護 acceptable

GLP 表單**本來就 template-driven**（`templates/` 已有 6 份官方範本含直橫混用手術表）。docx fill = template 即源；無 mimicry 漏洞。

### 9.2 最終架構

```text
                                     +-- /api/v1/{資源}/:id/preview-pdf-v3 --+
                                     |                                       |
React detail page                    |   Backend Rust                        |   Python service        LibreOffice
  (web 原生 UI，                  ── click ──>  資料蒐集  ── HTTP POST ──>  docxtpl fill ── subprocess ──>  soffice --headless
   不模仿 Word)                   ── click ──>                                templates/*.docx               --convert-to pdf
                                  「下載 docx」                                                                 │
                                  「下載 PDF」                                                                  ▼
                                                                                                          回 binary
```

- **Templates** 維護在 `templates/`，docxtpl 變數格式（`{{ animal.ear_tag }}` / `{%p for evt in events %}`）；vet / QA 可自己編輯
- **Web** 不變動現有 detail page UI，只在 header 加 2-3 個按鈕（預覽 / 下載 docx / 下載 PDF）
- **Backend Rust** 不存模板邏輯，只蒐集資料 + 呼 Python service
- **Python `pdf-service`** rewrite — 從 Jinja2 改成 docxtpl + LibreOffice
- **LibreOffice** 同 Python container（`apk add libreoffice`）或獨立 container，依測試決定

### 9.3 任務狀態總表（v3）

| 原任務 | 動作 | 新狀態 |
|---|---|---|
| R32-1 盤點 | ✅ 完成（本文件）| `[x]` |
| **R32-2 print stylesheet baseline** | ❌ **砍** — web 不模仿 Word 不需 print stylesheet | 移除 |
| **R32-3 ?print=1 query param** | ❌ **砍** — 同上 | 移除 |
| **R32-4 Protocol print 樣式** | ❌ **砍** — 同上 | 移除 |
| **R32-5 病歷 print 樣式** | ❌ **砍** | 移除 |
| **R32-6 手術彙整 print 樣式** | ❌ **砍** | 移除 |
| **R32-7 Audit log print 樣式** | ❌ **砍** | 移除 |
| R32-8 階段 1 回歸驗證 | 🔄 **改** — 改成驗證「預覽 PDF / 下載按鈕跑得起來」| 重寫 |
| R32-9 使用者教學 | 🔄 **改** — 教如何按預覽 / 下載按鈕 + docx 模板修改指南 | 重寫 |
| R32-10' Gotenberg url_to_pdf | ❌ **砍** — 不走 HTML→PDF | 移除 |
| R32-10b 自建 Gotenberg 中文字型 | ❌ **砍** — Q3 字型問題已閃開 | 移除 |
| R32-11 chromiumoxide | ❌ **砍**（先前已砍）| 移除 |
| R32-12 service token | ❌ **砍** — Backend Rust 直接呼 Python service，內網信任 | 移除 |
| R32-13 4 個 v3 endpoint | 🔄 **改** — 改成 docx template fill endpoint | 重寫 |
| R32-14 GLP 永久存證 schema (D5=c) | ✅ **保留** — `pdf_artifacts` 表照樣 | 保留 |
| R32-15 砍舊路徑 | ✅ **保留+擴大** — 砍 printpdf + html2canvas + Jinja2 + Gotenberg `convert/html` 路徑（4 條全砍）| 擴大 |
| R32-7b 遷移 useAuditLogExport.ts | 🔄 **改** — 改呼新 docx-based audit log export | 重寫 |
| R32-9b GLP 合規性驗證 | ✅ **保留** | 保留 |

### 9.4 新任務清單（v3）

| # | 項目 | 說明 |
|---|---|---|
| **R32-A1** | **Python service 重寫**（`pdf-service`） | `pip install python-docx-template python-docx`；新 `/render/<doc_type>` endpoint 接 JSON → 載入 `templates/<doc_type>.docx` → docxtpl fill → 回 .docx；移除既有 Jinja2 + Pydantic schema 重複（單一 Pydantic schema 供型別檢查即可） |
| **R32-A2** | **LibreOffice headless 整合** | Python container 加 `apk add libreoffice` 或獨立 container；endpoint `/render/<doc_type>?format=pdf` 跑 `soffice --headless --convert-to pdf` 轉檔 |
| **R32-A3** | **Templates 變數化** | 把 `templates/*.docx` 改成 docxtpl 變數格式：(1) AUP 計畫書、(2) 病歷總表、(3) 觀察紀錄（橫式）、(4) 手術紀錄表（直橫混用）、(5) audit log（新建）。每份產出時搭配一份 `schemas/<doc_type>.py` Pydantic schema |
| **R32-A4** | **Backend Rust handler** | 新 module `services/pdf_v3/`；4 個 endpoint：`/api/v1/protocols/:id/{export-docx,preview-pdf,export-pdf}` + 對應 animal-medical / surgery-summary / audit-log；handler 蒐集資料 → `pdf_service_client::render(doc_type, payload, format)` |
| **R32-A5** | **Frontend 預覽 / 下載 UI** | 各 detail page header 加 3 按鈕（預覽 PDF / 下載 docx / 下載 PDF）；預覽用 `<iframe src="...preview-pdf-v3">` 或 PDF.js |
| **R32-A6** | **GLP 永久存證**（同舊 R32-14） | `pdf_artifacts` 表 schema migration + 產 PDF 後寫表 + audit + 整合 `electronic_signatures.meaning` |
| **R32-A7** | **砍舊路徑**（同舊 R32-15 擴大） | 砍 `services/pdf/service.rs` 1,236 行 + `printpdf` / `lopdf` 依賴 + `useProtocolPdfExport.ts::exportFromClient` html2canvas + `html2canvas` / `jspdf` npm 依賴 + `services/gotenberg.rs::html_to_pdf` 路徑（保留 client struct 給未來其他用途）+ pdf-service Jinja2 templates |
| **R32-A8** | **回歸驗證 + GLP 合規**（合併舊 R32-8 / R32-9b） | 4 種報表 × 3 樣本 → 預覽 + 下載 + 比對 templates 範本；GLP 維度：PDF/A 合規、metadata、HMAC chain、字型完整性 |
| **R32-A9** | **使用者教學文件** | `docs/USER_GUIDE.md` 加「PDF 匯出」章節 + `docs/dev/docx-template-guide.md` 給 vet / QA 學 docxtpl 變數語法（Jinja-like） |

### 9.5 工程量重估

| 階段 | 任務 | 預估 |
|---|---|---|
| **校正 v3** | R32-A1 ~ R32-A9（9 項）| **~3-4 週全職** |

對比：
- v1 原計畫：5-7 週（階段 1 + 階段 2）
- v2 校正計畫（Gotenberg + CSS Paged Media）：4.5-5.5 週（含字型授權處理）
- **v3 校正計畫（docx template fill）：3-4 週**

**節省關鍵**：templates 已存在無需復刻 + 字型問題完全消失 + 不做 print stylesheet。

### 9.6 取捨總結

**v3 接受**：
- Web ↔ PDF 雙軌維護（modify schema 時要兩邊改：Rust models + docxtpl 變數）
- Python service 仍存在（多一個語言維護負擔，但 docxtpl 太成熟值得）
- 2 個容器（`pdf-service` Python + LibreOffice，可能 merge 成 1 個）

**v3 取得**：
- 字型授權 0 風險（OS 字型 + Word 渲染）
- vet / QA 自己改模板（docx 編輯比 React 友善）
- 工程量降 ~30-40%
- Web UX 不被 A4 版型綁架（手機/小螢幕保持可用）

### 9.7 ⏭ 下一步

R32-1 標記 `[x]` + TODO.md R32 區塊全面更新（v1/v2 任務 obsolete + 加入 R32-A1~A9）→ 開純 docs PR 鎖定 v3 計畫 → 然後 R32-A1（Python service docxtpl PoC）開工。
