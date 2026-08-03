# R45 Final：GLP→daemon / 非 GLP→HTML 路由收斂

> 立案：2026-05-13
> 取代：[`pdf-html-migration.md`](pdf-html-migration.md)（Phase 3 AUP 走 HTML 的決策）
> 決策來源：2026-05-13 對話「GLP daemon, 非 GLP HTML, askuserquestions」

## 1. 最終路由矩陣

| Template | 分類 | PDF 路徑 | docx/xlsx 下載 | Fallback |
|---|---|---|---|---|
| `aup_protocol.docx` | 🔒 GLP | Word daemon | docxtpl | **無**（fail-fast 500）|
| `review_reply.docx` | 🔒 GLP | Word daemon | docxtpl | 無 |
| `review_result.docx` | 🔒 GLP | Word daemon | docxtpl | 無 |
| `vet_patrol.docx`（vet_patrol_report）| 🔒 GLP | Word daemon | docxtpl | 無 |
| `vet_patrol_template.xlsx` | 🔒 GLP | Excel daemon | passthrough | 無 |
| `warehouse.docx` | 非 GLP | **HTML/Chromium** ✅（已上線） | docxtpl | docx → daemon → Gotenberg |
| `audit_log.docx` | 非 GLP | HTML/Chromium（待做） | docxtpl | 同上 |
| `blood_test.docx` | 非 GLP | HTML/Chromium（待做） | docxtpl | 同上 |
| `medical_record.docx`（單隻）| 非 GLP | HTML/Chromium（待做） | docxtpl | 同上 |
| `medical_record.docx`（**批次 zip**）| 非 GLP | HTML/Chromium **並行** | n/a | 同上 |
| `surgery.docx` | 非 GLP | HTML/Chromium（待做） | docxtpl | 同上 |
| `audit_log_skeleton.docx` | n/a | **不暴露**（無 caller） | n/a | n/a |

## 2. 設計原則

### GLP fail-fast 原則
- GLP 文件（AUP / 審查回覆 / 審核結果 / 巡場報告 / 欄位狀態表）**只接受 daemon 出來的輸出**
- daemon 失敗 → HTTP 500 + 「PDF 渲染失敗，daemon 服務未上線」訊息
- **不走 Gotenberg LibreOffice fallback** — GLP 文件需 100% Word fidelity
- 前端匯出前 ping daemon `/health`，未上線禁用按鈕

### 非 GLP HTML 主路徑
- format=pdf 預設走 HTML/Chromium
- HTML 失敗 → 自動 fallback docx → daemon → Gotenberg（多層 safety net）
- format=docx → docxtpl 直接吐 .docx（編輯用）

### 已建 GLP HTML park 策略
4 個 GLP 的 .html 檔案（aup_protocol / review_reply / review_result / vet_patrol_report）：
- 移到 `pdf-service/app/templates_html/_parked/`
- pdf-service `has_html_template()` 不會看到 → endpoint 走不到 HTML
- 保留為「未來如要回到 HTML 路徑時可重啟用」的紀錄

## 3. 實作工項

### Phase 1：GLP daemon-only 收斂（半天）
- [ ] R45-F1：4 個 GLP endpoint 移除 HTML 優先 branch（main.py 內 `if fmt == "pdf" and has_html_template(...)` 全 GLP route 刪掉）
- [ ] R45-F2：4 個 GLP HTML 檔移 `templates_html/_parked/`
- [ ] R45-F3：GLP daemon 路徑改成 fail-fast — 把 `_docx_to_pdf_word_first` 改可選 `allow_fallback` 參數；GLP route 傳 `allow_fallback=False`，非 GLP 保留 True
- [ ] R45-F4：vet_patrol_template.xlsx 同理 `_xlsx_to_pdf_excel_first(..., allow_fallback=False)`

### Phase 2：前端 GLP health check + Email 通知（1 天）
- [ ] R45-F5：backend 加 `GET /api/v1/daemon-health` — 代理到 pdf-service → daemon `/health`
- [ ] R45-F6：前端在 4 個 GLP 匯出按鈕加 health pre-check：未上線時 disable + tooltip「daemon 服務未上線，請聯繫管理員」
- [ ] R45-F7：health 結果 cache 30s（避免每次 hover 都打 API）
- [ ] R45-F8：**daemon down 自動 email 通知 admin**：
  - 觸發點：backend `daemon-health` endpoint 偵測到 daemon 不可用時
  - 收件者：`system_settings.admin_email`（或 first user with role=ADMIN）
  - 內容：『[iPig 告警] PDF daemon 服務未上線』+ 時間 + 細節（哪個 daemon、HTTP 狀態 / connection error）
  - **Rate limit**：30 分鐘內最多 1 封（in-process last_alert timestamp）
  - 信道：reuse 既有 `services/outbox/email_adapter.rs`

### Phase 3：4 張非 GLP HTML 建模（2-3 天）
- [ ] R45-F8：`audit_log.html`（純表格、簡單）
- [ ] R45-F9：`blood_test.html`（欄位 + 表格）
- [ ] R45-F10：`medical_record.html`（多區塊欄位 + 病程表）
- [ ] R45-F11：`surgery.html`（手術紀錄 + 嵌圖）
- [ ] R45-F12：wire 4 endpoints 加 HTML 優先 branch

### Phase 4：medical_record 批次 zip 並行（半天）
- [ ] R45-F13：`/render-project-medical/from-project-data` 改 `asyncio.gather` 並行渲染 N 隻動物
- [ ] R45-F14：benchmark 30 隻試驗豬 zip — 目標 ≤ 20s

### Phase 5：清理 + 文件（半天）
- [ ] R45-F15：`docs/dev/pdf-render-paths.md` 更新路由矩陣
- [ ] R45-F16：`docs/TODO.md` R45 標 done
- [ ] R45-F17：`docs/glp/glp-document-numbers.md` 補「GLP fail-fast」設計原則
- [ ] R45-F18：commit + push

## 4. 不做的事

- **不**動 frontend hook 邏輯（chromium 自然視為成功，gotenberg_fallback 才 toast）
- **不**改任何 endpoint URL 或 backend handler 介面
- **不**動 GLP docx template 結構（已是 fidelity 標準）
- **不**追 HTML 100% pixel match — 95% 視覺等效即收
- **不**做 PagedJS / TOC 自動頁碼（在 Gotenberg + Chromium 嘗試失敗，park）

## 5. 風險與回退

| 風險 | 應對 |
|---|---|
| daemon 在 prod 罕見 down，使用者 GLP 全部卡住 | health check + clear UX 提示；docx 下載仍可用 |
| 非 GLP HTML 視覺與 daemon 差 5% | 接受（非合規文件，使用者體驗 > pixel match）|
| medical_record 批次並行記憶體爆 | 限制 concurrent = 4（Chromium tab pool）|
| 未來 NAS 部署沒 Word | GLP 自動 fail-fast → 強制 NAS 上 daemon 部署有解前不開放 GLP 匯出 |

**回退路徑**：任一 phase 都可獨立 revert（commit 切細粒度）。最壞情況 GLP 重新接 Gotenberg fallback（恢復現況降級行為）。

## 6. 驗收標準

| 指標 | 目標 |
|---|---|
| GLP 匯出 X-PDF-Renderer | `word_daemon` / `excel_daemon`（無 `gotenberg_fallback`） |
| 非 GLP 匯出 X-PDF-Renderer | `chromium`（無 `word_daemon`） |
| daemon down → GLP 匯出 | HTTP 500 + 明確訊息（不靜默 fallback）|
| 30 隻試驗豬 batch zip | ≤ 20s（從現況 ~3 分鐘）|
| 前端 UI | 完全沒視覺改變（除 GLP daemon down 時按鈕 disable）|
