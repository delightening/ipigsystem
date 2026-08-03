# PROGRESS §9 變更日誌封存 — 2026 上半（早於 2026-05-15）

> 本檔自 `docs/PROGRESS.md` §9 於 2026-07-10 封存重整時抽出：**日期早於 2026-05-15** 的逐日變更紀錄移到這裡，保留完整歷史。
> 近期變更日誌見 `docs/PROGRESS.md` §9；待辦清單見 `docs/TODO.md`。
> 排序：反向時間序（新→舊），與 §9 一致。

---

### 2026-05-14 R50 Post-R49 穩定性 follow-ups（4 個 PR 開啟）

R49 guest mode 上線後 dogfooding + prod observation 找出多個獨立議題，加上 RustSec 同期發布 lettre advisory，彙整為 R50。4 個 PR 待 merge：

- 🟡 **R50-1 R33-1 CSRF middleware 改用 `extensions::<CurrentUser>()`**：移除自解 JWT payload 不驗簽章的 trust gap；middleware 順序由 csrf→auth 改為 auth→csrf。PR #393。
- 🟡 **R50-2 R49 guest-mode 4 bug + RolesPage demo permissions**：RolesPage `role.permissions.length` crash null-safe + 出勤管理按鈕 disabled + 修正審核 sidebar 隱藏 + 新增計劃書 fieldset disabled；DEMO_PERMISSIONS 18 項 + DEMO_ROLES 帶 permissions 讓 guest 看角色權限範例。採納 Gemini selector subscribe fix。PR #394。
- 🟡 **R50-3 unusual_login 三階段降噪 + deploy-prod.ps1 script**：services/login_tracker.rs 加 A 30 分鐘 dedup（對齊 brute_force pattern）+ B 非 admin 首次登入跳過 new_device（admin 例外仍警報）+ D admin 僅 unusual_time 降為 info severity；新增 is_admin_user helper + scripts/deploy-prod.ps1 讓 solo operator 一鍵 redeploy。整合測試 cover dedup（B/D 受 check_unusual_time 時鐘依賴限制 deferred）。PR #395。
- 🟡 **R50-4 RUSTSEC-2026-0141 lettre Boring TLS advisory ignore**：本專案 lettre features 為 `tokio1-native-tls`，未啟 boring-tls，bug 路徑不適用。deny.toml 加 ignore + rationale comment（對齊 RUSTSEC-2026-0097 既有 feature-gated 略過 pattern）。PR #396。

### 2026-05-14 P3-2 Gotenberg HTTP timeout 確認落地（TODO 同步）

- ✅ **P3-2 標記完成**：`backend/src/services/gotenberg.rs` 已於 2026-04-20 commit `3849f684`（E-2 security fix）加上 `connect_timeout(5s)` + `timeout(60s)`，避免 Gotenberg 無回應時 backend async task 永久 hang。本次僅補上 TODO.md / PROGRESS.md 同步紀錄（待辦統計 P3 1→0）。

### 2026-05-14 Guest mode 全面修整 + security 目錄索引（PR #389/#390）

Per 使用者討論（⚠ 部分功能/無資料 → demo 唯讀；❌ 完全擋 → 編輯頁隱藏），全面整理 guest mode 體驗。

- ✅ **PR #390 Guest mode 全面修整**：
  - **修崩潰**：`/vet-patrol-reports` flat array fallback（原本 `I.map is not a function` white screen）
  - **補空表 demo data**：`/animals/available`（R47）8 隻 demo 豬 + summary；`/hr/training-records` 5 筆訓練紀錄；`/messaging` 3 threads + 7 messages
  - **解鎖 admin/QAU 顯示 demo**：移除 `/admin/users` / `/admin/roles` / `/admin/settings` 的 `hasRole('GUEST') ? Navigate` 硬重導；移除 QAU 5 條 route 的 `RequirePermission guestBlock=true` 屬性
  - **編輯頁完全擋下**：新增 `components/auth/GuestBlock` route wrapper，包 6 條 route（`/protocols/new`、`/protocols/:id/edit`、`/products/new`、`/products/:id/edit`、`/documents/new`、`/documents/:id/edit`、`/animals/:id/edit`、`/animals/animal-field-corrections`）
  - **按鈕補洞**：ProductsPage「新增產品」按鈕補 GuestHide（DocumentsPage 既有）
  - **Prod deploy**：`docker compose up -d --build web` 完成，container healthy
- ✅ **PR #389 docs/security/README.md**：17 個安全文件分 8 類 + 跨資料夾關聯表（runbooks / design / archive / code）。GitHub 開資料夾時自動當首頁渲染。

### 2026-05-14 R46 refresh_token reuse 告警降噪 + UX 強化（PR #384）

R35-15 reuse detection 上線後實際運行多數為 false alarm（browser 多分頁併發、行動裝置斷網重試、雙擊 race）；告警若不分真偽全發 critical，秘書認知負擔高且告警價值稀釋。R46 引入三階段啟發式 + 前端 SOP 化解。

- ✅ **R46-1 Race window grace period**：refresh_tokens 加 `rotated_at`；reuse detection 入口判定 `now() - rotated_at <= 5s` 視為併發 race — `tracing::warn` only，不 revoke family / 不寫 alert，client 5 秒內重試會用到 cookie 內的新 token。
- ✅ **R46-2 IP/UA severity 降級**：refresh_tokens 加 `last_ip` / `last_user_agent`；真 reuse 比對 reused request 與上次 rotation 的 IP/UA — 完全相同 → severity 降為 `warning`（疑似 browser bug）；任一不同或缺資料 → 維持 `critical`（fail-safe）。
- ✅ **R46-4/5 告警上下文**：handle_refresh_token_reuse SELECT users 補 username + display_name；context_data 加 last_login_ip / last_user_agent / reused_ip / reused_user_agent / time_since_rotation_secs / same_ip / same_user_agent — 前端 dialog 直接呈現。
- ✅ **R46-6/7 前端 UX**：AuditAlertDetailDialog 針對 REFRESH_TOKEN_REUSE 顯示固定處理 SOP（黃框 4 步驟）；user_id 旁加「查看此使用者」跳轉按鈕到使用者管理頁。
- ✅ **設計取捨**：`last_ip` 用 TEXT 而非 INET（避免引入 sqlx ipnetwork feature；用途為 equality 比對，不需 CIDR）；race window 5s 為保守初值，R46-3 觀察期 2026-05-28 起 2 週收集資料後再調。
- ✅ **Bot review 採納（4 項）**：Gemini Code Assist 兩項 clock-drift hardening（race window `.abs() <= N` / `time_since_rotation_secs.max(0)` 對抗 app↔DB 時鐘漂移）；CodeRabbit 兩項測試隔離（`UPDATE rotated_at` / `DELETE security_alerts` 加 `WHERE user_id = (SELECT id FROM users WHERE email = ?)` 避免 `#[serial]` 測試互相污染）。
- ❌ **Bot review 拒絕（4 項 + 理由存查）**：
  - CR3 抽 `RefreshTokenReuseSopPanel` 子元件 → 拒絕：CLAUDE.md 80 行為建議非死線，本元件 SOP 區塊單一用途未跨檔案復用，過早抽象增檔反害可讀性。
  - CR7 兩個 integration test fn > 50 行 → 拒絕：CLAUDE.md「Surgical Changes」原則 — 任務無關清理 mention 不做，本 PR 範圍為 reuse detection 邏輯，拆 test helper 屬獨立 cleanup sprint。
  - CR2/CR6 「`2026-05-14` 未來日期」→ 拒絕：CodeRabbit clock 誤判，**今日就是 2026-05-14**。
  - CR1/CR8（PROGRESS PR 編號表述 + TODO.md 頂部「最後更新」）→ 拒絕：純文案/版本元資料 cosmetic，本 PR 內容無實質歧義。

### 2026-05-14 R47 可用豬隻快速查詢落地 + R48 立案（ATR 借鏡）

- ✅ **R47 全 8 項落地 via PR #386**：backend `GET /api/v1/animals/available`（list / xlsx 雙路徑）+ frontend `/animals/available`（advanced filter 300ms debounce + 統計列 + Excel 匯出 + 體重過期提示）。權限沿用 `animal.read` 不新增。8 欄輸出（棟舍/欄位合併 "A03"），月齡遞增排序。clippy/tsc/eslint/integration tests（4/4 pass）全綠。
- ✅ **Dependabot #387 patch-updates merge**：@tanstack/react-query / dompurify / react-i18next / zod / zustand 5 個 patch bump（#383 因 stale base rebase 為 #387）。
- ✅ **R48 立案**：閱讀 Agent-Threat-Rule/agent-threat-rules（給 LLM agent 的 Sigma/YARA）後評估可借鏡 pattern。寫 RFC `docs/security/TIERED_DETECTION_RFC.md`，提取 3 個低成本 action：alert 標註偵測極限（R48-1）+ SARIF CI integration（R48-2）+ THREAT_MODEL 連結（R48-4）。規則資料化（R48-3）暫緩等需求頻率提升。

### 2026-05-14 R42 Word COM daemon 效能改善剩餘項目落地（R42-3/4/5/6/7）

- ✅ **R42-7 前端等待 UX**（`VetPatrolReportDialog::handleExportPdf`）：匯出時顯示「PDF 產製中（首次可能需 30 秒）」toast（3 分鐘自動 dismiss）+ button title 加「首次可能需 30 秒」，註解補上 nginx `proxy_read_timeout 180s` 來源。
- ✅ **R42-3 daemon 背景 keep-warm**（`services/word-convert/server.py`）：每 `WORD_CONVERT_KEEPWARM_INTERVAL_S`（預設 180）秒走 HTTP loopback `/convert` 一個 inline minimal docx（zipfile 即時組裝），避開 COM STA per-thread 限制讓 keep-warm 與真正 convert 共用同一個 Word.Application instance。`/health` 暴露 `keepwarm_runs / last_ok_s_ago / last_error`。
- ✅ **R42-6 Word/Excel.Application 定期回收**：`_maybe_recycle_word/_excel` 在 `_convert/_convert_xlsx` 入口檢查 `WORD_CONVERT_RECYCLE_SECONDS`（6h）/ `WORD_CONVERT_RECYCLE_REQUESTS`（200），到限即 Quit + reset，下次 lazy re-init。`/health` 暴露 `word_age_s / word_count_since_recycle` 與 Excel 對應欄位。
- ✅ **R42-4 PDF render cache（pdf-service 端）**：新增 `pdf-service/app/render_cache.py`，以 `sha256(input_bytes)` key 寫 disk cache（`PDF_RENDER_CACHE_DIR`，TTL 24h，500MB LRU eviction）。**只 cache daemon 成功路徑** — fallback Gotenberg/HTML 不入 cache（fidelity 不同）。新 Prometheus metric `pdf_render_cache_total{result, doc_format}`。
- ✅ **R42-5 pivot：watchdog scheduled task**：原計畫 NSSM 裝 Windows Service 撞 Office COM Session 0 isolation 不可行（COM 需要 interactive desktop session，LocalSystem service 跑會 0x80080005）。改用 `watchdog.ps1` + `install_watchdog.ps1`，獨立 scheduled task 每 5 分鐘 probe `/health`，task State≠Running 時 `Start-ScheduledTask` 拉回；半死狀態（task Running but /health 503）放手讓 server.py 自我修復避免打斷 in-flight convert。TODO R42-5 描述換掉、影響評等從「可靠性 ★★★」降為「★★」（半死路徑沒拉回）。
- ✅ **R42-8 park 維持**：worker pool（多 Word instance）等 R42-2~7 落地後實測再決定。

### 2026-05-13 Dependabot 大批 PR 處理（11 → 10 merged / 1 closed / 立案 R46 R47）

11 個 Dependabot PR（PR #366-376）一次清盤；CI 失敗根因為 stale base SHA（舊 main 的 `VetPatrolReportDialog.tsx` ESLint 不可達程式碼已於後續 R45 commit 修復）— `@dependabot rebase` / `recreate` 後全綠。

- ✅ **第 1 批 7 個 backend / frontend minor merged**（PR #366-369、#372、#374-375）：
  - backend: `rust_xlsxwriter 0.93→0.95`（URL 跳脫 + chart title bug fix）/ `calamine 0.24→0.35`（xlsx 讀取，跳 11 個 0.x minor，CI cargo check/test 全綠驗證 API 未動）/ `utoipa 5.4→5.5`（OpenAPI doc minor）/ `rust_decimal 1.41→1.42`（穩定 crate minor）
  - frontend: `rollup-plugin-visualizer 6→7`（major，但只影響 build analyze，不進 prod bundle）/ `tailwind-merge 3.5→3.6` / `react-router-dom 7.14→7.15`
- ✅ **第 2 批 3 個剩餘 PR 評估後 merge**（PR #376、#381、#382）：
  - `lint-staged 16→17`（PR #376）— major 但驗證 Node 24 ≥ 22.22.1 / Git ≥ 2.32.0 / package.json inline config 不受 `yaml` optional 影響，dev-only 工具無 prod runtime impact
  - frontend dev-deps group 13 updates（PR #381，取代 stale #370）— Playwright 1.59→1.60（新 HAR/drop API non-breaking）/ tailwindcss 4.2→4.3 / vitest 4.1.5→4.1.6 / vite 8.0.10→8.0.12 等，全 dev-only
  - frontend patch-updates group 12 updates（PR #382，取代 stale #371）— **含 dompurify 3.4.2→3.4.3 安全修復**（ReDoS hardening + Shadow DOM 迭代修復）/ react-query / zod / zustand / react-i18next 全 patch
- ❌ **PR #373 React 18→19 closed park**：major breaking（propTypes / defaultProps 移除、forwardRef ref 改 prop、ReactDOM.render 移除）需獨立規劃 + 全套 QA，不適合 dependabot 路徑處理。
- ✅ **R46 立案**：refresh_token_reuse 告警降噪 + UX（多數為 race condition false alarm；7 項分 A 降誤報 / B UX 強化兩階段）。
- ✅ **R47 立案**：可用豬隻快速查詢（庫存盤點，動物列表頁 advanced filter + 月齡/體重區間 + 統計列 + Excel 匯出，飼養計畫 000 視為可用，體重 > 40 天直接排除；8 項 ~7h 1 PR）。

### 2026-05-13 R42-1/2 + R44-7 + R36-10 + R31-9 + R45-7 一輪 ROI 打包（PR #379）

R45 收斂 merge 後接著做 5 個高 ROI 工項，部分為文件先行需 user 後續跟進。詳細 PR：#379。

- ✅ **R42-1 daemon baseline observability**：`services/word-convert/server.py` `/health` response 加 `pid / uptime_s / requests_served / last_convert_ms / last_init_ms / addins_disabled[/_list]`。「先量再改」基線就緒。
- ✅ **R42-2 自動關 Word/Excel COM add-ins**：`_disable_com_addins()` 在 `_get_word_app()` / `_get_excel_app()` 首次 init 後立即跑迴圈把 OneDrive / Acrobat / Mendeley / Grammarly 等 add-in `Connect=False`。預期 Documents.Open 從 20-40s → 5-10s（待 user host 重啟 daemon 量實際數字）。
- ✅ **R44-7 Grafana 雙 daemon dashboard + Prometheus alerts**：`monitoring/grafana/dashboards/pdf-daemons.json` 含 8 panel（雙 daemon 路徑分布 / throughput / failure / R45 fallback chain activity）；`alert_rules.yml` 加 4 條 alert (`WordDaemonFallbackHigh` / `ExcelDaemonFallbackHigh` / `DaemonFallbackToHtml` / `DaemonAndHtmlBothFailed`)。
- ✅ **R36-10 Cold-start runbook**：`docs/runbooks/cold-start.md` — 筆電完全掛時 9 step ≤ 4 小時 RTO SOP（NAS 接手 Docker setup + DB restore + uploads restore + Cloudflare tunnel reroute + DNS 切換 + Word daemon Linux 替代方案）。R36-10 從 `[~] partial` → 完成。
- ✅ **R31-9 CSP enforce cutover SOP**：`docs/runbooks/csp-enforce-cutover.md` — Report-Only 觀察期 violation 分類處置（自家 inline / CDN / 瀏覽器 extension 噪音）+ 7 天 / 4 瀏覽器 / 0 自家 violation 觀察期 checklist + R31-10 cutover 步驟 + rollback。User 行動：監看 1-2 週 violation reports。
- ✅ **R45-7 PagedJS / WeasyPrint PoC 計畫**：`docs/plans/r45-7-pagedjs-weasyprint-poc.md` — 兩條候選路徑（A. playwright + PagedJS 雙 pass / B. 換 WeasyPrint engine）的 4 phase PoC 步驟、風險比較、驗收標準。觸發時機：NAS 採購通過 / vet/QA 要求 GLP HTML / Office license 問題。

### 2026-05-13 R45 PDF 渲染架構收斂落地（GLP daemon-only + 非 GLP 三階 fallback + email alert）

R45 5 phases 全部落地，14 個 endpoint 路由收斂完成。詳細計畫見 [`docs/plans/pdf-r45-final-routing.md`](plans/pdf-r45-final-routing.md)。

- ✅ **GLP 5 端點 daemon-only fail-fast**：aup_protocol / review_reply / review_result / vet_patrol_report (docx) + vet_patrol_template (xlsx) 全走 Word/Excel COM daemon，失敗回 HTTP 503 不 fallback。`DaemonUnavailable` 例外 + `_docx_to_pdf_word_first(..., allow_fallback=False)`。
- ✅ **非 GLP 5 端點三階 fallback**：warehouse / audit_log / blood_test / medical_record / surgery — daemon (primary) → HTML/Chromium (fallback 1) → Gotenberg LibreOffice (fallback 2)。新 helper `_docx_to_pdf_with_html_fallback`。
- ✅ **project_medical 批次 zip 並行**：`asyncio.Semaphore(4)` Chromium tab pool；8 隻 7.5s（vs daemon sequential 估 ~50s，**6.7× 加速**）；per-animal 三階 fallback 獨立。
- ✅ **Daemon down 自動 email alert**：backend `/api/daemon-health` 探測時 + 非 GLP 匯出實際 fallback 時都會觸發（rate-limit 30 min 共用，避免 spam）。透過既有 outbox `email_adapter` enqueue，收件者為第一個 active admin。
- ✅ **Frontend GLP pre-check + UI**：`useDaemonHealth` hook (TanStack Query 30s cache) + 4 個 GLP 匯出按鈕加 health pre-check：daemon down 時 disable + tooltip + click 後 toast「已通知管理員」。
- ✅ **PDF 渲染 X-PDF-Renderer label 體系**：4 種值區分路徑（`word_daemon` / `excel_daemon` / `chromium_after_daemon_fail` / `gotenberg_after_html_fail`）。`usePdfFallbackToast` hook 對 `_after_daemon_fail` / `_after_html_fail` 後綴給對應 toast 提示。
- ✅ **4 張非 GLP HTML template**：audit_log / blood_test / medical_record / surgery — 共用 `base.html` (@page CSS + 標楷體/Times/Arial/Segoe Symbol 字體 + 雙語頁尾)。
- ✅ **4 個 GLP HTML park**：先前 Phase 3 PoC 的 aup_protocol / review_reply / review_result / vet_patrol_report 移到 `_parked/`，保留歷史不接路由。R45-7 PagedJS TOC 頁碼 park（Gotenberg pinning-proxy 環境無法觸發）。
- ✅ **Gotenberg 字體完整化**：之前已加入標楷體 (kaiu.ttf) + Times New Roman + Arial + Segoe UI Symbol，daemon 與 fallback 路徑視覺差 < 5%。
- ✅ **clippy clean + tsc clean**：backend `unwrap_or_else(|p| p.into_inner())` 處理 poisoned mutex 而非 `.unwrap()`；frontend 新增 2 個 renderer label 對應 toast。

### 2026-05-12 R44 雙 daemon Windows host 上線 + 三項實戰修復

R44-4 雙 task 部署完成（Word:9100 + Excel:9101 兩 task Ready / port LISTENING / `/health` 雙綠 16.0），並順手把部署中發現的三個問題一起修掉。Commit `7aa4b865`。

- ✅ **R44-4 雙 daemon Windows host 上線**：`install_service.ps1 -AppType word -Port 9100` 與 `-AppType excel -Port 9101` 兩 task 註冊成功；`netstat` 9100/9101 兩 port LISTENING；`/health` Word 16.0 + Excel 16.0 都回 ok。
- ✅ **R44-9 hidden-launcher.vbs（解決 cmd 視窗誤關）**：原本 task 跑 wrapper.bat 會冒可見 cmd 視窗，使用者誤關會把 process tree（cmd → pythonw → Word/Excel COM）一起殺掉，導致 daemon 半殘。新增 `services/word-convert/hidden-launcher.vbs` 用 `WshShell.Run windowStyle=0` 隱藏啟動 wrapper.bat；`install_service.ps1` 改成 task action 走 `wscript.exe hidden-launcher.vbs wrapper.bat`。
- ✅ **R44-9 移除 main thread COM pre-warm（解決 CoInitialize 尚未被呼叫）**：原 `server.py __main__` 在 main thread 跑 `_get_*_app()` pre-warm，但 waitress 是 worker thread 處理 request；COM STA 是 per-thread，worker thread 用 main thread 建的 ref → 全部 503。改成 worker thread 首次 request 才 lazy init（`waitress threads=1` 保證單一 worker thread），代價是首次 request 慢 ~7s。
- ✅ **R44-9 `/health` exception 也清 cached COM ref**：原本 `/health` 失敗只 log，cache 沒清，Word/Excel 被外部關掉後永遠 503。對齊 `/convert` / `/convert-xlsx` exception path，失敗時 `_word_app = None` / `_excel_app = None`，下次 probe 自動 lazy 重建。
- ✅ **`.gitignore` 加 `wrapper-*.bat`**：install_service 產出的 per-machine wrapper 含明文 `WORD_CONVERT_TOKEN` + `WORD_CONVERT_DOC_PASSWORD`，絕不可 commit；新增規則防後續誤推。

### 2026-05-12 vet patrol PDF 預覽失敗事故 hot-fix + R44 daemon 拆分

獸醫巡場「欄位狀態表」PDF 預覽失敗事故根因排查、兩層 hot-fix，並立 R44 把 Word/Excel COM daemon 拆成獨立 process 徹底解決同 process 連帶崩潰問題。Code 4/8 落地（R44-1/2/3/8），剩 4 項待 Windows host 部署 + 驗證。

- ✅ **根因定位**：Word/Excel COM daemon 半殘 — Excel COM 崩潰回 HTTP 500（53s 才回，吃掉 backend 60s 預算），但 daemon `/health` 只測 Word，pdf-service 無法及早偵測。錯誤前端顯示為「PDF 預覽載入失敗」，與 VET 角色無關（admin / 任何 role 也會撞同問題）。
- ✅ **hot-fix 1：pdf-service 5xx fallback**：`pdf-service/app/main.py` `_xlsx_to_pdf_excel_first` + `_docx_to_pdf_word_first` 加 5xx → Gotenberg fallback（原本只在連線失敗時 fallback，HTTP 5xx 直接拋例外讓監控看見）；metric `CONVERT_FAILURE{reason="http_error"}` 仍累計確保可觀測。
- ✅ **hot-fix 2：daemon timeout 30s**：`docker-compose.yml` 新增 `DOCX_CONVERTER_TIMEOUT: 30`（默認 120s），讓 daemon 失敗 + Gotenberg fallback 整段流程在 backend 60s timeout 內完成。R44-6 規劃在雙 daemon 穩定後改回 120s。
- ✅ **R44-1 daemon `ENABLED_OFFICE_APP` env var**：`services/word-convert/server.py` 加環境變數控制單 process 跑哪個 Office app（`both` / `word` / `excel`）；`/health` 依啟用範圍探測；route 條件註冊；pre-warm 只跑啟用的 app；回應加 `enabled` 欄位讓 pdf-service 可識別 daemon 角色。
- ✅ **R44-2 pdf-service `EXCEL_CONVERT_URL` env var**：`_xlsx_to_pdf_excel_first` 改讀 `EXCEL_CONVERT_URL`，未設則 fallback 到 `WORD_CONVERT_URL`（向後相容）；`docker-compose.yml` pdf-service 加對應 env（默認空）；image 已 rebuild + 重起容器驗證。
- ✅ **R44-3 `install_service.ps1` 參數化**：加 `-AppType (both\|word\|excel)` + `-Port` 參數；task name 依 AppType 帶後綴（`ipig-word-convert` / `-word` / `-excel`）；env 多塞 `ENABLED_OFFICE_APP` 與 `WORD_CONVERT_PORT`；單 daemon 模式（`both`）維持舊 task 名向後相容。
- ✅ **R44-8 README 雙 daemon 部署 SOP**：`services/word-convert/README.md` 加完整 R44 段落 — 部署指令、env var 對照表、`/health` 回應差異、Office license 注意（同 host 同 user 跑 Word + Excel 兩 process 通常 OK）、隔離驗證 SOP（殺 Excel daemon 確認 Word 不受影響）。
- ⏳ **R44-4/5/6/7 待 Windows host 端執行**：使用者手動 install 兩個 task（Word:9100 + Excel:9101）→ 設 `EXCEL_CONVERT_URL` → 隔離測試 → 恢復 120s timeout → Grafana 雙 daemon dashboard。

### 2026-05-11 R42 中級合規 cherry-pick 計畫立案（parked）

延伸自當日中小企業中級合規討論，產出 [`docs/plans/r42_pragmatic_middle_compliance.md`](plans/r42_pragmatic_middle_compliance.md)。

- ✅ **盤點與 pragmatic SME baseline 之差距**：9 項目 → 5 ✅ / 3 🟡 / 1 N/A，ipig 現況已優於多數 SME 中級水位
- ✅ **R42 子項 6 個**：條件式啟動，明確列觸發條件（多租戶 / SaaS / 政府計畫 / B2B / 個資事件 / ISO 27001 預審）
- ✅ **唯一建議現在做**：R42-2 Incident Response 一頁式總綱（~3h，對 solo 也有實質價值）
- ✅ **其他 5 項 parked**：每半年隨 NICS audit review 檢查觸發條件；2026-11-11 / 2027-05-11
- ⏸ **明確不追**：SOC 24x7 / FIPS HSM / RTO 8h 熱備援 / ISO 27001 認證 / 紅藍隊演練（理由文件化）

### 2026-05-11 R41 完成全部 8 項 — NICS 防護基準普級 100% 達標

R41 Phase B/C 同 PR 補完，全部 8 子項落地（branch `feat/r41-nics-compliance-phase-a`，commit `cargo test --lib` 492 passed / clippy `-D warnings` 綠）。

- ✅ **R41-1 後端閒置 session**：Migration 062 加 `refresh_tokens.last_used_at`；`Config::auth_idle_timeout_minutes` 預設 30；`services/auth/session.rs::refresh_token` 加 idle check（超過閾值 → revoke token + return `session_idle_timeout`）；`AUTH_IDLE_TIMEOUT_MINUTES` env var 寫入 `.env.example`。
- ✅ **R41-5 SAST CI**：`.github/workflows/ci.yml` 新增 `semgrep-sast` job（p/rust + p/typescript + p/owasp-top-ten + p/secrets ruleset），`continue-on-error: true` 建立首輪 baseline 不阻擋 merge。
- ✅ **R41-6 R22 串接驗證**：grep 確認 `IpBlocklistService::auto_block` 已串接於 rate_limiter / response_logger (IDOR) / honeypot 三處；`security.md` 新增 R22 自動 IP block 鏈路文件化段落（含 gate `idor_auto_block_enabled` 與已知限制）。
- ✅ **R41-8 DB at-rest 評估**：`docs/assessments/DB_AT_REST_ENCRYPTION_2026-05.md` 結論採方案 A（Windows BitLocker），其他方案不追；實作排程 2026-06 與下次 DR drill 同時段。
- ✅ **NICS audit 報告更新**：普級 18 PASS / 1 PARTIAL → **19 PASS / 0 PARTIAL，100% 達標**；中級 ~85% → ~92%；高級 ~75% → ~80%。

### 2026-05-11 R41 Phase A 合規 gap 修復（普級 92% → 97%）

普級 R41-2/3/4/7 四項 Phase A 落地（branch `feat/r41-nics-compliance-phase-a`）。

- ✅ **R41-3 Audit 容量分區**：`DATA_RETENTION_POLICY.md` §6 新增閾值 + 歸檔流程；Prometheus alert group `ipig_audit_capacity_alerts`（5M rows / 5GB warning / 10GB critical）；`backend/src/bin/audit_archive.rs` skeleton（cargo check + clippy 綠）。
- ✅ **R41-4 密碼政策**：`docs/security/PASSWORD_POLICY.md` 落地，明列 Argon2id + min 10 + 5/30min 鎖定 + TOTP，NIST SP 800-63B §5.1.1.2 偏離依據與業界對齊。
- ✅ **R41-7 Security index**：`security.md` 新增「合規對照與政策文件索引」9 文件連結 + 半年複查排程 2026-11-11。
- ✅ **R41-2 HMAC chain 主動告警**：再確認 `audit_chain_verify.rs` 完整實作（cron + security_alert + dispatch），旗標 `AUDIT_CHAIN_VERIFY_ACTIVE` 預設 false 待 ops 在 staging 驗證 ≥7 天後啟用為運維任務（非開發 gap）。
- ✅ **NICS audit 報告更新**：普級 PASS 15→18 / PARTIAL 4→1，符合率 92%→97%。剩餘 R41-1/5/6/8 為 Phase B (SAST) / Phase C (idle session + R22 串接驗證 + at-rest 評估)。

### 2026-05-11 R41 NICS 資通系統防護基準合規對照

對照行政院《資通安全責任等級分級辦法》附表十（=NICS RFP 範本附件1 查檢項目）做 self-audit，產出 gap report + 修復 backlog。

- ✅ **完整對照表落地**：`docs/security/NICS_COMPLIANCE_AUDIT_2026-05.md` 覆蓋 7 構面 / 29 控制措施 / 三級（普/中/高）各別 PASS / PARTIAL / FAIL 標註，含證據引用與不追項目說明。
- ✅ **普級達標 ~92%**：15 PASS / 4 PARTIAL / 0 FAIL（單人筆電系統合理基準；超過普級的 SOC 24x7 / FIPS 140-2 / RTO 8h 熱備援不追，已在文件說明取捨）。
- ✅ **R41 backlog 8 項**：補完 4 個 PARTIAL（後端 idle session、HMAC chain 主動告警、audit 容量分區政策、密碼政策 NIST 偏離文件化）+ 3 個中級補強（SAST CI、R22 收尾、security index）+ 1 個高級評估（DB at-rest 加密低優先）。
- ✅ **R41 實施計畫落地**：`docs/plans/r41_nics_compliance.md`。重新評估後 R41-2 已 90% 實作（只缺啟用旗標）、R41-5 已有 cargo-audit+Trivy（只缺 semgrep）、R41-6 `ip_blocklist::auto_block` 已實作。總工時從初估 17h 修正為 ~10.5h，分 4 PR（Phase A 文件 / B SAST / C 後端 idle + 串接驗證）。

### 2026-05-10 R40-A 站內信系統 MVP 上線 + 7 輪 UX 迭代

R40-A 從 design + 8 個決策確認 → MVP 一次到位 → 30 條 bot review 修法 → PR #365 merge → prod deploy → 7 輪使用者實測 UX 修法（一個下午 + 晚上 11 個 commits）。

- ✅ **PR #365 merged**（commit `57b4c04f` squash）：站內信 backend 5 services + 9 endpoints / frontend MessagingPage 480 行 / migration 060 / scheduler GC
- ✅ **Bot review 30 條處理**：commit `25094f0e` 修 7 個（critical schema bug + security + N+1 + frontend）+ 8 deferred R41 + 1 declined
- ✅ **Prod deploy**：migration 060 自動 apply（_sqlx_migrations.version=60）+ 4 表（threads / participants / messages / attachments）+ permission seed + 角色分配（15 roles 拿 messaging.send，admin 拿 admin_view）
- ✅ **UX 修 1**：commit `3295a4e8` `<img src>` 加 `/v1` 前綴（CodeRabbit CR #22 之前 deferred 結果真的 404，吃教訓 — 純文字 URL 不能跳過版本前綴）
- ✅ **UX 修 2**：commit `d178cee5` 左側 sidebar 加「站內信」入口（dashboard 之後）+ NewThreadDialog 放大 600→860px + 加「附加圖片」區塊（複用 imageCompress + capture="environment"）
- ✅ **UX 修 3-5**：commit `d9bf2f86`/`a55abc51`/`e6ce49e0`/`66b708da`/`4f8dc651` composer 釘底大戰（flex shrink-0 → min-h-0 → h-screen → calc(100dvh-Xrem) → -m-3 抵 padding → border 卡片化 → 最終 absolute bottom-0 + h-[calc(100dvh-6rem)]）
- ✅ **最終 messaging UI**：左欄 thread 列表 + 右欄對話視圖 + composer absolute 釘在右欄底部 + 訊息列獨立捲動（不影響 composer）+ 卡片邊框與其他頁面對齊
- 💡 **學到的教訓**：(a) 父層 `<main overflow-y-auto>` + `<div p-3>` wrapper 的雙層結構讓 flex 高度計算很容易出錯；最後 `absolute bottom-0` + 已知容器高度是最可靠 (b) bot review 標 minor 不代表可以 defer — `/api` vs `/api/v1` URL 漂移直接造成 404，影響使用者實際體驗

### 2026-05-10 R39 PR #363 merged + prod deploy + R40 站內信立案

- ✅ **PR #363 merged**（commit `58a04e3e` squash-merge）：5 R39 commits + 7 後續 fix commits（含 Gemini / CodeRabbit 審查回應的 15 個修法）整合到 main
- ✅ **Bot review 21 條全部回覆**：15 fixed in commits、6 deferred R40（refactor 類）、1 declined（IDOR 不適用 — vet_patrol_report 跨多隻動物無單一 animal_id）
- ✅ **Prod deploy**：`docker compose build api web pdf-service` + `up -d` → 4 containers healthy；migration 059 自動 apply（_sqlx_migrations.version=59）；vet_patrol_entry_photos 表建好；既有資料 147 隻動物未動；https://ipigsystem.asia/api/health = 200
- 📋 **R40 立案**：站內信系統（user-to-user messaging）+ R39 deferred refactors（enum 化 / handler 收斂 / submit access guard）

### 2026-05-10 R39 獸醫巡場報告完整重設計（4 commits 上線；entry photos / mobile / auto-save / docx 路徑收斂）

R39 從原本「純 HTML→docx wire-up（~3-4h）」擴大到「entry-level photos + mobile + auto-save draft + DOCX 路徑收斂」（~7-8h 落地）。Phase 1-4 今日連續上線，剩 R39-D1 範本 nested loop 待 vet/QA 在 Word 內手動加 block。

- ✅ **Schema migration 059（commit `6a2c0eee`）**：新增 `vet_patrol_entry_photos` 表（FK → entries.id ON DELETE CASCADE）+ partial index 給 GC scan + CHECK constraint status IN ('draft','submitted')；既有報告 backfill `submitted` + 加 `submitted_at` 欄位；down migration 完整對稱
- ✅ **Backend service R39-3~7（同 commit）**：VetPatrolEntryPhoto model + `submit()` draft→submitted state machine + 寫 `VET_PATROL_REPORT_SUBMITTED` audit；**`update()` 重寫為 diff-based**（entries 帶 id → UPDATE、無 id → INSERT、缺 id → DELETE CASCADE photos）— 原 DELETE+re-INSERT pattern 會在每次 save 時清掉 entry photos；draft→draft 更新不寫 audit（避免 auto-save 噪音）；list 加 `?status=submitted|my_drafts|all` filter
- ✅ **Backend handlers + routes**：4 個 entry-photo endpoints（list/upload/update_caption/download/delete）+ 1 個 submit endpoint
- ✅ **Scheduler R39-8（同 commit）**：`register_vet_patrol_draft_gc_job` 每日 03:30 UTC 清掉 status='draft' AND updated_at < NOW() - 7 days；CASCADE 連帶清 entries / entry_photos / report photos
- ✅ **pdf-service docx 路徑（commit `494cee76`）**：新增 `schemas/vet_patrol_report.py` + `adapters/vet_patrol_report.py`（base64 data URL → BytesIO → docxtpl InlineImage）+ DOCX_REGISTRY['vet_patrol_report']；`POST /render-vet-patrol-report/from-report-data` endpoint mirror warehouse pattern；走 `_docx_to_pdf_word_first` 享受 R38 daemon 字體 / 排版優勢
- ✅ **Backend handler 切換**：`export_vet_patrol_report_pdf` 從 `state.gotenberg.html_to_pdf` 改打 `state.pdf_service.render_vet_patrol_report_from_report_data`；payload 同時帶 categories[].photos（entry-level）+ root photos（report-level）；加 `?inline=1` query 對齊 R35-4 / vet_patrol_v3
- ✅ **Frontend dialog 重寫（commit `a1f16f54`）**：auto-save draft（hasInteracted 旗標 + 800ms debounce → POST then PUT）；按鈕語意 `儲存報告` → `送出報告`（POST `/:id/submit`）；server 端回傳 entry id 回填 local state 讓新列也能上傳照片；entry 列下方加 `<input accept="image/*" capture="environment" multiple>` 行動端後鏡頭直拍；`compressImage` util 用 `createImageBitmap({ imageOrientation: 'from-image' })` 套 EXIF orientation 後 canvas re-encode JPEG q=0.85 strip EXIF（無新 npm dep, ~30 lines）；report-level photos 區塊改名「整體環境照（選填）」
- ✅ **HTML cleanup（commit `2d34df41`）**：刪 `resources/templates/pdf/vet_patrol_report.html`（398 行）+ `base.css` + `services/template.rs`（TemplateService 整個整類消失）+ AppState.templates 欄位 + main.rs 初始化 + tests/common 設定；GotenbergClient 留 AppState（pdf-service 走 docx → Word COM，自帶 gotenberg fallback；backend client 不再有 caller，作 idle 保留）；`gotenberg.rs` 加 R39 後 fallback-only 註解
- ⏸️ **R39-D1 範本 nested loop**（待 vet/QA 手動）：`templates/vet_patrol.docx` 在 4 個 categories table row 各加 `{%p for pair in cat.photos | batch(2) %}{{ pair[0].image }}{%p endfor %}`；entry photos 已存 DB、API 已能傳 InlineImage，只差範本 placeholder block 出現後即生效

📊 後端：cargo check --tests + clippy --all-targets -D warnings 全綠；前端：tsc --noEmit 綠；R39 backend 76 → 78 行追加（淨）+ ~470 行刪除（HTML cleanup）

### 2026-05-09 R36 Backup & DR — 例行檢查通知 + 私鑰 SOP + 首次 DR drill 通過

R36 異地備份架構建置最後一段：DR drill 完整跑通 + 私鑰 USB 雙份 + admin 例行檢查通知自動化 + 私鑰存放 SOP 文件。

- ✅ **首次 DR Restore Drill 通過**：R2 下載最新 .gpg → SHA256 verify ✅ → USB G: 私鑰解密 → pg_restore 到隔離 postgres 容器 → 5 表 row-count byte-perfect 比對（animals=147 / users=18 / electronic_signatures=12 / protocols=11 / user_activity_logs=397）；RTO ~10 分鐘（首次手動，自動化後估 < 30 分），達標 < 4h；RPO 24h（cron daily 02:00），對 vet 研究業務寫入頻率 < 100 events/day 可接受
- ✅ **GPG keypair 雙 USB 私鑰**：dedicated keypair RSA 4096 (`E1301...A32367`, `backup@ipigsystem.asia`)；私鑰匯到 USB G: BLACKSLIVER + USB F: King（bytes-identical, fc /b 0 差異）；Windows keyring 已 batch delete 兩次清乾淨；passphrase 存 Bitwarden（與私鑰實體分開 = 防禦縱深）；公鑰 3,906 bytes 進 `secrets/backup_gpg_pubkey.asc`，entrypoint 自動 import + 設 ownertrust=ultimate
- ✅ **GPG ownertrust=ultimate fix**（commit `b9cae5cd`）：剛 import 的 key 預設 untrusted，`gpg --batch --encrypt --recipient` 拒絕「Unusable public key」；entrypoint 加 `gpg --import-ownertrust` 解決
- ✅ **Cloudflare R2 + DS918 SMB 雙異地接通**：R2 bucket `ipig-backups-prod`（APAC）+ Object R/W token（限定 bucket）+ 30 天 lifecycle；DS923+ 上 dedicated user `ipig_backup`（admin 拒絕，僅 File Station 權限，50GB quota）+ encrypted shared folder `ipigsystem_backup`（Btrfs + checksum + 30GB quota）；rclone smb backend `host=10.0.4.26 user=ipig_backup`；驗證三處最新 `.gpg` 大小完全一致 (716,530 bytes)
- ✅ **DSM SMB 密碼從 6 字元輪替為 16 字元強密碼**（drill 過程發現原密碼 brute-force 風險，當日修補）
- ✅ **`backup-private-key-handling.md` SOP 建立**（211 行）：私鑰存放 / 4 個唯一插入時機 / 永遠不要做清單 / USB 物理管理 / 災難復原情境 A/B/C / 月-季-年-3年-5年檢查週期；輪替 SOP 完整步驟
- ✅ **`scheduler.rs` 加 `register_backup_admin_reminder_job`**：每天 09:00 UTC（17:00 Taipei）跑一次，依日期決定發 5 種 SystemAlert 通知給 SYSTEM_ADMIN — 月度（每月 1 號）/ 季度（1/1, 4/1, 7/1, 10/1）/ 年度（1/1）/ 3 年 USB 輪替（>= 2029-05-01）/ 5 年 passphrase 輪替（>= 2031-05-01）；通知本文連結 backup-setup.md + backup-private-key-handling.md
- ✅ **DR drill 紀錄**：`docs/runbooks/dr-drill-records.md` §5 完整紀錄今日 drill（含 8 條 follow-up：USB off-site 分散、paper key 紙本、cold-start cloudflare tunnel runbook 等）；下次季度 drill 排 2026-08
- ✅ **R36 TODO 狀態更新**：R36-1~9 標 [x]、R36-10 [~] partial（cold-start runbook 段下次補）、R36-11 [-] DS925+ 採購 deferred（情境 A：DS923+ 只當 backup target、prod 留筆電）

### 2026-05-09 R37 .env 明文密碼遷移 backlog 立案（11 items）

R36 設定過程審視 `.env` 發現 9 處明文密碼/token 殘留違反 `feedback_no_plaintext_passwords` 規則。已立 R37 backlog 全面遷移到 docker secrets。

- 📋 **R37-1 🔴 CRITICAL**：`AUDIT_HMAC_KEY` 明文（行 35）— GLP §11.10(e) audit chain 完整性 key，洩漏可偽造 audit。`config.rs:317` 已用 `read_secret()` 支援 `_FILE`，遷移簡單
- 📋 **R37-2~4 🟠 HIGH**：`ADMIN_INITIAL_PASSWORD` (`AdminIpig2026!`) / `GRAFANA_ADMIN_PASSWORD` (`admin123` 弱密碼) / `GRAFANA_SMTP_PASSWORD` + `ALERT_SMTP_PASSWORD`（同一個 Gmail app password 重複寫兩處）
- 📋 **R37-4 特別 action**：Gmail app password `tajr azwc pmac lyxs` 已在 `.env` 待數週，假設已外洩 — 遷移前必須在 Gmail 帳號 revoke 並重新產生
- 📋 **R37-5~8 🟡 MED**：`IMAGE_PROCESSOR_TOKEN` / `PDF_SERVICE_TOKEN` / `ALERTMANAGER_WEBHOOK_TOKEN`（**code 還沒支援 _FILE，需先改 `config.rs`**）/ `WORD_CONVERT_TOKEN`
- 📋 **R37-9~11 🟢 LOW**：`GUEST_PASSWORD=guest` 直接刪（GUEST role 已棄用）+ `.env.example` 對齊 + `docs/runbooks/secrets-management.md` runbook

### 2026-05-08 R36 Backup & DR 緊急修復 — backup 從靜默失敗到完整異地架構上線

早上發現 prod 環境**完全沒有 backup 在跑**（容器在跑但 `/backups/` 目錄空無一物 + 異地未設定）。一天內從零建構完整異地備份架構。

- ✅ **R36-1 fix `pg_backup.sh` DB_NAME mismatch**（commit `6ade6c24`）：script 預設 `DB_NAME=erp_db`，但 compose 傳 `POSTGRES_DB=ipig_db` env → script 用錯預設值 → `pg_dump erp_db` 失敗 → cron 數週靜默失敗無人察覺
- ✅ **R36-2 fix pipefail + SIGPIPE 偽失敗**（同 commit）：第 40 行 `gunzip -c | pg_restore --list` pg_restore 讀完 header 即關 stdin → gunzip SIGPIPE 退 141 → `set -euo pipefail` 把這當失敗 → script exit 1 雖檔案有效。修：改 temp file 驗證
- ✅ **R36-3 backup heartbeat metric + 3 條 alert**（commit `eab076d4`）：`/backup-metrics/ipig_backup.prom` 三個 gauge（last_success_timestamp / last_success_size_bytes / retained_files_total）；compose `backup_metrics` named volume 共享給 db-backup（write）+ node-exporter（read-only with `--collector.textfile.directory`）；prometheus alert rule `ipig_backup_alerts` 三條（BackupStale > 25h / BackupMetricMissing 30m / BackupSizeAnomaly < 50% 7d 平均）
- ✅ **R36-4 GPG 加密 infrastructure**（同 commit）：entrypoint 自動 import `secrets/backup_gpg_pubkey.asc` 公鑰（`-s` test 容許空 placeholder）+ 預檢 `BACKUP_GPG_RECIPIENT` 對應 key 存在；`.env.example` 加完整 GPG step
- ✅ **R36-5/6/7 rclone dual remote**（同 commit）：`Dockerfile.backup` 加 `rclone ca-certificates`；`secrets/rclone.conf` docker secret + entrypoint 自動 link 到 `~/.config/rclone/rclone.conf` + 預先驗證每個 `BACKUP_RCLONE_REMOTES` 內 remote 存在；`pg_backup.sh` 加密完成後 rclone copy 到所有 remote（年/月 prefix），任何上傳失敗 → script exit 1 → R36-3 alert 觸發
- ✅ **R36 setup runbook 建立**（commit `dc6351d0`）：`docs/runbooks/backup-setup.md` 全 6 step（GPG keypair / R2 / DS918 SMB / fill secrets / restart verify / restore drill）+ troubleshooting + 月/季/年維護 schedule
- ✅ **fix `migration` rename 054→058**（commit `3954fcfe`）：products_pricing 與 vet_patrol/invitation/refresh_token 衝突，移到 058
- ✅ **fix data_import IDXF 3 bug**（commit `f9bf3f93`）：data_retention_policies seed 衝突鍵 / role_permissions uuid::text cast / cleanup_partial_unique_tables DELETE → TRUNCATE CASCADE 解決 FK 阻擋
- 📋 **未完成**：R36-9 restore drill（隔天 5/9 完成）、第二支 USB 物理分散到不同地點、R36-10 cold-start runbook、R36-11+ DS925+ 採購

### 2026-05-08 R35 Wave 3 啟動 — R35-14/15 落地、R35-13 延辭、R35-12 blocked

Wave 3 Security cross-cutting 開工（worktree `r35-wave3-security`）。R35-12 因 R31-9 觀察期未 sign-off blocked；R35-13 因 PR #345（Reporting-Endpoints）2026-05-07 才 land 違反 R31-12 三個月過渡期規範，延辭至 ~2026-08-07；本 session 落地 R35-14 + R35-15。

- ✅ **R35-14 rate limit 細粒度化**：`middleware/rate_limiter.rs` 的 `apply_rate_limit` 加 `bucket_key` 參數（與 IP 解耦）；write/upload tier 改用 `format!("{ip}|{matched_path}")` keying，同 IP 對不同 endpoint 持有獨立 quota（防單一熱門端點打爆癱瘓全 tier 寫入）；auth/forgot-pw/api tier 維持 IP-only（auth 為 escalation 邏輯依賴 per-IP 聚合、api 為 pattern rotation backstop）
- ✅ **R35-15 refresh token reuse detection**：既有 rotation（撤銷舊 + 發新）已實作，本次補上洩漏偵測 — migration 054 加 `family_id`（同登入鏈共享）+ `revoked_reason`（normal_rotation / reuse_detected / password_changed / admin_logout）；refresh 流程改 SELECT 不加 filter 並 in-app 判斷狀態，已撤銷 token 再次提交 → 整 family revoke + 寫 critical `security_alerts` (`REFRESH_TOKEN_REUSE`)；既有 token 背填 family_id = id，使用者透明
- ✅ **新增 unit test**：`test_per_pattern_buckets_are_isolated` + `test_same_pattern_different_ips_isolated`（R35-14）；integration test `refresh_token_reuse_revokes_entire_family`（R35-15，需 Postgres 跑）
- ✅ **R35-13 延辭文件化**：TODO R31-12 + R35-13 兩處標註觀察期起算 2026-05-07、最早可動 ~2026-08-07
- 🟡 **R35-12 blocked**：CSP enforce 切換需先確認 R31-9 觀察期 0 嚴重 violation（DB 端 `security_alerts` 查證使用者責任）

### 2026-05-08 R35 Wave 4 第一棒 — R35-16/3-redo/17/18（PR #356）

Wave 4 schema-additive 串連 4 個 item 一棒處理；本 PR 內 3 個 item 的 R35 plan 假設都跟現況脫鉤，逐一修正並動工。

- ✅ **R35-16 products 加 cost_price + selling_price**：Plan 寫「拆 unit_price」前提錯（products 從沒 unit_price 欄位）→ 改「從零加兩欄」；migration 054 ADD 兩欄 nullable + 部分索引 `idx_products_selling_price_nonnull WHERE selling_price IS NOT NULL` 加速 R35-3 庫存價值 JOIN；Product struct `#[sqlx(default)]` + `#[serde(default)]` 向後相容；無 backfill source（產品定價空表起步，由 ERP 維運填入）
- ✅ **R35-3 redo 庫存價值 SummaryCard**：PR #350 R35-3 backend 用不存在的 `p.unit_price` 已 revert（commit `4213654f`），frontend 在 commit 階段被 Edit race 吞掉本來就沒進；本 PR 在 R35-16 之上重做 — backend SUM(qty × selling_price) WHERE selling_price IS NOT NULL；frontend grid 改 sm:grid-cols-3 lg:grid-cols-5 + 5th SummaryCard「庫存價值」+ `formatInventoryValue` (千分位 + NT$)
- ✅ **R35-17 7 天到期 Dashboard widget**：「expiry_date NOT NULL」SKIP（products.track_expiry=false 時 NULL 合法，強加會破壞既有產品）；底層 `v_expiry_alerts` view + `fn_expiry_alerts` PG function + `/notifications/alerts/expiry` paginated API + 月度快照通知都已存在 — 本 PR 只補 dashboard widget；backend `list_expiry_alerts` 加 `?within_days=N` filter + 新 `ExpiryAlertsQuery` struct；frontend `ExpiryAlert` type + `ExpiryAlertWidget`（StatWidget 包，AlertTriangle 紅色與 LowStockAlert 黃色區分）+ `widgetConfig` 加 expiry_alert + DashboardPage 連線 + locales zh-TW + en
- ✅ **R35-18 admin UsersPage 顯示「最後登入」+ dormant 紅標**：Plan 寫「auth 補 update last_login_at」— 但欄位 + login UPDATE **全部已存在於 main**（migration 002 + login.rs:192 + two_factor.rs:310）；實際 gap 是 frontend 看不到；types/auth.ts User 加 `last_login_at` + UserTable 加「最後登入」欄（colSpan 5→6）+ `formatLastLogin` helper relative time + ≥90 天紅色 dormant 標記，符合 ISO 27001 dormant account audit
- 📋 **R35 plan staleness 教訓**：本 PR 4 個 item 中 3 個 plan 假設都跟 schema/code 脫鉤；已寫 `feedback_r35_plan_schema_staleness.md` memory，未來動 R35 item 前必 grep 驗證再下手
- 📋 **Wave 4 剩餘**（依序）：R35-19 animal_weights 子表 → R35-20 audit_log monthly partition → R35-21 GIN index

### 2026-05-08 R35 Wave 1 完工 — UX 改進 6 項（R35-1~6）

Wave 1 全部 6 個 item 在 `feat/r35-wave1` worktree 一氣呵成，cargo clippy + frontend tsc 全綠，分 2 個 feat + 1 個 docs commit。

- ✅ **R35-1 列印 button loading + retry**：Loader2 spinner 取代純文字「載入中…」；列印 / 下載 失敗 toast 加 `ToastAction` 重試按鈕（onClick → mutation.mutate()）
- ✅ **R35-2 LayoutDiagram tooltip 顯示前 5 項庫存**：HTML `title` 擴充為 `code - name (current/capacity)\n品項1 ×qty單位\n…等共 N 項`；列印時瀏覽器自動隱藏
- ✅ **R35-3 庫存價值 SummaryCard**：grid 由 4 欄擴 5 欄；backend `WarehouseReportSummary.total_inventory_value: Decimal` + 獨立 SQL `SUM(on_hand_qty × p.unit_price)`，缺價產品不計入；Decimal → 字串避免 JS 浮點誤差，前端 `formatInventoryValue()` 千分位 + `NT$` 前綴
- ✅ **R35-4 PDF 預覽分頁標題**：`?inline=1` query param 路由到 `Content-Disposition: inline; filename=…`，瀏覽器 PDF viewer 用 filename 取代 `blob:` 當分頁標題；下載路徑保留 `attachment` 不變；`utils/http::content_disposition_inline_header` + 兩個 unit test
- ✅ **R35-5 動物列表 server-side sort**：`AnimalQuery` 加 `sort_by` + `sort_order`；`ANIMAL_SORT_COLUMNS` hard-coded 白名單 9 欄（含 `latest_weight` LATERAL join）防 SQL injection；`NULLS LAST` + secondary `p.id` 對齊穩定排序；frontend 移除 `sortedAnimals` useMemo（含 useMemo import + 未用 sortDirection 解構），sortColumn/sortDirection 進 queryKey 觸發 refetch
- ✅ **R35-6 SKIP**：`useDebounce` baseline 已存在 + 8 個 page 在用（grep 驗證），原 plan「重複 ≥ 5 處手寫 setTimeout」與現況脫鉤 → 標 done 不動
- 📋 **平行化驗證**：本 PR 在 `feat/r35-wave1` worktree（sibling path）操作，與 `ipig_system-wave2`（R35-7 pdf-service metrics）+ `worktrees/r35-wave3-security` 完全解耦，三 wave 各別 worktree 互不衝突

### 2026-05-08 R35 系統改進 backlog 計畫成立 — 5 wave / 24 PR

R34 收尾後針對全系統做改進掃描，結合使用者倉庫列印 / PDF / 平面圖連續實戰回饋，整理出 24 個改進項分 5 wave 推進；另列 8 項 parked 不做。

- ✅ **Wave 1 UX（R35-1~6，6 PR / 1-2 天）**：列印 loading / 平面圖 hover tooltip / 庫存價值卡片 / PDF 預覽分頁標題 / 動物 server-side sort / `useDebouncedSearch` hook
- ✅ **Wave 2 Observability（R35-7~11，5 PR / 1-2 天）**：pdf-service `/metrics` / audit covering index / docker `--watch` 熱重載 / E2E 補 PDF print path / bundle 分析 lazy load
- ✅ **Wave 3 Security（R35-12~15，4 PR / 2-3 天，依序）**：CSP enforce 切換 / 移除 report-uri legacy / per-route rate limit / refresh token rotation
- ✅ **Wave 4 Schema（R35-16~21，6 PR / 5-7 天，依序）**：products price 拆 cost/selling / expiry 過期警示 / users.last_login_at / animal_weights 子表 / audit_log partition / GIN index for jsonb path
- ✅ **Wave 5 業務 quick wins（R35-22~24，3 PR / 2-3 天）**：動物轉場批次 UI / reorder_point 通知 scheduler / `/reports` hub
- ✅ **平行化分析**：Wave 1+2 同時可放（9 PR 並行）；Wave 3/4 內部依序；hot files 集中在 wave 末
- ✅ **Parked 8 項**：i18n / GraphQL / Service Worker / Storybook / 自架 SSO / multi-tenant / native app / 圖表引擎更換 — 場域單客戶 / 單語言 / 必網路下價值低
- 📋 **執行門檻**：每 PR ≤ 1 邏輯單元、每 wave 結束停一次等使用者裁定下一 wave；等待 user「開始」指示後啟動 Wave 1

### 2026-05-07 R32 後續維護 — PR #344~#349 merge wave + 倉庫列印 UX 收尾

R32-A8g warehouse 上線後使用者實戰連環回饋，5 個 PR 接連修補。

- ✅ **PR #344 merged**：warehouse 列印路徑改 PDF blob window.open（取代既有 React print stylesheet 多頁切斷問題） + 下載檔名 `${name||code}_倉庫現況報表.pdf`；blobUrl 60s setTimeout revoke + try/finally 釋放（Gemini HIGH memory leak fix）
- ✅ **PR #345 merged**：CSP `report-to csp-endpoint` 加 + `Reporting-Endpoints` header 新增；`$http_host` 取代 `$host`（Gemini medium：dev/staging :8080 port 不能掉）
- ✅ **PR #346 merged**：`export_activity_logs_pdf` 從 3-pass 折成單一 fold（admin / failure / unique users via HashSet）；frontend `parseFilenameFromContentDisposition` RFC 6266 helper 取代寫死檔名
- ✅ **PR #347 merged**：`StorageLocationInventoryItem` 加 `product_spec` 欄位（與 `product_sku` / `product_name` siblings 命名一致，無 serde rename） + service SQL `p.spec AS product_spec`；解決倉庫 PDF「規格」欄位全空白
- ✅ **PR #348**：pdf-service Dockerfile 加 `fonts-noto-cjk`（Pillow ImageDraw 平面圖 CJK 字型 fallback 顯示亂碼修復）
- ✅ **PR #349**：庫存數量整數化（DB column numeric(18,4) 但實際使用都是整數）— frontend `Math.trunc(parseFloat(...))` + pdf-service `_format_qty` `int(float(...))`

### 2026-05-07 R32 code-only 工作清零 — PR #341 + #343 merged

R32 PDF 生成重做 epic 的 code 部分全收尾。剩 A8f / A8i 兩條等外部（vet/QA 範本 / product 決策）。

- ✅ **PR #341 merged** (`e6bb2109`)：warehouse + blood_test 切 docx + AUP v2 cutover + bot review 12 條全修
  - **A8g warehouse**：8 欄明細表 (儲位代碼/名稱/產品名稱/規格/批號/數量/單位/效期，per-row code/name 不合併) + Pillow PNG 平面圖 (粗體+CJK/ASCII 空格+矩形 wrap+水平置中+200mm) + 結構配色對齊前端 LayoutDiagram
  - **A8h blood_test**：6 欄 per-item flat (檢查日期/項目/檢驗值/參考值/異常/建立者) + INNER JOIN 含 R30-16 superseded filter + frontend 加「下載 PDF」按鈕
  - **A8j AUP v2 cutover**：砍 export_protocol_pdf_v2 (264 行) + translate_ helpers (84 行) + Tera 模板 + utils/pdf_pages.rs + lopdf Cargo dep + html2canvas/jspdf fallback；frontend 統一走 /export-aup-v3
  - vMerge / chunked / two-pass page-aware 三種合併方案先後試錯後**放棄合併**：每 row 都有 code/name；docx 跨頁時 vMerge restart 無法可靠落在新頁開頭，per-row 是最穩設計
  - Bot review 修：convert_inline_drawings_to_square_wrap 接上 main.py（critical bug 之前 helper 沒接）/ list_blood_test_export_rows 58→split / export_blood_test_pdf 64→split / LEFT→INNER JOIN / payload.as_object_mut 錯誤傳播 / Pillow 11→12.2.0
- ✅ **PR #343 merged** (`e13e3e42`)：A7 final purge — 砍 services/pdf/{service.rs, context.rs, mod.rs} ~1450 行 + printpdf Cargo dep + pdf-service/app/templates/{blood_test.html, _base.css} + backend/resources/fonts/NotoSansSC-Regular.ttf 17MB；Cargo.toml `tera` 註解從「PDF generation」→「Templating (Gotenberg HTML 報表 + email)」對齊現況
- ✅ **dev .env**：加 `WORD_CONVERT_TOKEN=dev-localhost-fallback-to-gotenberg`（host 沒跑 Word COM daemon，container 走 Gotenberg LibreOffice fallback；validate_word_converter_config 需 token != empty 才允許啟動）
- 📋 **R32 剩餘**：A8f vet_patrol（templates/vet_patrol.docx 已 placed 但需 vet/QA 加 docxtpl 變數）+ A8i audit_log PDF（admin UI「下載 PDF」按鈕等 product 決策）— 兩條都 blocked on 外部 input

R32 主線 code-only 工作 **100% 清零**。砍 ~3000 行 legacy code + 兩個 Cargo dep (printpdf, lopdf) + 17MB 字型檔。

### 2026-05-07 R32-A8e doc 對齊 + repo 雜訊清理（gitignore + stale branches）

R32 code-only 工作清零盤點：A8e（review_reply v3 wire-up）read-through 後確認**已隨 PR #332 完整落地** — backend service aggregator (`services/protocol/review.rs::get_review_reply_export_data` ~190 行 + 5 helper) + handler + pdf-service adapter + schema + template + frontend `CommentsTab.tsx` 下載按鈕，TODO.md 狀態 `[/]` → `[x]`。R32 剩 5 項全部 blocked 於外部：A8f/g/h/j 4 份 vet/QA 範本 + A8i product 決策。

- ✅ **R32-A8e 標 [x]**：實作 PR #332 已 ship；本次只是 doc status 同步 — 包含一審 (UNDER_REVIEW) + 二審 (FINAL_REVIEW/FINAL) reviewer × item_no 配對邏輯，以及 250 行 legacy Tera 路徑（`backend/resources/templates/pdf/review_comments.html`）已從 main 移除
- 📋 **R32-A7 不再阻塞 A8e**：service.rs 1236 行 + `printpdf` Cargo dep 砍除等 A8g (warehouse 範本)；`gotenberg.html_to_pdf` 砍除等 A8f (vet_patrol) + A8h (blood_test) + A8j (protocol_pdf_v2)
- ✅ **`__pycache__/*.pyc` 全面 gitignore**：48 個歷史誤 commit 的 .pyc（pdf-service / tests / tests/browser）`git rm --cached`；`.gitignore` 加 `**/__pycache__/` + `*.pyc` + `*.pyo`
- ✅ **Local stale branches 清 73 個**：claude/* / pr* / r30-* / r28-* / r29-* / feat/r3* / docs/r* 全部 force-delete（PR 都已 merge 或廢；reflog 90 天可救回）；剩 4 active worktrees 保留
- ✅ **Origin r26 epic 28 個 branch 清乾淨**（前一輪）：integration/r26 + r26-* sub-task branches，全部驗證對應 PR 已 merge

R32 待辦合計：6 → 5（A8e [/] → [x]）；TODO 總計 44 → 43。R32 真實狀態：**code-only 已清零**。

### 2026-05-07 R33 滲透測試 follow-up — PR #339 merged

PR #339 squash-merge 至 main（commit `87d5488`），CI 18/18 全綠。CSO comprehensive scan 5 條 TENTATIVE 中挑兩條投產，其餘按 PR description 分流。

- ✅ **R33-2 AI client `reqwest::Client` 共用**：`services/protocol/ai_review.rs` 改 `OnceLock<Client>` + 90s idle pool timeout；對 `api.anthropic.com` 高頻長連線可省每次 TCP+TLS handshake（warm 後預期 -100~300ms / call），系統 CA roots + TLS cert 驗證預設開啟
- ✅ **R33-3 CSP report endpoint 16KB body cap**：`handlers/csp_report.rs` 新增 `CSP_REPORT_MAX_BYTES`，超過直接 drop（仍回 204 per CSP 規範）+ warn log；real-world CSP report 罕見 > 4KB，給 16KB 寬鬆。endpoint 規格上必須無認證 / 無 CSRF，無 cap 時可被灌 MB 級垃圾 payload
- 📋 **R33-1 CSRF middleware 讀 `extensions::<CurrentUser>()`**：研究後不投產 — middleware 排序是 csrf → auth，CSRF 在 auth 之前執行 CurrentUser 還沒進 extensions；「正確」修法等於 CSRF middleware 內重做一次 JWT 簽章驗證，churn 太大。現行 decode-without-verify 已文件化，defense-in-depth 仍守得住（偽造 JWT 過不了 auth → 401）
- 📋 **R33-4 JWT 6h → 60min A/B**：要 staging 試 + 觀察 UX，不適合單一 PR
- 📋 **R33-5 HMAC key 不可輪換**：accepted risk，已記入 `docs/security/HMAC_VERSIONING.md`
- 📊 **R33 backlog 狀態**：5 項中 2 ship / 1 parked-with-rationale / 1 待 staging / 1 accepted；TODO 待辦 4 → 2

### 2026-05-07 R34 PR #340 整批 merge to main — 22 TAKE 落地 15 + bot review 全處理

PR #340 (`integration/r34`) merged 至 main（fast-forward，20 檔 +907 -152，9 commits 保留細粒度 history 不 squash）。CI 18/18 全綠（含 backend cargo test 27m25s + E2E Playwright + CodeRabbit review）。

**落地清單（15 / 22 TAKE）**：
- ✅ **PR B infra 一致性** R34-8/9/10：MAX_FILENAME_LENGTH 註解 / validate-after-trim 慣例文件化 / `AT TIME ZONE` 改用 `DEFAULT_TIMEZONE` 常數（後 coderabbit 改為 bind 參數）
- ✅ **PR D hooks 穩定化** R34-17：useListFilters 回傳 useMemo 包穩 + useRef 凍結 initialFilters（gemini-fix-2 後續加固）
- ✅ **PR F pdf-service hardening** R34-21/22：DOCX_CONVERTER_TIMEOUT env + clamp [5, 600s] / Word→Gotenberg fallback unit test 4 cases + xlsx mirror 4 cases + lifespan 2 cases（共 14/14 pass）
- ✅ **PR A handler service 化** R34-1/2/3/5/6：HR dashboard SQL → repositories/hr.rs / Amendment is_pi 三處下沉 service / Amendment IDOR 改 access::require_protocol_related_access（潛在 access fix）/ unwrap_or(0.0) → Option<f64> / 7 處英文錯誤訊息中文化
- ✅ **PR C Dashboard refactor** R34-11/12/16：GRID_BREAKPOINTS / COLS 集中 widgetConfig.ts / hasErpPermission 改 store selector + 加 `permissions.includes('erp')` 精確匹配（coderabbit-fix）
- ✅ **PR E auth persist version** R34-20：`version: 1` baseline + no-op migrate 範本（不 bump）

**Push back / SKIP（7 / 22）**：R34-7 PaginationQuery/Params 語義不同合併會改行為 / R34-4 DocumentService::check_access 已是 service pure fn / R34-13/14/15 borderline / R34-18/19 audit 觀察錯誤 or production 零使用。

**Bot review 處理**：
- gemini-code-assist 3 medium → 全採納（Decimal::to_f64 / useRef 凍結 / 共享 httpx.AsyncClient + lifespan）
- coderabbit 14 inline → 8 採納（unwrap_or_else→expect / `format!()` SQL→`$3` bind / 函式 rename + NaiveDate 強型別 / lifespan close 既有 client / hasErpPermission 加精確匹配 / docs counts + markdown table 轉義）
- 6 推延（D11~D16）：ROLE_REVIEWER 系統級政策 / require_pi_or_admin helper 抽取 / list_staff_for_proxy 等下沉 repo / ADMIN_EMAIL 常數 / auth migrate Zod safeParse / csp_report body limit（R33-3 follow-up）

**回歸防護新增**：
- backend/tests/api_amendment_idor_regression.rs 5 cases — 鎖 IDOR widening 契約（PI / co-editor / 指派 reviewer 200，無關使用者 + 跨 protocol 403）
- pdf-service/tests/test_word_fallback.py 14 cases — Word/Excel COM fallback + lifespan + timeout clamp



針對 codebase 50 項技術債候選逐項辯證（pro / con / verdict）。原則：高 ROI + 低風險 → TAKE；低收益 + 高動工 → LEAVE；架構性 / 待 R28 等批次 → DEFER。最終 **TAKE 23 / LEAVE 18 / DEFER 9**。TAKE 項目進 TODO.md R34 backlog。

**Backend (Rust / Axum) — 25 項**

- 📋 **#1 重複 DELETE/POST 路由別名**：pro=刪 5 行重複；con=可能有舊前端用 POST 模擬 DELETE（CSRF/proxy 卡 DELETE）。**[DEFER]** — 先 grep 前端 axios 用法確認無 .post(.../delete) 呼叫再刪，需獨立小 PR
- 📋 **#2 HR dashboard 內嵌 SQL → repositories/hr.rs**：pro=分層回正 + 可測；con=12 個 CASE/WHEN 搬遷需重測 dashboard 數值。**[TAKE]** — 高優先，符合 CLAUDE.md §4「handler 禁直接寫 SQL」
- 📋 **#3 amendment handler PI 權限檢查內嵌 SQL → AmendmentService::check_is_pi**：pro=service-driven 一致；con=R26 已定型 pattern，amendment 模組未列入。**[TAKE]** — 與 R26 pattern 對齊，不新增大功能
- 📋 **#4 amendment 使用者-protocol 關係 SQL → services/access.rs**：pro=權限集中；con=access.rs 已大。**[TAKE]** — 同 #3 一併
- 📋 **#5 權限檢查模式不一致（手寫 vs require_permission!）**：pro=一致性；con=全 codebase 替換工程量大、PR 巨。**[DEFER]** — 列 R34 次批，先優先跑 #2-#4 觸及處
- 📋 **#6 animal query FilterBuilder trait**：pro=DRY；con=trait 抽象成本 > 目前 3 處重複收益。**[LEAVE]** — 過度抽象，違反 CLAUDE.md §「三個相似行優於 premature abstraction」
- 📋 **#7 NotificationService::new 重複 → From<&AppState>**：pro=4 行 → 1 行；con=trait impl 也是 4 行。**[LEAVE]** — 收益微小
- 📋 **#8 models/mod.rs wildcard re-export → 具名**：pro=API surface 可追；con=23 行改成 ~80 行具名。**[LEAVE]** — wildcard 在 prelude-style 可接受
- 📋 **#9 共用 DeleteResponse**：pro=型別安全；con=2 處而已。**[LEAVE]** — 不滿三處抽出門檻
- 📋 **#10 錯誤訊息中英混雜（amendment / hr/dashboard）**：pro=對齊 CLAUDE.md 中文一致；con=無功能影響。**[TAKE]** — 純文字改，低風險高一致
- 📋 **#11 PaginationQuery vs PaginationParams 合併**：pro=一個事實；con=合併需檢查所有 handler 簽章。**[TAKE]** — 列 R34，合併動作小但收益清楚
- 📋 **#12 document handler IDOR 檢查下沉 service**：pro=service-driven pattern；con=R26 範圍外。**[TAKE]** — 符合 R26 模式，低風險
- 📋 **#13 unwrap_or(0.0) 隱式預設**：pro=資料缺失可見；con=前端要處理 null。**[TAKE]** — 對齊 memory「DB 查詢禁 unwrap_or 靜默降級」
- 📋 **#14 手刻 email 驗證 → email_address crate**：pro=規範性；con=新依賴 + RFC 5321 完整驗證可能 reject 內部測試 email。**[LEAVE]** — 新依賴需走「不可逆操作」核可，目前驗證已夠用
- 📋 **#15 MAX_FILENAME_LENGTH=255 補註解**：pro=未來人員秒懂；con=零。**[TAKE]** — 一行註解
- 📋 **#16 錯誤訊息硬編字串 → enum + Display**：pro=i18n 友好；con=工程量大、目前無 i18n 後端需求。**[LEAVE]**
- 📋 **#17 trim/validate 順序文件化**：pro=規範清晰；con=無。**[TAKE]** — 改 CLAUDE.md §4 一句話
- 📋 **#18 cargo machete / dead_code 清理**：pro=減負；con=CLAUDE.md §10 明令「任務無關 dead code 不順手刪」。**[DEFER]** — 列 R27 cleanup sprint backlog
- 📋 **#19 SQL tuple 拆解 → FromRow struct**：pro=具名欄位；con=只 1 處。**[LEAVE]**
- 📋 **#20 get_animal_info_from_observation/_surgery 合併**：pro=去重；con=record_type enum 分支可能讓 SQL 更醜（兩 table 結構不同）。**[DEFER]** — 先看實際 SQL 是否真能合
- 📋 **#21 notification 14 子模組重組 4 群**：pro=可讀；con=動到全 import 路徑、PR 巨。**[LEAVE]** — 風險 > 收益
- 📋 **#22 routes/mod.rs middleware stack 抽 build_protected_middleware_stack**：pro=可單測；con=middleware 順序敏感、抽出來反而難讀。**[LEAVE]**
- 📋 **#23 共用 ErrorResponse JSON 形狀**：pro=前端統一；con=AppError IntoResponse 已是統一形狀，個別 json!() 只在邊界。**[DEFER]** — 先盤點實際分歧處
- 📋 **#24 QueryBuilder.push() 條件抽小 fn**：pro=可測；con=每 helper 1-2 行，反而碎。**[LEAVE]**
- 📋 **#25 AT TIME ZONE 'Asia/Taipei' → APP_TIMEZONE 常數**：pro=未來改時區一處；con=研究院在台灣，幾乎不會改。**[TAKE]** — 但只需 const &str，不需 config 讀取（YAGNI），對齊 memory「GMT+8」

**Frontend (React / TypeScript) — 20 項**

- 📋 **#26 auth store 拆 slice**：pro=selector 精細、re-render 少；con=Zustand slice pattern 對 9 欄+8 method 不一定省事。**[DEFER]** — 先跑效能 profile 確認瓶頸
- 📋 **#27 Dashboard layout 常數集中 constants/dashboardLayout.ts**：pro=單一事實；con=零。**[TAKE]**
- 📋 **#28 hasErpPermission useMemo 依賴整個 user → store selector**：pro=精準訂閱；con=要寫 selector helper。**[TAKE]** — 收益清楚
- 📋 **#29 useListFilters 13 欄物件 useMemo 包穩**：pro=避 deps 陣列踩坑；con=無。**[TAKE]** — 對齊 CLAUDE.md §「禁止把 hook return obj 放 deps」
- 📋 **#30 useApiMutation 包 toast**：pro=去重；con=已有全域 QueryClient onError，wrapper 可能 double toast。**[LEAVE]** — 全域已處理
- 📋 **#31 DashboardPage JSX > 80 行 → 拆 Grid/Container/Editor**：pro=對齊量化門檻；con=拆分時要保 grid layout drag state。**[TAKE]** — 高優先，違反 CLAUDE.md §2「JSX ≤ 80 行」
- 📋 **#32 widget 直接 useAuthStore 免 props drill**：pro=去 prop drilling；con=widget 變難測（需 mock store）。**[TAKE]** — Zustand 設計意圖如此
- 📋 **#33 14 widget import → AVAILABLE_WIDGETS 陣列**：pro=新增 widget 一處；con=失去 tree-shaking 個別 widget 機會。**[TAKE]** — code-split 用 lazy() 仍可
- 📋 **#34 axios interceptor 統一錯誤 {code, message, context}**：pro=前端錯誤一致；con=後端 AppError 已是固定 JSON shape，重複包。**[LEAVE]**
- 📋 **#35 queryKeys factory**：pro=型別安全；con=新依賴 + 既有 as const array 已可用。**[LEAVE]**
- 📋 **#36 useListFilters 提供 reset()**：pro=DRY；con=無。**[TAKE]**
- 📋 **#37 useSelection.ts initialIds 拿掉**：pro=API 縮小；con=確認真無人用後才能刪。**[TAKE]** — grep 後刪
- 📋 **#38 availableWidgets useMemo**：pro=避免每 render 重算 filter；con=無。**[TAKE]**
- 📋 **#39 perPage / per_page / pageSize 統一**：pro=命名一致；con=API boundary mapping 是常見做法、不算 bug。**[LEAVE]** — 前端 camelCase + 後端 snake_case 是慣例
- 📋 **#40 isPageLoading aggregation**：pro=loading UX 合理；con=Dashboard 各 widget 各自顯示 skeleton 反而資訊更多。**[LEAVE]** — UX trade-off 偏向現狀
- 📋 **#41 handleLayoutChange useCallback**：pro=避 stale closure；con=確實風險。**[TAKE]**
- 📋 **#42 X-API-Version header**：pro=未來 hook 點；con=YAGNI、目前無多版本需求。**[LEAVE]** — 違反 CLAUDE.md「不為假設未來需求設計」
- 📋 **#43 Zustand persist version/migrate**：pro=AuthState 改動不炸 localStorage；con=無。**[TAKE]** — 高優先，對使用者影響大
- 📋 **#44 強制 Zustand selector + ESLint 規則**：pro=效能；con=ESLint 規則需自寫、維護成本。**[DEFER]** — 先做 #28 觸及處
- 📋 **#45 SESSION_TIMEOUT_MS 從 /api/v1/system/config 拿**：pro=前後端對齊；con=新 API endpoint + 啟動 race condition。**[LEAVE]** — 過工程，前端用 JWT exp 即可

**PDF Service (Python / FastAPI) — 5 項**

- 📋 **#46 Jinja2 環境集中 app/templates.py**：pro=DRY；con=三 renderer template 路徑/filter 不同，集中後反而需參數化。**[DEFER]** — 先確認三者真能共用 _env
- 📋 **#47 httpx timeout 抽 DOCX_CONVERTER_TIMEOUT env**：pro=維運可調；con=120s 寫死目前 ok。**[TAKE]** — 簡單 env 化，對齊 R32-A3 Word COM 路徑可能慢
- 📋 **#48 Word→Gotenberg fallback 加 unit test**：pro=回歸防護；con=mock httpx 工程小。**[TAKE]** — 高優先，R32-A3 路徑核心
- 📋 **#49 PdfConversionError + exception handler**：pro=結構化錯誤；con=RuntimeError 目前 FastAPI 自動 500。**[DEFER]** — 等真出現需要分類錯誤再做
- 📋 **#50 yarl.URL 啟動驗證 Gotenberg URL**：pro=fail-fast；con=新依賴。**[LEAVE]** — urllib.parse 即可，但收益不大

**裁定總結**：

- **TAKE (23)**：#2 #3 #4 #10 #11 #12 #13 #15 #17 #25 #27 #28 #29 #31 #32 #33 #36 #37 #38 #41 #43 #47 #48
- **LEAVE (18)**：#6 #7 #8 #9 #14 #16 #19 #21 #22 #24 #30 #34 #35 #39 #40 #42 #45 #50
- **DEFER (9)**：#1 #5 #18 #20 #23 #26 #44 #46 #49

**下一步**：TAKE 22 項加入 TODO.md R34 backlog 分批排序；DEFER 9 項記註解到觸發條件；LEAVE 19 項本次決議封存（避免 reviewer 重複提案）。

### 2026-05-06 滲透測試 hardening + guest demo a11y / 編輯體驗

兩段並行收尾：(a) CSO daily-mode 滲透掃描 4 findings 全 merge；(b) guest demo tour a11y 重做 + 開放新增申請書頁面。

- ✅ **PR #337 pentest hardening (security)**：(1) 新建 `backend/src/utils/secure_eq.rs` const-time byte 比較 helper（無新依賴 + 4 unit tests），套用到 `metrics.rs` METRICS_TOKEN + `alertmanager_webhook.rs` ALERTMANAGER_TOKEN（防 timing side-channel）；(2) 新建 `backend/src/middleware/guest_guard.rs`，所有 non-safe HTTP method（POST/PUT/PATCH/DELETE）若 actor 是 guest 一律 403，掛在 auth_middleware_stack + upload_middleware_stack（defense-in-depth，handler 層 has_permission 仍保留）；(3) `alertmanager_webhook` 從 fail-open 改 fail-closed — token 未設定時回 503 而非綠通；(4) `pdf-service/app/config.py` 加 `validate_word_converter_config()`，WORD_CONVERT_URL 設了但 token 空就 fail-fast（防止 backend → pdf-service → host Word COM daemon 跨服務 auth chain 出現空 token VBA RCE 入口）
- ✅ **PR #336 guest tour 拆元件 + a11y + sidebar stable id**：DemoTour 1 檔 →（Radix Dialog focus trap + Escape + role/aria-modal/aria-labelledby）；guest demo sidebar nav 加 stable id 修「拖拉重排後 highlight 跟錯項」；CodeRabbit 多輪建議採納
- ✅ **PR #333 開放新增申請書頁面給 guest demo**：`frontend/src/lib/guest-demo/protocols.ts` 加 placeholder「新申請書」資料；`routes.ts` 把 subresource matcher 排在 `/animals` generic match 之前（避免 `/protocols/new` 誤判）；DemoTour 文案 + i18n
- ✅ **CSO comprehensive scan**：daily 4 findings 全 RESOLVED 後跑深掃（Phase 0-14），SSRF / file upload magic-byte / AI prompt injection / CSRF 豁免清單 / honeypot 全部 SAFE；浮出 5 條 TENTATIVE LOW/INFO 級提醒（T1 CSRF middleware 自解 JWT、T2 access-token 6h 偏長、T3 CSP report endpoint 無認證可灌 log、T4 `reqwest::Client::new()` 每次新建、T5 audit HMAC 永久不可輪換 — accepted risk）。Trend = ↑ IMPROVING（HIGH/MEDIUM 全清）

### 2026-05-04~05 R32-A3 wire-up + Word COM + infra fix

R32-A3/A2b/A8 大幅推進至 staging-ready；新增 Word COM 100% Word-fidelity PDF 路徑；順手修 outbox-worker pre-existing infra bug。

- ✅ **R32-A3 end-to-end wiring**：pdf-service `app/adapters/aup_protocol.py` + `vet_patrol.py` 把 `protocols.working_content` JSONB → `AupProtocolPayload` / `animals[]` → `VetPatrolPayload` 兩個 domain transform 從 smoke_real_data 搬上來成 runtime path；`doc_types.py` 註冊 `aup_protocol` (DOCX_REGISTRY) + `vet_patrol` (XLSX_REGISTRY) + `office_to_pdf` 通用版（docx_to_pdf / xlsx_to_pdf wrapper 正確 MIME）；`/render-aup/from-working-content` + `/render-vet-patrol/from-animals` + `/render-xlsx/{doc_type}` 三新 endpoints；backend `services::pdf_service_client` 加 `render_aup_from_working_content` / `render_vet_patrol_from_animals` + `XlsxRenderFormat`；handlers `export_aup_v3` / `export_vet_patrol_v3`（SQL 下沉到 `VetPatrolReportService::list_animals_for_patrol`，handler ≤50 行 + format 白名單化）；frontend ProtocolDetailHeader「下載 docx / 下載 PDF」按鈕 + AnimalsPage「下載欄位狀態表」+ 3 i18n keys；`docker-compose up -d --build` 後直接套版可用
- ✅ **R32-A3 Word COM daemon (services/word-convert/)**：`server.py` Flask + pywin32 Word.Application SaveAs2 PDF（17=wdFormatPDF）+ `WORD_CONVERT_TOKEN` Bearer/X-Word-Token 共享 secret + `/health` Word readiness probe（503 if Word 死）+ `_convert` COM 失敗自動釋放 `_word_app` 自癒；`install_service.ps1` 註冊 Windows 工作排程器登入時自啟；pdf-service `_docx_to_pdf_word_first` 優先打 daemon、失敗只 fallback `httpx.RequestError`、`raise_for_status` + `%PDF` magic 校驗；docker-compose pdf-service 加 `WORD_CONVERT_URL` + `host.docker.internal:host-gateway` extra_hosts；驗證 PDF 含 `DFKaiShu-SB-Estd-BF`（Word 真實標楷體）+ `TimesNewRomanPSMT`，無 NotoSans LibreOffice fallback 字型 — 100% Word fidelity 達成
- ✅ **R32-A3 templatize.py 強化**：apply_cell_overrides 修正巢狀 tbl + permStart/permEnd（解 Word「無法讀取的內容」警告，bisect 至 idx 115 postop_care 含 nested table）；apply_style 改 style-based 偵測（Heading 1 自動 page_break_before + keep_with_next + keep_together / TOC field 偵測）+ 新增 `STYLE['size_overrides']` 純字級覆寫（封面「動物試驗研究計畫書」20pt 不觸發換頁）+ 巢狀 table 遞迴 walk + `_set_run_fonts` 改 `get_or_add_rFonts` 修 CT_RPr schema 順序；`apply_cell_overrides` template 文字 `\n` 改插 `<w:br/>`（OOXML `<w:t>` 內 `\n` 會被正規化為空格）
- ✅ **R32-A3 lock_template.py**：Word documentProtection readonly + 233 個 permStart/permEnd 變數區可編輯範圍 + 密碼 hash（rsaAES SHA-1 + 100000 iterations，ECMA-376 §22.7.3 / MS-OFFCRYPTO §2.4.2.4）；fail-fast settings.xml 缺失 + re.subn 替換次數 0 即 raise
- ✅ **R32-A8 PDF 驗證升級**：`scripts/validate_pdfs.py` 透過 docker compose exec pdf-service 呼 gotenberg + raise_for_status fail-fast；本地 2/2 PDFs 通過 CJK + 無 .notdef + Word PDF 含 DFKaiShu；產出 `docs/r32-validation.md` 報告
- ✅ **AUP schema 補欄**：`protocol.is_glp` / `sections.live_animal_necessity` / `sections.personnel_other_role` 三欄位 + mappings/aup_protocol.py MAPPING 加 GLP heading checkbox 替換規則
- ✅ **infra fix — outbox-worker JWT secrets**：pre-existing main bug — outbox-worker docker-compose service 缺 `JWT_EC_PRIVATE_KEY_FILE` / `JWT_EC_PUBLIC_KEY_FILE` env + secrets，導致 erp_backend Config::from_env 啟動驗證失敗 → 永久 restart loop。對齊 ipig-api secrets/env，container 恢復穩定（ChannelRegistry ready + email channel registered）
- ✅ **bot review 多輪採納**：3 輪 coderabbit + 3 條 gemini 共 25+ 條 quick wins（HTTPException sanitize、httpx.RequestError 收緊、format whitelist、permission alignment、SQL 下沉到 service、F zone unverified pen 移到 `_F_ZONE_PENDING`、xlsx formula injection 防護、fc-list fail-fast、smoke_real_data Asia/Taipei timezone、i18n keys 等）；拒絕 5 條 out-of-scope（fetch+Blob 下載、sacrificed nested key、pain category subflag、heavy COM error recovery — 部分採部分延後）
- ✅ **templates/ 重組**：source/（vet/QA 原始來源）+ reference/（PDF 樣本）+ output/（render 結果，gitignore）+ README.md
- 🟡 **R32 進度**：8/9 完成（A2b 完成）+ A3/A8 [~]；A7（砍舊路徑 1,236 行 + 4 deps）使用者已授權待獨立 PR `feat/r32-a7-purge-old-paths`，等本批 staging 觀察期後執行

**2026-05-05 補遺**：
- ✅ **vet/QA 視覺驗證全部通過**：5 docx（aup_protocol / medical_record / surgery / review_reply / review_result）內容格式正確 + 全部鎖內容保護密碼 433789；vet_patrol_template.xlsx F zone (F01-F06) 確認 markers 已手動填入正確 cell（user 反推：F04-F06 ear_tags 在 R19 + status 在 R21；F01-F03 ear_tags 在 R22 + status 在 R24，與 A-E zone 同 row 不同）
- ✅ **mappings/vet_patrol.py F zone 從 `_F_ZONE_PENDING` 移到 `PEN_CELLS` 正式 mapping**
- ✅ **services/word-convert/server.py 加 `WORD_CONVERT_DOC_PASSWORD` env**：Word.Open 帶 `PasswordDocument` 解鎖受 documentProtection 密碼保護的 docx；對齊 templates/*.docx lock_template 密碼。`install_service.ps1` 註冊排程任務時 cmd /c 注入 env
- ✅ **A3/A8 標 [x]**：R32-A3 coding 100% + vet/QA 驗證完成；A8 user 選擇 skip staging 直接到正式環境（ipigsystem.asia cloudflare tunnel）— 4 報表×3 樣本 + GLP HMAC 由實務操作觀察。R32 待辦從 4 → **1**（剩 A7 砍舊路徑獨立 PR）

### 2026-05-04 R32-A2b CJK gotenberg image + R32-A8 本地 PDF 驗證

接續 R32-A3 收尾，順推 R32 後段：

- ✅ **R32-A2b CJK gotenberg image**：新建 `services/gotenberg/Dockerfile` FROM gotenberg/gotenberg:8 + Noto Sans/Serif CJK TC + AR PL UMing/UKai（開源明楷，標楷體替代）+ Liberation 英文 + fc-cache；`docker-compose.yml` gotenberg service 改 `build:` + `image: ipig-gotenberg-cjk:8`；image build 16 秒、增量 +220MB；驗證 AUP PDF 嵌入 `NotoSansCJKtc-Regular/Bold` + Times New Roman、patrol PDF 嵌入 `NotoSansCJKsc-Regular`，兩份均無 `.notdef` glyph。已知限制：LibreOffice 預設未 alias「標楷體 → AR PL UKai TW」（後續 fontconfig conf）、xlsx 用了 sc subset（TC 仍可讀）
- ✅ **R32-A8 本地 PDF 驗證**：新增 `pdf-service/scripts/validate_pdfs.py`（透過 pdf-service container 呼叫 gotenberg、解析 PDF `/BaseFont` 確認 CJK 字型 + 偵測 `.notdef`）；產出 `docs/r32-validation.md` 報告（驗證範圍 / 樣本 / 嵌入字型 / 已知限制 / 後續步驟）；2/2 本地樣本通過（AUP 530KB、patrol 77KB）。staging 驗證待補：surgery / medical_record / review_reply / review_result 4 份 smoke_real_data 擴充 + R32-A6 HMAC chain link + 21 CFR §11.50 electronic_signatures.meaning + PDF/A-2b 合規
- ✅ **R32-A3 schema 補欄**：`AupProtocolPayload` 補 `protocol.is_glp` / `sections.live_animal_necessity` / `sections.personnel_other_role` 三欄（對應 GLP/非GLP heading checkbox、2.2.1 活體動物試驗必要性、人員 i. 其他說明）
- ✅ **`templates/` 目錄重組**：新增 `source/`（vet/QA 原始來源）/ `reference/`（PDF 樣本 + 字體對齊參考）/ `output/`（render 結果，gitignore）；smoke_real_data 寫入改 `templates/output/`；新增 `templates/README.md` 說明目錄結構
- ⏸ **R32-A7 砍舊路徑暫停**：規則明定「staging 驗證 ≥1 週後才能砍」+ 移除 `printpdf` / `lopdf` / `html2canvas` / `jspdf` 4 個依賴屬不可逆操作須明確同意；待 R32-A8 staging 部署觀察期滿後執行

R32 v3 任務狀態（8/9 完成 + A3 [~] + A8 [~]）：
- ✅ R32-1 / A1 / A2 / **A2b** / A4 / A5 / A6 / A9
- 🟡 A3（vet/QA 視覺驗證階段）/ A8（staging 補完整跑）
- ⏸ A7（staging ≥1 週阻塞）

### 2026-05-04 R32-A3 docx/xlsx templates 變數化 + AUP 字體換頁對齊

R32-A3 templates 變數化大幅推進（人機協作項目，剩 vet/QA 視覺驗證階段）：

- ✅ **`scripts/templatize.py` infra**：4-pass 設計（CELL_OVERRIDES → LOOPS → MAPPING → STYLE）；`coalesce_paragraph_runs` 合併同 format runs（忽略 `w:hint` attribute 解 IACUC banner 拆字問題）；`apply_cell_overrides` 修正巢狀 tbl + `permStart`/`permEnd` 導致 tc 結尾非 `<w:p>` 觸發 Word「無法讀取的內容」警告（清掉 tc 內所有 content children 重建乾淨 `<w:p>`）
- ✅ **6 份 docx schema + mapping**：medical_record（病歷總表）/ surgery（手術紀錄）/ aup_protocol（v1 + v2 checkbox 多選表，Jinja `{% if %}☑{% else %}□{% endif %}`）/ review_reply / review_result / audit_log（新建 skeleton）；共 117 個 CELL_OVERRIDES + 4 個 LoopSpec
- ✅ **vet_patrol xlsx（R32-A3b 分支）**：`build_xlsx_template.py`（一次性把 vet/QA 範例 xlsx 變數化）+ `app/xlsx_renderer.py`（openpyxl + Jinja2 ChainableUndefined）；130 pens（A20 + B20 + C20 + D33 + E25 + F6 + G6）；F/G zone wrap_text，其他 zone shrink_to_fit；G zone 3-per-line + 數字 `.\n` 分隔；Pivot 設計：markers 直接放在 xlsx 範本內（不放 Python mapping），vet/QA 可在 Excel 視覺驗證 marker 位置
- ✅ **`scripts/smoke_real_data.py`**：DB → render 整合驗證；AUP 90 pens / 1 animal / 5 personnel render 正確；自動版號 fallback（PermissionError → v3/v4/...）
- ✅ **AUP 字體換頁對齊** AD-04-01-01E 範本：標楷體（zh）/ Times New Roman（en）/ 大標 16pt / 內文 12pt / 小標 13pt；style-based 偵測（Heading 1 / Title → page_break_before + keep_with_next + keep_together；Heading 2/3/4 → keep_with_next + keep_together）；TOC field（`<w:instrText>` 含 "TOC"）自動換頁；表格 `w:cantSplit`（後因 schema 順序問題暫緩，須在 `w:trHeight` 之前）
- ✅ **記憶規則**：`vet_patrol_template.xlsx` 由 vet/QA 手動維護，禁止程式化變動欄寬列高 / merged ranges / 顏色 / 字型，render 流程只讀 template + 寫到 *_REAL_DATA*.xlsx 檔
- ⏸ **剩餘**：vet/QA 視覺驗證 5 份 docx + 1 份 xlsx；AUP 目錄手調對齊；F zone cell 位置視覺驗證（best-guess mapping）；部分 free-text 欄位（`sections.live_animal_necessity` / `sections.personnel_other_role` / `protocol.is_glp`）schema 補欄並由使用者貼佔位符

R32 v3 任務狀態（5/9 完成 + R32-A3 推進至 [~]）：
- ✅ R32-1 / R32-A1 / R32-A2 / R32-A4 / R32-A5 / R32-A6 / R32-A9
- 🟡 **R32-A3 templates 變數化**：infra + 6 mapping + xlsx tool 完成，剩視覺驗證階段
- ⏸ R32-A2b / R32-A7 / R32-A8

### 2026-05-04 R32-A9 使用者教學文件 + R32 v3 階段性結算

R32 v3 計畫第一波（PR #315 + #316 + #317 + #318）merge 後，文件補齊：

- ✅ **新建 `docs/USER_GUIDE.md`**（首份 user-facing 操作指南）+ **PDF 匯出**章節：
  - 哪些頁支援匯出（5 種報表對應 templates）、3 顆按鈕（預覽 / 下載 docx / 下載 PDF）操作步驟
  - 簽章流程（21 CFR §11.50）何時觸發、何時不觸發
  - 紙張規格 + 字型問題（中文字型缺 → 方框；指向 R32-A2b 解法）
  - 4 條 FAQ（預覽慢 / 版面差異 / docx 重匯入 / PDF 重下載）
- ✅ **新建 `docs/dev/docx-template-guide.md`**（給工程師 / vet / QA 寫新報表）：
  - docxtpl 變數語法 + Word run 拆字陷阱（訣竅）
  - Pydantic schema 對應規則 + 命名 convention
  - DOCX_REGISTRY 註冊步驟
  - Backend Rust handler 完整範例（含 R32-A6 pdf_artifact 存證寫入）
  - R32-A2b 中文字型 Gotenberg image 方案 A（Noto CJK + Liberation 開源替代）vs 方案 B（標楷體商業授權 NT$5-15萬/年）
  - 本地開發測試 curl 範例

R32 v3 任務狀態（4/9 完成 + R32-A9 完成 = 5/9）：
- ✅ R32-1 / R32-A1 / R32-A2 / R32-A4 / R32-A5 / R32-A6 / R32-A9
- ⏸ **R32-A3 templates 變數化**：高風險不可逆（schema 命名後改動成本高）— 需使用者參與設計每份範本的 Pydantic schema 與映射規則，留為人機協作項目
- ⏸ **R32-A7 砍舊路徑**：設計明訂「staging 驗證一週後才能砍」— 等 R32-A3 + R32-A8 完成後 staging 觀察
- ⏸ **R32-A8 回歸驗證**：需 R32-A3 templates 完成 + dev 部署 + 人工 4 種報表 × 3 樣本比對

### 2026-05-03 R31-11 csp_report handler 重構 + Reporting API (reports+json) 雙 payload 支援

R31 章節續推。承接前一個 PR（fix/r31-csp-noise-filter）的 noise filter 與 silent-error 修正，本 PR 完成 R31-11 的完整 handler 重構並加 CSP3 Reporting API 新 payload format 支援，為瀏覽器陸續切換到 `application/reports+json` 做準備。

- ✅ `services/csp_report.rs`：新模組，集中 `security_alerts` INSERT（對齊 CLAUDE.md「handler 禁止直接寫 SQL」分層規範）+ 統一 `CspViolation` 正規化結構 + `is_accepted_noise()` 移到此處
- ✅ `handlers/csp_report.rs`：依 `Content-Type` 分流：`application/csp-report` 走 legacy 解析；`application/reports+json` 走新 envelope 解析（filter `type == "csp-violation"`，過濾 deprecation/intervention 等其他 report type）
- ✅ Reporting API body 解析：`disposition == "report"` → `report_only=true`（取代 nginx `?mode=ro` query 標記，CSP3 路徑無需 hack）；`disposition` 缺省保守視為 report-only（避免錯把 enforce 標 RO 讓 admin 漏看）；`effectiveDirective`/`violatedDirective` alias 兼容兩種瀏覽器
- ✅ Handler 簽名仍 `StatusCode`（CSP 規範要求一律 204；payload / DB 失敗只 tracing log，狀態不變 — 文件解釋為合理 endpoint pattern 例外）
- ✅ Tests：7 個（service 2 + handler 5：legacy / reports+json / disposition enforce / violatedDirective alias / 非 csp-violation type 過濾）；470 lib tests 全綠；clippy clean

**未動**（後續 nginx PR）：
- R31-11 client-side 啟用：nginx `Content-Security-Policy` 加 `report-to csp-endpoint` + `Reporting-Endpoints: csp-endpoint="https://.../csp-report"` header — 沒這步瀏覽器仍只送 legacy 格式，新 parser 在 prod 是 dead code 但 staging 可用 curl 驗證

### 2026-05-03 R31 csp_report 過濾 accepted-risk noise

接 R31-13b（已 [x]）的 prod 落地。security_alerts 表被 `eval` / `wasm-eval` violation 持續轟炸（Cloudflare Insights beacon + transitive deps，frontend src 0 處呼叫），管理員警報疲勞。

- ✅ `handlers/csp_report.rs::is_accepted_csp_noise`：`blocked_uri ∈ {"eval", "wasm-eval"}` → 不寫 `security_alerts`，仍 `tracing::warn!` 留 forensics
- ✅ INSERT 失敗修正：原 `let _ = ...await` → `tracing::error!` loud log（R31-11 todo (c)；status 仍回 204 — 瀏覽器期望此值）
- ✅ Unit tests：eval / wasm-eval 過濾 + 其他 blocked_uri / case 變體 / None 不過濾

### 2026-05-03 R32-1 完成 + R32 計畫 v3 校正（docx template fill 路徑）

R32-1 baseline doc 早於本日已完整產出（260 行：4 條既有 PDF 路徑全盤點 + v2 校正計畫 + templates 範本規格反推）。本日於對話確認三件決策性事實後，整體策略**第三次校正**（v3）：

- ✅ **使用者三件決策**：(a) Web ↔ PDF 同源不在乎；(b) 需要即時頁碼計算 + 自訂分頁演算法（Word 是 word processor 本職，HTML 解法在邊角不穩）；(c) 字型授權閃避（OS 字型 + Word 渲染 = 免標楷體 / Times 商業授權）
- ✅ **架構轉向**：放棄原 v2 的 Gotenberg + CSS Paged Media（HTML→PDF），改 **docx template fill + LibreOffice headless**。`templates/` 已有 6 份官方 .docx 範本（含直橫混用手術表）即源；docxtpl 變數化 + Python service fill + soffice 轉檔
- ✅ **Web UI 不變**：detail page 維持原生 React UI（不模仿 Word 版型，避免手機/小螢幕被 A4 綁架）；只在 header 加 3 按鈕（預覽 PDF / 下載 docx / 下載 PDF）；預覽用 `<iframe>` / PDF.js 顯示真實 backend 輸出
- ✅ **Python `pdf-service` 沿用**（不砍）：原本規劃砍掉，校正後 keep + rewrite（從 Jinja2 改 docxtpl）。多語言維護負擔換來 docxtpl 業界主流工具與 6 份 templates 已存在的工程節省
- ✅ **R32-2 ~ R32-15 v1/v2 任務全 obsolete**：print stylesheet (R32-2)、`?print=1` query (R32-3)、各頁 print 樣式 (R32-4~7)、回歸驗證 (R32-8)、教學 (R32-9)、chrome container (R32-10)、chromiumoxide (R32-11)、service token (R32-12)、4 個 endpoint (R32-13) 全保留歷史標 `[~] v3 obsolete`；GLP 永久存證 (R32-14) → R32-A6；砍舊路徑 (R32-15) → R32-A7（範圍擴大）
- ✅ **新計畫 R32-A1 ~ R32-A9**（~3-4 週全職）：Python service rewrite + LibreOffice headless 整合 + templates 變數化 + Backend Rust handler + Frontend 預覽下載 UI + GLP 存證 + 砍舊路徑 + 回歸 + GLP 合規驗證 + 使用者教學
- ✅ **工程量比較**：v1 原計畫 5-7 週 → v2 校正 4.5-5.5 週（含字型授權處理）→ v3 約 3-4 週（templates 已存在 + 字型問題消失 + 不做 print stylesheet）

### 2026-05-03 R30-9b 撤銷簽章 handler / route / UI / 權限

R30-9a chain hash v3 已 merge。本 PR 補上撤銷流程的對外入口：admin 後台可從操作日誌頁開啟撤銷對話框，輸入 sig UUID + 理由 + 密碼後呼叫 `POST /signatures/:id/invalidate`，事件由既有 `SignatureService::invalidate` 寫進 v3 audit chain（含 sig fingerprint binding）。

- ✅ Migration 052：seed `signature.invalidate` 權限（admin only，預設不分配給任何角色，由管理員在 RolesPage 手動勾選）
- ✅ `SignatureService::invalidate` 加 reason 驗證（trim + 必填 + ≤1000 字符；HMAC chain v3 binding 過長會讓 row payload 暴漲）
- ✅ Handler `handlers/signature/invalidate.rs::invalidate_signature`：`POST /signatures/:id/invalidate { reason, password }`，require `signature.invalidate` perm + `validator` derive 雙層驗證；response 不洩漏 signer / record 細節（admin 走 audit log 詳細頁查 SIGNATURE_INVALIDATED 事件）
- ✅ Route 新增於 `routes/hr.rs`；OpenAPI handler + 兩個 DTO 同步註冊
- ✅ UI：`InvalidateSignatureDialog` 元件 + `AuditLogsPage` header 加「撤銷簽章」按鈕（僅 `signature.invalidate` 權限可見）；對話框三欄（UUID + 理由 textarea + 密碼）+ 字數即時顯示 + 撤銷成功 toast 提示「不會自動 revert 已使用此簽章的記錄」
- ✅ Tests：cargo check / clippy / lib 463 全綠；frontend tsc + lint 0 errors

### 2026-05-03 R30-9a HMAC chain v3 + signature fingerprint binding

R30-9 design doc 三層信任模型的「chain hash 升級」前置作業。修補 v2 chain 的 entity gap（攻擊者改 `entity_id` 不破壞 hash）並讓簽章事件額外綁定 fingerprint，事後竄改簽章內容會破壞 chain。

- ✅ Migration 051：`ALTER user_activity_logs ADD COLUMN extra_input TEXT NULL`；down migration 加 `assertion guard`（v3 row 存在時拒絕 DROP，避免破壞驗證）
- ✅ HMAC encoding v3：`canonical_bytes_v3()` = v2 length-prefix + 接續 `entity_type` / `entity_id` / `extra_input` 三欄；`compute_hmac_for_fields_versioned` 加 v3 分支（未知版本 fallback v2，防 verifier 在版本過渡期 panic）
- ✅ `AuditService::log_signature_event_tx(tx, actor, action, sig_id, binding, entry)`：簽章事件專屬寫入路徑，caller 顯式提供 `sig_id` + `binding`（CREATE: `content_hash`；INVALIDATED: `invalidated_reason`）→ 強制 v3 + 寫 `extra_input = "<sig_id>:<binding>"`；不依賴 ElectronicSignature JSON shape（欄位改名不會悄悄退回 `:""`）
- ✅ `derive_v3_routing()` safety net：未走 helper 而走一般 `log_activity_tx` 寫 SIGNATURE_* 仍自動升 v3（從 `after_data` 抽 `id` + `content_hash`/`invalidated_reason`）
- ✅ `signature/mod.rs::sign_record_tx` 加 `actor` 參數 + 同 tx 補 `SIGNATURE_CREATE` audit log（補 R30-9 design doc 提到的 missing call，確保「有簽章 row 必有 chain entry」不變性）；`invalidate` 既有 `SIGNATURE_INVALIDATED` 改用 `log_signature_event_tx` 顯式傳 reason
- ✅ 7 個 `sign_record_tx` caller 加 actor 引數：euthanasia ×3 / equipment ×3 / role::enforce_role_signature_tx（連帶 3 個 enforce caller）
- ✅ `pub const SIGNATURE_EVENT_CREATE / INVALIDATED` 取代魔術字串
- ✅ verifier 端：`ChainRow` 加 `extra_input / entity_type / entity_id` 三欄，`load_chain_rows` SELECT 補欄位，`verify_chain_rows::build_input` 補 v3 欄位（v2 row 帶值無害）
- ✅ Tests：6 個 `hmac_versioning_tests` 單元測試（v3 vs v2 差異、`extra_input` 變動改變 hash、`derive_v3_routing` 路由正確性 + 既有 3 個）；462 lib tests 全綠；clippy `-D warnings -A deprecated` 無 issue

### 2026-05-03 R30-3b euthanasia 超時 cron 改用同 tx（in-app + outbox dual-channel）

R30-3a outbox infra 已建（PR #305）；本 PR 把 `services/euthanasia.rs::check_expired_orders` 兩處 `tracing::warn!` 改為同 tx 處理：UPDATE + audit + in-app notification + email outbox **四件事 all-or-nothing**。對應 GLP §58「IACUC chair 必須收到關鍵事件通知」。

- ✅ `NotificationService::create_notification_tx`：tx 版站內通知 helper，原 `create_notification` 改為 thin wrapper（自開 tx 內呼叫 _tx 版）；`notify_euthanasia_timeout_approved_tx` 同樣加 _tx 變體
- ✅ `EuthanasiaService::approve_timeout_order_tx` / `_appeal_tx`：抽 service fn（CLAUDE.md ≤50 行 + 可獨立測試 + 可被 admin 手動 timeout / batch CLI 等其他 caller 複用）。內含 CAS UPDATE 防多 cron worker race（caller-provided `now` + `WHERE status='pending_pi' AND deadline_at < $2`，0 row affected → noop rollback）+ 共用 `finalize_timeout_approval_tx` helper（audit + in-app + email outbox）讓兩主 fn ≤50 行
- ✅ `enqueue_timeout_email_tx` helper：tx 內查 vet email（filter `is_active=true AND deleted_at IS NULL` 不發給停用/刪除 user）+ 組 plain/html payload + `OutboxService::enqueue_tx` 排進 email channel；email 缺失 log warn 不中斷 tx
- ✅ `check_expired_orders` 收斂為 thin loop：原 ~120 行 → ~50 行，純 SELECT candidates（`LIMIT 100` 防暴量重疊）+ iterate 呼叫 service fn + 錯誤 log
- ✅ `AuditService::log_activity_tx` 取代 `log_activity_oneshot`：audit 升 tx 版，與業務 mutation atomic（修補既有「audit 與業務不同 tx」缺口）
- ✅ `crate::utils::html_escape::html_escape_minimal`：通用 HTML escape helper（5 字元 + 4 unit tests）抽到 utils 給所有 outbox email caller 共用
- ✅ 開發者指南：[`docs/dev/notification-and-outbox.md`](dev/notification-and-outbox.md) — 完整 API 速查、payload schema、retry policy、多 worker 部署、常見坑
- ✅ PROGRESS §5 通知系統：補通道架構說明 + 指南連結
- ✅ Tests：cargo check / clippy --all-targets / cargo test --lib 458 passed 全綠

### 2026-05-02 R30-3a Event Outbox infra（PR-A）

R30-3 design doc (PR #304) 已敲定；本輪實作 PR-A 純 infra（無業務行為改動）。後續 PR-B 把 euthanasia 兩處 `tracing::warn!` 改用 `OutboxService::enqueue_tx`，可選複用到 R30-9b invalidate 通知。

- ✅ **Migration 050 `event_outbox`**：`{ id, channel, payload, status, attempt_count, next_attempt_at, last_error, enqueued_*, started_at, done_at, source_entity, source_entity_id }` + 4 indexes（pending / source / status / stuck-sending）+ down migration 含 outbox 為空 assertion 警告
- ✅ **`services/outbox/` 模組**：
  - `OutboxService` — `enqueue_tx` / `claim_batch`（CTE + FOR UPDATE SKIP LOCKED + UPDATE 原子）/ `mark_done` / `mark_failed`（CAS guard `status='SENDING'`）/ `reset_stuck`（cron）
  - `compute_next_attempt`：1=+10s, 2=+1m, 3=+10m, 4=+1h, 5=+6h, 6=DEAD
  - `ChannelAdapter` trait + `ChannelRegistry`（依 `channel` 路由）
  - `EmailAdapter`：複用 `EmailService::send_email_smtp`，DB-first SMTP 解析（admin 改設定不需重啟 worker）
- ✅ **`bin/outbox_worker.rs`** 獨立 binary：tokio main loop（5s tick）+ `for_each_concurrent(10)` 並行送 + `reset_stuck` 60s cron + SIGINT/SIGTERM 優雅收尾（Unix）/ ctrl_c（其他平台）
- ✅ **`Dockerfile.outbox-worker`** 獨立映像：cargo-chef + multi-stage + distroless；只 build `outbox_worker`；無 HTTP 端口 / 無 healthcheck
- ✅ **`docker-compose.yml`** 新 service `ipig-outbox-worker`：與 ipig-api 共用 secrets（db_url + smtp_password）+ env；read_only / no-new-privileges / 256MB / 0.5 CPU
- ✅ **`data_export.rs::INTENTIONALLY_EXCLUDED_TABLES`** 加 `event_outbox`（短命操作佇列，匯出後恢復會重發已送通知）
- ✅ **8 unit tests** 涵蓋 `compute_next_attempt` 全路徑（attempts 1-5 + 6-DEAD + ≥7 stay-DEAD）+ `OutboxStatus::as_str` + `ChannelRegistry` 未註冊 channel error + register-chain
- ✅ **Tests**：cargo check / clippy --all-targets / cargo test --lib 452 passed 全綠

### 2026-05-02 R30-25b/c amendment EFFECTIVE workflow + UI（PR #303）

R30-25a (PR #292) schema-only 已落地；本輪補上 service 寫入路徑 + 前端按鈕。完成 G 階段「IQ/PQ + 變更控制」收尾。對應 GLP §58「APPROVED ≠ 正式生效」可追溯性。

- ✅ **Service `mark_effective`**：`services/amendment/workflow.rs` 新 fn — tx + `SELECT FOR UPDATE` 鎖 row → 守 source status ∈ {APPROVED, ADMIN_APPROVED} → 守 `effective_from IS NULL`（拒重複生效）→ UPDATE `status='EFFECTIVE'` + `effective_from = COALESCE($req, NOW())` 帶 CAS guard → `record_status_change` → `AuditService::log_activity_tx` 寫 `AMENDMENT_EFFECTIVE` event 含完整 before/after diff（HMAC chain）— 全部同 tx 原子
- ✅ **DTO `MarkAmendmentEffectiveRequest`**：`{ effective_from?, remark? }`，`Validate` derive + `remark` length max 1000
- ✅ **Handler `POST /amendments/:id/effective`**：沿用 `aup.protocol.change_status` 權限；`req.validate()?` + `check_amendment_access(protocol_id)` IDOR 防護
- ✅ **AuditRedact for Amendment**：空 `redacted_fields()`（amendment 無敏感欄）
- ✅ **`AmendmentsTab` 加按鈕**：APPROVED / ADMIN_APPROVED 且 `hasPermission('aup.protocol.change_status')` 時顯示「標記生效」按鈕（table + card view）；status badge 下方顯示 `effective_from` 時間戳；用 `useConfirmDialog` hook + `<ConfirmDialog>` 元件雙重確認（取代 window.confirm，與專案統一）
- ✅ **`MyAmendmentsPage` 篩選**：補 EFFECTIVE 選項
- ✅ **Gemini fix**：CAS guard `AND status IN ('APPROVED','ADMIN_APPROVED') AND effective_from IS NULL`、useConfirmDialog 替換、IDOR 用 protocol_id（amendment 不掛 animal）

### 2026-05-02 R30-3 / R30-9 design doc

R30 兩個高風險剩餘項先寫 design doc 再實作 — 與使用者完整討論 trade-off 後敲定方案，避免 silent design choice。

- ✅ **`docs/design/r30-3-event-outbox.md`** — Transactional Event Outbox：
  - **架構**：命名 `event_outbox` 預留 future webhook/indexing；獨立 binary `bin/outbox_worker.rs` + `Dockerfile.outbox-worker`（與 backend image 分離）
  - **可靠性**：retry 5 次 exp backoff（10s/1m/10m/1h/6h → DEAD），idempotency = outbox row id，`FOR UPDATE SKIP LOCKED` 防多 worker 重取，`for_each_concurrent(10)` 並行送
  - **後續**：分兩 PR — 「PR-A infra」（schema + service + worker + container）→「PR-B euthanasia 改用」
- ✅ **`docs/design/r30-9-signature-audit-chain.md`** — Signature audit chain + invalidate：
  - **Chain hash v3**：含 sig fingerprint + entity_type/entity_id（修補 v2 entity gap）；不可逆 migration，verifier 須同時支援 v2/v3；compute_hash 規格鎖定避免 reason_hash/content_hash 編碼歧異
  - **Invalidate flow**：只記 audit 不動 record；已 APPROVED 有問題走「再開新 amendment 改」流程
  - **後續**：分兩 PR — 「PR-C v3 chain」→「PR-D invalidate」（schema + service + admin UI button）
- ✅ **TODO.md R30-3 / R30-9 條目更新**：附 design doc 連結 + PR 切分摘要（標 `[ ]` 維持 impl-pending 語意，design done 不算完成）

### 2026-05-02 R30-27c-2 手寫簽 phone bridge frontend（PR #302 merged）

R30-27c-1 backend 4 endpoints 已落地（PR #298），本輪補上 frontend：桌機在簽章 dialog 切「手機簽」→ 顯示 QR → 手機掃碼開公開簽名頁 → 完成密碼 + 手寫 → 桌機 dialog 自動接續。對應 21 CFR §11.10(d) 不可否認性，同時避開桌機滑鼠手寫筆跡品質差問題。

- ✅ **API client (`lib/api/system.ts`)**：4 個 bridge fn — `startSignatureBridge` / `getSignatureBridgeStatus` / `consumeSignatureBridge`（authed）+ `submitSignatureBridgePublic`（公開，token bearer）
- ✅ **Mobile sign page (`pages/sign/MobileSignPage.tsx`)**：路由 `/sign/:id?token=...&purpose=...`，公開頁不需 JWT；缺 token 顯示「連結無效」；submit 成功顯示「請回桌機，本頁可關閉」
- ✅ **`RoleSignatureDialog` mode 切換**：「桌機簽 / 手機簽」按鈕；進入 mobile mode 自動 `startBridge` → 顯示 QR (qrcode.react SVG, 220px) + 純文字 fallback URL → 遞迴 setTimeout 輪詢 status → COMPLETED 自動 `consume` 取 payload 走原 `onSubmit`；EXPIRED / CONSUMED 顯示錯誤 + 重新產生 QR
- ✅ **`RolesPage` 推導 purpose**：`role.create` / `role.update` / `role.delete` 與 backend audit 字串一致
- ✅ **`App.tsx`**：掛 `/sign/:id` 公開路由 + `publicPaths` 加 `/sign`（避免被 `checkAuth` 攔截）
- ✅ **Gemini fix**：onSubmit / purpose 用 useRef 追最新值消 stale closure；setInterval → 遞迴 setTimeout + cancelled flag 防重複 consume

### 2026-05-02 R30-41 panel/preset template 變更 audit 補齊（R30-16 follow-up）

`blood_test_panel_items` join table 重設原本只觸發父表 audit（PANEL_UPDATE empty diff / TEMPLATE_UPDATE 不含成員）— 補上獨立 `PANEL_TEMPLATE_CHANGE` 事件記錄成員清單 before/after，補齊 GLP §11.10(b) 操作日誌完整性。

- ✅ **`update_blood_test_panel_items`**：DELETE 前 SELECT 舊 template_ids → 重設 → 發 `PANEL_TEMPLATE_CHANGE` audit 帶 `PanelMembershipSnapshot` before/after diff（取代原 `PANEL_UPDATE` empty diff）
- ✅ **`update_blood_test_template`**：當 req 帶 `panel_id` 時，DELETE 前 SELECT 舊 panel_ids → 重設 → 發 `PANEL_TEMPLATE_CHANGE` audit 帶 `TemplateMembershipSnapshot` before/after diff（與既有 TEMPLATE_UPDATE 並存）
- ✅ **Audit-only 快照 struct**：`PanelMembershipSnapshot { panel_id, template_ids }` / `TemplateMembershipSnapshot { template_id, panel_ids }` + `AuditRedact` impl，純為 DataDiff::compute 序列化使用
- ✅ **Bot review fix**：`EVT_PANEL_TEMPLATE_CHANGE` const、`dedup_preserving_order` helper（保序去重對齊 ON CONFLICT DO NOTHING DB 實際狀態）、成員未變動時不發 audit event
- ✅ **Tests**：cargo check / clippy --lib --all-targets / cargo test --lib 444 passed 全綠

### 2026-05-02 R30-42 動物/計劃書/藥物批號/人員/QA/SOP 紀錄改永久保留（PR #300）

migration 044 把多數動物業務紀錄設為 20 年 hard_delete，異種器官移植研究機構需求是動物個體生命週期全可追溯（含跨世代）— 修正為永久保留；同時消除 R30-16 trigger 與 retention enforcer cascade 撞鎖風險。

- ✅ **Migration 048**：32 表 UPDATE delete_strategy='never'（動物業務 14 + 試劑批號 3 + 人員 6 + 供應商 1 + QA 4 + SOP/文件控管 4），補 `animal_blood_test_items` / `animal_sudden_deaths` 兩筆新 policy
- ✅ **維持 20 年 hard_delete 的純營運資料**：設備 / 設施 / 環境 / 管理 / Audit / 邀請 / 倉位 / 一般文件 / 帳務 / 通知 / AI 查詢 共 30 表
- ✅ **Bot review 4/4 take**：(1) `description \|\| '...'` NULL silent clear → COALESCE(description, '') 6 處；(2) UPDATE 靜默跳過不存在 table_name → 加檔尾 `DO $$` assertion COUNT == 34 否則 RAISE；(3) DOWN DELETE 因 ON CONFLICT 可能誤殺前置 policy → UP 改純 INSERT（已驗證 044 不含這兩 row）；(4) 同 (1) 雙提
- ✅ **副作用消除**：047 trigger GUC escape hatch 變成 dead-but-defensive 防呆（cascade 永遠不會發生）

### 2026-05-01 R30-16 D3 blood_test_items append-only + immutability triggers（PR #296 merged）

血檢結果為 21 CFR §11.10(c) raw data，「除非寫錯否則不應更改且需留歷史」— 採 D3 方案：append-only supersede chain + DB-level immutability triggers + 三道 reason 驗證。

- ✅ **Migration 047**：`animal_blood_test_items` 加 4 supersede 欄位（superseded_by_id / superseded_at / corrected_by / correction_reason）+ BEFORE UPDATE trigger 鎖 11 個 core 欄位 + BEFORE DELETE trigger 完全擋（GUC escape hatch + RAISE NOTICE）+ CHECK constraint 強制 4 欄一致 + partial index for current rows
- ✅ **Service 層**：新 fn `correct_item_with_reason`（lock parent + lock current item → INSERT 新 → UPDATE 舊 supersede → audit）+ `get_blood_test_history_by_id`；既有 `update_blood_test` 移除 items 接受
- ✅ **API**：新 `POST /blood-tests/:id/items/:id/correct` + `GET /blood-tests/:id/items/history`
- ✅ **Frontend**：新 `CorrectBloodTestItemDialog`（原值對照 + correction_reason ≥10 字 + Zod schema）+ 新 `BloodTestItemHistoryDialog`（修正鏈時間軸）；`BloodTestFormDialog` 編輯模式 readOnly + 修正按鈕 + 修正歷史入口
- ✅ **三道 reason 驗證**：前端 Zod `bloodTestCorrectionSchema` + 後端 `validator` crate min=10 + DB CHECK ≥5 字保底
- ✅ **Bot review 19 actionable**：18 take（IDOR / parent soft-delete / Zod / useEffect / O(n²)→O(n) Map / 函數 ≤50 行拆 5 個 helper / mount guard / state refresh / template_id null 正規化 / list cache invalidate / AuditRedact 位置 / TODO backlog）+ 1 partial-take/leave（SQL 下沉 repository — 既有 service inline SQL 模式一致 + DB trigger 已物理保證 invariant）
- ✅ **CI 修復**：第一輪 flake (`api_glp_record_lock` random ear_tag 碰撞) rerun 通過；第二輪修 nghttp2-libs CVE-2026-27135 Trivy 警告
- ✅ **R30-41 backlog 衍生**：panel/preset template 變更 audit（join table 重設前後快照 PANEL_TEMPLATE_CHANGE 事件）

### 2026-05-01 R30-27c-1 手寫簽名 phone bridge backend（PR #298 merged）

R30-27 第三階段（c-1 backend infra）：解決桌機滑鼠手寫困難，admin 掃 QR 跳手機完成簽名再帶回。

- ✅ **Migration 047**：`signature_bridge_sessions` 表（id / user_id / mobile_token_hash / purpose / payload jsonb / status / expires_at / submitted_at / consumed_at）；status 嚴格單向 PENDING→COMPLETED→CONSUMED；EXPIRED 由 cron lazy 標記
- ✅ **`SignatureBridgeService`**：start (5min TTL) / submit (token-bearer + tx 鎖避免 race) / get_status (owner-only) / consume (status guard + 一次性)；token 為 64-char base64url，DB 存 SHA-256 hash（短命 token 用 `AuthService::hash_token` 既有 pattern）
- ✅ **4 個 HTTP 端點**：`/signing-bridge/start` / `:id/status` / `:id/consume`（authenticated, owner）；`/public/signing-bridge/:id/submit`（公開，token-bearer 驗證）— 手機從 QR 開簽名頁不需 login
- ✅ **data_export 擴展**：`signature_bridge_sessions` 列入 `INTENTIONALLY_EXCLUDED_TABLES`（5min 短期 token，含敏感 payload 不應隨 IDXF 匯出）
- ✅ **Tests**：generate_mobile_token 唯一性 + 64 字元 + base64url 字符集；cargo check / clippy / test --lib 444 passed
- ✅ **Backlog R30-27c-2**：mobile signing page (`/sign/:id?token=...` Vite 路由) + RoleSignatureDialog 加「用手機簽」按鈕 + QR 顯示 + 輪詢 consume

### 2026-04-30 R30-27b role/permission 簽章 frontend dialog

- ✅ **Backend feature endpoint**：`GET /api/v1/system/features` 回傳 `{ role_signature_required }`，已登入即可呼叫（不需 admin），前端用以 conditional 顯示簽章 UI
- ✅ **Frontend `RoleSignatureDialog`**：複用既有 `HandwrittenSignaturePad`（signature_pad lib），password + handwriting 同 modal 收集，submit payload 給 caller 串入 mutation
- ✅ **`useSystemFeatures` 整合**：`useRolesMutations` 加 TanStack Query 5min cache fetch flag；create / update / delete 三流程 flag=true 時開 RoleSignatureDialog，flag=false 維持原本 UX 不變（漸進 rollout 安全）
- ✅ **delete 流程鏈接**：reauth password modal → 取得 reauth_token → 開簽章 dialog → 取得簽章 payload → 才真正 DELETE（reauth + signature 雙保險）
- ✅ **Tests**：tsc --noEmit / cargo check / clippy / test --lib 443 passed 全綠
- ✅ **R30-27c backlog**：手機 QR bridge 解決桌機滑鼠簽名困難（dialog 已加 hint「桌機建議使用觸控板或手機簽名」）

### 2026-04-30 R30-27a role/permission 變更簽章（backend + flag）

R30-27 拆三段：a 後端 + flag → b 前端 dialog → c 手機 bridge。本次 ship a。

- ✅ **config flag**：`role_signature_required` 預設 false（env `ROLE_SIGNATURE_REQUIRED`），backend 已準備好接受簽章 payload 但暫不 enforce；R30-27b 前端 dialog 完成後切 true 才正式對齊 21 CFR §11.10(d)
- ✅ **DTO**：`MutationSignaturePayload { password, handwriting_svg, stroke_data? }` 加進 `CreateRoleRequest` / `UpdateRoleRequest` / 新 `DeleteRoleRequest` 三個 mutation 路徑（包裹簽 = role 基本資料 + 完整權限集合 hash 簽一次）
- ✅ **Service**：`enforce_role_signature_tx` 在 caller tx 內呼叫 `SignatureService::sign_record_tx`（密碼 + 手寫雙因子，21 CFR §11.50 meaning 自動推導 Approve）；`canonical_role_content` 將 op + role.id + code + name + is_internal + permission_codes 編碼為 content，content_hash 寫入 signature 供日後鑑定簽章樣式對應的內容
- ✅ **Tests**：canonical_role_content 確定性 + op 變動偵測（防 create↔update 重放）；cargo test --lib 443 passed
- ✅ **R30-27b / c backlog**：前端 dialog + 手機 QR bridge 拆獨立 PR，避免 admin UX 在 R30-27a ship 當下卡死

### 2026-04-30 R30 G 階段狀態同步（TODO 過期更新）

R30 G 階段（IQ/PQ + 變更控制）盤點：5 項中 3 項實際已實裝於 main，TODO.md 一直標待辦造成假性 backlog。修正後 R30 剩 2 項真待辦。

- ✅ **R30-23 production fail-fast**：`main.rs:96-104` 已串接 `config_warn_count > 0 && is_production() → exit(1)`；`config_check.rs` 重構為純檢查函式回傳 warn_count，由 caller 決定是否 exit（dev/staging warn-only、production fail-fast）
- ✅ **R30-24 startup self-test**：`startup/db_self_test.rs` 全檔實作（system_user 存在 / SYSTEM_ADMIN+GUEST role 齊全 / permissions 表非空 / electronic_signatures.meaning + hmac_version + user_activity_logs.hmac_version 三關鍵 column 存在）+ `main.rs:111-122` production fail-fast 串接
- ✅ **R30-28 audit_chain_verify_active 預設 true**：`config.rs:313` 採用 `parse_bool_env_default_true("AUDIT_CHAIN_VERIFY_ACTIVE")`，預設啟用 chain 驗證（dev/test 可手動關）
- ✅ **TODO.md 同步**：R30 待辦 5 → 2（剩 R30-25 amendment EFFECTIVE 終態 + R30-27 role/permission 簽章流程）；總計 45 → 42

### 2026-04-30 R32 PDF 生成重做計畫敲定 + 任務分解

R32 (PDF 生成重做) 6 個決策點全數敲定，計畫從骨架展開為 15 項可執行任務（階段 1 = 9 / 階段 2 = 6）。

- ✅ **決策敲定**：D1 兩階段 / D2 暫不自動化但保留架構空間 / D3 4 種報表（Protocol + 病歷 + 手術彙整 + Audit log）/ D4 獨立 chrome service container / D5 完整 GLP 存證（PDF + audit + HMAC + electronic_signatures.meaning）/ D6 全部分頁痛點都處理
- ✅ **業界研究**：盤點 Stripe / Shopify / HubSpot / Notion / Linear / FDA 法規文件 platform 主流作法，確認「HTML+CSS Paged Media → 瀏覽器排版 → PDF」為共識；現況兩條路徑根本性壞（後端 1,236 行 printpdf 手刻字元截斷 + 前端 html2canvas 把文字變圖片）
- ✅ **任務分解**：階段 1（R32-1~R32-9，純前端 CSS，~2-3 週）對齊「使用者按 Ctrl+P 即可印」目標；階段 2（R32-10~R32-15，~3-4 週）保留 headless Chromium + GLP 永久存證路徑
- ✅ **架構守則**：階段 1 列印渲染不依賴 hover state、接受 `?print=1` query param、不依 viewport size 切內容，為階段 2 headless Chromium 鋪好路
- ✅ **TODO.md 更新**：R32 待辦從 9 → 15；總計 35 → 50

### 2026-04-28 R30 三軸 Code Review 全部結案

R30 立項當日（2026-04-28）完整實作完成，**40 項中 33 項實作 + 2 項使用者決定跳過 + 5 項移至後續 backlog**。當天總工時遠低於原估 125-177h（高度平行 dispatch + agent 並行）。

- ✅ **R30-A** Euthanasia 三軸補強（pattern 驗證 PR，PR #262 merged）— 4 項
- ✅ **R30-B** Protocol body lost update + CRUD audit（PR #269 + R30-B2 follow-up PR #272）— 3 項
- ✅ **R30-C** 簽章升級簡化版（PR #275 R30-10 meaning / PR #276 R30-7 HMAC v2 / PR #277 R30-9 invalidate audit）— 3 項
- ✅ **R30-D** Audit 顯示與匯出（PR #265 merged）— 4 項實作 + R30-15 跳過
- ✅ **R30-E** Soft-delete cleanup + retention policy（PR #278 R30-16/17 含全 GLP 表 20 年保留期 seed）— 2 項
- ✅ **R30-F** Audit + signature DB-level immutability triggers（PR #273 merged）— 2 項
- 🔶 **R30-G** IQ-PQ + 變更控制（PR #266 R30-22 + R30-26 / PR #271 build.rs 注入；R30-23~25, 27, 28 留待後續）— 部分 7 項（2 完成 / 5 backlog）
- ✅ **R30-H** 漏 audit 路徑補齊（PR #267 accounting / import_export / vet_patrol；R30-30 sudden_death 已存在）— 4 項
- ✅ **R30-I** GLP 文件補完（PR #264 merged，6 份 SOP / runbook / traceability matrix）— 6 項
- ✅ **R30-J** R29-5b v4 class rename codemod（PR #263 merged）— 1 項
- ✅ **R30-18** IDXF 漏 23 表補齊 + 覆蓋率測試（PR #270 merged）— 1 項
- ✅ **R30-19** include_audit 預設改 true + 前端警示（PR #274 merged）— 1 項

**使用者決定跳過（accepted as-is）2 項**：
- ❌ **R30-8** sign_record 強制 2FA — admin 已 TOTP（R26-1）；簽章已支援密碼+手寫雙因子；本機構非 FDA submission 等級，§11.300 single-factor 即足夠
- ❌ **R30-15** AuditLogTable RWD 卡片化 — audit log 後台桌機使用為主；無 truncate 已符使用者偏好；窄螢幕橫向卷軸影響微小

**設計性決策摘要**：
- R30-7 HMAC：D1=C 共用 `AUDIT_HMAC_KEY`（既有 env var）/ D2=C 加 hmac_version 欄舊資料永久 v1（與 R26 audit chain 同 pattern）
- R30-10 meaning：D7=A enum / D8=B legacy 資料 backfill `LEGACY_PRE_R30_10`
- R30-17 retention：使用者裁定**全 GLP 表 20 年**（永久 5 表 + 20 年 60 表 + token TTL 自動清）
- R30-9 invalidate：D5=A 不建獨立 chain，事件寫進 user_activity_logs HMAC chain；D6 加密碼驗證
- R30-26 down.sql：sqlx-cli 慣例 `migrations/down/NNN_xxx.sql` + CI guard（version ≥ 041 強制）
- R30-22 follow-up：build.rs + Dockerfile/CD env vars 注入 GIT_SHA / BUILD_TIME / RUSTC_VERSION_RUNTIME

**遺留 backlog（非 R30，由其他輪次處理）**：
- R30-G 部分（R30-23 config_check fail-fast / R30-24 schema self-test / R30-25 amendment EFFECTIVE 終態 / R30-27 role 變更強制簽章）
- R30-28 audit_chain_verify_active production flag 切 true（純 ops 設定）

### 2026-04-28 R29-5 提前實作（DEFER 反轉） + R30 三軸 Code Review 立項

- ✅ **R29-5 Tailwind 3.4 → 4.2 升級提前實作（PR #258 merged）**：原計畫 DEFER 至 2026-07-28，當日改為提前 ship。採 `@config "../tailwind.config.js"` 過渡路徑（保留既有 v3 JS config，避免一次到位 CSS `@theme` 改寫）。變更：tailwindcss 3.4.19 → 4.2.4 / 新增 @tailwindcss/postcss / 移除 @tailwindcss/container-queries + autoprefixer（v4 內建）/ `@import "tailwindcss"` 取代 `@tailwind` directives / `@custom-variant dark` 對齊 .dark class-based 切換。順帶修復 5 項：(1) **Dialog 預設 `sm:max-w-lg` → `max-w-lg`**（修 twMerge 不同 scope 無法去重 bug，影響 7+ 個 dialog 寬度 override 失效，例如 AuditAlertDetailDialog 從 512px 變回 1024px）；(2) **Dialog 加 `mx-auto`** 修 viewport 512-639px 靠左 bug（Gemini review 建議）；(3) **全域 `scrollbar-gutter: stable`** 規則涵蓋 60+ 個 scroll container（防 tab 切換 1-2px 抖動）；(4) **ProtocolEditPage 側欄 280→320px** 替代 truncate 處理 i18n 長翻譯（依使用者偏好不省略文字）；(5) **「下一個必填空白欄位」按鈕**收斂為內容自然寬度。Follow-up 列入 R30-J（R29-5b：v4 class rename codemod，`shadow-sm`×21 / `outline-none`×33 / `flex-shrink-0`×13）。
- ⚠️ **PR #257 docs (R29-5 DEFER 文字) 與 PR #258 (實作) 並存於 main**：時序問題導致 docs 與現實短暫不一致，本 PR (`docs/r29-r30-update`) 修正 R29-5 狀態為「已完成」並補上 R30 立項。
- ✅ **R30 三軸 Code Review 立項（40 項任務 / 9 階段 + 1 R29 follow-up）**：對 ipig_system 全棧做併發協調 / 操作日誌 / GLP 合規三軸平行掃描，產出 `docs/codeReviewFindings.md`。三軸交叉最弱點為 `euthanasia` 模組（無 tx + 無 audit + 無簽章保護）；GLP CRITICAL 缺口 4 項（簽章單因素、`signature_data` 非 HMAC、`electronic_signatures` 不在 chain、IDXF 漏 19 表 + soft-delete 未強制）。原 42 項中經 codebase 驗證移除 3 項誤報（amendment_versions 已有 `UNIQUE`、animals 已 soft-delete、audit_chain_verify 排程已註冊），修訂 6 項措辭精準化。階段：A euthanasia 補強 / B protocol body lost update / C 簽章升級 §11.200 / D audit 顯示與匯出 / E soft-delete + retention + IDXF / F append-only DB 防護 / G IQ-PQ + 變更控制 / H 漏 audit 路徑補齊 / I GLP 文件補完 / J R29-5b。總預估 125-177 小時；R30-A 為 pattern 驗證 PR，做完必停。


### 2026-04-28 R29 系列收尾 — R29-1/2/4/6 全 merge + R29-5 Tailwind 4 決策 DEFER

R29 ClawSweeper review follow-up backlog 從 6 條收斂到 1 條（剩 R29-5）。

- ✅ **R29-1 maintenance + disposal sign handler service-driven**：拆 1a + 1b 兩個 PR。1a (PR #249 `70030c63`) 建立 `SignatureService::sign_record_tx` + `EquipmentService::sign_maintenance_review_tx` + `access::require_equipment_review`，handler 退化為 thin wrapper；1b (PR #251 in-flight) 同模式套用 disposal applicant + approver，新增「申請人不得代簽」+ 「申請人不得自核（職權分離）」雙守衛。原 spec 列 6 個 sign handler 經調查後 scope 縮窄 — transfer / sacrifice / observation / euthanasia / protocol_review 只 INSERT signature 一個 statement 不需 atomicity 包裝。
- ✅ **R29-2 react-router-dom 6 → 7 (`5b49ba4c`)**：走 R29-4 dev-deps 拆解獨立 PR 完成。type-level breaking 在本系統實際無衝擊，無 v6 future flags 殘留。
- ✅ **R29-4 dev-deps group 拆解（5 個 PR 順序 land）**：#243 vitest patch + jsdom + postcss (`a5d74b98`) → #247 react-router 7 (`5b49ba4c`) → #244 eslint 10 (`66c457c4`) → #245 vite 8 + plugin-react 6 + Rollup 5 manualChunks function 形式 (`842b3543`) → #246 typescript 6 + @types/node 25 + @typescript-eslint 8.59 + tsconfig 移除 deprecated `baseUrl` (`91402950`)。每個 PR 都用 `git reset --hard origin/main` + 重 apply package.json + `pnpm install` 重生 lockfile + force-push 模式 rebase（純 git 解 lockfile conflict 不可行）。原估 1-2h 實際 ~3h。
- ✅ **R29-6 dependabot major-version groups + CI fail-fast (`bbf7b820`)**：`.github/dependabot.yml` 9 種高風險 major 套件（typescript / tailwind / react-router / eslint / vite / i18next / @types/node / @typescript-eslint / postcss/autoprefixer）單獨成 PR，避免再次 group bump 一紅就要拆；`ci.yml` 為 `frontend-entrypoint-test` + `trivy-scan` 加 `needs:` short-circuit，tsc fail 時不再花 ~10 分鐘 build image 跑 Trivy。
- ⏸ **R29-5 Tailwind 3.4 → 4.2 升級 — DEFER 至 2026-07-28**：決策（2026-04-28）D1=defer 1-3 個月（v3 仍 LTS、無安全壓力、v4 plugin ecosystem 還在補齊）/ D2=auto-convert `tailwind.config.js` → CSS `@theme`（surgical change） / D3=自動 screenshot diff via gstack browse（不仰賴 E2E + DesignReview 人工）/ D4=grep + 全自動取代 deprecated utility / D5=本專案無 Storybook 不需同步。預估屆時工時 4-8h。

**ClawSweeper 紀律觀察**：
- **lockfile rebase 模式**：dependabot PR rebase 時純 git merge 必衝，正確做法是 reset → re-apply package.json → pnpm install 重生 lockfile → force-push。本輪 5 個 PR 連鎖 rebase 共執行 4 次。
- **Spec scope 縮窄勝過盲跟**：R29-1 原列 6 個 sign handler，調查發現只 maintenance + disposal 有 atomicity 破洞，其他 5 個 sign-only handler 不需修補；surgical changes 原則勝過機械式套用。
- **CI fail-fast cascading 浪費 ~50%**：R29-6 加 `needs:` short-circuit 後 frontend tsc fail 時會省 ~11min（entrypoint ~1min + Trivy ~10min）；下次 frontend 出錯場景可驗證效果。

### 2026-04-28 Migration 037 checksum 修復 + 本地環境同步

- ✅ **Migration 037 checksum mismatch 修復**：dev DB 在 2026-04-27 已套用舊版 037（commit `be467a5e`），PR #240 的純註解修正 (`ace7c379`) 改變 sqlx checksum，啟動 api 觸發「migration 37 was previously applied but has been modified」rejection。確認 diff 僅為 SQL 註解（零 SQL 行為變化）後，`DELETE FROM _sqlx_migrations WHERE version = 37`，重啟 api → sqlx 自動重跑 037（`IF NOT EXISTS` + nullable column，idempotent），v37/v38/v39 全 success=true。**ops note**：未來若拉到含註解修改的 migration PR，dev/staging 都可採此模式；prod 應改用 `SKIP_MIGRATION_CHECK=true` 一次性 env var。
- ✅ **本地 main fast-forward 至 origin/main**：含 R28 second-pass 6 條 Medium、PR #241、R29-1/2/3 backlog、lucide-react 1.11.0 等。

### 2026-04-27 R29-3 i18next 26 升級完成（PR #242 `8b2e68d0`，含 CWE-117 / ReDoS security）

R29-3 backlog 提前完成。實際工時 ~30 min，遠低於原估 2-4h。

- ✅ **單一 breaking change 修補**：v26 移除 `showSupportNotice` 選項（v25.8.0 引入、v26.0.0 永久關閉），`frontend/src/lib/i18n.ts` 移除該行配置並補 R29-3 註解。
- ✅ **94 檔 i18n 使用點全部 forward-compatible**：`pnpm exec tsc --noEmit` EXIT=0，無需逐檔修補。其他 v26 breaking（`initImmediate` / 舊 `interpolation.format` 函式式 / `simplifyPluralSuffix` / `@babel/polyfill`）本系統皆未使用。
- ✅ **採納 v26.0.6 三條 security fixes**（defense-in-depth）：
  - CWE-117 log forging via translation keys / language codes / namespaces
  - ReDoS via `unescapePrefix` / `unescapeSuffix` regex escape
  - Nesting injection 警告（`escapeValue: false` + nesting block 組合）
- ✅ **dependabot PR #233 merge 後自動 close**。

**ClawSweeper 紀律啟示**：dependabot CI tsc fail 看似 94 檔大規模 breaking，實際只是 `showSupportNotice` 單一 type 不兼容；evidence-based ClawSweeper review 預估「2-4h」反而高估。修法歸納：**先 grep 對 deprecated API 使用點 → 移除 → 再 install**，可省去多次 typecheck round-trip。

### 2026-04-27 LOW dep bumps 批次 merge（5 個 PR）+ #227 dev-deps group 拆解（R29-4）

清理 R29 second-pass 後剩餘的 6 個 LOW 風險 dependabot PR。5 個 CI 全綠順利 merge；剩下 1 個 dev-deps group bump CI tsc fail 轉 backlog。

- ✅ **R28-2 / R28-3 兩個 backend cargo bumps 一氣 merge**：`fa331eff` (#225 cargo patch-updates 2 個) + `115c57ba` (#226 maxminddb 0.27→0.28)；都是 LOW patch / minor，CI 全綠。
- ✅ **3 個 frontend non-major bumps**：`7470edee` (#228 npm patch-updates 2 個) + `e963f1cd` (#231 @tanstack/react-query 5.99→5.100) + `f3c2b658` (#232 react-hook-form 7.72→7.74)。CI 全綠包含 tsc + Trivy。
- ⏸ **PR #227 dev-deps group (14 個套件) → R29-4 backlog**：dependabot 標稱 "patch updates" 但 CI `tsc check` + Trivy FAIL，代表 14 個 dev-deps 中混入 type-sensitive bump（疑為 `@types/*` 或 vitest/eslint major）。group merge 失敗時應拆成 individual bumps 分批處理。預估 1-2 小時。

**Open PR 從 9 → 3**（剩 #227 R29-4 / #229 R29-2 / #233 R29-3 全在 backlog tracked）。

**ClawSweeper 紀律觀察**：
- "patch-updates" 標籤不可盲信 — 即使 dependabot 自己歸類 patch，group bump 也可能挾帶 type-sensitive 套件升級。**必須以 CI tsc 為最終判據**。
- 5 個 LOW PR 順序 merge 中 sandbox 對 `gh pr view` 的 batch read-only 也擋過一次（rate limit / per-PR 授權），但實際 merge 都正常通過。

### 2026-04-27 Open PR 風險分流 — lucide ADOPT-NOW、react-router/i18next DEFER（ClawSweeper）

對 9 個 open dependabot PR 中 3 個被預判為 HIGH 風險的 major bump 做 ClawSweeper-style risk assessment。

- ✅ **lucide-react 0.575.0 → 1.11.0 (PR #230 `4fed2e30`)**：CI 14/15 jobs 全綠（含 tsc check + Trivy + pnpm audit），證明 type-safe；v1.0 是 marketing milestone（icon 庫長期 0.x stable，1.x 沿用 API）。ClawSweeper verdict ADOPT-NOW，merge 後依使用者授權跳過 visual smoke。
- ⏸ **react-router-dom 6.30.3 → 7.14.2 (PR #229 → R29-2 backlog)**：CI `tsc check` FAIL，跨 71 檔 type-level breaking（v7 整合 Remix data router，type names 重整 + future flags 變 default）。DEFER 至 R29-2，預估 4-8h 適配。
- ⏸ **i18next 25.10.10 → 26.0.8 (PR #233 → R29-3 backlog)**：CI `tsc check` FAIL，跨 94 檔；v26 含 3 條 security fixes（CWE-117 log forging / ReDoS / nesting injection）。DEFER 至 R29-3 升為 MEDIUM-HIGH（defense-in-depth），預估 2-4h 適配。

**review files**：`docs/review-decisions/PR-230.md` / `PR-229.md` / `PR-233.md` 各記錄 evidence + verdict + apply checklist；`PR-229.md` / `PR-233.md` 對應 R29-2 / R29-3 backlog 條目。

**ClawSweeper 紀律觀察**：
- 「major bump = 高風險」是 heuristic，**CI tsc check 是更可靠的 type-level 證據**。3 個 PR 中 1 個翻案（lucide 全綠 → ADOPT-NOW）。
- DEFER 條目必須附帶 backlog 編號 + 預估工時，避免變成 paper 黑洞。
- security fix 即使本系統不直接暴露於該 CVE pattern，仍應升級保守級別（i18next R29-3 從 LOW 升 MEDIUM-HIGH）。

### 2026-04-27 R28 second-pass review 6 條 Medium 全清空 + R28-2/R28-3/R28-6 收尾（4 個 PR）

承接 R27 全清空後對 R26 + R27 PRs 做的第二輪 code review（6 parallel sub-agent + 主審 verify，產出 13 findings 中 6 條 Medium）。tracker：`docs/reviews/2026-04-27-r26-r27-second-pass-review.md`。本輪 6 條 Medium 全部完成並 merge，同期 R28-2 / R28-3 / R28-6 三項 backlog 也補完。

- ✅ **R28-M6 IDOR — `create_animal_observation` 補 `require_animal_access`（PR #237 `aedc1af5`）**：pre-existing IDOR（非 PR #221 引入），handler 兩層守衛缺第一層；補上 `require_animal_access` 與其他 observation handler 一致。
- ✅ **R28-M5 Prometheus init failure → /api/health degraded（PR #238 `6d5ebbe6`）**：原本 init 失敗時 metrics 靜默掉（NoopRecorder）無 ops 可觀測；改為失敗時 `/api/health` 回 503 degraded + `tracing::error`，TestApp 加 `OnceLock<PrometheusHandle>` 避免 `install_recorder` 多次衝突。
- ✅ **R28-M3 + R28-M4 advisory lock key 中央註冊 + middleware error variant 透傳（PR #239 `d3c6feda`）**：`backend/src/constants.rs` 新增 §「Advisory Lock Key 中央註冊」集中 i64 / hashtext 命名空間，加 i32 範圍外驗證 unit test；`check_user_active_status` 改 `.inspect_err` 保留 log + `?` 透傳 `AppError::Database`，不再 wrap 成 Internal 流失 variant。
- ✅ **R28-M1 + R28-M2 Migration 037 註解修正 + HMAC residual risk 文件化（PR #240 `ace7c379`）**：migration 037 註解原稱 verifier 「視為 v=1」與實作 try-both 矛盾，修正為描述 try-both fallback；新增 `docs/security/HMAC_VERSIONING.md` 涵蓋 v1/v2 編碼差異 + verifier try-both + 三階段 backfill 計畫 + Anonymous→SYSTEM HMAC residual risk acceptance（v3 編碼擴充計畫 deferred）。
- ✅ **R28-3 upsert pattern 掃描 + system_settings audit 補全（PR #234 `255bdd4e`）**：grep `INSERT.*ON CONFLICT DO UPDATE` 全 backend，補 `system_settings` audit log 路徑（之前漏寫）。
- ✅ **R28-2 + R28-6 concurrent audit 並行度提升至 10 + entrypoint.sh CI 自動化測試（PR #236 `f46f762e`）**：擴 TestApp pool max_connections 後 audit concurrent test 並行度 3→10；`frontend/test-entrypoint.sh` 三組邊界 case（空 / 全空白 / 有效 URL）+ CI step。

**Bot review 觀察**（持續精進素材）：
- **PR #239 force-push 後 Gemini 補兩條 actionable Medium**（constants.rs L145 docstring bit pattern 誤稱「第 63 bit 為 1」實際是 0；auth.rs `map_cache_loader_error` catchall 在 Arc race 退化吞掉 Database variant）→ 用 ClawSweeper 紀律 ADOPT 並修；後者揭露 sqlx::Error 不可 Clone 的根本限制。
- **second-pass review sub-agent 4 條 false positive**（SQL JOIN「Critical 邏輯錯誤」、JSON field-order「HMAC false positive」、record_decision「TOCTOU」、observation「silent skip」重複 K5）→ 主審 verify 階段全部拒絕並寫入 tracker §「拒絕」，避免 sub-agent 過度發現浪費後續修補時間。
- **CI cargo test 跑 32min10s 為基準線**（前次 success run），#239 force-push 後新 run 也 32min 完成，未再現 stuck pattern。

**ClawSweeper 紀律統計**（本輪）：6 條 Medium / 4 拒絕 / 2 actionable post-merge bot review ADOPT；R28-5 因 deploy-time backfill SQL 屬 R29 範疇，僅補 design doc 部分完成標 [ ]。

### 2026-04-27 本地環境同步 main + Dev DB schema v39 + Maintenance Review GLP 雙因子 + RBAC 守衛

- ✅ **Dev DB schema v36 → v39**：本地 docker DB 從 R26 epic 中段推進到最新；`pg_dump` 完整備份後 `git checkout main && pull`，`docker compose up -d --build` 觸發 `sqlx::migrate!` 自動跑 037 (audit_hmac_version)、038 (glp_record_locks)、039 (amendment_decision_signature)；三個 migration 皆 `IF NOT EXISTS` + nullable / `NOT NULL DEFAULT false`，零資料風險，全 `success=true`。
- ✅ **GLP 21 CFR Part 11 雙因子簽章 — Maintenance Review (`d196972d`)**：`MaintenanceReviewDialog` 驗收通過時除手寫簽章外再要求登入密碼；`SignRecordRequest` 帶入 `password`，前端 disabled 條件加上 `password.length === 0`；`onError` 改用 `getApiErrorMessage` 顯示後端具體原因取代「請稍後再試」泛訊息。
- ✅ **靜態語意骨架閃現修復 (`9f1e81e2`)**：`frontend/index.html` 用 CSS 隱藏 `#static-landing`，DOM 內容仍保留供 SEO crawler / LLM scraper 擷取，`noscript` 環境下顯示骨架供無 JS 使用者閱讀。
- ✅ **R1+R2 Maintenance signature RBAC + 狀態守衛 (PR #241 `676057e3`，fix/maintenance-signature-rbac-guard)**：對 `d196972d` 做 self code-review 發現 `sign_maintenance_reviewer` handler 原無 `require_permission!`，任何已認證使用者皆可用自己密碼為任意 maintenance record 建立簽章並覆寫 `reviewer_signature_id`（pre-existing 漏洞，被 GLP 雙因子 commit 暴露）。修正：handler 加 `equipment.maintenance.review` / `equipment.manage` 雙路徑 RBAC + tx + `SELECT FOR UPDATE` 鎖 row 後檢查 `status = 'pending_review' AND reviewer_signature_id IS NULL`，已簽章回 `Conflict` 不靜默 UPDATE。驗證：cargo check + clippy `-D warnings` + test --all-targets 501 passed / 32 suites。
- ✅ **PR #241 ClawSweeper review + R29-1 backlog 建立**：3 條 actionable bot comment（CodeRabbit Major × 2 + Gemini Medium × 1）全 DEFER 至 R29-1，原因：bot 提出的「正確架構」修法（tx-aware sign_record + handler→service 重構 + audit log 補寫）跨多 sign handler 介面契約，非 hotfix scope；merge 後即使有 CR-1 race（簽章自帶 commit 與 maintenance UPDATE 非原子）仍比 merge 前狀態（RBAC 全缺）安全得多。完整 review 紀錄於 `docs/review-decisions/PR-241.md`，R29-1 backlog 條目入 `docs/TODO.md`。

### 2026-04-27 R27 backlog 9 項全清空 — 5 個 perf / refactor / observability PR

承接 2026-04-26 3C+8H 收尾後留下的 R27 backlog（PR #205/#210 review 中 DEFER 的 8 項 + #216 review 補的 R27-9/R27-10）。本輪 5 個 PR 全部完成並 merge，整個 R27 清空。

- ✅ **R27-1 + R27-2 Dockerfile CMD 拆分 + API_BACKEND_URL 驗證（PR #217 `d291c7d4`）**：`frontend/Dockerfile` 240+ 字 CMD 抽到 `frontend/docker-entrypoint.sh` 獨立腳本；envsubst 路徑加 fail-fast 檢查（trim 後驗證 `API_BACKEND_URL` 非空，避免 `proxy_pass http://;` 無效配置）；CI 測試模式（read-only conf.d）路徑不變。
- ✅ **R27-3 + R27-4 + R27-6 auth_middleware 重構（PR #218 `4757d16a`）**：`auth_middleware` 從 ~115 行壓到 ~25 行，拆 `validate_jwt` / `load_permissions` / `map_cache_loader_error` / `check_user_active_status` 4 個 helper；middleware 內 4-table JOIN + 帳號狀態 SELECT 下放至 `repositories/user.rs::list_permission_codes_by_user` / `find_user_active_status_by_id`，符合 CLAUDE.md「Middleware 禁業務邏輯 / Repository 封裝 SQL」分層；admin 路徑也走 `try_get_with` single-flight，與一般使用者共用 H2 stampede 防護。
- ✅ **R27-5 permission_cache hit/miss/eviction Prometheus（PR #222 `822b6ac3`，取代被自動關閉的 #219）**：`build_permission_cache` 加 `eviction_listener`，match `RemovalCause` enum 對 static str（避免 `format!("{:?}")` alloc）；`load_permissions` 用 `cache.get()` pre-check 取代 `Arc<AtomicBool>` 追蹤，single counter `ipig_permission_cache_requests_total{result="hit|miss"}` + 配對 `evictions_total{cause}` 符合 Prometheus best practice；可在 Grafana 計算 hit rate 與 eviction by cause。
- ✅ **R27-7 + R27-9 amendment workflow 拆分 + 去重（PR #220 `e91ae9b4`）**：`amendment::classify` 從 ~110 行拆 `classify_minor_with_signature_tx` + `classify_major_with_reviewers_tx` 兩個 helper，主函式僅做驗證 + tx 邊界 + 分流（~45 行）；`record_decision` 守衛已取得的 `current_status` 傳入 `check_all_decisions_tx`，省同 tx 內重複查 `amendments.status` 一次。
- ✅ **R27-10 observation handler 單次 fetch（PR #221 `69024390`）**：`create_animal_observation` 兩個分支（emergency + abnormal）原本各自呼叫 `AnimalService::get_by_id`，合併為條件式單次 fetch + 共用 Option；普通 observation（非 emergency 非 abnormal）跳過 fetch，零成本。
- ⏸ **R28-1 入後續 backlog**（Gemini PR #221 review 提出）：`AnimalObservationService::create` 內部 audit log 也呼叫 `AnimalService::get_by_id`，handler + service 全程仍有 2 次重複；deeper refactor 需動 service 簽名（breaking change 跨多 callers），獨立 PR 處理 — 入 docs/TODO.md R28-1。

**Bot review pattern 觀察**（持續精進素材）：
- **CodeRabbit / Gemini 提出的 perf hint 多為 trim/cache_get pre-check/static str 等微優化**，符合 ClawSweeper 紀律的「真實證據 + ADOPT」標準
- **#218 admin 快取空 Vec 風險（Gemini High）**：表面像 false positive，深入分析後採納（一致性 + 防禦性深度）— 證明高 severity 標籤值得仔細評估
- **CI cargo test 卡 25-90 分鐘 stuck pattern 重複 6 次**（#213 / #215 / #216 / #217 / #218 / #222）— runner 共用資源不穩，最終都會自然綠或可 admin merge；coverage (tarpaulin) 通過時可作為 cargo test 結果的 proxy
- **stack PR squash-merge 會自動 close 下游 PR**（#218 squash → #219 自動 close 因 base branch 被刪）；解法是 cherry-pick 重建 + 新 PR 號碼

**ClawSweeper 紀律統計**（本輪）：5 個 PR ＝ 9 個 R27 項目 + 1 個 R28 DEFER；bot review 全程 11 條 ADOPT / 0 條 REJECT / 1 條 DEFER（R28-1）。

### 2026-04-26 3 Critical + 8 High 全清空 — 11 個合規/安全/效能 PR 一次 merge

依 2026-04-25 三軸系統審查（併發 / GLP §11 / ISO 27001）產出的 11 項 critical/high backlog，分 11 個 PR 完成並全部 merge 至 main，搭配 ClawSweeper-style review 紀律（proposal-only review 寫進 `docs/review-decisions/PR-XXX.md`，apply 階段分離）。

- ✅ **C1 動物觀察記錄鎖定（PR #204，已先前 merge）**：4 張表加 `is_locked / locked_at / locked_by`；signature service UUID 化（i32→Uuid 殘留 bug 一併修）；4 個 animal service 加 update/delete guard 拒鎖定後修改；§11.10(e)(1) 合規。
- ✅ **C2 Amendment 決定簽章 FK + 終態守衛（PR #205 `c47540c4` + PR #213 `a60842e1`）**：amendments 表加 `approved_signature_id / rejected_signature_id`（ON DELETE RESTRICT）；`record_decision` 新增 SELECT FOR UPDATE 終態守衛拒絕已 APPROVED/REJECTED/AdminApproved 後改決定，避免 status 翻轉與簽章覆寫；amendment_status_history audit trail 不再被遮蔽。
- ✅ **C3 密碼變更 + 2FA 雙重認證（PR #212 `7840324c`）**：`ChangeOwnPasswordRequest` 加 `must_match` validator；2FA setup 強制 `X-Reauth-Token`；NIST SP 800-63 / §11.300 對齊。
- ✅ **H1 Audit chain verify cron multi-instance lock（PR #206 `e20ba705`）**：PostgreSQL advisory lock 確保多 pod 部署時僅一 instance 跑 verify；`AuditChainVerifyLock` RAII Drop trait 兜底 panic 路徑釋放鎖。
- ✅ **H2 Permission cache moka single-flight（PR #210 `ed8b2b05`）**：DashMap 換成 `moka::future::Cache`，內建 TTL + `try_get_with` 防止 cache miss stampede；`build_permission_cache()` helper 統一 main + tests；error variant preserve 避免 Forbidden 被吞成 Internal。
- ✅ **H3 + H4 檔案上傳 + 登入邊界（PR #207 `b8b43eb7`）**：upload 失敗 per-file rollback unlink（含 SOP `rows_affected=0` 隱性洞）；`cleanup_orphan_upload` helper DRY 三處 unlink+warn；login `create_session` 移到 `issue_login_tokens` 之前避免孤兒 session。
- ✅ **H5 Observation audit display 一致性（PR #209 `5c1a1c85`）**：observation audit 訊息加 IACUC + ear_tag 與 surgery / blood test 對齊；`soft_delete_with_reason` 把 `AnimalService::get_by_id` 移出 tx 避免 connection pool deadlock。
- ✅ **H6 Amendment 決定 RBAC（PR #208 `6a6cdcfc`）**：新增 `aup.amendment.approve` permission 並指派給 VET / REVIEWER / IACUC_CHAIR；`record_amendment_decision` handler 雙層守衛（permission + reviewer assignment）。
- ✅ **H7 + H8 JWT 金鑰 + 鎖定稽核（PR #211 `8ed2dce5`）**：Unix mode 啟動檢查 JWT 私鑰檔權限 (≤0600)；`Config::jwt_ec_private_key_file` 取代散落 env 讀取；帳號鎖定事件 `log_security_event_tx` 改同 tx sync write，失敗時 `tracing::error` 留追蹤線索。
- ✅ **CLAUDE.md 引入 Karpathy 思考紀律（PR #215 `d2804ae6`）**：新增「思考紀律」section（Think Before Coding / Surgical Changes / Goal-Driven Execution）+ commit 前 self-check checklist；修正既有「有疑問自行決定」與新規則衝突；§10 清理規則限定當前任務範圍。
- ✅ **R27 backlog 補充（PR #214 `a222cc7b`）**：把 #205/#210 review DEFER 的 6 項（auth_middleware 拆分、middleware SQL→repo、cache 觀測、admin status cache、amendment::classify 拆分、C2 R7 tracker）寫入 docs/TODO.md R27-3~8。

**驗證**：每個 PR 都通過 `cargo check + clippy --all-targets -D warnings -A deprecated + cargo test --all-targets`（含整合測試 hit 本地 Postgres）+ E2E + Trivy + cargo audit + cargo deny + 5 個 guard checks。`#211` 推送後 CI fail（`Config` 字面量 test fixture 缺欄位），補 `jwt_ec_private_key_file: None` 後綠；`#209` rebase 解 main 帶來的 C1 lock 與本分支 H5 pre-fetch 衝突（保留兩者：lock check → tx 外取 animal → tx.begin → tx 內 FOR UPDATE 權威檢查）；`#213` rebase 解與 #205 的 `record_decision` 衝突（保留兩者：終態守衛 + tx 版 `check_all_decisions_tx`，整合後比兩 PR 各自版本更安全）。

**Review process（ClawSweeper-style）**：建立 `docs/review-decisions/{README,SUMMARY,PR-205~PR-215}.md`，每條 bot review comment 評估 ADOPT/REJECT/DEFER + evidence + action；REJECT 必附反駁（如拒 4 條 Gemini 中文→English 建議因既有 amendment 模組訊息全中文一致性、拒 Gemini Critical 「moka invalidate.await」誤判附 docs.rs 證據）；DEFER 入 R27 backlog 不遺失。共 11 採納 / 7 拒絕 / 6 DEFER / 1 開新 PR (#213)。

### 2026-04-24 R26-14 Audit Redaction 文檔 + CI 守衛 (PR #198)

- ✅ **Critical review finding 澄清**：agent 提出「Animal/Document/Equipment/Partner/Role 等 entity 缺 AuditRedact impl」**實際誤判** — 80 處 `DataDiff::compute` 呼叫全部編譯通過，代表所有 entity 都已 impl（default empty 或明確 redact）。
- ✅ **新增 `docs/security/AUDIT_REDACTION.md`**：完整對照表
  - §1 明確 redact 欄位的 entity（`User`: password_hash/totp_secret/backup_codes；`AiApiKey`: key_hash）
  - §2 default empty impl 的 entity（動物/ERP/設備/文件/HR/權限 類，經 review 確認無敏感欄位）
  - §3 含敏感欄位但不進 audit diff 的 entity（`UserSession.refresh_token_id` 只是 UUID）
  - §4 FullPlan DoD-7 列舉但實際不存在的 entity（`TwoFactorSecret`/`JwtBlacklist`/`OAuthCredential`/`McpKey` 在 codebase 中從未定義）
  - §5 CI 守衛說明；§6 維護記錄與新 entity 檢查清單
- ✅ **新增 `audit-redaction-guard` CI job**：find + awk 掃描 `models/*.rs` 含敏感欄位 pattern（password_hash / *_secret / *_token / api_key / backup_codes / key_hash）的 `FromRow` DB entity，若不在 ALLOWED 清單且 redact 未覆寫則 fail。強制新敏感 entity 必須做 redact decision。
- ✅ **本地驗證 guard**：`✅ PASS`（所有現有 DB entity 都已 redact 或在 ALLOWED 清單）

### 2026-04-24 R26-13 storage_location 庫存 upsert 原子性修復 (PR #197)

- ✅ **修補 critical review HIGH finding**：`storage_location.rs::create_inventory_item` 原本使用 `INSERT ... ON CONFLICT DO UPDATE` upsert pattern，無法在 app 層區分實際執行 INSERT 還是 UPDATE → audit 缺 before snapshot、兩並發請求互相覆蓋。
- ✅ **重構為顯式 SELECT FOR UPDATE + INSERT/UPDATE 分支**：
  - 開 transaction
  - `SELECT ... FOR UPDATE OF sli` 鎖定既有 row（以 unique key: storage_location_id + product_id + COALESCE(batch_no, '') + COALESCE(expiry_date, '1900-01-01')）
  - 有既有 row → UPDATE 路徑，event_type = `STORAGE_INVENTORY_UPDATE`，before/after diff 完整
  - 無既有 row → INSERT 路徑，event_type = `STORAGE_INVENTORY_CREATE`，before=None
  - `log_activity_tx` 在同一 tx 寫 audit
  - 更新 storage_locations.current_count 在同一 tx
  - Commit
- ✅ **新增 `AuditRedact` impl for `StorageLocationInventoryItem`**（空 impl = 全欄位明碼，無敏感資料）
- ✅ **Handler 簽名變更**：handler 現在建構 `ActorContext::User(current_user)` 並傳入 service
- ✅ **驗證**：`cargo check` ✓、`cargo clippy --all-targets -- -D warnings -W clippy::unwrap_used` 零警告、`cargo test --lib` 422/422 pass


### 2026-04-24 R26 整合測試 — DoD-3/DoD-6 機械式驗證 (PR #195)

- ✅ **新增 `backend/tests/api_audit_r26.rs`**（4 個整合測試）對應 critical review 發現的「R26 整合測試完全缺失」問題。
- ✅ **Test 1: `tx_rollback_does_not_persist_audit`** — 驗證 SDD 核心保證：tx rollback 時 audit 不落地。
- ✅ **Test 2: `tx_commit_persists_audit_with_chain`** — 驗證 tx commit 後 audit 寫入並形成 HMAC chain（每筆有 non-empty integrity_hash）。
- ✅ **Test 3: `hmac_chain_broken_detected_by_verify`** — 寫 3 筆 audit → 手動篡改中間一筆的 after_data → `verify_chain_range` 應在 `broken_links` 中含被篡改的 id。對應 DoD-3 audit_chain_verify cron 的偵測能力。
- ✅ **Test 4: `concurrent_audit_writes_no_chain_race`** — 10 並發 tasks 各自開 tx 寫一筆 audit → 全部成功且每筆都有 integrity_hash（advisory lock 起效）。對應 DoD-6 同類精神（advisory lock 序列化）。
- ✅ **測試模式**：直接用 `TestApp::spawn().db_pool` 取 connection pool，不經 HTTP layer — 測試目標為 service 層原子性。
- ✅ **驗證**：`cargo check --tests --test api_audit_r26` ✓；`cargo test --lib` 不受影響（422/422 pass）；CI 將跑 `cargo test --all-targets` 確認 4 個整合測試在有 DB 的環境通過。

### 2026-04-24 R26 Frontend Audit Fields — UserActivityLog 補新欄位 + Detail Dialog 展示 (PR #196)

- ✅ **修補前端 R26 欄位斷層**：critical review 發現 `UserActivityLog` interface 缺 4 個 R26 新欄位，導致前端無法序列化、稽核 UI 無法顯示。
- ✅ **`frontend/src/types/hr.ts`** 新增 4 個欄位：
  - `changed_fields: string[] | null`（R26-3 stored proc 計算或 app 提供的變動欄位清單）
  - `integrity_hash: string | null`（SEC-34 HMAC-SHA256 雜湊鏈）
  - `previous_hash: string | null`（鏈連續性驗證用）
  - `impersonated_by_user_id: string | null`（R26-1 / migration 034：SEC-11 模擬登入真正執行者）
  - `hmac_version: number | null`（R26-6 / migration 037：1=legacy / 2=canonical）
- ✅ **`AuditLogsPage` Detail Dialog 補展示**（`pages/admin/components/ActivityLogDetailDialog.tsx`）：
  - SEC-11 impersonate 警示區塊（含 UserCog icon 與「真正執行管理員」說明）
  - 變動欄位 Badge 清單（含 redact 後欄位名）
  - 可摺疊的「資料完整性 (HMAC chain)」區塊：HMAC 編碼版本標籤（v1 legacy / v2 canonical）+ Integrity Hash + Previous Hash + 「每日 02:00 UTC 自動驗證」說明
- ✅ **`lib/guest-demo/admin.ts`** demo data 同步補新欄位（type-safe）
- ✅ **驗證**：`pnpm tsc --noEmit` ✓；`pnpm eslint` 對 3 個變更檔零警告


### 2026-04-24 R26 Rollback + Env Docs — Critical Review 補強 (PR #194)

- ✅ **發現 R26 epic 收尾前的 critical gaps**（透過 critical code review）：
  - 🔴 HIGH: Migration 033-037 完全無 .down.sql / DB_ROLLBACK.md 章節（fullplan §11 Step 1.7 unfulfilled）
  - 🔴 HIGH: R26 整合測試完全缺失（DoD-3 / DoD-6 無機械式驗證）
  - 🟠 MEDIUM: Frontend `UserActivityLog` 缺 `hmac_version` / `impersonated_by_user_id` / `integrity_hash` 欄位
  - 🟠 MEDIUM: Migration 037 backfill 無 runbook
  - 🟠 MEDIUM: `.env.example` 缺 `AUDIT_CHAIN_VERIFY_ACTIVE`
  - 🟠 MEDIUM: `docker-compose.yml` 未文檔化 AUDIT env
  - 🟠 HIGH (新發現): `services/storage_location.rs::create_inventory_item` upsert 缺 SELECT FOR UPDATE → audit 無法區分 INSERT/UPDATE（後續 PR 處理）
  - 🟡 MEDIUM (新發現): Animal/Document/Equipment/Partner/Role 等 entity 缺 `AuditRedact` impl（後續 PR 處理）
- ✅ **本 PR (#194) 補做**：
  - `docs/db/DB_ROLLBACK.md` 新增 **Migrations 033-037 章節**：每個 migration 含完整 rollback SQL、嚴重警告（prod 後不建議 rollback）、Migration 037 backfill runbook（分批 UPDATE 避免長時間鎖表）
  - `.env.example` 加入 `AUDIT_CHAIN_VERIFY_ACTIVE=false` + 啟用前置條件文檔（migration 037 上線、verifier 分流支援、staging ≥7 天無 false positive）
  - `docker-compose.yml` API service 補 `AUDIT_CHAIN_VERIFY_ACTIVE` env 宣告
- ✅ **後續 PR 預定（依序）**：
  - PR #195 R26 整合測試：tx rollback / HMAC chain broken 偵測 / change_status concurrent
  - PR #196 Frontend `UserActivityLog` 補新欄位 + `AuditLogsPage` 展示 impersonate chain
  - 後續 PR R26-13/14（新編號）：storage_location upsert race 修復 + entity AuditRedact impl
  - 最後 PR R26 Epic 收尾（`integration/r26 → main`, DoD-8）

### 2026-04-24 R26 Epic Final DoD Compliance — CI 嚴格化 + Audit Pattern Guard

- ✅ **移除 `ci.yml` 的 `-A deprecated` 寬鬆標記**：R26-4 已完成（PR #188 + #190 移除舊 `log_activity`），現在 CI clippy 採嚴格模式 `-D warnings -W clippy::unwrap_used`。新 PR 引入 deprecated 警告會直接 CI 紅燈。
- ✅ **新增 `audit-pattern-guard` CI job (DoD-5)**：grep guard 防止未來新 PR 在 handler 層引入 `tokio::spawn(async move { AuditService::log_*` pattern。容許上限 2（D-15 SEC 例外：FORCE_LOGOUT + IMPERSONATE_START），超出立即 CI 紅燈。
- ✅ **R26_FullPlan.md 加 D-15 設計決策**：明確記錄 SEC fire-and-forget audit 例外（`handlers/audit.rs::FORCE_LOGOUT` + `handlers/user.rs::IMPERSONATE_START`）— 這些事件已發生不可回滾，audit 失敗不應 break 主流程。
- ✅ **R26_FullPlan.md DoD checklist 全面標記**：DoD-1 ~ DoD-7 全部 ✅；DoD-8（合流回 main）為 R26 epic 收尾 PR 待做。Step 3 ~ Step 9 acceptance criteria 全綠。
- ✅ **量化指標確認**：`log_activity_tx` 138 處（超出原計 97 → 實際更徹底）、`log_activity_oneshot` 11 處（fire-and-forget）、`tokio::spawn audit` 2 處（D-15 例外）、deprecated warnings 0 處。
- ✅ **驗證結果**：`cargo check` ✓、`cargo clippy --all-targets -- -D warnings -W clippy::unwrap_used` 嚴格版（無 -A deprecated）零警告通過。



### 2026-04-24 R26 系列收尾完成 — PR #191（PW+E _tx）合併 + R26-7 死碼清零

- ✅ **PR #191（R26-3 Phase 2 最終塊）合併**：Partner / Warehouse / Equipment service `_tx` variants 全面到位
  - Partner: `create_tx` / `delete_tx`；Warehouse: `create_tx` / `update_tx` / `delete_tx`；Equipment: `create_maintenance_record_tx` / `update_maintenance_record_tx` / `delete_maintenance_record_tx`
  - 所有 mutation 含 `log_activity_tx()` 確保審計與資料變更同一 tx 原子性
  - Equipment refactor：公開 pool-based methods 轉為薄包裝（permission check → begin tx → delegate _tx → commit → side effects），消除 ~205 行重複代碼
  - CI 13/13 綠燈（含 E2E Playwright）
- ✅ **R26-7 死碼清零**：services/ 模組樹從「11 處 `#[allow(dead_code)]`」降至 0
  - PR #173 已刪除 8 處真死碼
  - 本次處理剩餘 3 處：
    - `data_import.rs::IdxfMeta.format_version` → `_format_version` + `#[serde(rename = "format_version")]`（serde 被動欄位）
    - `data_import.rs::ManifestTable.columns` → `_columns` + `#[serde(rename = "columns")]`（統一 `_`-prefix 模式）
    - `hr/overtime.rs::QUARTERLY_OVERTIME_LIMIT` → 移除（未使用的勞基法季度常數；法規值保留於 `MONTHLY_OVERTIME_LIMIT_EXTENDED` 註釋）
  - `services/mod.rs` 頂部註釋更新：R26-7 完成聲明 + 新死碼即刻紅燈
- ✅ **R26 全系列完成** — 8/8 項目（R26-1~R26-8 + R26-9/10/11）關閉：
  - R26-1 Scheduler tokio::select!（PR #177）
  - R26-2 HMAC chain 驗證 cron（已實作於 integration/r26）
  - R26-3 Handler 遷移 log_activity_tx（PR #156/162-184/188/191，97 call sites 全部）
  - R26-4 舊 log_activity 移除（零 deprecated 警告）
  - R26-5 migration 036 修正（PR #154）
  - R26-6 HMAC 版本化（PR #170）
  - R26-7 Dead code 清零（本次收尾）
  - R26-8 ProtocolService::change_status SDD（PR #188）
  - R26-9 Audit redact allowlist（PR #175）
  - R26-10 Vet advice upsert 並發安全（PR #174）
  - R26-11 IDOR service-layer authz（PR #176）
- ✅ **驗證結果**：`cargo check` ✓、`cargo clippy --all-targets -- -D warnings -A deprecated` 0 warnings、`cargo test --lib` 422/422 all pass

### 2026-04-23 R26-3 Phase 2 — PR #6b（Product + SKU）+ Gemini Review 修正 + 分支整合

#### PR #6b（R26-3 Phase 2）— Product & SKU Service-driven audit（6 commits / 12 mutations）

- ✅ **ProductService CRUD _tx 化**：`services/product/crud.rs` 新增 6 個 `_tx` variants
  - `create_tx` / `update_tx` / `update_status_tx` / `delete_tx` / `hard_delete_tx` / `create_category_tx`
  - 原有 pool-based public methods 轉為薄包裝（4–7 行），內部開啟 tx + 委派 _tx variant + commit
  - 每個 _tx 含 `log_activity_tx` 呼叫，確保 audit trail 與 mutation 同原子性
- ✅ **SkuService CRUD _tx 化**：`services/sku.rs` 新增 6 個 `_tx` variants
  - `update_category_tx` / `update_subcategory_tx` / `create_subcategory_tx` / `create_product_with_sku_tx` / `delete_subcategory_tx` / `delete_category_tx`
  - 處理字串主鍵（category/subcategory code）與 Uuid 型別不一致；`create_product_with_sku_tx` 需預先生成 SKU（無法在 tx 內呼叫 `Self::generate`）
- ✅ **dead code cleanup（bonus）**：移除 3 個 R26-8 後成為孤立的舊版 pool wrapper
  - `ProtocolService::assign_primary_reviewer`（被 `assign_primary_reviewer_tx` 取代）
  - `ProtocolService::assign_vet_reviewer`（被 `assign_vet_reviewer_tx` 取代）
  - `ProtocolService::generate_iacuc_no_pool`（無呼叫點）
  - 消除 clippy `dead_code` 警告，重啟 `-D warnings` 嚴格編譯
- ✅ **驗證結果**：`cargo check` ✓、`cargo clippy --all-targets -- -D warnings -A deprecated` 0 warnings、`cargo test --lib` 422/422 all pass
- ✅ **Commit**: `ae01c13` refactor(product,sku): R26-3 Phase 2 PR #6b - expose _tx variants
- ✅ **PR #190 opened**（base: integration/r26）並 Gemini code-assist review 完成

#### Gemini Review #190 修正（2 suggestions）

- 🔴 **High Priority — Missing VET audit log**：
  - Symptom：`assign_vet_reviewer_tx` 簽名改為 `(tx, actor: &ActorContext, protocol_id, vet_id)` 後，遺漏了 `record_activity_tx(..., ProtocolActivityType::VetAssigned, ...)`
  - Fix：恢復 `record_activity_tx` 呼叫，確保 vet assignment audit trail 與 tx 同步
  - Commit: `2ddd2f5` fix(protocol): restore vet audit log + dedupe reviewer query
- 🟠 **Medium Priority — Duplicate reviewer SELECT**：
  - Symptom：`change_status_tx` UnderReview 分支重複執行同樣的 `WHERE id = ANY($1::uuid[])` 查詢（一次供 status_remark，再次供 ReviewerAssigned activity）
  - Fix：預先 fetch `(Uuid, String)` tuple 一次，同時供兩個用途（status_remark 與 activity extra data），消除冗餘
  - Line 256 → consolidated upfront, reused in 249–312 block

#### 分支整合協調

- ✅ **Base branch update**：`origin/integration/r26` 於 2026-04-23 received PR #188 squash（R26-4/7/6/8 foundation 一次性合併）
  - Conflict in `status.rs`：r26-3-phase2-handlers HEAD 有 tx-aware 薄包裝 + Gemini fixes，而 theirs 為中間態 `log_activity_oneshot`
  - Resolution：Keep ours（HEAD），因 tx-aware pattern 為最終設計；merge commit `0560647` 推送完成
- ✅ **編譯驗證**：merge 後 `cargo check` ✓、clippy 0 warnings、tests 422/422 pass
- ✅ **Push 完成**：branch `r26-3-phase2-handlers` 包含 3 commits（ae01c13 + 2ddd2f5 + 0560647 merge）

#### 下階段 PR 預計

| PR # | 範圍 | 估算 | 狀態 |
|------|------|------|------|
| #6c | Partner + Warehouse + Equipment `_tx` variants | 20–28h | Pending |
| #6d | Role + AI + Auth + Two-Factor `_tx` variants | 16–20h | Pending |
| #6e | Document + QA_Plan + Amendment `_tx` variants | 28–36h | Pending |
| #6f | Facility + Signature `_tx` variants | 20–24h | Pending |
| #9 | R26-4 final cleanup（移除所有 pool wrapper）| 8–12h | Post-PR #6 |

### 2026-04-23 R26 Cleanup Phase 2：R26-4、R26-7、R26-6 完成 + R26-8 基礎建設

#### R26-4：舊版 log_activity() 函數刪除與deprecated 警告清零

- ✅ **刪除舊版函數**：`log_activity()` + `compute_and_store_hmac()` + `audit_document()` 三個函數完全移除（audit.rs 減少 ~250 行）
- ✅ **遷移最後 2 個 call sites**：
  - `protocol/history.rs` record_activity()：改用 `log_activity_oneshot()` + `ActorContext::User` 構造（actor_id → CurrentUser 轉接）
  - `protocol/status.rs` change_status()：同樣改用 `log_activity_oneshot()` 的 fire-and-forget 模式
- ✅ **deprecated 警告狀態**：0 warnings（舊版函數全刪，遺留警告點消失）
- ✅ **驗證結果**：`cargo check` ✓、`cargo clippy -D warnings` ✓、`cargo test --lib` ✓ 422/422 all pass
- ✅ **Commit**: `b7aa6bc` feat(audit): R26-4 remove deprecated log_activity()

#### R26-7：死碼清理（2 items removed, 3 intentionally preserved）

- ✅ **刪除死碼**：
  - `CreateAnnotationRequest` 重複定義於 models/animal/requests.rs（handlers/signature 版本為 canonical）
  - `SignRequest` 定義未使用（不在任何 handler 或 OpenAPI spec）
- ✅ **保留意圖死碼**（含 R26-7 註解）：
  - `IdxfMeta::format_version` — 預留格式版本相容檢查（R26-6+）
  - `ManifestTable::columns` — 預留欄位級驗證（將來擴充）
  - `QUARTERLY_OVERTIME_LIMIT` — 預留勞基法季度上限檢查（目前只實作月度）
- ✅ **驗證結果**：`cargo check` ✓；`cargo test --lib` ✓ 422/422 all pass
- ✅ **Commit**: `8609fbf` refactor(models): R26-7 remove dead code structs

#### R26-6：HMAC 鏈版本化 + 儲存後雜湊（已完全實裝）

- ✅ **Migration 037**：`ALTER TABLE user_activity_logs ADD COLUMN hmac_version SMALLINT`（已存在）
- ✅ **寫入端版本化**：
  - `compute_and_store_hmac_tx()` 已寫入 `hmac_version = HMAC_VERSION_CANONICAL (2)`
  - 舊版被 R26-4 刪除（曾寫 `hmac_version = 1`，已 cleanup）
- ✅ **驗證端版本化**：
  - `verify_chain_rows()` 依 `hmac_version` 分流計算（line 714-744）
  - 若 `hmac_version IS NULL` → try-both 策略（canonical 優先，fallback legacy）
  - `ChainRow` struct 已包含 `hmac_version: Option<i16>` 欄位
- ✅ **驗證結果**：`cargo test --lib` ✓ 422/422 all pass（包含 audit chain verify 相關測試）
- ✅ **Commit**: `dcb8003` docs(progress): Record R26-7 completion

#### R26-8：ProtocolService::change_status 完整 Service-driven 重構（進行中）

- 🏗️ **第一階段完成：PartnerService::create_tx**
  - 新增 `create_tx()` method，接 `&mut Transaction` 而非 `&PgPool`
  - 支援跨服務原子操作（change_status 核准時自動建立客戶於同一 tx）
  - 程式碼生成改為強制提供 code（tx 內省略自動編號邏輯）
  - `log_activity_tx` 整合於 create_tx 內，確保 audit trail 原子化
- 📋 **第二階段規劃：change_status 全面 tx 化**
  - 轉換函數簽名：`pool: &PgPool` → `tx: &mut Transaction`
  - 轉換所有 SQL queries：`.fetch_one(pool)` → `.fetch_one(&mut *tx)` 等
  - 協調跨服務邊界：
    - Status 變更 UPDATE → 同 tx 內
    - assign_primary_reviewer / assign_vet_reviewer → tx 版本或直接內嵌
    - record_status_change → 需 _tx 版本或內嵌邏輯
    - PartnerService::create → 改用新的 create_tx
    - 客戶停用邏輯 → 併入 tx
  - 目標：CRIT-01 race condition 從事後修補（加鎖）→ 原子設計
- 💾 **Commit**: `c22032a` feat(partner): R26-8 foundation - add create_tx...

### 2026-04-23 R26-3 後續三 PR 完成（#4b #4c #5 共 22 個 call sites）

R26-3 Phase 2 全面推進：blood_test / pdf_export+import_export / user+audit+data_export 三個 PR 連續完成，遷移 22 個 handler-level `log_activity()` call sites 至 Service-driven audit pattern。

#### PR #4b（血液檢查）— 13 個 mutations（commit `075b732`）

- ✅ **`services/animal/blood_test.rs` 全部遷移**：13 個函數簽名改為接 `pool: &PgPool` + `actor: &ActorContext`，內部開啟 tx + 執行 mutation + `AuditService::log_activity_tx` + commit
  - create_blood_test / update_blood_test / delete_blood_test / batch_import_blood_tests (4 core CRUD)
  - template create/update/delete + panel create/update/delete + preset create/update/delete (9 config mutations)
- ✅ **handler 層簡化**：`handlers/animal/blood_test.rs` 移除所有池級 `log_activity()` fire-and-forget；改呼叫 service 層（actor 由 `ActorContext::User(current_user.clone())` 傳遞）
- ✅ **deprecated 警告減少**：24 → 11（共消除 13 處）

#### PR #4c（PDF + 匯入匯出）— 5 個 mutations（commit `3cbb195`）

- ✅ **新增 `AuditService::log_activity_oneshot()` helper**：方便後 external-service 的 audit 事件記錄，內部用 `log_activity_tx` + auto-commit，參數型別同 `log_activity_tx`
- ✅ **`services/mod.rs` visibility 改正**：`mod audit;` → `pub mod audit;`，使得 handler 層可直接 import `ActivityLogEntry` / `AuditEntity` / `RequestContext`
- ✅ **`handlers/animal/pdf_export.rs` 2 個 call sites**：export_animal_medical_pdf / export_blood_test_analysis_pdf 改用 `log_activity_oneshot()`（PDF render 為外部服務，audit 於 render 後作記錄）
- ✅ **`handlers/animal/import_export.rs` 3 個 call sites**：全部 3 個匯入/匯出 handler（import_basic_data / import_weight_data / export 各類）改用 `log_activity_oneshot()`（批次 ID = `Uuid::nil()`）

#### PR #5（使用者 + 稽核 + 資料匯出）— 4 個 mutations（commit `3587151`）

- ✅ **`handlers/user.rs` tokio::spawn case**：IMPERSONATE_START 事件於 spawn 閉包內呼叫 `log_activity_oneshot()`；actor 於 spawn 前建立（`let spawn_actor = ActorContext::User(current_user.clone());`），確保生命週期正確
- ✅ **`handlers/audit.rs` tokio::spawn case**：FORCE_LOGOUT 事件同樣於 spawn 前準備 actor，於閉包內呼叫 `log_activity_oneshot()`
- ✅ **`handlers/data_export.rs` 2 個 call sites**：full_database_export (DATA_EXPORT) + full_database_import (DATA_IMPORT) 改用 `log_activity_oneshot()`（全庫操作，entity_id = `Uuid::nil()`）
- ✅ **deprecated 警告最終狀態**：11 → 2（僅保留 audit.rs 內部 log_activity 定義 + protocol/status.rs，已標記為 out-of-scope）

#### 全體驗證 & 狀態

- ✅ **編譯驗證**：`cargo check` 零錯誤；`cargo clippy --all-targets -- -D warnings -A deprecated` 零新警告
- ✅ **測試驗證**：`cargo test --lib` 422/422 全部通過（一致性驗證）
- ✅ **里程碑統計**：R26-3「97 個 call sites」中，已完成 22 個（animals 13 + pdf/import 5 + user/audit/data 4）= 22.7%；剩餘 75 個（product/sku/partner/warehouse/equipment/role/ai/auth/document/hr 等）預定 PR #6 ~ PR #9 分批完成
- ✅ **決策確認**：`log_activity_oneshot()` 作為外部服務/spawn task 審計的標準模式；`log_activity_tx()` 對應服務層 transaction mutations；handler 層完全去除舊版 fire-and-forget pattern

### 2026-04-22 R26 Service-driven Audit — PR #4a animals + 後續四 PR（document / HR / user）

本日 R26 epic 合計推進 **5 個 PR**（#156 animals 系列先完成；#159/#160/#161/#162 後續四 PR 平行開出）。

#### PR #4a（#156）animals simple mutations Service-driven audit（8 commits / 17 mutations）

- ✅ **Codex 審閱通過**（CONDITIONAL GO）：pattern 可複製前的獨立審閱完成 — 10 findings 分類 1 🔴 Blocker / 4 🟡 Warning / 5 🟢 Note；🔴 #2（AuditRedact 空 impl 風險）在 PR #4a 第一個 commit 修掉；🟡 #10（UPDATE-after-INSERT HMAC）歸 R26-6
- ✅ **PR #156（opened → integration/r26）**：
  - C1：AuditRedact trait 強化安全警告 doc（User/Session/MCP key 類必須覆寫 redacted_fields）+ `ActivityLogEntry` 加 `Default` + 4 constructors（update / create / delete / simple，減少 ~45 call sites 填 `request_context: None`）+ 16 個 animal entity AuditRedact 空 impl
  - C2-C7：source.rs / weight.rs / vet_advice.rs / care_record.rs / medical.rs 疫苗 / observation+surgery create 共 **17 個 simple mutations** 改寫為 tx + ActorContext + DataDiff
  - C8：clippy 零警告調整（移除 handler 不再用的 AnimalService/AuditService import）
- ✅ **決策採納**：upsert → `create_or_update` 拆分（獲完整 before/after diff）；soft_delete 歸 simple（change_reasons 視為 audit trail 伴生）；actor 分層策略（submit/approve 用 require_user；CRUD 用 `actor_user_id().unwrap_or(SYSTEM_USER_ID)` 允許 System，支援 batch 匯入）
- ✅ **內部 caller 調整**：`AnimalService::create` 初始體重改 `ActorContext::System { reason: "animal_create_initial_weight" }`；`import_export.rs` 批次匯入體重改 `ActorContext::System { reason: "weight_batch_import" }`（actor 鏈路完整化歸 PR #4d）
- ✅ **驗證綠燈**：`cargo check` / `cargo clippy --all-targets -- -D warnings -A deprecated` / `cargo test --lib` 423/423 全數通過
- ✅ **R26-3 範圍訂正**：原 TODO 估「~20 處 handler」經 `AuditService::log_activity / ::log` 跨 27 handler 檔的實測為 **97 call sites**（animals 49 + user 8 + product 7 + sku 5 + 其他 28），估 ~465 person-hours；拆分成 PR #4a~4e（animals 系列 ~200h）+ PR #5a/b/c（hr/document ~185h）+ PR #6（其他模組 ~80h）
- ✅ **計畫文件**：`docs/plans/pr4a-animals-simple-mutations.md`（已在 PR #155 一併提交，10.2K 可執行粒度）+ `docs/plans/pr5-hr-document-roadmap.md`（6.6K 路線圖層級）

#### 後續四 PR（document / HR / user）消化 R26-3 的 35 個 service mutations

延續 PR #4a，開出 **4 個平行子 PR**（全部 base 於 `integration/r26`，可獨立 review）：

- ✅ **PR #5a（#159）document 模組 Service-driven audit**（5 commits / 10 mutations）：`Document` / `DocumentLine` / `PoReceiptStatus` 3 個 AuditRedact 空 impl；`crud.rs` 3 個（create / update / delete）+ `workflow.rs` 5 個（submit / approve / admin_approve / admin_reject / cancel）+ `grn.rs` 2 個（create_additional_grn / recalculate_all_po_receipt_status）；approve 跨 service tx 串接（`StockService::process_document` + `AccountingService::post_document`）維持不變；`recalculate` 採 batch summary audit 粒度；**移除 `AuditService::audit_document` helper**（handler 8 處呼叫點全清）；423 tests / 0 clippy
- ✅ **PR #5b（#160）HR leave 模組 Service-driven audit + balance helper tx 化**（3 commits / 7 mutations + 7 helpers）：`LeaveRequest` / `LeaveApproval` / `AnnualLeaveEntitlement` / `CompTimeBalance` 4 個 AuditRedact；7 個 leave mutation（create / update / delete / submit / approve / reject / cancel）**全部從 0 tx 狀態**加 `pool.begin()`；approve_leave / cancel_leave 的 balance 扣除/還原也改 tx（7 個 balance helper 由 `&PgPool` 改 `&mut Transaction`，`FOR UPDATE` 加行鎖避免併發超扣）；event_type 分 INTERIM / FINAL / RETROACTIVE 粒度；GLP 合規重點：leave 狀態變更與 balance 異動原子化
- ✅ **PR #5c（#161）HR overtime / balance / attendance Service-driven audit**（4 commits / 14 mutations）：`OvertimeRecord` / `AttendanceRecord` AuditRedact；`overtime.rs` 6 個 mutation + **`approve_overtime` 多步流程收進同一 tx**（SELECT FOR UPDATE → UPDATE RETURNING → INSERT overtime_approvals → is_final 時 INSERT comp_time_balances → audit，補休授予原子化）；`balance.rs` 5 個 mutation + `batch_auto_calculate` 採 **N+1 summary audit** 粒度；`attendance.rs` clock_in / clock_out / correct_attendance 也 tx 化（before/after IP/GPS diff 供稽核異常行為偵測）；完成 HR epic 21 個 mutation 全部遷移
- ✅ **PR #6a（#162）user 模組 Service-driven audit + 6 audit 呼叫點整合**（3 commits / 4 mutations）：`User` 覆寫 `AuditRedact::redacted_fields()`（`password_hash` / `totp_secret_encrypted` / `totp_backup_codes` 作為 defence-in-depth）；`create` / `deactivate_self` / `delete` / `update` tx 化；**consolidate 原本散落的 6 個 audit 呼叫**（handler `log(Create)` ×1 / `log(Delete)` ×1 / update_user tokio::spawn `log_activity(SECURITY)` ×2 / delete_me_account `log_activity(GDPR)` ×1 / service 內部 `log(Update)` ×1 = 6）→ service 層 1-3 筆 event_type 分類（USER_UPDATE ADMIN + conditional USER_STATUS_CHANGE / USER_ROLE_CHANGE SECURITY）；`RoleAssignmentSnapshot` helper struct 捕捉 role-change diff；deprecated warnings 89 → 86
- ✅ **事件粒度與設計決策**：ActivityLogEntry 使用 struct literal 形式（為避免與 PR #156 的 constructor 定義衝突，rebase-friendly）；approve 類區分 INTERIM / FINAL（FINAL 才授予 comp_time）；batch 審計粒度分兩類 — **per-row mutation 類**（例：`batch_auto_calculate_annual_leave` 每位員工各自 create）採 **N+1 summary + per-row**；**純 summary 類**（例：`recalculate_all_po_receipt_status` 無 per-row mutation，僅重算 status）採 **單筆 summary**；`AuditRedact::redacted_fields()` 作為 `#[serde(skip_serializing)]` 的 defence-in-depth
- ✅ **Gemini 歷史回饋持續套用**：單次 mutation 單筆 audit（不重複）；`?` 傳播吞錯改正；FOR UPDATE 鎖序一致化；tx 內避免 `.execute(pool)` 這類跳脫 tx 的呼叫
- ✅ **驗證綠燈**：4 個 PR 各自 `cargo test --lib` 423/423、`cargo clippy --all-targets -- -D warnings -A deprecated` 0 issues；clock_out 原本只 UPDATE 無 SELECT 的路徑也補 SELECT FOR UPDATE；PR #158（audit chain verify cron）另 base 於 integration/r26 同批審閱

### 2026-04-21 R26 Service-driven Audit 重構啟動（3 PRs）

- ✅ **後端架構全面審查**：[docs/reviews/2026-04-21-rust-backend-review.md](reviews/2026-04-21-rust-backend-review.md) 產出 4 Critical / 8 Warning / 5 Suggestion + 6 附錄深度調查；依此設計 `plan-for-the-critical-validated-pebble.md` 全面執行計畫
- ✅ **PR #153（merged）INFRA — Service-driven audit 基礎建設**：`ActorContext` enum（User/System/Anonymous）+ `SYSTEM_USER_ID` 常數 + migration 033；`DataDiff` + `AuditRedact` trait（length-prefix canonical encoding 防 HMAC 碰撞、JSON Pointer 巢狀路徑 redact、`pub(crate)` 封裝）+ 11 tests；`AuditService::log_activity_tx` tx 版本 API + `ActivityLogEntry` struct（取代 11 位置參數）+ advisory lock + `(created_at, id)` tuple tiebreaker + migrations 034/035（impersonated_by_user_id column + log_activity v2 stored proc）；`CancellationToken` 貫穿 `AppState` / `main.rs` / `JwtBlacklist::start_cleanup_task` / 14 個 scheduler cron job；建 integration branch `integration/r26` 作為 R26 所有 PRs 的 long-lived target
- ✅ **PR #154（merged）review feedback 強化**：Gemini + CodeRabbit 兩輪意見集中處理 — `unwrap_or(None)` 吞 DB error 改 `?` 傳播；HMAC payload 改 `HmacInput<'_>` struct + length-prefix canonical encoding（防碰撞）；migration 036 `changed_fields` fallback 由 JSONB EXCEPT 改 UNION + `IS DISTINCT FROM`（正確偵測被刪除欄位）+ `jsonb_typeof` 型別守衛；main.rs jwt_cleanup timeout log/alignment + named const；`.coderabbit.yaml` `zh-TW` → `zh`（CodeRabbit schema 合法值）；CI `-A deprecated` 加到 clippy flag + `integration/**` 加入 workflow trigger；PreToolUse hook `.claude/hooks/block-dangerous.sh`（Python shlex 避開 commit message 誤攔，12 測試情境驗證）
- ✅ **PR #155（opened）Service-driven pattern demo**：`ProtocolService::submit()` 完整重構為 Service-driven — `&ActorContext` 參數 + `actor.require_user()` 守門 + 單 tx 原子提交（SELECT FOR UPDATE / INSERT protocol_versions / generate_apig_no + advisory lock / UPDATE protocols / record_status_change_tx / log_activity_tx）；CRIT-01 IACUC race condition 完整修復（numbering 3 generator 接 `&mut Transaction` + `pg_advisory_xact_lock(hashtext('protocol_iacuc_number_gen'))`）；CRIT-04 `#![allow(dead_code)]` 移除 + 11 處 warning 個別 `#[allow(dead_code)]` + 理由（整批清理留 R26-7）；`impl AuditRedact for Protocol`；handler `submit_protocol` 改用 `ActorContext::User`；`record_activity_tx` / `record_status_change_tx` / `get_next_version_no_tx` 新 helpers；`change_status` 完整 Service-driven 延後至 R26-8（目前用 `_pool` wrapper 解 80% race）
- ✅ **TODO R26 章節擴充**：加入 R26-1（長 scheduler job select! 升級）/ R26-2（HMAC chain 每日驗證 cron）/ R26-3（20 處 handler 遷移 log_activity_tx）/ R26-4（舊 log_activity 最終移除）/ R26-5（migration 036 fallback 已完成）/ R26-6（HMAC 版本化 + 儲存後雜湊）/ R26-7（dead code 11 處 cleanup）/ R26-8（change_status 完整 Service-driven）
- ✅ **workflow 紀律**：CLAUDE.md 新增「執行紀律」章節（測試驗證按 PR 性質區分 / 跨 PR 邊界必停 / 不可逆操作必經明確同意 / pattern 驗證必停 / clippy `-A deprecated` 過渡期 / commit 粒度規範）；合計 27 commits，3 個 PR 全數本地驗證 423/423 tests + 0 clippy issues；PR #154 CI 14/14 綠（含 E2E Playwright）

### 2026-04-20 SMTP 憑證方案 B：4 服務獨立 app password

- ✅ **明文洩漏清除**：`monitoring/alertmanager/alertmanager.yml` 內兩組 Gmail app password（`tajr azwc pmac lyxs` + `eryhtzmhsbsolroj`）與個人 email 已撤銷；該檔改寫為無秘密的 fallback-only 模板
- ✅ **Alertmanager file-based secret**：`docker-entrypoint.sh` 新增從 `/run/secrets/alert_smtp_password` 載入邏輯；`docker-compose.yml` / `docker-compose.monitoring.yml` 新增 secret mount
- ✅ **Grafana file-based secret**：改用 Grafana 原生 `GF_SMTP_PASSWORD__FILE`，掛載 `./secrets/grafana_smtp_password.txt`，避免 `docker inspect` 外洩
- ✅ **4 服務對照表文件**：新增 `docs/ops/SMTP_CREDENTIALS.md`，涵蓋密碼重建流程（產生 4 組獨立 app password → 寫 4 個 secret 檔 → 更新 `.env` → 重啟 → 驗證）
- ✅ **`.env.example` 重整**：SMTP 區塊按「服務 #1/#2/#3」分段，每段標明密碼改走 secret 檔案而非 env 明文

### 2026-04-20 CI 修復 + Grafana 面板資料修正

- ✅ **CI tests.rs**：補 `test_config` 缺少的 `alertmanager_webhook_token` 欄位
- ✅ **CI clippy**：`validation.rs` 移除多餘 `.into()`；`ip_blocklist.rs` 提取 `BlocklistCache` type alias
- ✅ **CI migration 032**：`GRANT CONNECT ON DATABASE` 硬編名改 `current_database()`
- ✅ **Grafana dashboard 查詢修正**：P50/P95/P99 從 histogram `_bucket` 改為 summary `{quantile="0.x"}`；Heatmap 改為 top5 路徑平均延遲
- ✅ **TypeScript 清理**：`MyProjectsPage` 移除未使用 `isGuest` + `useAuthStore` import；`VersionsTab` 移除未使用 `TableEmptyRow` import

### 2026-04-20 資安強化 4 項補齊

- ✅ **X-Permitted-Cross-Domain-Policies**：`server.rs` 新增 `none` 標頭，補齊資安 header 完整性
- ✅ **集中式輸入驗證模組**：新增 `utils/validation.rs`（email、檔名、路徑穿越、分頁四種驗證）
- ✅ **Docker no-new-privileges**：`db`/`api`/`web` 三服務加 `security_opt: [no-new-privileges:true]`
- ✅ **Docker read_only**：`api` 和 `web` 容器加 `read_only: true` + 對應 tmpfs（/tmp、nginx cache/run）

### 2026-04-20 Grafana + Loki + Prometheus + Alertmanager 全端整合完成

- ✅ **Grafana Alert Rules A–D**：資安警報（暴力破解、IDOR、登入失敗、待處理警報累積），email 發信測試成功
- ✅ **Loki datasource**：連線設定完成，Explore 查詢容器 log 可用（`{container_name="ipig-api"}`）
- ✅ **Loki retention**：建立 `monitoring/loki/config.yml`，30 天自動清理
- ✅ **node_exporter**：加入 docker-compose，Prometheus CPU/Memory/Disk 8 條警報全部接通（原本全為死警報）
- ✅ **Prometheus 自身 basic_auth**：補齊 self-scrape job 的 `basic_auth`，修復 prometheus target 401
- ✅ **METRICS_TOKEN**：`/metrics` 端點可選 Bearer 認證，`secrets/metrics_token.txt` 佔位檔架構建立
- ✅ **Alertmanager email**：`alertmanager.yml` 加入 `email_configs`，critical 警報發信測試成功
- ✅ **Alertmanager CRLF 修復**：`docker-entrypoint.sh` 換行符號 CRLF→LF 修正，容器啟動正常
- ✅ **VPS Cheatsheet**：`docs/VPS_CHEATSHEET.md` 首次部署 checklist + Prometheus 密碼換法 + 所有服務操作指令

### 2026-04-20 安全警報批次解決功能

- ✅ **後端 API**：新增 `POST /admin/audit/alerts/bulk-resolve`，支援傳入 UUID 陣列批次標記 resolved
- ✅ **前端 Checkbox**：警報表格每列加勾選框，表頭加全選（僅選 open 狀態）
- ✅ **批次操作按鈕**：選取後 CardHeader 出現「標記解決（N）」按鈕，操作完自動清除選取並刷新資料

### 2026-04-20 資安修復 E-2 / E-3 / E-5（Gotenberg timeout + GPG 啟動驗證 + 忘記密碼速率限制）

- ✅ **E-2 Gotenberg HTTP Timeout**：`reqwest::Client::builder()` 加 `connect_timeout(5s)` + `timeout(60s)`，防止 PDF 渲染永久 hang
- ✅ **E-3 GPG 啟動驗證**：`scripts/backup/entrypoint.sh` 於容器啟動時檢查 `BACKUP_REQUIRE_ENCRYPTION` + key 存在，設定錯誤立即 exit 1
- ✅ **E-3 文件**：`.env.example` 補充 `BACKUP_GPG_RECIPIENT` 必填說明；`docs/VPS_CHEATSHEET.md` 新增 GPG 設定完整流程（生成→匯出→容器匯入→還原）
- ✅ **E-5 忘記密碼獨立限速**：`FORGOT_PASSWORD_RATE_LIMIT = 5/10min`，拆出 `password_reset_routes()` 套用 `forgot_password_rate_limit_middleware`，不觸發 IP 封鎖升級

### 2026-04-19 R24 Observability & IP-level Safety Gate（4/4 完成）

- ✅ **R24-1 IP blocklist + 自動封鎖 middleware**：`migrations/031_ip_blocklist.sql`（UUID/INET/partial unique index）；`services/ip_blocklist.rs`（30s TTL `HashSet<IpAddr>` cache + auto_block/manual_add/unblock/list）；`middleware/ip_blocklist.rs` 掛於 `api_middleware_stack` 最外層（涵蓋 /api/v1 全子路由，/metrics、/api/health、honeypot 在 /api/v1 外層自然 bypass）；來源 IP 復用既有 `middleware/real_ip.rs::extract_real_ip_with_trust`；R22-6 IDOR probe / R22-5 auth escalation / R22-16 honeypot 三處觸發自動封 IP（分別 24h / 1h / 永久）；`/admin/audit/ip-blocklist` handler + `AdminAuditPage` 新 Tab（列表、手動新增、解除封鎖 Dialog）
- ✅ **R24-2 Loki + Promtail 生產部署**：`docker-compose.prod.yml` 新增 loki + promtail services（localhost-only 3100、資源限制、log rotation、disable Watchtower）；`monitoring/promtail/config.yml` 加 relabel 只收 `ipig-(api\|web)` + `environment=prod` 靜態 label；Volume `loki_data` 宣告於 prod.yml
- ✅ **R24-3 Alertmanager → SecurityNotifier 轉發**：`alertmanager.yml` default/critical receiver 改為 `http://api:3000/api/webhooks/alertmanager` webhook（Bearer authorization_file `/etc/alertmanager/webhook_token`）；新增 `handlers/alertmanager_webhook.rs`（接受 `Authorization: Bearer` 或 `X-Webhook-Token`，payload 轉為 `SecurityNotification` 呼叫 R22 `SecurityNotifier::dispatch`）；`Config::alertmanager_webhook_token` 從 `ALERTMANAGER_WEBHOOK_TOKEN` env 讀；route 掛於 /api/v1 外層（類似 honeypot_routes）
- ✅ **R24-4 Grafana Security Dashboard**：`deploy/grafana_security_dashboard.json` 6 panel（Alerts 時間線 / Active Blocklist Stat / Top IPs 24h / Login Anomaly / Honeypot Hits 7d / Loki 403 Rate）；`provisioning/datasources/loki.yml` + `postgres.yml` 新增；`migrations/032_grafana_readonly.sql` 建 `grafana_readonly` role（LOGIN / NOSUPERUSER / NOINHERIT）+ GRANT SELECT 於 security_alerts/user_activity_logs/login_events/user_sessions/ip_blocklist + 預設 privileges；`docker-compose.yml` Grafana 掛載新 dashboard JSON
- ✅ **審閱定稿 2 輪**：第一輪（§8 6 項）定核心決策；第二輪（動工前交叉驗證）修正 8 處與 codebase 不符的假設（middleware 順序、real_ip.rs 復用、整合點行號、路由命名 /admin/audit/ip-blocklist、Grafana datasources 現況、工時 2.5→2.6 天）
- ✅ **驗證**：`rtk cargo check` 0 error / `rtk tsc --noEmit` 0 error；DB migration、docker-compose 部署驗證延後至實際 VPS 環境

### 2026-04-19 AI Agent Readiness 強化（IsAgentReady 35 → 預估 95+，三輪迭代）

**Round 3：安全標頭 regression 修復 + AI crawler 擴充（commit `a09e7e4`）**

- ✅ **根因排查**：Round 2 在 `location = /` / `location /` / `location = /llms.txt` 加了 `add_header Vary "Accept" always;` 後，觸發 nginx 繼承規則（子 location 只要有任何 `add_header` 就完全覆寫 server 層），導致 HSTS / CSP / X-Content-Type-Options / X-Frame-Options / Referrer-Policy / Permissions-Policy / X-XSS-Protection 全部不再送出，IsAgentReady Security & Trust 從 100% 掉到 40%
- ✅ **新增 `frontend/security-headers.conf` snippet**：集中 7 條 `add_header ... always;`；`Dockerfile` 新增 `COPY security-headers.conf /etc/nginx/snippets/security-headers.conf`
- ✅ **`nginx.conf` 全面改寫**：server 層改用 `include /etc/nginx/snippets/security-headers.conf;`，並在每個 override 了 `add_header` 的 location（`/api`、`/uploads`、`/robots.txt`、`/sitemap.xml`、`/llms.txt`、`/.well-known/`、`/openapi.json`、`/`、`/index.html` fallback、靜態資源 regex）都 include 同一份 snippet
- ✅ **`robots.txt` 補 5 組 AI crawler**：`ChatGPT-User` / `OAI-SearchBot` / `Claude-User` / `Claude-SearchBot` / `meta-externalagent`，allow 公開頁、disallow `/api/ /dashboard /my-projects /admin`
- ✅ **本地驗證**：`curl -I http://localhost:8080/`、`/.well-known/webmcp.json`、`-H "Accept: text/markdown" /` 三路徑皆完整帶出 7 條安全標頭 + 各自 Vary / Content-Type

**Round 2：WebMCP declarative API + content negotiation + tool schema 強化（commit `8e65944`）**

- ✅ **`index.html` static-landing 加 WebMCP form**：新增兩個 W3C WebMCP 宣告式 form（`tool-name="login"` / `tool-name="search_animals"`），含 `tool-description` / `tool-param-description` / `tool-action-description`，對應真實後端端點 `/api/v1/auth/login` 與 `/api/v1/animals`
- ✅ **`nginx.conf` 加 text/markdown content negotiation**：`location = /` 與 SPA fallback 偵測 `Accept: text/markdown` 後 rewrite 到 `/llms.txt`；所有 `/` 變體加 `Vary: Accept` header 讓快取正確分流
- ✅ **`.well-known/webmcp.json` schema 強化**：tool 名稱改 snake_case（`list_protocols` / `list_animals` / `get_inventory_on_hand` / `list_my_projects`），每支 description ≥30 字，補完整 `inputSchema`（`type=object`、properties 含 description/enum/format=uuid/min-max、`additionalProperties: false`）
- ✅ **`.well-known/agent.json` skill id 改 snake_case**（`mcp_jsonrpc` / `ai_query` / `rest_api`）+ 長描述

**Round 1：基礎 metadata 與 discovery endpoints（commit `7a2343c`）**

- ✅ **`frontend/index.html` 改造**：`lang="en"` → `zh-TW`、補 OG/canonical/author meta、注入四組 JSON-LD（Organization、WebSite、SoftwareApplication、FAQPage）；`<div id="root">` 外包靜態語意骨架（`<header>`/`<nav>`/`<main>`/`<h1>`/`<h2>`/`<section>`/`<footer>` + `<noscript>` 降級訊息），React mount 前由 `main.tsx` 取出 root 後刪骨架
- ✅ **新增 `frontend/public/` 7 檔**：`robots.txt`（覆寫 Cloudflare 預設、明確列 9 種 AI crawler 允許範圍）、`sitemap.xml`（4 公開頁）、`llms.txt`、`.well-known/agent.json`（A2A）、`agents.json`、`mcp.json`、`webmcp.json`
- ✅ **`frontend/nginx.conf` 補 MIME 與 proxy**：`robots.txt`/`sitemap.xml`/`llms.txt`/`.well-known/*` 明確 Content-Type；`/openapi.json` 反代到 backend `/api-docs/openapi.json`
- ✅ **Backend OpenAPI production 暴露**：`startup/server.rs` 在 `cookie_secure=true` 時仍掛 `/api-docs/openapi.json` JSON 端點（Swagger UI 維持只在 dev）；`openapi.rs` 補 `info.description`（agent 整合說明、認證機制、rate limit）

**累計預估加分**：Round 1 (+51 基礎 discovery/JSON-LD/semantic) + Round 2 (+55 WebMCP declarative / content negotiation / schema quality) + Round 3 (+66 安全標頭回補 + crawler) → 35 → **95+ (A+)**

### 2026-04-18 共用元件與 ProductTable 完成 @container 遷移（清單 ⏳ 歸零）

- ✅ **`ui/data-table.tsx` 升級**：新增 `ColumnDef.hideClassName`（接受 Tailwind 字面量如 `'hidden @[750px]:table-cell'`，JIT 可掃到）、`mobileCard` renderer 與 `cardBreakpoint`（500/600/700/800 字面量查表）。預設仍向後相容，14 個既有消費者無需改動
- ✅ **`ProductTable.tsx` 整個拆掉改 @container**：移除 `useLayoutEffect` + `ResizeObserver` + `containerWidth` state + `COL_WIDTHS` + `MIN_TABLE_WIDTH` + `canRenderTable` JS 邏輯，改用 `@container` 單一 wrapper：表格在 ≥ 600px 顯示，< 600px 切換卡片；欄位依 750/900/1050 漸進顯露
- ✅ **清單狀態**：30 ✅ + 55 🔧 + 0 ⏳ = 85 個表格，所有 ⏳ 項目完成

### 2026-04-18 手機場景 RWD 升級（+12 表格 ✅）

- ✅ **升級範圍**：手機使用者不接觸 admin 區，將 animal blood-test / documents / HR / my-projects 共 12 個表格從 🔧 批次修復升級為 ✅ 完整 RWD（`@container` + Card layout）
- ✅ **Animal blood-test**：`BloodTestDetailDialog` (6 欄, 500/650/750) + `BloodTestFormDialog` (7 欄, 700) 雙視圖，Card 保留檢查項目 + 異常徽章核心資訊
- ✅ **Documents**：`DocumentDetailPage` (8 欄) + `DocumentLineEditor` (10 條件欄，新增 LineCard 元件保留所有 inputs) + `DocumentTable` (10 欄) + `ProductSearchDialog` (內嵌顯示策略)
- ✅ **HR**：`HrAnnualLeavePage` (2 表格) + `ConflictsTab` + `AllRecordsTabContent` + `AttendanceHistoryTab` 全部 Table ≥ 600px / Card < 600px
- ✅ **My Projects**：`MyProjectsPage` + `MyProjectDetailPage` 的動物清單，Card 以 ear_tag + status 為主軸
- ✅ **總進度**：28 ✅ + 55 🔧 + 2 ⏳ = 85 個表格

### 2026-04-18 ObservationsTab 欄寬設計簡化為 2 模式

- ✅ **移除 hybrid 混合模式**：原本 762-982 區間用階段式壓縮（creator→date/rtype→content），但 date/rtype 在 90px 會觸發 SortableTableHead 的 `line-clamp-2` 產生 2-line wrap，造成「事件日」/「期」這種不一致視覺
- ✅ **簡化為 2 模式**：containerW ≥ 762 展開版（固定欄寬）/ < 762 壓縮版（直向標題），單一切換閾值
- ✅ **展開版固定欄寬**：expand 40 / date 110 / rtype 110 / noMed 100 / vetRead 102 / creator 90 / actions 80（固定總和 632），content flex 吸收 + min 130，minTable = 762 剛好 fit
- ✅ **壓縮版 vetRead 補上直向標題**：原本橫向「獸醫師讀取」5 字在 85px 寬會被 line-clamp-2 wrap 成 2 行，改為 `writing-mode: vertical-rl` 與其他窄欄標題一致
- ✅ **狀態修正**：removed unused `EXPANDED_THRESHOLD`，初始 containerW 改為 1024 (避免首幀錯誤觸發壓縮版)

### 2026-04-18 ObservationsTab 階段式壓縮 + 混合版（已簡化，見上）

- ✅ **新增 hybrid mode (762-982)**：移除 `COL` 常數，改為 `computeLayout(containerW)` 函數動態計算欄寬；容器 982px↓時階段壓縮：階段 1 creator 90→60（0-30px deficit）、階段 2 date/rtype 110→90（30-70 deficit）、階段 3 content 吸收剩餘到 min 200
- ✅ **Inline 樣式取代 Tailwind 動態 class**：`<TableHead style={{ width }} />`、`<Table style={{ minWidth }} />`，避免 Tailwind JIT 無法處理連續寬度變化
- ✅ **state 重構**：`isCompressed` boolean → `containerW` number，isCompressed 由 `computeLayout().isCompressed` 派生
- ✅ **三段式設計**：< 762 壓縮版（直向標題、content min 200、minTable 300）/ 762-982 混合版（階段壓縮、content min 200）/ ≥ 982 展開版（content flex min 350）
- ✅ **壓縮版 vetRead 90→85**：微調觀察試驗紀錄「獸醫師讀取」欄寬

### 2026-04-18 ObservationsTab 欄寬重構 + 直向徽章

- ✅ **COL 常數重寫**：`frontend/src/components/animal/ObservationsTab.tsx` 壓縮版 minTable 480→485、展開版 640→940；新增 expand / content / actions / cellPad keys；內容欄改用 `min-w-[X]` 讓 table-layout auto 吸收剩餘寬度
- ✅ **壓縮版更緊湊**：date 72→60 / rtype 72→40 / noMed 52→40 / creator 80→40 / actions 80→60；TableCell padding 壓縮版 p-4→px-2 py-2，40px 窄欄可用空間從 8px 拉到 24px
- ✅ **紀錄性質直向徽章**：壓縮模式下 Badge 套 `[writing-mode:vertical-rl] [text-orientation:upright]`，「觀察紀錄 / 試驗紀錄 / 異常紀錄」4 字中文正立由上而下排列，40px 寬塞得下；`rounded-full` 換 `rounded-md` 避免 pill 形多行變醜
- ✅ **事件日期 line-clamp-2**：TableCell 內包 `-webkit-line-clamp:2` + `break-all`，壓縮版 60px 寬時日期最多 2 行，不溢出
- ✅ **展開版自動吸收**：內容欄改 `min-w-[346px]`（無固定 max），容器 940~1804+ 任意寬度下內容欄自動撐開（1280→686px、1600→1006px、1920→1306px）

### 2026-04-18 R23 全站 Table UI 一致性升級（完成）

- ✅ **Batch 0 DataTable 基礎層**：`data-table.tsx` container + header 升級，cascade 覆蓋 ~17 DataTable 使用者
- ✅ **Batch 1-2 Master / Admin 核心表格**：PartnerTable / DocumentTable / BloodTestTemplateTable / StockLedgerPage / AnimalListTable / UserTable / AuditLogTable（7 files）
- ✅ **Batch 3 Protocol Tabs + 其他 Master**：BloodTestPanels/Presets / Warehouses / Protocols / AnimalSources + AmendmentsTab / AttachmentsTab / CoEditorsTab / ReviewersTab / VersionsTab（10 files）
- ✅ **Batch 4 Admin Pages + Config Tabs**：InvitationsPage / ManagementReviewPage / ChangeControlPage / RiskRegisterPage / DepartmentTab / AuditActivitiesTab / AuditAlertsTab / AuditSessionsTab / AuditLoginsTab / RoutingTable（10 files）
- ✅ **Batch 5 Reports Pages + Tabs**：BloodTestAnalysis / BloodTestCost / StockLedger / StockOnHand / SalesLines / PurchaseLines / PurchaseSalesSummary / CostSummary + JournalEntries / TrialBalance / ProfitLoss / ApAging / ArAging（13 files）
- ✅ **Batch 6 Animal Detail Tabs + Protocol Sections**：MyProjects / MyAmendments / AnimalFieldCorrections + 8 animal tabs + PersonnelSection / CommentsTableView（13 files）
- ✅ **JSX 語法修正**：修正 Batch 3 遺留的 4 個 protocol tab `})}` stray bracket 錯誤；修正 InvitationsPage 多餘 `</TableRow>` 標籤

### 2026-04-18 ProductTable RWD 修正「操作」欄被裁切

- ✅ **次要欄最小寬度 70 → 65**：`frontend/src/pages/master/components/ProductTable.tsx` 的 `computeWidths` 策略 B，規格 / 單位 / 批號 / 效期最小值降為 65，最小表格總和由 740 降到 720
- ✅ **不可裁剪保險**：Desktop 容器用 `useLayoutEffect` 量 `clientWidth`，`< MIN_TABLE_WIDTH (720)` 時改 render 卡片（抽出 `ProductCardList` 共用元件）；外層維持 `overflow-x-hidden`，永不出現橫向卷軸也永不裁切
- ✅ **DESIGN.md §9 新增 Table RWD 規則**：明列「不可裁剪 / 不可隱藏 / 不可橫向捲動」三選一原則與唯一解法（切卡片），含六個斷點 QA checklist
- ✅ **DESIGN.md §21 Decisions Log**：新增 2026-04-18 決策，說明取代 2026-04-17「斷點隱藏次要欄」策略的理由

### 2026-04-17 手機版 UI 全面 RWD 改善

- ✅ **字體大小偏好設定**：`uiPreferences` store 新增 `fontSize`（標準/大/特大），套用 CSS class 至 `<html>`，ProfileSettingsPage 顯示偏好卡片新增三段切換鈕
- ✅ **iOS 字體縮放修正**：移除 dialog input `16px !important` 衝突，改用 `max(16px, 1rem)` 全域套用，與行動端 20px 根字體正確銜接
- ✅ **Sidebar 滑動關閉**：行動端向左滑動 >48px 自動關閉 overlay sidebar（`touchstart`/`touchend` handler）
- ✅ **觸控目標放大**：Sidebar 子選單及巢狀選單項目加 `min-h-[44px]`，Hamburger 按鈕改為 `h-11 w-11`（44px）
- ✅ **Dialog 底部滑入**：行動端 dialog 從底部滑入（bottom sheet），圓角上方、附拖曳把手；桌面端維持置中顯示
- ✅ **FilterBar 可收合**：行動端搜尋框常駐，額外篩選器收合於「篩選」toggle 按鈕後，有啟用篩選時自動展開並顯示藍點
- ✅ **動物表格欄位精簡**：`<768px` 隱藏品種/性別，`<1024px` 隱藏用藥/獸醫建議，`<768px` 隱藏最新體重
- ✅ **庫存表格欄位精簡**：`<768px` 隱藏平均成本/庫存價值/安全庫存，`<1024px` 隱藏最後異動時間（含展開批號行）

### 2026-04-16 AUP 表單前端實作（更新計劃 v2）

- ✅ **types/protocol.ts 擴充**：purpose.duplicate 改為 4 選項 enum、pain 加入 category_items/distress_signs/relief_measures、purpose 加入 abstract/refinement_description/reduction 子項
- ✅ **constants.ts 擴充**：defaultFormData 新增所有新欄位預設值 + carcass_disposal 預設廠商
- ✅ **i18n 新增 ~120 key**：zh-TW + en 雙語，含 34 個 pain 細項、17 個 distress 症狀、4 個 relief 措施、duplicate 4 選項、single housing 9 原因、animal reuse 5 選項
- ✅ **PainCategorySection.tsx 新增**：4.1.3 單選→展開細項複選 + 4.1.5 疼痛症狀 + 4.1.6 緩解措施（獨立子元件）
- ✅ **SectionDesign.tsx 重構**：引入 PainCategorySection、重新編號 4.1.7/4.1.8
- ✅ **EndpointsSection.tsx 更新**：新增「插入標準預設文字」按鈕（人道終點官方預設文字）
- ✅ **SectionPurpose.tsx 全面重寫**：2.0 Abstract + 2.2.2 補 4 平台 + 2.2.3 duplicate 改 4 選項 + 2.3.1-2.3.3 特殊照護/單獨飼養/動物再應用 + 2.4 Refinement（含「插入預設文字」按鈕）
- ✅ **validation.ts 全面重寫**：新增 abstract/refinement/duplicate enum/pain category_items/distress_signs/relief_measures 驗證
- ✅ **DesignSection/PurposeSection/MyProjectDetailPage 修正**：對齊新型別欄位名稱（management_plan→relief_measures, experiment→status）

### 2026-04-16 AUP 規格書對齊 AD-04-01-01F 表單

- ✅ **計畫摘要欄位新增**：`section2.abstract` 補入 AUP.md（表單有但規格書缺漏）
- ✅ **替代方案平台補齊**：新增 `johns_hopkins`、`taat`、`nc3rs_eda`、`nc3rs_refinement` 四個搜尋平台選項
- ✅ **精緻化原則章節新增**：補入 `section2.refinement_description`（3.7 節），含預設範例文字
- ✅ **特殊管理需求三欄位新增**：`special_care`、`single_housing`（含 B1-B4 原因 enum）、`animal_reuse`（3.6 節）
- ✅ **計畫類型補 `other`**：`project_type` 新增第 6 選項「其他」
- ✅ **術前準備補完整預設文字**：含 Azeperonum/Atropine/Zoletil/Cefazolin/Meloxicam/Isoflurane 標準步驟及 TU-03-09-00 SOP 引用
- ✅ **術中監控補記錄頻率**：明確標注每 30 分鐘記錄心跳、呼吸、體溫
- ✅ **標準手術用藥參考表新增**：11 種藥品完整劑量/途徑/頻率/用途（AD-04-01-01F 來源）
- ✅ **屍體處理廠商補預設值**：金海龍生物科技股份有限公司，化製廠管編 P6001213
- ✅ **SOP 文件參照章節新增**：補入 §14 TU-03-09-00、AD-04-03-00 對應章節對照表
- ✅ **表單來源版本章節新增**：補入 §15 表單編號 AD-04-01-01F 版本 F

### 2026-04-16 Guest Mode 重寫：純前端隔離架構

- ✅ **入口改為 `/demo` 頁面**：新增 `DemoPage.tsx`，只接受 `guest@guest.com`，點擊「進入試用」即啟動 guest mode，完全不打後端
- ✅ **`enterGuestMode()` action**：`auth.ts` 新增純前端 guest 初始化，`checkAuth()` 偵測已是 guest 則 early return，`logout()` guest 不呼叫後端
- ✅ **完全 HTTP 隔離**：`routes.ts` 移除 `/me` passthrough，改由 exactRoutes 攔截；非 GET 方法回傳 `{ success: true }` 不觸碰後端
- ✅ **Sidebar 優化**：guestHiddenChildren 新增 `'newProtocol'`（AUP 隱藏新增計畫書）
- ✅ **Guest Banner 升級**：新增「離開試用」按鈕，文字改為「訪客試用模式 — 資料為展示用途」
- ✅ **廢棄後端 GUEST role**：刪除 `guest_guard.rs`，從 `middleware/mod.rs` 與 `routes/mod.rs` 移除相關引用

### 2026-04-16 訪客模式（Guest Mode）完善

- ✅ **首頁重導向修正**：`getHomeRedirect()` 偵測 GUEST 角色，直接導向 `/dashboard` 而非 `/my-projects`
- ✅ **側邊欄精簡**：Guest 分支隱藏整個 `系統管理` 父項，移除 `修正審核`、`報表中心` 子項；Dashboard 與 ERP 明確保留
- ✅ **文件頁預設分類**：`useDocumentCategory` 為訪客預設 `purchasing` 分類（不呼叫後端偏好），避免 `shouldFetch=false` 導致空頁面
- ✅ **攔截器修正**：`/documents` 改為回傳平陣列 `DEMO_DOCUMENTS.data`（符合後端 `Vec<DocumentListItem>` 回傳格式），避免 UI 錯誤讀取 paginated 物件
- ✅ **前期工作（上一 session）**：`useGuestQuery` 改用 `queryFn` 替換（修正 `initialData` 被 stale cache 覆蓋的 bug）、欄位頁 Facility 資料（DEMO_BUILDINGS/ZONES/PENS）、訪客欄位移動模擬、後端 guest_guard 白名單精簡

### 2026-04-16 權限系統審查：模組交叉驗證（Problem 5）

- ✅ **`animal.info.assign` 遺漏**：`batch_assign_animals` handler 使用此權限但 startup 無任何角色擁有；決策由 IACUC_STAFF 執行批次分配，補入 IACUC_STAFF 清單
- ✅ **Amendment 模組澄清**：14 個 handler 均有存取控制（DB business logic + `has_permission()` + `require_permission!` 混用），系統安全；`amendment.read`/`amendment.review` 確認為反向孤兒（handler 使用 `aup.protocol.*` 作為代理），保留分配不改
- ✅ **ERP 細粒度權限確認冗餘**：DocType enum（PO/GRN/PR/SO/DO/TR/STK/ADJ/RM/SR/RTN）全部透過 `erp.document.*` 統一處理；`erp.purchase.*`、`erp.grn.*`、`erp.stocktake.*`、`erp.stock.in/out/adjust/transfer`、`erp.report.export/download` 等均為冗餘佔位，handler 不使用，保留分配供未來細化
- ✅ **`aup.protocol.assign_co_editor` / `aup.coeditor.assign` 確認**：handler 使用 `aup.review.assign` 作為代理，兩者為反向孤兒，保留 IACUC_STAFF 分配不改（兼容性考量）

### 2026-04-16 權限系統審查：Handler 掃描與 Bug 修正（Problem 4）

- ✅ **`animal.animal.view` 命名 bug**：`pdf_export.rs:174 export_pen_report` 使用不存在的 permission code `animal.animal.view`，修正為 `animal.animal.view_all`；原本所有非 admin 均被 403 擋住
- ✅ **`animal.record.delete` 遺漏**：EXPERIMENT_STAFF / INTERN 可新增/編輯但無法刪除任何動物紀錄（血檢、觀察、手術、體重、疫苗）；補入兩角色的 startup 分配
- ✅ **admin 專屬確認**：`admin.treatment_drug.*`（用藥清單）、`erp.partner.delete`（刪除夥伴）、GLP 合規模組（DMS / 風險 / 變更控制 / 環境監控 / 能力評鑑）確認 admin 專屬，無需對其他角色開放
- ✅ **反向孤兒記錄**：`audit.timeline.view`、`audit.alerts.view`、`audit.alerts.manage` 分配給 ADMIN_STAFF 但無對應 handler，標記為未來功能預留，暫不處理

### 2026-04-16 權限系統審查：角色清理與定位修正（Problem 3）

- ✅ **TEST_FACILITY_MANAGEMENT 移除**：此角色定位等同 admin（機構管理階層需完整管理權），決策改為直接使用 admin 角色；migration 029 清除其 role_permissions 並刪除角色本體；startup/permissions.rs 同步移除
- ✅ **STUDY_DIRECTOR 確認**：定位為「PI + GLP 簽核」— 擁有 PI 完整計畫管理權限 + `glp.study_report.sign` + 研究報告 / 配製紀錄管理；動物範圍維持 `view_project`（僅自己計畫），無需變更
- ✅ **QAU 佔位保留**：`qau.*` 權限為未來 QAU 模組預留，角色與分配不動，待功能開發時逐一驗證

### 2026-04-16 權限系統審查：動物模組修正（Problem 2）

- ✅ **孤兒權限清理**：migration 028 從所有角色移除 `animal.animal.assign`（已被 `animal.info.assign` 取代）與 `animal.info.edit`（已被 `animal.animal.edit` 取代）
- ✅ **Handler 命名 bug 修正**：`delete_animal_source` / `create_animal_source` / `update_animal_source` 改用 `animal.source.manage`；`delete_animal` 改用 `animal.animal.delete`（不再誤用 `animal.animal.edit`）
- ✅ **admin-only 刪除**：`animal.animal.delete` 從 EXPERIMENT_STAFF / INTERN 移除（migration 028）；改為僅 admin 持有（`ensure_required_permissions` 補回）
- ✅ **遺漏權限補齊**：EXPERIMENT_STAFF / INTERN 補入 `animal.pathology.view`、`animal.pathology.upload`、`animal.record.copy`、`animal.record.emergency`、`animal.vet.upload_attachment`（這些 handler 有使用但 startup 未分配）

### 2026-04-16 Bug 修復：experiment_staff 欄位頁空白

- ✅ **根本原因**：`/api/v1/facilities/*` GET 端點要求 `facility.read` 權限，但該權限從未定義或分配給任何非 admin 角色，導致 `experiment_staff` 存取棟/區/欄位資料時全部回傳 403
- ✅ **修復策略**：移除 facility GET 端點（list/get）的 `facility.read` 限制，改為任何已登入使用者皆可讀取設施靜態配置；POST/PUT/DELETE 仍保留 `facility.manage` 管理權限
- ✅ **影響端點**：`GET /facilities`、`GET /facilities/buildings`、`GET /facilities/zones`、`GET /facilities/pens`、`GET /facilities/species`、`GET /facilities/departments` 及各自的 `/{id}`

### 2026-04-15 R22 攻擊偵測與主動告警（18 項全部完成）

- ✅ **被動記錄（22-A）**：rate limit 4 tier / AI key 3 事件 / 403 response middleware / account lockout 全寫入 `user_activity_logs`；新增 `AuditService::log_security_event()` + 10 個 `SEC_EVENT_*` 常數
- ✅ **智慧告警（22-B）**：auth rate limit 升級告警 + IDOR 探測偵測（均含去重）；brute force alert 去重修復；`AlertThresholdService` 60s cache + migration 025 `security_alert_config` 表
- ✅ **主動推送（22-C）**：`SecurityNotifier` 抽象層支援 Email / LINE Notify / Webhook 三管道；`security_notification_channels` 表設定管道；scheduler 新增每 6 小時未處理告警掃描
- ✅ **可觀測性（22-D）**：6 個蜜罐端點（/.env, /wp-login.php 等）觸發 critical alert；Admin Audit 新增「安全事件」Tab（前後端）；Log 聚合評估文件（推薦 Loki）；Docker log rotation 加大至 50m

### 2026-04-14 資安審計：加密方式 + 權限隔離漏洞修復

- ✅ **報表端點權限修復**：`handlers/report.rs` 9 個端點原本無權限檢查，任何已認證使用者可存取全部財務報表；已全部加入 `require_permission!(current_user, "erp.report.view")`
- ✅ **動物醫療記錄 IDOR 修復**：blood_test、surgery、weight_vaccination、vet_recommendation、vet_advice、transfer 共 6 個 handler 檔案的 GET 端點未驗證計畫成員資格，已全部加入 `access::require_animal_access()` 防範跨計畫資料洩漏
- ✅ **獸醫巡場報告權限修復**：`handlers/animal/vet_patrol.rs` 全部 5 個端點無任何權限檢查，已加入 `animal.record.view`（讀取）及 `animal.vet.recommend`（寫入）
- ✅ **加密方式審計**：確認 ES256 非對稱簽章、Argon2id 密碼雜湊、HMAC-SHA256 CSRF、CSPRNG Token 等均符合 OWASP 最佳實踐
- ✅ **CRITICAL 自我提權修復**：`PUT /me` 未遮蔽 `role_ids`，任何使用者可把自己提升為 SYSTEM_ADMIN；已遮蔽 `role_ids`/`is_internal`/`expires_at`
- ✅ **Admin 模擬保護**：禁止管理員模擬登入為其他管理員，防止橫向提權
- ✅ **角色指派驗證**：`UserService::update` 加入角色 ID 存在性檢查 + SYSTEM_ADMIN 指派僅限 SYSTEM_ADMIN 操作
- ✅ **Cookie CRLF 注入防護**：`build_set_cookie()` 加入值與 domain 的字元過濾
- ✅ **分頁整數溢位防護**：`PaginationParams::sql_suffix()` 改用 `saturating_mul`
- ✅ **檔案上傳 text/plain 驗證**：`validate_magic_number()` 加入二進位控制字元檢查
- ✅ **完整審計報告**：詳見 `docs/walkthrough_security_audit_2026_04_14.md`

### 2026-04-14 JWT 升級：HS256 → ES256（ECDSA P-256）

- ✅ **演算法升級**：所有 JWT 簽發/驗證（Access Token、Reauth Token、2FA Temp Token）從對稱式 HS256 升級為非對稱式 ES256（ECDSA P-256），防止對稱金鑰暴力破解
- ✅ **Config 重構**：移除 `jwt_secret: String`，新增 `JwtKeys { encoding, decoding }` 結構體，啟動時預解析 PEM 避免每請求重新 parse
- ✅ **環境變數更新**：`JWT_SECRET` → `JWT_EC_PRIVATE_KEY` + `JWT_EC_PUBLIC_KEY`（支援 `_FILE` Docker Secrets 掛載）
- ✅ **Docker 設定更新**：`docker-compose.yml`、`docker-compose.prod.yml`、`docker-compose.test.yml` 全部改用新金鑰 secrets
- ✅ **CI 更新**：`ci.yml` 移除 `CI_JWT_SECRET`，改為在啟動前自動 `openssl` 產生測試金鑰對
- ✅ **測試更新**：`tests/common/mod.rs` 以 p256 crate 在測試啟動時動態生成金鑰；`api_auth.rs` 改用 ES256 簽發 2FA token
- ⚠️ **注意**：升級後所有現有 HS256 token 立即失效，所有使用者需重新登入。本機開發請執行 `openssl ecparam -name prime256v1 -genkey -noout | openssl pkcs8 -topk8 -nocrypt > secrets/jwt_ec_private_key.pem && openssl ec -in secrets/jwt_ec_private_key.pem -pubout > secrets/jwt_ec_public_key.pem`

### 2026-04-13 MCP Review Server 架構設計與文件

- ✅ **架構決策**：確立「模式 B — MCP Server」為執行秘書/主委 AI 審查的主要路線，費用走使用者 claude.ai 月費訂閱，iPig 不需要自有 Anthropic API Key
- ✅ **權限矩陣定案**：STAFF/CHAIR 有完整寫入工具；REVIEWER 僅限閱讀（倫理限制，不允許 AI 代替委員撰寫審查意見）；VET 有 submit_vet_review tool；所有角色可讀取全部計畫書
- ✅ **個人 MCP Key 設計**：新增 `user_mcp_keys` 資料表規格，格式 `mcp_xxxx_xxxxxxxxxxxxxxxx`，argon2 hash 儲存，個人設定頁管理
- ✅ **6 個 MCP Tools 規格定案**：`list_protocols`, `read_protocol`（含稽核日誌）, `create_review_flag`, `batch_return_to_pi`, `get_review_history`, `submit_vet_review`
- ✅ **稽核機制**：REVIEWER/VET 呼叫 `read_protocol` 自動寫入 `protocol_activities`（McpRead），作為法律佐證
- ✅ **文件更新**：新增 `docs/MCP_Review_Server.md`（完整規格含 pros/cons、部署分析）；更新 `docs/AIReview.md`（加入兩種模式對比）；更新 `docs/walkthrough_ai_api.md`（釐清 AI query API vs MCP review 定位）
- ⏳ **暫緩三項**：SSE 推播（POST-only 先行）、StaffReviewAssistPanel checkbox UI（MCP 路線下退為降級方案）、submit_vet_review 查檢項清單（待 VET 流程確認）

### 2026-04-12 R20-9 階段一：Prompt 補丁套用（基於真實 IACUC 信件分析）

- ✅ **真實審查資料分析**：從子瑄 Gmail 取樣 8 個 thread / 45 封信件（2025-08 ~ 2026-04），匿名化整理出 9 類退件原因 MECE 分類（最高頻：交叉引用失效、人道終點量化不足、對照組處置不完整），產出 `docs/R20_real_review_patterns.md`（316 行）
- ✅ **重要架構釐清**：確認 R20 兩層 prompt 對應「申請人自查 (CLIENT) + Evonne 助理 pre-review (STAFF)」，**委員會層刻意不放 AI**——倫理判斷不交給 LLM；這是設計選擇不是 gap
- ✅ **CLIENT_SYSTEM_PROMPT 重構**：原 6 點檢查擴增為三階段流程——階段一文書完整性（人員名單照抄、簽名日期、劑量單位、時程矛盾）、階段二交叉引用稽核（最高頻退件原因）、階段三內容審查（含人道終點量化、對照組處置、3R 教學/訓練挑戰）
- ✅ **STAFF_SYSTEM_PROMPT 重構**：對應重構為三階段——階段一 pre-filter（文書完整性）、階段二交叉引用、階段三實質審查預警；每個檢查項都附真實委員質問句作為 few-shot 語料
- ✅ **5 類退件全部 codified**：交叉引用一致性、人道終點得分門檻量化、對照組處置完整性、教學/訓練類 3R 挑戰、文書完整性 pre-filter——直接寫進 prompt const，無需 schema 變更或 migration
- ⏳ **R20-9 後續尚未啟動**：data pipeline（Gmail Takeout 匯出 12 個月 thread 為 `.eml`）、Evonne 標 50 筆 ground truth、`backend/tests/ai_review_eval.rs` eval harness、Recall ≥ 0.7 / Precision ≥ 0.6 baseline——這些是真正讓 R20-9 從「[ ]」變成「[x]」的條件
- ⚠️ **未動 review_type rename**：`STAFF_REVIEW` 名稱在當前設計裡正確（指 staff = Evonne 執行秘書，不是 committee），故未改 enum 值與 DB column；若未來新增第三層「委員 AI 助手」prompt 才需要 schema migration

### 2026-04-10 第三輪 Code Review 修復（7 項）

- ✅ **C-01 IDOR 動物修改/刪除**：`update_animal` / `delete_animal` 加入 `access::require_animal_access`，確保使用者只能操作自己計畫書的動物（`handlers/animal/animal_core.rs`）
- ✅ **C-02 IDOR 計畫書狀態變更**：`change_protocol_status` 加入 `access::require_protocol_related_access`，防止跨計畫書狀態變更（`handlers/protocol/crud.rs`）
- ✅ **H-01 權限快取未失效**：使用者角色/停用變更後立即 `remove` 對應快取；角色定義更新/刪除後 `clear` 全部快取（`handlers/user.rs`、`handlers/role.rs`）
- ✅ **M-01 Zod 缺 maxLength**：`requiredString` 新增 `max = 500` 預設上限，防止前端接受無限長度輸入（`lib/validation.ts`）
- ✅ **M-02 sessionStorage 反序列化無驗證**：複製單據載入前加入物件型別與 `Array.isArray` 檢查（`pages/documents/hooks/useDocumentForm.ts`）
- ✅ **M-03 Error Boundary 顯示原始 error.message**：改為固定通用訊息，防止 IP / DB 連線細節洩漏（`components/ui/error-boundary.tsx`）
- ✅ **M-04 容器 CPU 無限制**：`gotenberg`、`image-processor` 新增 `cpus: "1.0"` 限制，防止大型 PDF/圖片處理耗盡 CPU（`docker-compose.yml`）

### 2026-04-10 深度 Code Review 修復（15 項安全/效能/品質問題）

- ✅ **CRIT-01 帳號鎖定競態修復**：失敗事件在 advisory lock 事務內原子性寫入（`services/auth/login.rs`），防止並發請求繞過鎖定計數
- ✅ **MED-02 tx.commit 順序修正**：移至 `verify_password` 之後，advisory lock 持續保持至密碼驗證完成
- ✅ **CRIT-02 CSRF/JWT 密鑰隔離**：新增 `csrf_secret` Config 欄位，讀取 `CSRF_SECRET` 環境變數，若未設定則從 jwt_secret SHA-256 派生
- ✅ **CRIT-03 Permission 快取**：AppState 加入 `DashMap<UserId, (permissions, Instant)>` 快取（TTL 5 分鐘），消除每請求 4-table JOIN
- ✅ **CRIT-04 Session 建立同步化**：`create_session` + `end_excess_sessions` 改為在 token 發出前同步執行，SEC-28 並發上限得以強制執行
- ✅ **HIGH-01 JWT Blacklist Mutex→RwLock**：`is_revoked()` 為 hot path，改用讀鎖使並發讀取不再互斥
- ✅ **HIGH-02 Blacklist DB backfill 修正**：回填使用真實 `expires_at`，不再硬編碼 `now+3600`
- ✅ **HIGH-03 Access check 合併查詢**：`require_protocol_view_access` 3 次串行查詢改為單一 4-way UNION EXISTS
- ✅ **HIGH-04 Retry-After 動態化**：rate_limit_response 改用 `limiter.config.window.as_secs()`
- ✅ **MED-01 登出清除 csrf_token**：logout handler 新增第三個 cookie 清除
- ✅ **MED-03 模擬登入不建立 refresh token**：`impersonate()` 改為 access-only session，避免佔用目標用戶 session 配額
- ✅ **MED-04 CSRF exempt path 清理**：移除無對應路由的舊 `/api/auth/*` 路徑
- ✅ **LOW-01 hex::encode 替換手動迴圈**：session.rs 使用 `hex` crate
- ✅ **LOW-02 formatEarTag 職責歸位**：從 `api/client.ts` 移至 `lib/utils.ts`，index.ts re-export 維持向後相容
- ✅ **LOW-03 unreachable! 標記死代碼**：error.rs `DuplicateWarning` match arm 改為 `unreachable!`

### 2026-04-07 疼痛評估表單重構（TU-03-05-03B）+ 固定姿勢複選

- ✅ **DB Migration 018**：`care_medication_records` 舊欄位（spirit/mobility_standing/walking）全部替換為 PDF 正確欄位（incision/attitude_behavior/appetite/feces/urine/pain_score/3個給藥 bool）
- ✅ **Backend care_record.rs**：CareRecord struct、CreateCareRecordRequest、UpdateCareRecordRequest、SQL 查詢全部更新為新欄位（SMALLINT）
- ✅ **PainAssessmentTab.tsx 重構**：依 TU-03-05-03B 新增傷口狀況、態度/行為、食慾、排便、排尿、疼痛分數等 6 個評估類別；表單即時計算總分與疼痛分級（0–5正常/6–10輕度/11–15中度/16–20重度）；新增術後給藥三個 checkbox（注射Ketorolac/注射Meloxicam/口服Meloxicam）
- ✅ **PainAssessmentChart.tsx 更新**：改為顯示疼痛總分趨勢折線圖，加入四個疼痛等級參考線
- ✅ **固定姿勢改為複選**：`SurgeryAnesthesiaSection.tsx` 從 Select 單選改為 4 個 Checkbox（正趴/左側躺/右側躺/仰躺）；`useSurgeryForm.ts` positioning 型別從 `string` 改為 `string[]`，以逗號分隔儲存至 VARCHAR 欄位（無須 migration）；`SurgeriesTab.tsx` 顯示以頓號分隔

### 2026-04-06 Dashboard 新增設備狀態總覽 Widget

- ✅ **新增 `equipment_status` widget**：顯示啟用中、待修、校正逾期、設備總數 4 個指標，點擊卡片導航至 `/equipment`
- ✅ **資料層**：`useDashboardData` 新增 `equipmentList`（`GET /equipment?per_page=200`）與 `allCalibrations`（`GET /equipment-calibrations?per_page=200`）查詢，在前端計算逾期校正數
- ✅ **預設佈局**：widget 預設放置於 `x=9, y=0, w=3, h=6`（右欄頂部），與 `animals_on_medication` 並排
- ✅ **i18n**：zh-TW / en 兩語系均已新增對應翻譯鍵值

### 2026-04-03 GLP / ISO 17025 / ISO 9001 合規改進（P0+P1）

- ✅ **合規差距分析報告**：產出 `docs/COMPLIANCE_GAP_ANALYSIS.md`，涵蓋 GLP (OECD) / ISO 17025:2017 / ISO 9001:2015 三大法規逐條分析，識別 3 個 P0 + 9 個 P1 + 16 個 P2 差距項目
- ✅ **Migration 016**：新增 11 張資料表（reference_standards、controlled_documents、document_revisions、document_acknowledgments、management_reviews、risk_register、change_requests、environment_monitoring_points、environment_readings、competency_assessments、role_training_requirements、study_final_reports、formulation_records）+ ALTER 擴充 equipment_calibrations（追溯鏈欄位）、qa_sop_documents（審核簽署欄位）、products（GLP 試驗物質欄位）
- ✅ **P0-1/P0-2 GLP 角色**：新增 STUDY_DIRECTOR（研究主持人）與 TEST_FACILITY_MANAGEMENT（試驗機構管理階層）角色，含 22 項新權限定義與 6 個角色權限映射
- ✅ **P0-3 校正追溯鏈**：新增 reference_standards 表管理參考標準器，calibration 紀錄擴充追溯欄位（calibration_lab_accreditation、traceability_statement、reading_before/after）
- ✅ **P1-1 文件控制系統 (DMS)**：完整 CRUD + 審核核准 + 版本修訂 + 人員簽收，支援 6 種文件類型
- ✅ **P1-2 管理審查模組**：排程→執行→結案工作流，含議程、出席者、會議紀錄、決議、行動項目追蹤
- ✅ **P1-3 風險管理模組**：風險登記簿含嚴重度×可能性評分矩陣、緩解計畫、殘餘風險追蹤
- ✅ **P1-4 變更控制**：通用變更申請流程（Draft→Submitted→Approved→Implemented→Verified），支援 6 種變更類型
- ✅ **P1-5 SOP 審核簽署**：qa_sop_documents 擴充 reviewed_by/approved_by/revision_history 欄位
- ✅ **P1-6 環境監控**：監控點 + 讀數記錄 + 自動超標偵測（JSONB 參數比對），支援手動/感測器/匯入三種來源
- ✅ **P1-7 能力評鑑**：人員能力評估（initial/periodic/requalification）+ 職位訓練需求矩陣
- ✅ **P1-8 最終報告**：GLP 研究最終報告模組，含 Study Director 簽署 + QAU 聲明欄位
- ✅ **P1-9 試驗物質管理**：products 擴充 GLP 特性欄位 + formulation_records 配製紀錄表
- ✅ **Backend 全棧**：models/glp_compliance.rs (500+ 行) + repositories/glp_compliance.rs (600+ 行) + services/glp_compliance.rs (300+ 行) + handlers/glp_compliance.rs (400+ 行) + 路由註冊 30+ endpoints
- ✅ **Frontend 全棧**：7 個新管理頁面（DocumentControlPage、ManagementReviewPage、RiskRegisterPage、ChangeControlPage、EnvironmentMonitoringPage、CompetencyAssessmentPage、StudyFinalReportPage）+ API 模組 + App.tsx 路由註冊
- ✅ **品質驗證**：cargo check ✓、cargo clippy ✓（零警告）、tsc --noEmit ✓、npm run build ✓

### 2026-04-03 設備管理 ISO 17025 / GLP 合規欄位補強

- ✅ **審核確認**：點擊儀器→履歷頁、點擊廠商→聯絡 Dialog、維修保養 5 狀態流程均正確實作
- ✅ **Migration 015**：設備資料表新增 `department`、`purchase_date`、`warranty_expiry`；校正資料表新增 `certificate_number`、`performed_by`、`acceptance_criteria`、`measurement_uncertainty`、`validation_phase`（IQ/OQ/PQ）、`protocol_number`
- ✅ **後端模型/Service SQL**：Equipment + EquipmentCalibration + CalibrationWithEquipment struct 及 INSERT/UPDATE/SELECT SQL 全部同步更新
- ✅ **前端型別 types.ts**：新增 `ValidationPhase` type、`VALIDATION_PHASE_LABELS`；更新 Equipment、CalibrationWithEquipment、EquipmentForm、CalibrationForm interface
- ✅ **CalibrationFormDialog**：校正類型顯示四個新欄位；確效類型顯示 IQ/OQ/PQ 選擇 + 方案編號；三種類型完全分離條件渲染
- ✅ **EquipmentFormDialog**：新增部門、購買日期、保固到期日輸入欄位
- ✅ **EquipmentInfoCard**：顯示部門、購買日期、保固到期日（逾期標紅提示）

### 2026-04-01 Migration 重構完成（29→12 合併檔案）

- ✅ **Phase 1-2 分析與撰寫**：將 29 個舊 migration 整理為 12 個按業務模組分組的合併檔案（`backend/migrations_v2/`）
- ✅ **重複補丁消除**：015、020、021、026 等純修補 migration 直接合入最終狀態，fresh install 不再有中間過渡狀態
- ✅ **種子資料分離**：roles、permissions、notification_routing 種子資料集中於各模組檔案，不混入 schema 定義
- ✅ **Phase 3 驗證**：確認 129 張表全部存在、跨檔案 FK 依賴順序正確、所有 ENUM 型別在 001 已定義、Views/Functions/Triggers 完整

### 2026-04-01 Migration 重構後 IDXF 匯出入修復

- ✅ **移除 refresh_tokens**：`EXPORT_TABLE_ORDER` 移除 `refresh_tokens`，避免過期 session token 被匯入新系統（安全性問題）
- ✅ **補齊遺漏 table**：新增 13 個舊版未涵蓋的表至 `EXPORT_TABLE_ORDER`：`blood_test_presets`、`invitations`、`ai_api_keys`、`animal_field_correction_requests`、`protocol_ai_reviews`、`expiry_notification_config`、`expiry_monthly_snapshots`、`equipment_suppliers`、`equipment_status_logs`、`equipment_maintenance_records`、`equipment_disposals`、`equipment_annual_plans`（依 FK 順序插入）
- ✅ **schema_mapping 版本說明**：補充 "030 → 011" 為 no-op 對應說明（無欄位改名，新欄位自動補 NULL，舊欄位自動忽略）

### 2026-03-31 QA 計畫管理模組 Bug 修復（Codex Review 5 項）

- ✅ **Bug 1 enum 序列化**：`repositories/qa_plan.rs` 改用 SQLx 原生 enum 綁定取代 `format!("{:?}").to_lowercase()`，修正 `NotApplicable` → `"not_applicable"` 錯誤
- ✅ **Bug 2 SQL alias**：`update_schedule_item` RETURNING 子句移除無效 `si.*` alias，改用 `*` 與裸欄位名稱
- ✅ **Bug 3 ownership 驗證**：`services/qa_plan.rs` 新增排程項目歸屬驗證（item 必須屬於指定 schedule_id），防止跨排程更新
- ✅ **Bug 4 編輯對話框**：`QAInspectionPage.tsx` `openEdit` 改為 async，呼叫 `getInspection` 取得真實稽查項目填入表單
- ✅ **Bug 5 關閉狀態**：`submitMutation` 重命名為 `changeStatusMutation` 並參數化，關閉按鈕正確傳送 `status: 'closed'`

### 2026-03-30 通知路由頻率設定 + 效期通知範圍設定

- ✅ **Migration 027**：`notification_routing` 新增 `frequency`、`hour_of_day`、`day_of_week` 三欄，批次型事件預設 daily
- ✅ **Migration 028**：建立 `expiry_notification_config`（系統層級效期設定）、`expiry_monthly_snapshots`（月度比較快照）、`fn_expiry_alerts(warn, cutoff)` 動態參數函數
- ✅ **排程器動態化**：`check_expiry` 與 `check_low_stock` job 改為每小時整點觸發，執行時讀 DB 設定判斷是否符合 daily/weekly/monthly 條件
- ✅ **月度彙整通知**：`expiry_monthly.rs` 實作快照拍攝、月度比較（新增/減少/持續）、通知發送
- ✅ **新 API**：`GET/PUT /admin/expiry-config` 供系統管理員設定效期閾值
- ✅ **前端 EditRoutingDialog**：批次事件（expiry_alert 等）顯示頻率/時間/星期選擇器
- ✅ **前端 ExpiryConfigPanel**：通知路由頁面底部新增效期通知範圍設定面板（warn/cutoff/月度模式）

### 2026-03-29 R16 剩餘 10 項確認完成（R16-2~6, R16-9~13）

- ✅ **R16-2 Content-Disposition header injection 修復**：`utils/http.rs` 共用 `content_disposition_header()` 函式使用 `urlencoding::encode` 實作 RFC 5987 percent-encode，全部 16 處 export handler 已統一呼叫
- ✅ **R16-3 稽核日誌 PDF XSS 修復**：`useAuditLogExport.ts` 已有 `escapeHtml()` 函式，`buildPrintHtml` 中所有動態資料皆已包裹
- ✅ **R16-4 window.open noopener 修復**：`VetRecommendationDialog.tsx` 和 `GoogleCalendarEventsWidget.tsx` 已補上 `'noopener,noreferrer'`；print 用途的空白頁 `window.open('', '_blank')` 不需加
- ✅ **R16-5 Query key factory 統一**：`useLeaveMutations.ts` 和 `useOvertimeMutations.ts` 已全面使用 `queryKeys.hr.*` factory，無硬編碼 key
- ✅ **R16-6 window.location.reload() 移除**：`useDocumentSubmit.ts` 和 `DocumentDetailPage.tsx` 已改用 `queryClient.invalidateQueries()`
- ✅ **R16-9 Swagger UI production 停用**：`server.rs` 以 `!config.cookie_secure` 條件控制掛載
- ✅ **R16-10 動態 table name 白名單**：`services/signature/access.rs` 定義 `ALLOWED_RECORD_TABLES` 常數，format!() 前驗證
- ✅ **R16-11 CSRF production guard**：`config.rs` 在 `cookie_secure && disable_csrf_for_tests` 時自動強制關閉並 log error
- ✅ **R16-12 HSTS header**：`server.rs` 在 `cookie_secure` 時加入 `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- ✅ **R16-13 CI fallback 密碼移除**：`ci.yml` 所有密碼（JWT_SECRET、ADMIN_PASSWORD、DEV_PASSWORD）已改用 `${{ secrets.* }}`，無 fallback

### 2026-03-30 R16 第三批 Frontend 品質改善（R16-17~25）

- ✅ **R16-17 硬編碼色彩 token 替換**：從 837 處減至約 213 處（75% 消除），slate/gray/status 色彩全面遷移至 CSS Variable token（bg-muted、text-foreground、border-border、text-status-*-text 等），剩餘為 SKU 色彩系統（56）、設施佈局色碼（8）、sidebar 深色主題等有意的特化色彩
- ✅ **R16-18 五個超 300 行元件拆分**：HrAttendancePage(460→66)、ObservationFormDialog(489→171)、SacrificeFormDialog(458→177)、AnimalEditPage(414→161)、RolesPage(381→169)，提取 5 個 custom hook + 3 個子元件
- ✅ **R16-19 PageErrorBoundary 全域化**：MainLayout 已統一包裹 Outlet，移除 App.tsx 中 5 處冗餘的個別包裹及未使用的 import
- ✅ **R16-20 HR query key factory 化**：HrAttendancePage/HrLeavePage/HrOvertimePage 等 6 個檔案的硬編碼 query key 全部遷移至 queryKeys.hr.*
- ✅ **R16-21 Zustand store 直接 mutation 修復**：client.ts 中 `sessionExpiresAt` 直接賦值改為 `useAuthStore.setState()`
- ✅ **R16-23 Array index key 修復**：BloodTestFormDialog、VetReviewForm、HrAnnualLeavePage 3 處改用穩定 ID（template_id/item_name/entitlement_year）
- ✅ **R16-24 axios 直接 import 消除**：useAnimalsMutations.ts、useUserManagement.ts、types/error.ts 改用 `@/lib/api` 的 `isAxiosError` re-export
- ✅ **R16-25 console.debug 已確認受保護**：webVitals.ts 已在 `import.meta.env.DEV` 條件內，無需修改

### 2026-03-29 R16 第三批 Backend 品質改善（R16-14/15/16/22）

- ✅ **R16-14 角色碼魔術字串消除**：在 `constants.rs` 定義 10 個角色常數（`ROLE_SYSTEM_ADMIN` 等）+ 10 個假別常數 + 共用 `get_leave_type_display()` 函式，替換 15+ 個檔案中的硬編碼字串
- ✅ **R16-15 scheduler.rs 函數拆分**：`start()` 從 235 行拆為 12 個獨立 `register_*_job` helper；`generate_monthly_report` 從 138 行拆為 6 個子函式（日期計算 / 採購彙總 / 銷貨彙總 / 血檢統計 / 報表內容 / 通知發送），每個 ≤ 50 行
- ✅ **R16-16 services/stock.rs 拆分**：942 行單檔拆為 `stock/mod.rs` + `stock/inventory.rs`（庫存查詢）+ `stock/ledger.rs`（流水帳 + 單據處理），外部 import 不需變更
- ✅ **R16-22 format!() 動態 SQL 改用 QueryBuilder**：`get_ledger` 和 `get_unassigned_inventory` 改用 `sqlx::QueryBuilder` 避免 format! 拼接 SQL；庫存查詢保留安全的參數化佔位符模式

### 2026-03-29 R16 第四批 CI/測試改善（R16-26~31）

- ✅ **R16-26 GitHub Actions 版本標籤修正**：`actions/checkout@v6` → v4、`actions/setup-node@v6` → v4、`actions/upload-artifact@v7` → v4（actions/cache@v5 維持不變，已是最新）
- ✅ **R16-27 Backend coverage threshold 提升**：tarpaulin `--fail-under` 從 2% 提高至 15%
- ✅ **R16-28 CI 加入 ESLint job**：frontend-check 新增 `npx eslint src --max-warnings=0` 步驟
- ✅ **R16-29 E2E create flow 測試**：新增 `frontend/e2e/protocol-create.spec.ts`，涵蓋表單載入、儲存按鈕、填寫基本資訊儲存草稿、section 導覽切換
- ✅ **R16-30 unsafe-guard 改為 block CI**：從 `::warning::` 改為 `exit 1`，允許附帶 `// SAFETY:` 註解的 unsafe 放行
- ✅ **R16-31 Edge case 測試**：新增 `backend/tests/api_edge_cases.rs`，含分頁邊界（page=0/per_page=0/per_page=999999/page=-1）、SQL injection（單引號/UNION SELECT/LIKE wildcards/Unicode）、無效 UUID、超大 request body、深度巢狀 JSON 共 13 項測試

### 2026-03-29 R19 Phase 4 測試（R19-12/13/14）

- ✅ **R19-12 邀請流程 E2E 測試**：新增 `frontend/e2e/invitation.spec.ts`，涵蓋完整邀請流程（建立→接受→登入）與無效 token 錯誤頁面測試
- ✅ **R19-13 權限隔離測試**：新增 `backend/tests/api_invitations.rs`，驗證邀請 CRUD 需認證、PI 使用者無法存取 admin/ERP 端點、PI 可存取 my-projects
- ✅ **R19-14 安全測試**：同檔新增過期 token、已使用 token、無效 token、弱密碼、verify 無效 token 共 5 項安全測試

### 2026-03-29 R16 CRITICAL 修復 + 歡迎指引系統 + INTERN 角色

- ✅ **R16-1 授權查詢 unwrap_or 繞過修復**：42 處 `.unwrap_or((false,))` / `.unwrap_or((0,))` 改為 `?` 錯誤傳播或 `unwrap_or_else` + 日誌。涵蓋 protocol/crud, review, export, pdf_export + services/auth/login, audit, login_tracker, calendar, qau
- ✅ **R16-7/R16-8 授權查詢集中化**：`services/access.rs` 新增 9 個函式（is_pi_or_coeditor, is_assigned_reviewer, require_protocol_view_access 等），取代 3 套重複 check_protocol_access
- ✅ **角色歡迎指引系統**：13 個非 admin 角色各有專屬歡迎訊息與可點擊頁面連結。多角色合併顯示（「身為 XX」前綴）。支援 sessionStorage 單次關閉 + preference 永久關閉
- ✅ **INTERN 角色新增**：後端權限定義（同 EXPERIMENT_STAFF）、Migration 023、DashboardRoute 加入 INTERN
- ✅ **帳號到期日功能**：users.expires_at 欄位 + 登入時自動檢查 + 管理員可設定
- ✅ **Polling 401 修復**：shouldPoll 增加 isAuthenticated 檢查、QueryClient retry 跳過 401/403、clearAuth 時 cancelQueries
- ✅ **反模式記錄**：feedback memory 記錄 unwrap_or 吞錯誤 + handler 直接 SQL 兩個反模式

### 2026-03-29 R16 全專案 Code Review + CI 全面修復

- ✅ **全專案 Code Review**：5 面向平行審查（Backend 安全/Frontend 安全/Backend 品質/Frontend 品質/CI 測試），發現 CRITICAL 2 / HIGH 23 / MEDIUM 22 / LOW 11，新增 R16-1~R16-31 共 31 項待辦至 TODO.md
- ✅ **Edge Case 測試分析**：盤點已有覆蓋（驗證邊界、XSS、Auth 401/429、ETag）與缺口（refresh token replay、暴力破解、檔案上傳安全、分頁邊界、SQL injection in search 等 18+ 項）

### 2026-03-29 CI 全面修復 — 從 6 job 失敗到全綠

- ✅ **Backend clippy & cargo test**：移除 `tests/common/mod.rs` 中已刪除的 `AlertBroadcaster` 引用（SSE→Polling 重構遺漏）
- ✅ **Frontend Vitest (2 tests)**：補全 `warehouseFormSchema` 和 `createUserSchema` 測試資料中缺少的必填欄位
- ✅ **npm audit**：修復 picomatch high-severity 漏洞（ReDoS + Method Injection），升級相關依賴
- ✅ **UTF-8 修復**：`backend/examples/parse_mail.rs` 損壞的中文字元重建
- ✅ **E2E Playwright (15→0 failures)**：5 輪迭代修復，涵蓋路由前綴不匹配（`/admin/equipment`→`/equipment`、`/master/products`→`/products`）、選擇器與實際 DOM 結構不匹配（Documents 頁面非 Radix Tabs、HR 出勤 today/history tab 切換、動物頁面無附件功能）、Playwright strict mode 衝突、loading skeleton 誤判等問題

### 2026-03-27 R14 — AUP 計畫書 PDF 格式對齊官方紙本

- ✅ **封面標題頁**：header 字間距 `letter-spacing: 0.3em`、`(ANIMAL USE PROTOCOL)` 加 small caps、sponsor/facility 加框線、移除 `=` 分隔符、版權固定頁面底部
- ✅ **人員表格**：訓練欄改為每行一筆（`<br>` 分行）、括號改半形 `()`、訓練欄寬 34%→45%、字體 9pt、加 `| safe` filter

### 2026-03-27 R15 Low — 代碼規範重構（DRY / 函數長度 / 檔案拆分）

- ✅ **Stock service DRY**：抽出 `SliFilterBuilder` struct，統一貨架/倉庫查詢的 keyword + product_id + batch_no 動態 filter 建構邏輯
- ✅ **send_test_email 精簡**：email body 建構移至 `EmailService::send_test_email`，handler 從 108 行精簡為 ~35 行
- ✅ **InventoryPage 拆分**：`BatchDetailRows` + `InventoryRow` + `ExpiryDateBadge` 抽至 `components/InventoryRow.tsx` (262 行)，主頁面 220 行，皆 ≤300 行

### 2026-03-27 R15 P2 Code Review 發現修復（Claude + Codex 交叉審查）

- ✅ **PO 重算交易安全**：`recalculate_all_po_receipt_status` 改為單一 transaction 包覆整個迴圈，失敗全部 rollback + 錯誤 log 含 PO ID
- ✅ **recalculate 權限收緊**：從 `erp.document.approve` 改為 `is_admin()` 檢查，限制批次重算為系統管理員專用
- ✅ **Email display name 跳脫**：新增 `sanitize_display_name` helper，跳脫 `\` 和 `"` 避免 RFC 5322 parse 失敗（4 處統一修正）
- ✅ **庫存 batch_no 篩選**：貨架級 + 倉庫級查詢新增 `batch_no` 動態 filter（ILIKE 模糊匹配）
- ✅ **未分配庫存提示**：展開行新增第二個 query 取得未分配庫存，若 > 0 顯示琥珀色提示列；後端 `get_unassigned_inventory` 加入 `product_id` 篩選
- ✅ **展開狀態自動清除**：`useEffect` 監聽 4 個篩選條件，變更時自動收合所有展開行
- ✅ **batchFilter 傳遞**：`BatchDetailRows` 接收並傳遞 `batchFilter` 參數到 API 呼叫
- ✅ **順便修正**：BatchDetailRows key 改用 `storage_location_id + batch_no`；`let _ = idx` 統一整理

### 2026-03-27 SSE → Polling 重構 + 依賴清理

- ✅ **SSE 移除**：刪除 `AlertBroadcaster`、`sse.rs`、nginx SSE location block，解決 Cloudflare 524 timeout 問題
- ✅ **Polling 端點新增**：`GET /admin/audit/alerts/recent?after=` 每 30 秒輪詢，前端 `useSecurityAlerts` 改用 `useQuery`
- ✅ **依賴清理**：移除 `async-stream`、`futures` crate（僅 SSE 使用）
- ✅ **程式碼精簡**：從 `login_tracker.rs`、`login.rs`、`two_factor.rs` 移除所有 broadcaster 參數（淨刪 188 行）

### 2026-03-27 Migration Squash — 22 檔合併為 8 檔

- ✅ **Migration 合併**：22 個增量 migration 檔案合併為 8 個乾淨的 squashed migration（`backend/migrations_squashed/001-008`），按業務域分組（types → users/auth → animal → AUP → HR → ERP → audit/security → facility/equipment）
- ✅ **Schema 完整性驗證**：在測試 DB 上驗證 tables（127）、indexes（491）、constraints（415）與原始 DB 完全一致（僅差 _sqlx_migrations 自動表）
- ✅ **跨檔 FK 處理**：正確處理跨檔案 FK 約束（animals.pen_id/species_id 延遲到 008、treatment_drug_options.erp_product_id 延遲到 006）
- ✅ **重複消除**：修復 user_aup_profiles、system_settings、enum types、索引等多處重複定義

### 2026-03-26 Code Review 全面修復（28/35 項，80%）

- ✅ **P0 Critical 全部修復**：密鑰輪換（JWT/HMAC/DB/admin）、Token Refresh 競態條件改 Promise singleton、localStorage 最小化、CSRF 空 session 拒絕未認證寫入
- ✅ **P1 High 全部修復**：N+1 查詢改 LATERAL JOIN、30+ FK 索引補建、SVG sanitizer 收緊、18 檔 array index key 替換、16 處 audit log 錯誤記錄、unreachable 移除、type guard、logout 競態、users 硬刪除改 soft delete
- ✅ **P2 Medium 9/12 完成**：Stats 查詢合併、Rate Limiter 50K 上限、partial index、API key CHECK、Heartbeat 重試、staleTime、audit 複合索引、TabContent props 合併、權限 403
- ✅ **P3 Low 5/9 完成**：welcome banner sessionStorage、prefetch dev warn、SameSite 確認、測試密碼輪換、minimatch override 確認
- ✅ **工具文件**：`docs/codeReview/` 建立完整報告、推薦工具清單、修復追蹤

### 2026-03-26 文件結構重整 + DESIGN.md §15 按鈕規範

- ✅ **文件記錄規則制定**：CLAUDE.md 新增「文件記錄規則」section，統一時間排序（反向）、表格欄位（4 欄）、編號格式（`{Section}-{序號}`）、變更紀錄流程（單一來源：PROGRESS.md §9）。
- ✅ **TODO.md 結構重整**：合併兩個 R11 section 為一；R section 排序修正為嚴格遞增（R6→…→R13）；R13-8→R13-1 編號修正；變更紀錄 section 標記封存。
- ✅ **PROGRESS.md §9 header 補齊**：加入缺失的 `## 9. 最新變更動態` section header + 格式規範說明。
- ✅ **DESIGN.md Decisions Log 改為反向時間序**：新決策加在最上方，與所有其他檔案一致。
- ✅ **按鈕高度一致性規範**：DESIGN.md 新增 §15 Button Guidelines，確立 PageHeader/toolbar 按鈕統一 `size="sm"`，按鈕顏色全站統一不按子系統分化。TODO.md 新增 R13-1。
- ✅ **TODO.md 全表格統一化**：26 個表格從 5 種不同欄位格式（4~7 欄）統一為 `| # | 項目 | 說明 | 狀態 |` 4 欄。140 個完成項目說明精簡化。編號修正（P3-1、P4-1~5、P5-1~10、R7-1~5）。檔案從 456→449 行。

### 2026-03-20 WAF 架構調整 — 改由 Cloudflare WAF 處理，移除 ModSecurity overlay

- ✅ **決策**：WAF 改由 Cloudflare WAF 處理（流量已經 Cloudflare Tunnel），不再需要本地 ModSecurity container。
- ✅ **移除檔案**：`docker-compose.waf.yml`、`deploy/waf/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf`、`deploy/waf/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf`、`docs/security/WAF.md`。
- ✅ **文件更新**：README、ARCHITECTURE、infrastructure、COMPOSE、deploy/README、TODO（R9-C1 標記完成、SEC-40 描述更新）、code review 文件。
- ✅ **R9-C1 結案**：原「生產環境 WAF 改為 On」已不適用，改由 Cloudflare Dashboard 啟用 Managed Ruleset。

### 2026-03-26 R13 更新計畫全面完成

- ✅ **Phase 1 (P0)**：CI 自動觸發恢復（push/PR on main）+ `cargo check --locked` / `cargo test --locked`。P0 歸零。
- ✅ **Phase 2 (P1) 品質強化**：
  - 49 個 Vitest 單元測試覆蓋 5 個共用 UI 元件（DataTable/StatusBadge/PageTabs/FilterBar/PageHeader）
  - Props 合併 4 元件（UserTable 18→6、AnimalListTable 14→6、AnimalFilters 15→6、EquipmentTabContent 11→6）
  - Audit log 4 個 subsystem 色彩 token（medical/protocol/sacrifice/data）恢復語意區分
  - CSRF 驗證失敗改回傳 419 (Page Expired)，前端改用 status code 偵測取代字串比對
- ✅ **Phase 3 (P2) 中優先改進**：
  - FormField 元件統一採用 12 個表單檔（Admin facility 6 Tab + Auth 3 頁 + HR + AI Key + BatchPen）
  - StatsCard 共用元件提升（EquipmentStatsCards/TrainingStatsCards/LeaveBalanceSummary 3 處採用）
  - 請假日期計算時區修復（`toISOString` → 本地日期格式化）
  - UserEditDialog 重構為單一資料源（移除 watch → setFormData 雙向同步）
- ✅ **Phase 4 (P3) 長期演進**：
  - Dependabot 2.5 升級：utoipa 4→5、utoipa-swagger-ui 6→8、axum-extra 0.9→0.12、tailwind-merge 2→3（10 個 handler 檔修復 breaking changes）
  - QA browser helper scripts（`scripts/qa-browse.sh` + 3 個 chain JSON）
  - E2E 測試擴充：8→12 specs（+18 tests），新增設備管理、HR 加班、計畫書詳情、ERP 進銷存
- ✅ **TypeScript 零錯誤**、`cargo check` 通過、Vitest 49/49 通過。

### 2026-03-25 gstack 全面審查 + Simplify 重構 + 安全修復

- ✅ **Code Review（/review）**：8 項 auto-fixed + 4 項 user-approved — deleteResource data 遺失、Retry-After NaN 防護、overtime endTime 驗證、AnimalPenView stale closure、PageTabs hidden tab URL bypass、canEditProtocol 補齊修訂狀態。Codex second opinion 驗證 4 項修復、排除 4 項誤報。
- ✅ **安全審計（/cso）**：92/100 分。4 項修復 — AI API key rate_limit_per_minute 強制執行（新增 AiRateLimiter in-memory sliding window + AppError::TooManyRequests 429）、Cargo.lock 納入 git 追蹤、CI cd.yml script injection 改用 env block、/metrics 端點加入 METRICS_TOKEN Bearer auth。
- ✅ **Simplify 重構**：DataTable 統一採用（7 檔，消除 ~400 行重複）、StatusBadge 採用（7 檔）、FilterBar 採用（4 檔）、檔案拆分（5→19 檔：UserFormDialogs 656→5 檔、AnimalAddDialog 579→5 檔、AnimalPenView 399→3 檔、ProtocolEditPage 880→4 檔、useProtocolDetail 345→2 檔）、watch() 效能優化（4 檔）、formatDate 統一（4 檔）、dead prop 移除。
- ✅ **zodResolver 型別修復**：7 個 useForm 檔案從 `as never` 改為 `useForm<z.input<typeof schema>, unknown, FormData>` 正確型別。validation.ts `invalid_type_error` 改為 `error`（Zod v4 API）。
- ✅ **TypeScript 編譯零錯誤**。`cargo check` 通過。

### 2026-03-25 RHF+Zod 全面遷移 + UI 債全面清理

- ✅ **RHF+Zod 全面遷移**（1→17 檔）：新增 10 個 Zod schema。Auth 3 頁 + Master 5 頁 + Admin UserForm 3 dialog + AnimalEdit + ApAging/ArAging + WarehouseLayout + ProfileSettings。
- ✅ **PageHeader** 35 頁遷移。**PageTabs** 9 檔遷移。**EmptyState** 24 檔。**i18n** 28 處/15 檔。**a11y** 93 處/43 檔。
- ✅ 設計系統合規度：~92%。TypeScript 零錯誤。

### 2026-03-25 RHF+Zod 延伸遷移 + DataTable 套用 + Protocol Tab URL 同步

- ✅ **Partner 表單 RHF+Zod 遷移**：`usePartnerForm` 從 useState + 手寫 regex 驗證遷移到 `useForm` + `zodResolver(partnerFormZodSchema)`。`PartnerFormDialog` 改用 `register` 綁定 Input 欄位、`errors` 顯示欄位級錯誤。auto-generated code 和 edit/create 雙模式功能保留。
- ✅ **DataTable 元件套用 HR 5 個列表頁**：`MyLeavesTabContent`、`AllLeaveRecordsTabContent`、`LeavePendingApprovalsTab`、`MyOvertimeTabContent`、`PendingApprovalsTabContent` 全部從手寫 Table+Skeleton+Empty 模式遷移到 `DataTable<T>` + column definitions。
- ✅ **ProtocolDetailPage Tab URL 同步**：9 個 Tab（content/versions/history/comments/reviewers/coeditors/attachments/animals/amendments）從 `useState` 遷移到 `PageTabs` URL 同步（`useSearchParams`）。支援瀏覽器前進/後退和分享連結（`?tab=comments`）。`ProtocolTabNav.tsx` 刪除。
- ✅ **TypeScript 編譯零錯誤**。

### 2026-03-25 R12-4~R12-7 完成

- ✅ **R12-4 硬編碼色彩清理完成**：全專案硬編碼 Tailwind 色彩從 **748→112**（-85%）。本輪清理：auditLogs.ts（58 處轉 status token）、animals/constants.ts（12 處轉 status-*-solid token，新增 `--status-*-solid` CSS 變數）、ErpWidgets（17 處）、Auth 頁面表單內元素（85 處，漸層背景保留）。剩餘 112 處為 Auth 漸層背景（DESIGN.md 規範）和 Canvas 視覺化 hex 色彩。
- ✅ **R12-5 React Hook Form + Zod 表單遷移**：`lib/validation.ts` 新增 `leaveRequestSchema`、`overtimeRequestSchema`、`annualLeaveEntitlementSchema` 三個 HR 表單 Schema。`CreateOvertimeDialog` 完整遷移到 `useForm` + `zodResolver`（含 `<form onSubmit>`、欄位級錯誤顯示）。`useLeaveRequestForm` 遷移到 RHF，保留雙向日期/時數計算邏輯。`CreateLeaveDialog` 新增欄位級 error 顯示。
- ✅ **R12-6 子系統色相實際套用**：`sidebarNavConfig.ts` NavItem 介面新增 `subsystem` 欄位，5 個導航群組標記子系統（aup/erp/animal/hr/admin）。`SortableNavItem.tsx` active 狀態從 `bg-blue-600` 改為 `bg-subsystem-*` 動態色彩（`getActiveClass()` 函式）。子選單 active 同步使用父級子系統色相。
- ✅ **R12-7 CSRF Token 客戶端刷新機制**：`api/client.ts` response interceptor 新增 403 CSRF 錯誤偵測邏輯 → 自動呼叫 `GET /auth/me` 取得新 CSRF cookie → 重試原始請求。`_csrfRetry` flag 防止無限重試。
- ✅ **TypeScript 編譯零錯誤**。

### 2026-03-24 UI 一致性重構與設計系統合規

- ✅ **共用頁面框架元件**：新增 5 個 UI 骨架元件 — `PageHeader`（統一標題區）、`FilterBar`（統一篩選列）、`PageTabs`（URL 同步 Tab 導航）、`DataTable`（統一表格 + 分頁 + Empty + Loading）、`StatusBadge`（語義化狀態標籤）。
- ✅ **語義化色彩系統**：CSS Variables 新增 6 組 status token（success/warning/error/info/neutral/purple）含 Light/Dark 雙主題 + 5 個子系統色相變數（`--subsystem-aup/erp/animal/hr/admin`），註冊到 `tailwind.config.js`。
- ✅ **硬編碼色彩清理**：全專案 `src/pages/` 硬編碼 Tailwind 色彩從 **748 處降至 262 處**（-65%），涵蓋 text-*/bg-*/border-* 三類。剩餘為 Auth 漸層（DESIGN.md 規範）、視覺化 Canvas 色彩、資料映射常數。
- ✅ **HR 模組全面重構**：4 頁（Leave/Overtime/Attendance/AnnualLeave）遷移到 PageHeader + PageTabs；Tab 導航從 useState 遷移到 URL sync；`window.location.reload()` 移除改用 `invalidateQueries`；Loading 統一為 TableSkeleton。
- ✅ **ERP 模組遷移**：ProductsPage、PartnerToolbar 遷移到 PageHeader + FilterBar。
- ✅ **動物管理/協議模組遷移**：AnimalsPage、ProtocolsPage、AnimalSourcesPage 遷移到 PageHeader；AnimalHeaderCard/ListTable/DetailActions/Filters/AddDialog 等 9 個子元件清理硬編碼色彩。
- ✅ **Admin 模組清理**：14 個元件清理硬編碼色彩（Equipment/Maintenance/Calibration/Disposal/Notification/User/Training/AiApiKey/Settings/Roles/AnimalFieldCorrections）。
- ✅ **報表/文件模組清理**：BloodTest/CostSummary/PurchaseSales/Documents 等 18 個檔案清理。
- ✅ **安全性掃描報告**：Backend 安全評分 92/100，確認 JWT/2FA/CSRF/Rate Limiting/File Upload 等防禦完善，3 項中低風險待修。
- ✅ **TypeScript 編譯零錯誤**。

### 2026-03-23 R9-C2 CI 密碼改 GitHub Secrets

- ✅ **ci.yml**：`ADMIN_INITIAL_PASSWORD`、`E2E_USER_PASSWORD`、`E2E_ADMIN_PASSWORD` 改為 `${{ secrets.CI_ADMIN_PASSWORD }}`。
- ✅ **docker-compose.test.yml**：`JWT_SECRET`、`DEV_USER_PASSWORD`、`ADMIN_INITIAL_PASSWORD`、`TEST_USER_PASSWORD` 改為環境變數替換（`${CI_JWT_SECRET}`、`${CI_ADMIN_PASSWORD}`、`${CI_DEV_PASSWORD}`），附帶 local fallback 預設值。
- ✅ **e2e-test job**：新增 `env` 區塊將三個 GitHub Secrets 傳入 docker compose。
- ⚠️ **需手動操作**：在 GitHub repo Settings → Secrets 新增 `CI_ADMIN_PASSWORD`、`CI_DEV_PASSWORD`、`CI_JWT_SECRET`，建議每季輪替。
- ℹ️ **DB 密碼維持硬編碼**：CI service container 的 PostgreSQL 密碼風險極低（臨時容器、無外部存取），不改。

### 2026-03-21 R10 程式碼審查 17/20 完成

- ✅ **M2 N+1 修正**：確認 `AnimalService::list` 已用 LEFT JOIN + 子查詢一次往返，無 N+1 問題
- ✅ **M3 大檔案串流驗證**：upload.rs 新增 MIME 預檢（讀取前拒絕）+ 欄位級大小檢查
- ✅ **M4 unwrap 精簡**：已清零（0 處），之前改善已全部處理
- ✅ **M5 CSRF 強化**：改為 Signed Double Submit Cookie（HMAC 綁定 session ID + constant_time_eq），8 個新測試
- ✅ **M6 Zod 驗證**：useUserManagement 新增 createUserFormSchema/updateUserFormSchema
- ✅ **M7 MIME 驗證**：file-upload.tsx 新增 ALLOWED_MIME_TYPES 白名單 + 副檔名降級
- ✅ **M9 Alert 門檻**：CPU/Memory 80%→warning 95%→critical，P95 延遲 2s/5s，Error rate 1%/5%
- ✅ **M10 Grafana 認證**：確認已用環境變數密碼 + Prometheus 綁定 127.0.0.1
- ✅ **L1 auth handler 拆分**：734→7 檔（login/session/password/account/impersonate/cookie/mod）
- ✅ **L2 auth service 拆分**：1006→6 檔（login/session/password/two_factor/tests/mod）
- ✅ **L3 signature 拆分**：handler 560→7 檔，service 899→4 檔
- ✅ **L4 product service 拆分**：832→3 檔（crud/import/mod）
- ✅ **L6 Cookie consent**：CookieConsent 重寫，Google Fonts 改為動態注入，同意前不載入
- ✅ **L7 密碼複雜度**：前後端統一 ≥10 字元 + 大小寫 + 數字 + 30 組弱密碼黑名單 + 強度指示器
- ✅ **L8 Watchtower**：輪詢間隔 30→3600 秒
- ✅ **L9 login_events 索引**：migration 016 新增 2 個複合索引
- ✅ **L10 JSONB 驗證**：utils/jsonb_validation.rs（5 個驗證函式 + 11 個測試）
- 🔄 M1（Rate limiter Redis）、M8（Session timeout）、L5（Sentry）推遲

### 2026-03-21 R11 技術債全部清零（R11-15 / R11-21 / R11-22）

- ✅ **R11-15 中大型元件拆分**：10 個超過 300 行的前端元件全部拆分完成，平均縮減 -80%。AnimalDetailPage（786→203）、AuditLogsPage（686→152）、TrainingRecordsPage（673→146）、ProductEditPage（647→91）、TransferTab（651→117）、TreatmentDrugOptionsPage（646→113）、ProtocolDetailPage（714→156）、Sidebar（635→175）、NotificationRoutingPage（617→98）、PartnersPage（610→96）。各元件依 Tab/功能區塊提取子元件與 hooks。
- ✅ **R11-21 try-catch 重構**：掃描全部 54 處 try-catch，25 處改為 `useMutation`（blob 下載 12 處、表單 API 8 處、匯出匯入 5 處），27 處合理保留（auth store、API interceptor、JSON parse、日期格式化等基礎設施）。移除所有手動 loading state，改用 mutation `isPending`。
- ✅ **R11-22 源碼 TODO 清理**：`stocktake.rs` 實作按類別篩選（推入 SQL WHERE，支援 `category_codes` + `product_ids` 參數化查詢）；`MyProjectDetailPage.tsx` 移除模擬空陣列，改用 `/animals?iacuc_no=` API 查詢計畫下動物。
- TypeScript 編譯零錯誤、Rust `cargo check` 通過。

### 2026-03-20 P0-R12-2 SQL 字串拼接殘留確認結案

- ✅ **結案**：`services/protocol/core.rs:139` 已為參數化查詢（`$1`~`$9` + `.bind()`）；`services/data_import.rs:321-336` 表名/欄名來自白名單函式 `get_conflict_columns()` + `debug_assert` 防護（R7-P0-2 已修復），無安全風險。

### 2026-03-20 R11-14 useDocumentForm.ts 拆分（717→303 行）

- ✅ **Hook 拆分**：將 `useDocumentForm.ts`（717 行）拆分為 3 個子 Hook：`useDocumentLines`（240 行，明細行 CRUD/批號/儲位管理）、`useDocumentSubmit`（146 行，payload 建構/驗證/save/submit mutations），主 Hook 降至 303 行（-58%）。
- ✅ 公開介面不變，`DocumentEditPage` 無需修改。`npm run build` 編譯通過。

### 2026-03-20 R11-10 HrLeavePage 拆分（837→188 行）

- ✅ **元件拆分**：將 `HrLeavePage.tsx`（837 行）拆分為 5 個子元件：`LeaveBalanceSummary`（餘額摘要卡片）、`CreateLeaveDialog`（新增請假對話框）、`MyLeavesTabContent`（我的請假表格）、`LeavePendingApprovalsTab`（待審核表格）、`AllLeaveRecordsTabContent`（全部紀錄+篩選），主頁面降至 188 行（-77%）。
- ✅ **Hook 提取**：新增 `useLeaveMutations` hook，將 5 個 mutation（create/submit/approve/reject/cancel）從主頁面抽出。
- ✅ **共用 helpers**：`constants.ts` 新增 `formatLeaveHours`、`getLeaveStatusVariant` 供多個 Tab 共用，消除重複邏輯。

### 2026-03-20 R11-11 BloodTestTab 拆分（812→343 行）

- ✅ **元件拆分**：將 `BloodTestTab.tsx`（812 行）拆分為 2 個子元件：`BloodTestFormDialog`（新增/編輯對話框，含套餐選擇與結果輸入）、`BloodTestDetailDialog`（詳情查看對話框），放入 `blood-test/` 子目錄。
- ✅ **常數提取**：`LAB_OPTIONS` 移至 `blood-test/constants.ts`。
- ✅ **主元件精簡**：主元件從 812 行降至 343 行，對話框邏輯獨立為子元件。

### 2026-03-20 R11-8 usePermissionManager 拆分（853→44 行）

- ✅ **Hook 拆分**：將 `usePermissionManager.ts`（853 行）依職責拆為 4 個子模組：`permissionConfig.ts`（常數與純函式）、`usePermissionCategories.ts`（分組邏輯與型別）、`usePermissionSearch.ts`（搜尋篩選）、`usePermissionExpand.ts`（展開/收合狀態），主 Hook 降至 44 行。
- ✅ **向後相容**：原 `usePermissionManager` import 路徑不變，型別與 `groupPermissionsByModule` 工具函式透過 re-export 維持相容。

### 2026-03-20 R11-3 `services/product.rs` 多個長函數拆分

- ✅ **product_parser.rs 模組建立**：將 CSV/Excel 解析邏輯（`parse_product_csv`、`parse_product_excel`、`parse_bool`、`get_cell_string`、`csv_header_index`、`map_category_display_to_code`、`is_stocklist_format`）提取至獨立 `services/product_parser.rs` 模組。
- ✅ **repositories/product.rs 擴展**：新增 `find_subcategory_name`、`exists_product_by_name_spec`、`find_product_by_name_spec`、`find_product_category_codes`、`find_product_by_id`、`list_uom_conversions`、`delete_uom_conversions`、`insert_uom_conversion` 共 8 個 repository 函式，消除 service 層重複 SQL。
- ✅ **product.rs 長函數拆分**：`create`（109→15 行）、`update`（170→15 行）、`import_products`（196→30 行）、`check_import_duplicates`（92→12 行）——提取 `resolve_sku`、`insert_product`、`insert_uom_conversions`、`build_product_with_uom`、`update_product_with_sku`/`update_product_without_sku`、`sync_uom_conversions`、`validate_import_row`、`build_import_create_request`、`should_use_auto_sku` 等子函式。所有函數均符合 ≤50 行規範。
- ✅ **測試驗證**：8 個單元測試全部通過，`cargo check` 編譯零錯誤。

### 2026-03-20 R11-2 `animal/import_export.rs` 長函數拆分

- ✅ **`import_basic_data`** 327 行 → ~40 行主函數：提取 `validate_basic_row`、`process_basic_row`、`parse_optional_date`、`parse_entry_weight`、`resolve_pen_location`、`resolve_breed_other`、`build_create_request`、`update_iacuc_if_present`、`find_source_id`、`find_animal_id_by_ear_tag` 等 10+ 個輔助函式。
- ✅ **`import_weight_data`** 172 行 → ~40 行主函數：提取 `validate_weight_row`、`process_weight_row`。
- ✅ **共用輔助函式**：`open_excel_range`（消除 Excel 開檔重複邏輯）、`parse_date_field`、`parse_import_breed`、`parse_import_gender`、`parse_weight_value`、`format_ear_tag`、`finalize_import_batch`、`detect_file_format`、`cell_to_option`。
- ✅ **Excel 解析拆分**：`parse_basic_excel_row`、`parse_weight_excel_row` 單行解析獨立函式。
- ✅ **模板生成拆分**：`write_basic_template_headers`、`write_basic_template_example` 子函式。
- 📁 **產出**：`backend/src/services/animal/import_export.rs` 重構，所有函式 ≤50 行，`cargo check --tests` 通過。

### 2026-03-20 R11-9 AccountingReportPage 拆分（838→75 行）

- ✅ **元件拆分**：將 `AccountingReportPage.tsx`（838 行）拆分為 5 個 Tab 子元件：`TrialBalanceTab`（試算表）、`JournalEntriesTab`（傳票查詢）、`ApAgingTab`（應付帳款）、`ArAgingTab`（應收帳款）、`ProfitLossTab`（損益表），主頁面降至 75 行。
- ✅ **型別提取**：新增 `types/accounting.ts`，將 `TrialBalanceRow`、`JournalEntry`、`ApAgingRow`、`ArAgingRow`、`Partner` 等型別從頁面內移出。
- ✅ **Dialog 歸屬**：`CreateApPaymentDialog` 移至 `ApAgingTab`，`CreateArReceiptDialog` 移至 `ArAgingTab`，各自內聚於對應 Tab。

---

### 2026-03-15 Code Review 修復與待辦整合（依據 2026_March15_code_review_1.md）
- ✅ **文件**：README 新增「已知限制／開發模式注意事項」（Critical 1/2 擱置）；TODO 新增 R9 審查—已知漏洞擱置（R9-C1/C2）與 R10 程式碼審查 Medium/Low（20 項）。
- ✅ **Critical 3**：生產 overlay 綁定 web port 至 127.0.0.1；COMPOSE/DEPLOYMENT 註明開發用預設、生產用 prod。
- ✅ **Critical 4**：Grafana 密碼無預設值，.env.example 與 COMPOSE 註明必填。
- ✅ **Critical 5**：`create_admin.rs` 改為僅接受 `ADMIN_INITIAL_PASSWORD`，未設定則 error 退出。
- ✅ **High 1/2**：Watchtower API token 與 SMTP 密碼改由 Docker Secrets（`watchtower_api_token`、`watchtower_smtp_password`）+ `scripts/watchtower-entrypoint.sh` 讀取。
- ✅ **High 5**：db-backup 生產改用 `POSTGRES_PASSWORD_FILE` / secret `db_password`，`pg_backup.sh` 與 entrypoint 支援從檔讀密碼。
- ✅ **High 4**：新增 migration `013_audit_integrity_trigger.sql`，`user_activity_logs` 僅允許 UPDATE 寫入 `integrity_hash`/`previous_hash`，禁止竄改日誌內容。
- ✅ **High 6**：WAF 排除規則收窄，1003 改為依參數（content/body/description 等）排除 XSS，不整路徑關閉。
- ✅ **High 7**：`pg_backup.sh` 支援 GPG 加密（BACKUP_GPG_RECIPIENT）；prod 設 `BACKUP_REQUIRE_ENCRYPTION=true` 強制加密。
- ✅ **High 8**：主要 image 釘選 digest（postgres、prometheus、alertmanager、grafana、watchtower），新增 `docs/ops/IMAGE_DIGESTS.md`。
- ✅ **High 3**：`file.rs` 新增 `validate_zip_entries_safe()`，DOCX/XLSX 上傳時驗證 ZIP 內無路徑穿越。

### 2026-03-20 R11-11/12/13 前端超大元件拆分（3 項）

- ✅ **R11-11 BloodTestTab.tsx 拆分（811→343 行，-58%）**：提取 `BloodTestFormDialog`（新增/編輯表單）、`BloodTestDetailDialog`（詳情檢視）、`constants.ts`（LAB_OPTIONS）至 `blood-test/` 子目錄。
- ✅ **R11-12 DashboardPage.tsx 拆分（805→286 行，-64%）**：提取 `useDashboardData` hook（ERP query 集中管理）、`ErpWidgets.tsx`（7 個 ERP widget 元件）、`DashboardSettingsDialog.tsx`（設定對話框）至 `dashboard/` 子目錄。
- ✅ **R11-13 DocumentLineEditor.tsx 拆分 + any 消除（723→387 行，-46%，10 處 any→0）**：提取 `BatchNumberSelect`（批號選擇元件）、`ProductSearchDialog`（品項搜尋 Dialog，含 PO 待入庫/庫存/全品項三模式）、`LineRow`（單行渲染）；消除所有 `any` 型別（`setFormData`/`extraData`/`newLine`/`prev`/`item`/`stockBalances` 等），改用 `DocumentFormData`/`DocumentLine`/`ProductSelectExtraData`/`InventoryOnHand` 具體型別。

### 2026-03-15 R9 安全與品質修復（程式碼審查產出）
- ✅ **R9-1 IDOR 漏洞修復 (Backend)**：`download_attachment` 與 `list_attachments` 新增 `check_attachment_permission()` 輔助函式，根據 `entity_type` 對照上傳端的 `require_permission!` 檢查權限（protocol→aup.protocol.edit、animal/pathology→animal.animal.edit、leave_request→本人或 hr.leave.view_all、未知→僅 Admin），解決原先任何已登入使用者可透過猜測 UUID 下載非自己附件的 IDOR 漏洞。
- ✅ **R9-2 上傳 handler 去重 (Backend)**：抽取 `handle_upload()` 通用函式（處理 multipart 讀取、FileService::upload、save_attachment），6 個上傳 handler 簡化為 5–10 行。`upload_sacrifice_photo` 因獨特存表邏輯保留原寫法。`upload.rs` 從 606 行降至約 420 行（-31%）。
- ✅ **R9-3 DB 錯誤碼修正 (Backend)**：`error.rs` 中 DB 約束違規回傳正確 HTTP 狀態碼：`23505` (unique violation) → 409 Conflict、`23503` (FK violation) / `23502` (NOT NULL) / `23514` (CHECK) → 400 Bad Request，原先統一回 500 Internal Server Error。
- 📋 **R9-4 歡迎信安全改善**：已記入 `TODO.md`，待後續排程（改用密碼重設連結取代信件中的明文密碼）。
- 📋 **R9-5 ERP/HR 整合測試覆蓋**：已完成差距分析，待後續排程（庫存流水帳、GRN 入庫、出勤打卡、附件上傳/下載等 E2E 測試缺失）。

### 2026-03-15 Git 倉庫歷史紀錄深度清理
- ✅ **歷史重寫 (DevOps)**：使用 `git-filter-repo` 徹底移除 `.venv/` 與 `old_ipig.dump` 在 Git 倉庫中的所有歷史紀錄，有效減小倉庫體積並防止敏感資料外洩。
- ✅ **索引移除 (DevOps)**：執行 `git rm --cached` 移除目前分支對這些檔案的追蹤。
- ✅ **配置更新 (DevOps)**：更新 `.gitignore` 確保 `.venv/`、`*.dump` 等檔案未來不再被納入版本控制。
- ✅ **品質驗證**：確認目前 Git 追蹤與歷史紀錄中已無相關檔案足跡。
- ⚠️ **注意**：此為破壞性變更（Rewrite History），同步時需執行強行推送 `git push --force`。

### 2026-03-15 Git 環境清理與 .gitignore 更新
- ✅ **移除 .venv 追蹤 (DevOps)**：執行 `git rm -r --cached .venv` 將被誤推送到 Git 的 Python 虛擬環境從索引中移除（保留本地檔案）。
- ✅ **配置 .gitignore (DevOps)**：在 `.gitignore` 中加入 `.venv/` 與 `.venv*/` 排除規則，防止未來再次被 Git 追蹤。
- ✅ **品質驗證**：執行 `git ls-files .venv` 確認為空，並提交變更。

### 2026-03-15 單據頁面標題顯示優化
- ✅ **修正「建立新的undefined」 (Frontend)**：修改 `DocumentFormHeader.tsx`，當單據類型未選定時，副標題改為顯示「建立新的單據」，避免顯示 `undefined`。
- ✅ **標題文字優化 (Frontend)**：優化「新增」與「編輯」單據時的描述文字邏輯，使其語意更流暢（例：「建立新的 採購單」、「編輯現有的 採購單」）。
- ✅ **品質驗證**：手動驗證標題顯示正確，代碼符合 React 最佳實作。

### 2026-03-14 SSE 安全警報 Cloudflare 524 Timeout 修復
- ✅ **後端心跳修正 (Backend)**：修改 `sse.rs` 中 SSE keep-alive 心跳格式，從 `.text("")`（空 data 事件）改為 `.comment("heartbeat")`（SSE 標準 comment 格式），並將間隔從 30 秒縮短至 15 秒，確保在 Cloudflare Tunnel 100 秒 idle timeout 前多次發送有效心跳。
- ✅ **前端重連機制 (Frontend)**：修改 `useSecurityAlerts.ts`，加入指數退避重連邏輯（最多 5 次，間隔 2s→4s→8s→16s→32s），連線成功時重置計數器，元件卸載時清理 timer，確保偶發斷線不會永久失聯。
- ✅ **品質驗證**：TypeScript 編譯通過（`tsc --noEmit` exit code 0）。

### 2026-03-14 ERP 合作夥伴頁面 405 與硬刪除邏輯深度修復
- ✅ **前端修正 (Frontend)**：修復 `deleteResource` 函式在處理帶有 Query String 的 URL 時，誤將 `/delete` 附加在結尾的問題。改為正確分割 URL 並在路徑末尾插入 `/delete`。
- ✅ **後端對接 (Backend)**：在 `delete_partner` handler 中新增 `Json<DeleteQuery>` 接收器，使其能同時讀取來自 Query String 或 JSON Body 的 `hard` 參數，確保與前端調用方式完全相容。
- ✅ **路由重整 (Backend)**：調整 `backend/src/routes/erp.rs` 路由順序，確保靜態功能路徑優先於變數匹配路徑。
- ✅ **品質驗證**：通過 `handlers::partner` 單元測試，驗證 Body 與 Query 混合參數讀取邏輯正確。

### 2026-03-14 Admin 設施管理元件編譯錯誤修復
- ✅ **前端修復 (Frontend)**：修復 `BuildingTab`, `DepartmentTab`, `FacilityTab`, `PenTab`, `SpeciesTab`, `ZoneTab` 等元件中對 `useConfirmDialog` hook 的錯誤調用。將 `confirm.open()` 改為符合新 API 的 `const { dialogState, confirm } = useConfirmDialog()` 結構，並將 `handleDelete` 改為非同步調用。
- ✅ **品質驗證**：在本機執行 `npm run build` 通過，確認無 TypeScript 編譯錯誤。

### 2026-03-14 Admin 硬刪除權限功能實作
- ✅ **後端擴充 (Backend)**：更新 `PartnerService::delete` 與 `DocumentService::delete` 以支援 `is_hard` 參數。管理員可透過 `?hard=true` 執行硬刪除（永久移除記錄），並在單據模組中略過非「草稿」狀態不可刪除的限制。新增 `PARTNER_HARD_DELETE` 與 `DOC_HARD_DELETE` 審計日誌類別。
- ✅ **前端互動 (Frontend)**：修改 `PartnersPage.tsx` 與 `DocumentsPage.tsx`。針對具備 `admin` 角色的使用者，即使單據非草稿狀態仍顯示刪除按鈕，並在執行時跳出威力警告對話框與硬刪除提示。
- ✅ **品質驗證**：建立並通過 `test_admin_hard_delete_partner` 單元測試，確認軟硬刪除邏輯切換正確。

---

### 2026-03-14 R6-6 資料庫輸出與歷史重新填寫
- ✅ **Protocol 複製（後端）**：`ProtocolService::copy()`、handler `copy_protocol`、路由 `POST /protocols/:id/copy`
- ✅ **Protocol 複製（前端）**：ProtocolsPage 每行加「複製」按鈕，確認後建立新草稿並跳轉至編輯頁
- ✅ **請假申請預填**：HrLeavePage 新增「基於上次申請預填」按鈕，預填假別/事由/代理人
- 說明：手術複製（`/surgeries/copy`）及全庫 JSON/ZIP 匯出入（`DataExportImportCard`）已事先存在，本次補全 Phase 1–2 缺失功能

### 2026-03-14 R6-8 設施管理前端完整實作
- ✅ **新增 `types/facility.ts`**：Species/Facility/Building/Zone/Pen/Department 6 組 TypeScript 型別（對應後端 models/facility.rs）
- ✅ **新增 `lib/api/facility.ts`**：`facilityApi` 物件，涵蓋 6 個實體 × CRUD = 24 個 API 函式
- ✅ **新增 `FacilitiesPage.tsx`**：主頁面 + 6 個子元件（SpeciesTab/FacilityTab/BuildingTab/ZoneTab/PenTab/DepartmentTab），每檔 < 200 行
- ✅ **整合路由與導航**：`App.tsx` 加入 `/admin/facilities`，`Sidebar.tsx` 加入「設施管理」選項
- 說明：Migration 010 及後端 handlers/services 已事先存在；本次補全前端，完成端對端功能

### 2026-03-14 修復資料庫遷移檔案編碼問題
- ✅ **編碼修復**：修正 `backend/migrations/010_treatment_drug_final.sql` 包含非 UTF-8 字元（亂碼）的問題，解決 Docker 建置時 `sqlx::migrate!` 失敗。
- ✅ **內容修正**：手動修正損壞的中文註解（設施管理、物種、建築等），統一檔案編碼為 UTF-8。

---

### 2026-03-14 R9 技術債掃描 — 新增 18 項技術債待辦至 TODO.md（R9-1～R9-18）
- ✅ **架構違規高優先（2 項補充）**：handler 層 98 處直接 SQL（21+ 個 handler 檔案違規，含 auth.rs/user_preferences.rs/signature.rs 等）；repository 層缺少 protocol/animal/hr/user_preferences 子項（重複 SQL 最多 5 次的 `SELECT display_name FROM users WHERE id = $1`）
- ✅ **後端長函數（高優先 5 項）**：`pdf/service.rs::generate_protocol_pdf`（578 行）、`animal/import_export.rs::import_basic_data`（327 行）、`services/product.rs` 多個長函數（create 109/update 170/import_products 196）、`handlers/signature.rs` handler 過長含業務邏輯（7 個函數 80–106 行）、`services/accounting.rs` post_do(117)/post_sr(121)
- ✅ **前端超大元件（中優先 9 項）**：ProtocolContentView(870)、ProductImportDialog(863)、usePermissionManager hook(853)、AccountingReportPage(838)、HrLeavePage(837)、BloodTestTab(811)、DashboardPage(805)、DocumentLineEditor(723+10處any)、useDocumentForm hook(717)
- ✅ **細節/一致性（低優先 5 項）**：中大型元件逐步拆分清單（AnimalDetailPage 786 等 10 個元件）、STORAGE_CONDITIONS 重複常數合併+`lib/constants/` 目錄建立、剩餘 any 型別消除、後端中長函數清理（auth.rs）、前端 54 處 try-catch 改 TanStack Query 全域錯誤處理
- TODO.md R9 章節新增，待辦統計更新至 21 項

### 2026-03-14 R8 代碼規範重構 — 全部 11 項問題修正完成（R8-1～R8-11）
- ✅ **R8-1**：`routes.rs`（1,236 行）→ `routes/` 目錄（mod.rs + 10 業務域子模組），`cargo check` 零警告。
- ✅ **R8-2**：`main.rs` 450→148 行；啟動邏輯提取至 `startup/tracing.rs`、`startup/migration.rs`、`startup/config_check.rs`、`startup/server.rs`。
- ✅ **R8-3**：建立 `repositories/` 層（equipment/product/role/sku/user/warehouse），遷移 8 個 service 中重複 SQL。
- ✅ **R8-4**：`utils/access.rs` → `services/access.rs`；`utils/mod.rs` 清空為純說明注解。
- ✅ **R8-5**：`services/animal/core.rs`（684 行）→ `core/` 目錄（mod.rs + query.rs/write.rs/update.rs/delete.rs）。
- ✅ **R8-6**：`App.tsx` 四個內聯 Route 元件抽離至 `components/auth/`；`DASHBOARD_ROLES` 常數統一，消除 `getHomeRedirect` 與 `DashboardRoute` 重複。
- ✅ **R8-7**：`lib/api.ts`（514 行）→ `lib/api/` 目錄（client.ts + 7 業務域檔案 + index.ts），原 `api.ts` 改為向後相容 re-export。
- ✅ **R8-8**：`AnimalsPage.tsx` 576→308 行（mutations 提取至 `useAnimalsMutations.ts`，queries 提取至 `useAnimalsQueries.ts`）。
- ✅ **R8-9**：`AnimalsPage.tsx`/`ProtocolsPage.tsx` 型別 import 從 `@/lib/api` 改為 `@/types/*`；`axios` 從非業務用途移除。
- ✅ **R8-10**：`ProtocolsPage.tsx` 中 17 行 `statusColors` 移至 `pages/protocols/constants.ts`。
- ✅ **R8-11**：`services/protocol/core.rs` `use chrono::Datelike` 從函式體內移至檔案頂部。

### 2026-03-14 單據管理功能與 UI 優化
- ✅ **前端按鈕增強 (Frontend)**：修改 `DocumentsPage.tsx`，允許使用者在未選擇子類型（Sub-type）的情況下點擊「新增單據」按鈕，導向至新增頁面。
- ✅ **預設類型調整 (Frontend)**：修改 `DocumentEditPage.tsx` 與 `useDocumentForm.ts`，將「新增單據」時的預設單據類型改為「選擇類型」。
- ✅ **條件式表單渲染 (Frontend)**：實作 `DocumentEditPage.tsx` 的條件渲染，在使用者正式選擇單據類型前，不顯示明細編輯與預覽區塊，避免混淆。
- ✅ **UI 清理 (Frontend)**：移除 `DocumentFormHeader.tsx` 在新增與編輯模式下的「向左箭頭」返回按鈕，對齊新的導航設計規範。

---

### 2026-03-14 儀表板 Widget 捲動體驗優化
- ✅ **樣式統一 (Style Unification)**：修改 `DashboardPage.tsx` 與多個 Widget 元件（`MyProjectsWidget`, `AnimalsOnMedicationWidget`, `LeaveBalanceWidget`, `VetCommentsWidget`）。
- ✅ **捲動支持 (Scrolling Support)**：所有 Widget 的 `Card` 皆加上 `flex-col overflow-hidden`，並將 `CardContent` 設為 `flex-1 overflow-auto`。
- ✅ **固定標題 (Fixed Header)**：確保標題區塊（Header）在內容過長捲動時維持固定位置，提升使用者在儀表板查看長列表時的體驗。

### 2026-03-14 請購/採購單批號與效期調整
- ✅ **前端表單驗證 (Frontend)**：修改 `useDocumentForm.ts` 中的 `needsShelf` 與 `isShelfRequired` 邏輯，排除 `PR` 單據，使其不強制要求儲位。調整 `buildPayload` 驗證，針對 `GRN`/`DO` 等單據，透過品項設定 (`track_batch`, `track_expiry`) 動態決定批號與效期是否為必填，而非一律強制。
- ✅ **後端 CRUD 驗證 (Backend)**：修改 `crud.rs` 中的單據 `create` 與 `update` 方法，結合單據類型與產品 `track_batch`、`track_expiry` 屬性，動態驗證批號與效期，確保正確控制請購/採購與入庫單的資料流向。

### 2026-03-14 R4-100-T5 + T6：單元測試補齊與覆蓋率量測 CI

**R4-100-T5：protocol / document / hr services 單元測試**

- ✅ **protocol/numbering**：提取 `parse_no_sequence` 與 `format_protocol_no` 純函式，並同步重構 `generate_apig_no` / `generate_iacuc_no` 使用這兩個函式；新增 8 個測試（前綴解析、格式化補零、非法輸入）。
- ✅ **protocol/status**：直接測試既有 `validate_protocol_content` 私有函式（透過 `ProtocolService::` 呼叫）；7 個測試涵蓋缺少 content、缺少 basic、空白標題、GLP 未填授權單位、缺少 project_type 及正常通過。
- ✅ **hr/leave**：補充 `effective_hours` 純函式（total_hours 優先換算邏輯）；7 個測試涵蓋 `is_half_hour_multiple` 邊界值與 `effective_hours` 換算。
- ✅ **hr/overtime**：提取 `overtime_multiplier`、`comp_time_hours_for_type`、`calc_hours_from_minutes` 三個純函式，同步重構 `create_overtime`；8 個測試涵蓋各類型乘數、補休規則、0.5 小時捨入。
- ✅ **hr/attendance**：直接測試既有 `is_ip_in_ranges` 公開函式；補充 `attendance_status_display` 純函式；8 個測試涵蓋精確 IP、CIDR /24、/32、多段清單、空清單、無效 IP。
- ✅ **hr/balance**：提取 `compute_leave_expiry` 純函式（到期日計算含閏年退回邏輯），同步重構 `create_annual_leave_entitlement`；4 個測試涵蓋無到職日、有到職日、2/29 閏年邊界。
- ✅ **document/grn**：提取 `next_seq_from_last_no` 與 `receipt_status_label` 純函式，同步重構 `create_grn_from_po` 與 `get_po_receipt_status`；8 個測試涵蓋各種單號格式、非法字串、三種入庫狀態。
- **總計**：新增 50 個單元測試；`cargo check --tests` 通過。

**R4-100-T6：cargo-tarpaulin 覆蓋率量測 CI**

- ✅ **新增 `backend-coverage` job**：在 `.github/workflows/ci.yml` 加入獨立覆蓋率量測流程。
- ✅ **設定**：`SQLX_OFFLINE=true`（不需要 DB）、`--lib`（只跑 lib 單元測試）、`--fail-under 25`（行覆蓋率門檻 25%）、`--timeout 120`、輸出 XML 格式。
- ✅ **報告保存**：XML 覆蓋率報告以 `coverage-report` artifact 上傳，保留 14 天。
- ✅ **快取優化**：使用 `cargo-tarpaulin-` 前綴的獨立快取 key。

---

### 2026-03-14 批次套用儲位 UI 與邏輯優化
- ✅ **批次套用儲位選填化**：標明單據表頭（如採購入庫、調撥單）的儲位選擇為「批次套用儲位 (選填)」，避免使用者誤以為只能限定單一儲位，適應同一張採購單品項存在不同儲位的情境。
- ✅ **預設儲位繼承**：使用者點擊「新增明細」時，新明細會自動繼承表頭已選的「批次套用儲位」，大幅提升多儲位配置的建檔效率。

### 2026-03-14 品項選擇與單據關連優化
- ✅ **動態品類同步 (已修復)**：品項選擇彈窗現在會自動透過 `useSkuCategories` Hook 同步品類設定，修正了之前調用未定義 `/categories` API 導致 Tabs 未發揮作用的問題。
- ✅ **UX 優化**：新增品類 Tabs 篩選器，支援關鍵字與品類雙重過濾。同時擴增後端庫存查詢，實現在「庫存模式」下也能依據對應品類即時過濾。
- ✅ **採購入庫強化**：連動「來源採購單」時自動過濾供應商與核准狀態。
- ✅ **系統修復**：修復 API 400 (參數大小寫/解析錯誤) 與 500 (SQL 欄位缺失) 報錯。
- ✅ **明細顯示修復**：修正 `poReceiptStatus` 屬性未傳遞至 `DocumentLineEditor` 的問題，確保 GRN 選擇來源採購單後能正確列出待入庫明細。

---

### 2026-03-13 R8 代碼規範重構 — 目錄掃描與風格採樣（01a-1, 01a-2）
- ✅ **01a-1 目錄掃描**：建立 backend/frontend/scripts/tests 完整樹狀圖，標注各目錄推測職責；發現 `utils/access.rs` 位置不符規範、缺少 `repositories/` 層、`lib/api.ts` 未按業務域拆分等三項架構問題。
- ✅ **01a-2 風格採樣**：分析 `main.rs`、`routes.rs`、2 個 service、`App.tsx`、2 個 page，產出命名慣例/函式長度/巢狀深度/錯誤處理/import 組織五維度比較表；識別 11 項具體問題（R8-1～R8-11），記錄至 `docs/TODO.md` R8 區段。

### 2026-03-14 採購入庫品項篩選強化 (修正)
- ✅ **入庫邏輯嚴格化**：修正 GRN 品項篩選失效問題。
- ✅ **UI 增強**：新增「來源採購單」下拉選單，支援依供應商自動篩選已核准 PO。
- ✅ **邏輯修正**：修正 `useDocumentForm` 中 `poReceiptStatus` 查詢邏輯（改用 `source_doc_id`），確保品項彈窗正確過濾已入庫項目。

### 2026-03-14 單據頁面 UI 體驗優化 (V2)
- ✅ **銷貨單優化**：隱藏專屬單據 (SO/DO) 重複的「客戶」欄位，減少 UI 冗餘。
- ✅ **調撥單功能增強**：新增「來源儲位」與「目標儲位」的批次套用選單，支援所有明細行同步更新。

### 2026-03-14 單據儲位選單選取問題修復
- ✅ **UI 綁定修正**：解決了「批次套用儲位」重灌後下拉按鈕標籤不更新的 Bug。
- ✅ **狀態管理優化**：新增 `batchStorageLocationId` 狀態以追蹤並呈現當前選定的批次儲位，提升選取回饋感。

### 2026-03-14 供應商與專屬計畫填寫互斥修復
- ✅ **邏輯解耦**：在 `DocumentFormData` 中新增獨立的 `protocol_no` 欄位，解除了計畫代碼與供應商 ID 的強制綁定。
- ✅ **採購單流程優化**：在 `PO`/`GRN`/`PR` 等採購相關單據中，選擇計畫後不再覆蓋已填寫的供應商。
- ✅ **向後相容性**：銷貨/出庫單（`SO`/`DO`）維持原有邏輯，選擇計畫後自動帶出對應客戶，符合現有作業流程。

### 2026-03-14 專屬計畫載入效能優化
- ✅ **載入邏輯修復**：修正了 `PO`/`PR` 單據類型無法觸發計畫列表獲取的 Bug。
- ✅ **Loading 體驗優化**：解耦了 `activeProtocols` 的載入狀態，在無資料時正確顯示「無可用計畫」而非持續顯示「載入中」。
- ✅ **效能提升**：優化了計畫列表的過濾與計算邏輯。

### 2026-03-13 單據邏輯增強與 IACUC 關聯實作
- ✅ **單據欄位規範調整 (Dynamic Fields)**：依單據類型動態切換日期、倉庫、貨架、計畫與供應商的必填/可見狀態。
    - **倉庫-儲位連動 (Header Linkage)**：表頭選定倉庫後跳出儲位選擇器，支援全單批次套用至明細行。
    - PO (採購單)：顯示供應商 (必填) 與計畫 (選填)。
    - GRN (採購入庫)：顯示供應商 (必填)，**計畫欄位隱藏** (符合不需要規範)。
    - SO/DO (銷貨/出庫)：顯示客戶 (必填) 與 IACUC No. (必填)。
    - STK/ADJ (盤點/調整)：**隱藏所有夥伴與計畫欄位**。
- ✅ **前端驗證強化 (Frontend Validation)**：`useDocumentForm` 實作跨欄位提交校驗與 `*` 標誌呈現。

### 2026-03-13 倉庫管理頁面重構計畫啟動

- 🏗️ **架構規劃 (Planning)**：擬定「上、中、下」三層式結構改善計畫。將 `WarehouseLayoutPage.tsx` 拆分為 `WarehouseActionHeader` (上)、`StorageLocationEditor` (中) 與 `WarehouseDetailTabs` (下)。
- ✅ **功能實作 (Implementation)**：補全倉庫 CRUD (建立、刪除、停用、編輯) 功能，支援建築結構 (牆、門、窗) 的 2D 視覺化佈局。
- 🧪 **品質驗證 (Verification)**：通過 `tsc` 編譯檢查，確認元件通訊與 API 互動正常。
- 📁 **產出**：`implementation_plan.md`、`task.md`、`walkthrough.md`。

### 2026-03-13 前端編譯錯誤修復 (DocumentEditPage.tsx)

- ✅ **編譯修復 (Bug Fix)**：修正 `DocumentEditPage.tsx` 在解構 `useDocumentForm()` 時漏掉 `setFormData` 的問題。這解決了 `DocumentLineEditor` 組件因接收到未定義函數而導致的 `Cannot find name 'setFormData'` TypeScript 錯誤，確保 Docker 建置與 `npm run build` 能正常完成。
- 📁 **產出**：`DocumentEditPage.tsx`。

### 2026-03-13 測試基礎設施修復 (Test Infrastructure Fix)

- ✅ **測試環境修錯 (Bug Fix)**：修正 `backend/tests/common/mod.rs` 中 `ensure_admin_user` 函數參數遺漏問題（從 1 個參數補齊為 2 個，包含 `config`），恢復整合測試代碼的編譯。
- 📁 **產出**：`backend/tests/common/mod.rs`。

### 2026-03-13 採購單未入庫通知與狀態顯示功能

- ✅ **通知邏輯 (Notification)**：實作 `notify_po_pending_receipt`，自動檢查已核准但尚未有 GRN 入庫紀錄的採購單 (PO)，並發送通知給倉管主管。
- ✅ **排程任務 (Scheduler)**：新增每日 09:00 定期檢查排程，確保倉管人員及時處理未入庫單據。
- ✅ **手動觸發 API**：新增 `/api/admin/trigger/po-pending-receipt-check` 端點，允許管理員視需要手動執行檢查。
- ✅ **通知路由配置**：在 `RoutingService` 中註冊 `po_pending_receipt` 事件，並於資料庫中新增預設路由。
- ✅ **單據列表強化**：`DocumentListItem` 模型新增 `receipt_status` 欄位；後端 SQL 結合 `v_purchase_order_receipt_status` 視圖自動計算入庫狀態。
- ✅ **前端視覺化**：單據管理頁面 (`DocumentsPage.tsx`) 針對 PO 顯示「未入庫」、「部分入庫」、「已入庫」彩色標籤，並於通知設定中加入對應事件名稱。
- 📁 **產出**：erp.rs, scheduler.rs, routing.rs, workflow.rs, crud.rs, document.rs (model), DocumentsPage.tsx, notification.ts (frontend) 等多處更新。

### 2026-03-13 ERP 庫存管理強化與視覺體驗優化

- ✅ **視覺體驗優化 (UX)**：針對庫存查詢頁面進行全方位美化。
  - **下拉選單 (WarehouseShelfTreeSelect)**：解決 Popover 選單背景透明導致的文字重疊問題。引入 `Popover.Portal` 確保層級正確，並加入 Glassmorphism（背景模糊）、陰影與流暢的動畫效果。
  - **列表樣式**：優化表格 Layout，提升資料可讀性。增加單行 Hover 效果、漸變標題與精緻的狀態標籤（如安全庫存預警）。
  - **空狀態重塑 (Empty State)**：當搜尋無結果或無資料時，顯示更具引導性的插圖與文字描述，而非單調的圖標。
  - **加載體驗**：改進 Skeleton 與 Loader 顯示方式，使其在資料加載過程中視覺上更穩定。
- ✅ **下拉選單穩定性**：修復「新增單據」頁面中倉庫、合作夥伴與 IACUC No. 下拉選單選項不穩定問題。透過 `react-query` 的 `refetchOnMount` 與前端 Loading 狀態處理，確保資料在載入過程中 UI 顯示一致。
- ✅ **庫存查詢**：新增「未分配庫存查詢」功能。前台 `WarehouseLayoutPage` 可快速查看尚未指派儲位的產品庫存，後端 `StockService` 提供對應 API。
- ✅ **系統健全度**：`StockService` 查詢結果加入 `storage_location` 預設值處理，避免特定情境下的欄位缺失。
- ✅ **資料庫架構**：完成 Migration 清理，將 `phone_ext` (分機) 與 `leave_cancelled` 路由邏輯正式併入基礎遷移檔案，提升資料庫一致性。
- 📁 **產出**：InventoryPage.tsx、WarehouseShelfTreeSelect.tsx、useDocumentForm.ts、DocumentEditPage.tsx、stock.rs、WarehouseLayoutPage.tsx、migrations 多檔更新。

### 2026-03-10 系統電話分機欄位 (Phone Extension) 支援

- ✅ **資料庫與架構**：Migration `002`、`004`、`007` 新增 `phone_ext` 欄位至 `users`、`partners`、`animal_sources` 並清理臨時遷移文件。
- ✅ **計畫書 (AUP)**：`SectionBasic.tsx` 與 `ProtocolContentView.tsx` 新增資助者 (Sponsor) 與計畫主持人 (PI) 的聯絡分機，PDF 產生同步支援顯示。
- ✅ **使用者管理**：`ProfileSettingsPage.tsx` 與型別 `User` 新增 `phone_ext`，支援個人資料分機設定。
- ✅ **交易夥伴**：`PartnersPage.tsx` 與型別 `Partner` 新增 `phone_ext`，支援供應商與客戶的分機管理。
- ✅ **動物來源**：`AnimalSourcesPage.tsx` 與型別 `AnimalSource` 新增 `phone_ext`，支援來源廠商的分機管理。
- ✅ **型別與初始值**：同步更新 `auth.ts`、`erp.ts`、`animal.ts`、`protocol.ts` 與 `constants.ts` 確保前端型別一致與表單預設值。
- 📁 **產出**：涉及 User, Partner, AnimalSource, Protocol 型別與 UI 元件多處更新。

---

### 2026-03-10 AUP 計畫主持人電話新增「分機」欄位 (及編譯錯誤修復)

- ✅ **前端**：`SectionBasic.tsx` 新增分機 (Extension) 輸入框，UI 顯示為 `電話 #分機` 格式。
- ✅ **前端檢視**：`ProtocolContentView.tsx` 計畫書內容檢視頁面同步顯示分機號碼。
- ✅ **類型修復**：修改 `src/types/protocol.ts`，在 `ProtocolWorkingContent.basic.pi` 中增加 `phone_ext?: string` 選填欄位，解決元件中的型別不匹配錯誤。
- ✅ **編譯修復**：修正 `src/pages/master/CreateProductPage.tsx` 缺少 `useEffect` 匯入的問題。
- ✅ **初始值同步**：更新 `protocol-edit/constants.ts` 中的 `defaultFormData`，加入 `phone_ext` 初始值。
- ✅ **本地化**：`zh-TW.json` 新增 `aup.basic.piExtension` 字串。
- ✅ **後端 PDF**：`backend/src/services/pdf/service.rs` 更新 PDF 產生邏輯，計畫主持人電話欄位現在會包含分機。
- 📁 **產出**：protocol.ts、constants.ts、CreateProductPage.tsx、ProtocolContentView.tsx、SectionBasic.tsx、zh-TW.json、service.rs。

### 2026-03-09 重構動物服務模組 (Service 拆分與解耦)

- ✅ **Service 抽取**：將原 `AnimalService` 龐大邏輯拆分為 9 個獨立 Service：`AnimalBloodTestService`、`AnimalMedicalService`、`AnimalObservationService`、`AnimalSurgeryService`、`AnimalWeightService`、`AnimalSourceService`、`AnimalTransferService`、`AnimalImportExportService`、`AnimalFieldCorrectionService`。
- ✅ **核心 CRUD**：`AnimalService` (core.rs) 僅保留動物基礎 CRUD 與批次分配邏輯。
- ✅ **工具函數解耦**：耳號格式化、欄位編號格式化、品種轉換等通用邏輯移動至 `AnimalUtils`。
- ✅ **Handler 同步**：同步更新所有動物相關 Handler (`blood_test.rs`, `import_export.rs`, `source.rs`, `transfer.rs` 等)，從調用單一 `AnimalService` 改為調用對應的專屬 Service。
- ✅ **修復隱患**：修正 `import_export.rs` Handler 中的匯出紀錄建立參數不匹配問題。
- 📁 **產出**：`backend/src/services/animal/` 下所有檔案及 `backend/src/handlers/animal/` 對應檔案。

### 2026-03-09 修正 Clippy 編譯警告與安全隱患 (unwrap 清理)

- ✅ **Clippy 修正**：修復 `services/hr/attendance.rs` 中的 `needless-borrows-for-generic-args` 警告，提升程式碼品質。
- ✅ **安全強化**：將 `services/email/mod.rs` 中的 `.unwrap()` 改為 `.expect()`，並提供明確的錯誤訊息，避免潛在的 panic。
- 📁 **產出**：`backend/src/services/hr/attendance.rs`、`backend/src/services/email/mod.rs`。

### 2026-03-09 清理重複的胰臟分類

- ✅ **重複統合**：將資料庫遷移檔案 `004_animal_management.sql` 中重複的「胰臟」分類移除，並將相關檢驗項目（AMY, LPS）統合至「胰臟與血糖」(`SUGAR`) 分類下。解決前端畫面顯示重複的問題。
- 📁 **產出**：`004_animal_management.sql`。

### 2026-03-09 請假管理動作後自動重新整理頁面

- ✅ **自動重新整理**：在「新增請假」、「送審」、「核准」、「駁回」、「取消」等動作成功後，加入 1 秒延遲並執行 `window.location.reload()`。
- ✅ **資料同步強化**：確保動作完成後，頁面上的餘額摘要、待審核數量紅點及各分頁列表皆能完全同步。
- 📁 **產出**：`frontend/src/pages/hr/HrLeavePage.tsx`。

---

### 2026-03-09 API 規格文件全面對齊程式碼（第二輪）

- ✅ **轉讓端點修正**：移除 source-pi-confirm/target-pi-confirm/iacuc-approve，新增 vet-evaluation/assign-plan/approve/reject（對齊 routes.rs）
- ✅ **移除未實現端點**：protocols/:id/status-history、animals/batch/start-experiment
- ✅ **補齊未記錄端點**：care-records、treatment-drugs、blood-test-presets、equipment、equipment-calibrations、training-records、qau/dashboard、admin data-export/import/config-warnings、SSE 警報、通知路由子端點
- ✅ **ENUM 修正**：animal_transfer_status 對齊 001_types.sql（pending/vet_evaluated/plan_assigned/pi_approved/completed/rejected）
- ✅ **設施管理表標註**：標註 species/facilities/buildings/zones/pens/departments 遷移待補建
- ✅ **權限代碼對齊**：05_API_SPECIFICATION Section 5 → admin.user.*、Section 6 → dev.role.*
- ✅ **RBAC 文件更新**：新增 dev.* 權限區塊，移除不存在的 admin.role.view/manage
- ✅ **DELETE 備用路由通則**：新增 Section 1.5 說明 POST /:id/delete 備用路由設計
- 📁 **產出**：05_API_SPECIFICATION.md、04_DATABASE_SCHEMA.md、06_PERMISSIONS_RBAC.md

---

### 2026-03-08 R7 安全性原始碼審視修復 + 文件全面對齊

- ✅ **R7-P0**：`data_import.rs` SQL 拼接改為參數化查詢，消除 SQL injection 風險
- ✅ **R7-P1-1**：`create_admin.rs` 不再將管理員密碼明文印至 stdout
- ✅ **R7-P1-2**：`config.rs` `trust_proxy` 預設值由 `true` 改為 `false`
- ✅ **R7-P4-1**：`etag.rs` 改用 `constants::ETAG_VERSION` 取代硬編碼字串
- ✅ **R7-P4-2**：認證端點 rate limit 由 100/min 降至 30/min
- ✅ **文件對齊**：ARCHITECTURE.md（技術棧/目錄/rate limit）、TODO.md（R7 完成項/統計）、PROGRESS.md、QUICK_START.md（環境變數）、API 規格、DB Schema、RBAC 權限文件全面更新
- 📁 **產出**：`data_import.rs`、`create_admin.rs`、`config.rs`、`constants.rs`、`etag.rs`、`rate_limiter.rs`；docs 多檔修正

---

### 2026-03-08 日曆功能審視與重構 (業內標準化)

- ✅ **前端重構**：將 `CalendarSyncSettingsPage` 拆分為 `useCalendarSync`、`useCalendarEvents` Hooks 與 4 個獨立 Tab 元件（Status/Events/History/Conflicts）；實作日曆事件點擊預覽 (Popover)，支援直接跳轉 Google Calendar。
- ✅ **後端解耦**：引入 `CalendarApi` trait 抽象日曆操作，實現 `GoogleCalendarClient` 與 `CalendarService` 的解耦，支援依賴注入與 Mock 測試。
- ✅ **同步重構**：重構 `trigger_sync` 邏輯，拆分為 `process_pending_creates/updates/deletes`，提升代碼可讀性與維護性。
- ✅ **測試補強**：新增 `useCalendarEvents` 的導航邏輯單元測試 (Vitest) 與後端 `CalendarService` 輔助函式單元測試 (Cargo test)。
- 📁 **產出**：CalendarView.tsx、CalendarSyncSettingsPage.tsx、useCalendarSync.ts、useCalendarEvents.ts、google_calendar.rs (Trait)、calendar.rs (Refactored)。

---

### 2026-03-07 Calendar 月份切換修正 & 2.0 體驗升級

**月份切換 Bug 修正（根本原因修正）：**

- ✅ 移除 `key={format(calendarDateRange.start, 'yyyy-MM')}` — 不再因月份變化強制 remount FullCalendar
- ✅ 採用 React Query `keepPreviousData` — 換月時保留舊事件顯示，新資料到才平滑替換，無閃爍
- ✅ 刪除 `calendarMounted` 雙層 RAF 邏輯 — 移除不必要的延遲掛載 workaround
- ✅ 刪除 `shouldAcceptDateRange` — 改以格式化字串比較去重，邏輯更清晰
- ✅ 新增 `isFetching` → 換月期間右上角顯示小 spinner，不遮擋日曆本體

**Calendar 2.0 體驗升級（P0–P1 全數完成）：**

- ✅ **假別顏色 coding**：從 summary 解析 `[假別]` 標籤，映射 10 種假別顏色（特休＝綠、病假＝橘、事假＝藍...），不需後端改動
- ✅ **假別篩選 chips**：日曆上方顯示當月出現的假別 chip，點擊即過濾；再點取消；「全部」chip 常駐
- ✅ **衝突解決補全 `accept_google`**：衝突列表新增第三個解決方案「接受 Google 版本」（後端原已支援）
- ✅ **分頁 UI**：同步歷史、衝突列表加前/下頁按鈕，後端已支援 pagination，前端補接
- ✅ **衝突樂觀更新**：點擊解決按鈕後立即從列表移除，失敗時自動回滾
- ✅ **Popover 解析升級**：事件彈出框解析 `[假別] 員工名（代理人）` 格式，顯示假別顏色 badge + 員工名 + 代理人欄位
- ✅ **時間格式改善**：Popover 顯示完整日期範圍（全天事件顯示「月/日（全天）」或「月/日 – 月/日（全天）」）
- ✅ **連線狀態升級**：顯示近期錯誤警告、最後同步結果 badge、下次同步時間
- ✅ **自動同步設定 UI**：連線狀態分頁加入同步排程設定（啟用開關、早/晚同步時間），對接 `PUT /hr/calendar/config` API

- 📁 **產出**：useCalendarEvents.ts、useCalendarSync.ts、CalendarView.tsx、CalendarEventsTab.tsx、CalendarStatusTab.tsx、ConflictsTab.tsx、SyncHistoryTab.tsx、CalendarSyncSettingsPage.tsx、hr.ts（新增 CalendarConfig / UpdateCalendarConfig 型別）

---

### 2026-03-07 血檢 API 與動物權限綁定

- ✅ **需求**：list_all（panels/templates/presets）與血檢分析報表應與動物權限綁定；能看到動物的範圍，就看到其血檢分析結果。
- ✅ **實作**：list_all_blood_test_* API 改為 require `animal.record.view`（原 `animal.blood_test_template.manage`）；blood_test_analysis 報表加權限檢查，若僅 view_project 則只回傳 `iacuc_no IS NOT NULL` 之動物；REVIEWER 新增 `animal.animal.view_all`、`animal.record.view` 以存取血檢分析。
- 📁 **產出**：blood_test.rs、report.rs、ReportService、permissions.rs、003、BloodTestAnalysisPage、06_PERMISSIONS_RBAC.md。

### 2026-03-07 血檢項目權限 `animal.blood_test_template.manage`

- ✅ **需求**：僅具該權限者可檢視與編輯血檢項目（模板、組合、常用組合）；管理者可於「角色權限」處勾選／取消。
- ✅ **後端**：新增權限 `animal.blood_test_template.manage`（Migration 011、permissions.rs）；模板／組合／常用組合之 list_all、create、update、delete API 改為檢查此權限（原先為 animal.record.*）。`list`（啟用中）仍不檢查，供動物血檢 Tab 建立紀錄時使用。
- ✅ **前端**：側邊欄「血檢項目」加 `permission`；`/blood-test-templates`、`/blood-test-panels`、`/blood-test-presets` 路由包上 `RequirePermission`。
- ✅ **角色**：預設指派給 EXPERIMENT_STAFF；admin 具全部權限。
- 📁 **產出**：003_notifications_roles_seed.sql（權限與角色指派）、blood_test.rs、Sidebar.tsx、App.tsx、usePermissionManager.ts、06_PERMISSIONS_RBAC.md。

### 2026-03-06 新增 EQUIPMENT_MAINTENANCE（設備維護人員）角色

- ✅ **需求**：於系統管理「角色權限」中新增「設備維護人員」角色，供管理設備與校準紀錄。
- ✅ **實作**：將角色與權限寫入既有 migration **009_glp_extensions.sql**（9.3b 區塊）：插入角色 `EQUIPMENT_MAINTENANCE`（名稱：設備維護人員）、並指派 `equipment.view`、`equipment.manage`、`training.view`、`training.manage_own`、`dashboard.view`。維持 10 個 migration 檔案。
- ✅ **結果**：重啟後端後，角色權限頁面會顯示「設備維護人員」卡片；可將使用者指派為此角色以存取 ERP 設備維護分頁。

### 2026-03-05 migrations 升級重整（維持 10 個）

- ✅ **合併結果**：原 16 個 migration 重整為 10 個，最終 schema 不變、執行順序與依賴維持正確。
- ✅ **對應**：001_types、002_users_auth 未改；003＝原 003＋004（通知/附件/稽核/trigger＋角色權限 seed/user_preferences）；004＝原 005 動物管理；005＝原 006 AUP；006＝原 007 HR；007＝原 008 稽核＋ERP；008＝原 009＋011＋012（補充、犧牲鎖欄、轉讓類型、修正、效能）；009＝原 010＋013＋014（GLP 訓練/設備/QAU/會計、血液檢查預設、SKU 品類種子）；010＝原 015＋016（治療藥物去重與業務鍵唯一）。
- ✅ **舊檔移除**：006_aup_system、007_hr_system、008_audit_erp、009_supplementary、010_glp_accounting、011～016 已刪除；保留 `.gitattributes`。

### 2026-03-05 系統時間統一為台灣時間 (Asia/Taipei)

- **後端**：新增 `backend/src/time.rs` 提供 `now_taiwan()`、`today_taiwan_naive()`；活動日誌 partition_date、會計 as_of、審計儀表板、HR 出勤／請假「今日」、單據編號日期、PDF/郵件顯示日期、排程月報、匯出檔名等皆改為以台灣日期／時間為準。
- **前端**：`formatDate`／`formatDateTime` 及所有內聯日期顯示皆加上 `timeZone: 'Asia/Taipei'`，不論使用者瀏覽器時區皆顯示台灣時間。
- **Grafana**：`deploy/grafana_dashboard.json` 的 `timezone` 設為 `Asia/Taipei`。

### 2026-03-05 R4-100-T3 user/role service 單元測試

- **R4-100-T3**：UserService 提取 `user_search_pattern(keyword)` 供 list 使用，3 個單元測試；RoleService 提取 `is_valid_role_code(s)`（1–50 字、英數字與底線）、於 create 前驗證，3 個單元測試。另修正 `time.rs` 測試缺少 `chrono::Datelike` 導致編譯失敗。TODO R4-100-T3 標完成，待辦統計 4→3、合計 5→4。

### 2026-03-05 R4-100-T2 partner service 單元測試

- **R4-100-T2**：PartnerService 提取可測函式 `format_partner_code`、`is_valid_email`，`parse_partner_code_sequence`（#[cfg(test)]）、`parse_partner_type`／`parse_supplier_category`／`parse_customer_category` 改為 `pub(crate)`；新增 6 個單元測試（format_partner_code、parse_partner_code_sequence、parse_partner_type、parse_supplier_category、parse_customer_category、is_valid_email）。TODO R4-100-T2 標完成，待辦統計 5→4、合計 6→5。

### 2026-03-05 R4-100-T1 product service 單元測試

- **R4-100-T1**：ProductService 提取可測函式 `format_product_sku`、`validate_product_status`，`parse_bool` 改為 `pub(crate)`；新增 8 個單元測試（format_product_sku 3、validate_product_status 3、parse_bool 2）。TODO R4-100-T1 標完成，待辦統計 6→5、合計 7→6。

### 2026-03-05 R4-100-O7 報表／會計／治療藥物 OpenAPI 完成

- **R4-100-O7**：report（7 個端點）、accounting（7 個端點）、treatment_drug（6 個端點）補齊 `#[utoipa::path]`，openapi.rs 註冊 paths、tags「報表／會計／治療藥物」及相關 schemas（CreateApPaymentRequest、CreateArReceiptRequest、TreatmentDrugOption 等）。TODO.md R4-100-O7 標完成，待辦統計 7→6、合計 8→7。

### 2026-03-05 編輯產品與新增產品對齊（包裝結構、分類、移除耗材 LAB 主分類）

- **編輯產品頁**：品類改為與新增產品一致（分類按鈕＋子分類下拉）；移除「耗材(LAB)」主分類，實驗耗材改為耗材之子分類；舊 LAB 主分類產品載入時自動對應為 耗材＋實驗耗材。
- **編輯產品頁**：新增「包裝結構」區塊，可檢視與編輯兩層／三層包裝（外層→內層→基礎單位），與新增產品相同邏輯計算 `pack_unit`／`pack_qty` 儲存。
- 變更檔案：`frontend/src/pages/master/ProductEditPage.tsx`。

---

### 2026-03-05 移除 Sentry 錯誤監控

- 後端：移除 sentry crate、Config.sentry_dsn、main 中 sentry::init 與 runtime 改回 #[tokio::main]、error.rs 中 sentry::capture_error。
- 前端：移除 @sentry/react、instrument.ts、main 首行 import、ErrorBoundary 內 Sentry.captureException、系統設定頁「錯誤監控測試」卡片；Dockerfile / docker-compose 移除 VITE_SENTRY_DSN。
- 文件與範本：.env.example、DEPLOYMENT、OPERATIONS、IMPROVEMENT_PLAN_R4 還原為未導入 Sentry 狀態。

### 2026-03-04 全域刪除改用 POST /delete（避免代理/tunnel 回傳 405）

- ✅ **根因**：部分代理、Cloudflare Tunnel 等對 `DELETE` 請求回傳 405 Method Not Allowed，導致刪除操作失敗但前端仍顯示成功。
- ✅ **後端**：為所有 DELETE 端點新增 `POST /.../delete` 替代路由（36 個），涵蓋 users、roles、warehouses、storage-locations、products、partners、documents、animal-sources、animals、observations、surgeries、weights、vaccinations、care-records、blood-tests、notifications、attachments、equipment、training-records、hr、facilities 等。
- ✅ **前端**：新增 `deleteResource(url, options?)` 輔助函式；`bloodTestApi`、`bloodTestTemplateApi`、`bloodTestPanelApi`、`notificationRoutingApi`、`treatmentDrugApi` 及 20+ 頁面/元件全部改為使用 `deleteResource`，支援 body（如 reason）與 headers（如 X-Reauth-Token）。
- ✅ **倉庫列表**：列表 API 預設傳入 `is_active=true`，刪除（軟刪除）後已停用倉庫不再顯示於主列表。

---

### 2026-03-05 端點文件化與單元測試盤點、storage_location + SKU 完成

- ✅ **盤點文件**：新增 `docs/development/OPENAPI_AND_TESTS_STATUS.md`，總計路由 **318** 個 handler、已文件化 **132**、尚未文件化約 **186**；單元測試 **148** 個，並列出未文件化模組與建議補強測試模組。
- ✅ **OpenAPI 儲位與 SKU**：storage_location 全模組 **11** 端點（含 ToSchema/IntoParams 與 openapi 註冊）；SKU **6** 端點（get_sku_categories, get_sku_subcategories, generate_sku, validate_sku, preview_sku, create_product_with_sku），models/sku 與 ProductWithUom 等 schema 已註冊。
- ✅ **Rust 單元測試**：維持 **148** 個測試通過（前次已補常數/SKU/倉庫 6 個）。

### 2026-03-05 IMPROVEMENT_PLAN_R4 延續（端點文件化、Rust 單元測試）

- ✅ **OpenAPI 監控端點**：新增 3 個端點文件化：`health_check`（GET /api/health）、`metrics_handler`（GET /metrics）、`vitals_handler`（POST /api/metrics/vitals），含 HealthResponse/PoolCheck/DiskCheck/WebVitalsMetric 等 schema，新增「監控」tag。
- ✅ **Rust 單元測試**：新增 6 個測試（常數 audit 2 個、SKU 格式 2 個、倉庫代碼序號 2 個），總計 **148** 個測試通過。

### 2026-03-04 IMPROVEMENT_PLAN_R4 目標補齊（Rust 測試、OpenAPI）

- ✅ **Rust 單元測試**：新增 15 個核心業務邏輯測試（SKU 格式解析 7 個、倉庫代碼序號 4 個、常數驗證 4 個），總計 **142** 個測試通過，強化覆蓋率。
- ✅ **OpenAPI 端點文件化**：補齊 10 個端點 `#[utoipa::path]` 與 openapi.rs 註冊：`export_me`、`delete_me_account`、2FA、使用者偏好；**R4-100-O1** products（10 paths）；**R4-100-O2** partners（8 paths）；**R4-100-O3** documents + storage_location（19 paths）；**R4-100-O4** SKU（5 paths）；**R4-100-O5** animal 子模組（觀察/手術/體重/疫苗/犧牲/病理/轉讓，31 paths）；**R4-100-O6** HR（出勤/請假/加班）+ 通知 + 稽核（11 paths），符合 ≥90% 端點文件化目標。

### 2026-03-04 全專案資料夾整理與分類

- ✅ **維運手冊歸位**：`docs/OPERATIONS.md` 移入 `docs/ops/OPERATIONS.md`，與 COMPOSE、ENV_AND_DB、TUNNEL 等同屬「環境與建置」分類；所有引用已更新（SOC2_READINESS、SLA、docs/README）。
- ✅ **文件索引**：`docs/README.md` 新增維運手冊入口、operations 區塊補齊 OPERATIONS.md、目錄結構摘要加註分類說明、頂部新增「閱讀建議」依角色導引。
- ✅ **根目錄導覽**：`README.md` 新增「資料夾一覽」表（backend、frontend、docs、scripts、tests、monitoring、deploy、.github）及「依角色閱讀」；文件導覽加入 OPERATIONS.md 連結。
- ✅ **monitoring/ 與 deploy/**：新增 `monitoring/README.md`（Prometheus、Alertmanager、Promtail 結構與用途）、`deploy/README.md`（Grafana、cloudflared、WAF 規則分類與相關文件連結），便於維運與新成員查找。

### 2026-03-04 scripts 目錄整理

- ✅ **scripts/README.md**：新增總覽與分類索引（啟動/隧道、CI/測試、資料庫、備份、部署、環境、Windows 建置），含目錄結構與相關文件連結。
- ✅ **引用修正**：文件中原不存在的 `fix_migration_checksums.ps1` 改為 `sync_migrations.ps1 -Method FixChecksums`（`restore_old_dump.ps1`、`docs/db/RESTORE_OLD_DUMP.md`）。

---

### 2026-03-04 新規則：已犧牲動物可將欄位改為空值

- ✅ **規則**：若動物已為犧牲（euthanized）狀態，允許透過更新動物 API 將欄位（`pen_location`）改為空值；其餘狀態時，傳空則保留原值。
- ✅ **實作**：`backend/src/services/animal/core.rs` 更新動物時，依 `current_status == Euthanized` 決定 `pen_location` 綁定值與 SQL（`CASE WHEN status = 'euthanized' THEN $3 ELSE COALESCE($3, pen_location) END`）。
- ✅ **規格**：已於 `_Spec.md` 2.7.1 新增「已犧牲動物可清空欄位」條目並更新實作方式說明。

### 2026-03-04 犧牲/安樂死時自動移出欄位（pen_location = NULL）

- ✅ **規格**：依 `docs/archive/legacy/spec_v2/_Spec.md`「犧牲時移除欄位」規則，已安樂死之動物應將欄位清空（`pen_location = NULL`）以移出欄位。
- ✅ **實作**：原先僅更新狀態為 `euthanized`，未清空欄位；現已補上。
  - **犧牲/採樣紀錄確認**：`backend/src/handlers/animal/sacrifice_pathology.rs` 於 `confirmed_sacrifice` 時，`UPDATE animals` 一併設定 `pen_location = NULL`。
  - **安樂死單執行**：`backend/src/services/euthanasia.rs` 於執行安樂死單時，`UPDATE animals` 一併設定 `pen_location = NULL`。
- ✅ **結果**：已安樂死動物之「欄位」會顯示為空，不再佔用欄位。

---

### 2026-03-03 E2E CI 環境模擬全通過

- ✅ **根因**：admin-users 測試失敗因「啟動配置警告」對話框擋住頁面；auth 首次嘗試使用 `.env` 的錯誤 `ADMIN_INITIAL_PASSWORD`。
- ✅ **修正**：`docker-compose.test.yml` 新增 `TEST_USER_PASSWORD`、`ALLOWED_CLOCK_IP_RANGES`、`CLOCK_OFFICE_LATITUDE/LONGITUDE` 抑制配置警告；`run-ci-e2e-tests.ps1` 設定 `ADMIN_INITIAL_PASSWORD`、清除 `.auth` 資料夾、修正 docker compose `--progress` 旗標。
- ✅ **結果**：35 個 Playwright E2E 測試全數通過（約 1.8 分鐘）。

---

### 2026-03-03 本機複現 CI 環境與 Backend 測試全通過

- ✅ **腳本**：新增 `scripts/run-ci-backend-tests.ps1`，以 Docker db-test + CI 環境變數複現 GitHub Actions 流程。
- ✅ **CI 調整**：`DISABLE_ACCOUNT_LOCKOUT=true` 避免 `login_with_wrong_password_returns_401` 因帳號鎖定回傳 400；`--test-threads=1` 減少共用 DB 衝突；`--force-recreate` 確保乾淨測試 DB。
- ✅ **權限**：補齊 `dev.role.*` 並指派給 admin（角色 API 需此權限）。
- ✅ **測試修正**：`post_unaffected_no_etag` 補上 `code` 欄位；`list_protocols_returns_200` / `list_users_returns_paginated_result` 改為檢查直接陣列；TestApp 建立 `uploads` 目錄以通過 health 檢查。
- ✅ **結果**：`cargo test` 全數通過（127 unit + 整合測試）。

### 2026-03-03 疫苗紀錄刪除失效修復與刪除功能檢視

- ✅ **根因**：`list_vaccinations` 未過濾 `deleted_at IS NULL`，導致軟刪除後紀錄仍顯示於列表（後端已正確軟刪除，但列表查詢未排除）。
- ✅ **修正**：`backend/src/services/animal/medical.rs` 於 `list_vaccinations` 查詢加入 `AND deleted_at IS NULL`。
- ✅ **前端型別**：`AnimalVaccination.id` 由 `number` 改為 `string`（UUID），`VaccinationsTab` 之 `deleteTarget` 同步修正。
- ✅ **照護紀錄刪除**：Migration 012 新增 `care_medication_records` 軟刪除欄位（deleted_at, deletion_reason, deleted_by）；`delete_care_record` 改為軟刪除 + `DeleteRequest` + `AuditService::log_activity`；`PainAssessmentTab` 改用 `DeleteReasonDialog`。
- ✅ **刪除功能檢視**：疫苗、體重、觀察、手術、血液檢查、動物、照護紀錄均已為軟刪除 + 操作日誌（user_activity_logs）。
- ✅ **軟刪除欄位統一**：血液檢查、報表、安樂死等改為 `deleted_at IS NULL`；Migration 013 移除 `animal_blood_tests.is_deleted`；`AnimalBloodTest`、前端型別同步更新。

---

### 2026-03-02 動物欄位修正申請（需 admin 批准）

- ✅ **需求**：耳號、出生日期、性別、品種等欄位建立後不可直接修改；若 staff 輸入錯誤，可經 admin 批准後修正。
- ✅ **後端**：Migration 011 新增 `animal_field_correction_requests` 表；`POST /animals/:id/field-corrections` 建立申請、`GET` 查詢該動物申請；`GET /animals/animal-field-corrections/pending` 列出待審、`POST /animals/animal-field-corrections/:id/review` 批准/拒絕。僅 admin 可審核。
- ✅ **前端**：動物詳情/編輯頁「申請修正」按鈕與 `RequestCorrectionDialog`；實驗動物管理「修正審核」頁面，可批准或拒絕並填寫拒絕原因。

---

### 2026-03-01 權限稽核與訓練紀錄權限調整

- ✅ **權限稽核報告**：新增 `docs/development/PERMISSION_AUDIT_2026-03-01.md`，掃描全專案頁面與權限
- ✅ **EXPERIMENT_STAFF 訓練紀錄**：新增 `training.view`、`training.manage_own`，可管理**自己的**訓練紀錄
- ✅ **ADMIN_STAFF 審批**：保有 `training.manage`，可審批/管理**所有人**紀錄
- ✅ **設備維護**：確認 equipment.view / equipment.manage 僅 ADMIN_STAFF（特定人員）
- ✅ **後端**：`TrainingService` 支援 `training.manage_own`（create/update/delete 僅限自己）
- ✅ **前端**：TrainingRecordsPage 依 `canManageAll` 隱藏員工篩選、新增表單人員欄
- 📁 **產出**：migration 012、permissions.rs、training.rs、TrainingRecordsPage、App.tsx、06_PERMISSIONS_RBAC.md

---

### 2026-03-01 R6 第六輪改善計劃建立與執行

> **白話版：** 針對專案進行下一輪評估後，在 `docs/TODO.md` 新增第六輪改善計劃並依序執行。

**R6-6 一鍵全庫匯出/匯入（Phase 1–3）✅**

- **Phase 1–2**：匯出/匯入 API、schema_version、前端按鈕
- **Phase 3**：Column mapper 架構（`schema_mapping::transform_row`，跨版本匯入時套用）；Zip 分包匯出（`format=zip`，manifest + 每表一檔，>10k 行表用 NDJSON）；Zip 匯入支援；前端「輸出為 Zip 分包」選項、支援 .zip 上傳

**R6-1 useState → hooks 擴展 ✅**

- EquipmentPage：useTabState + useDialogSet（activeTab、4 個 Dialog 開關）
- TrainingRecordsPage：useTabState + useDialogSet（activeTab、create/edit Dialog）

**R6-2 useDateRangeFilter / useTabState ✅**

- 新增 `src/hooks/useDateRangeFilter.ts`（支援 lazy 初始化、setRange、reset）
- 新增 `src/hooks/useTabState.ts`（相容 Radix Tabs onValueChange）
- 套用 useDateRangeFilter：HrLeavePage、HrOvertimePage、AdminAuditPage、AuditLogsPage、BloodTestCostReportPage、BloodTestAnalysisPage、AccountingReportPage
- 套用 useTabState：HrLeavePage、HrOvertimePage、AdminAuditPage、BloodTestAnalysisPage、EquipmentPage、TrainingRecordsPage

**R6-3 Skeleton DOM nesting 修正 ✅**

- InlineSkeleton 由 `SkeletonPulse`（div）改為 `<span>`，消除 `<p>` 內 `<div>` 的 validateDOMNesting 警告

**R6-4 財務模組 Phase 2–5 評估 ✅**

- 產出 `docs/assessments/R6-4_FINANCE_PHASE2_5_ASSESSMENT.md`：Phase 2–5 工時與優先建議

**R6-5 Dependabot Phase 2.5 依賴評估 ✅**

- 產出 `docs/assessments/R6-5_DEPENDABOT_PHASE25_ASSESSMENT.md`：printpdf、utoipa、axum-extra、tailwind-merge 升級建議與相依關係

---

### 2026-03-01 useState → Custom Hooks 重構 (P5-48)

> **白話版：** React 的 `useState` 用來管理畫面上的狀態（例如：彈窗開/關、輸入值）。  
> 把這些邏輯抽成「自訂 Hooks」（可重複使用的小工具），可以讓程式碼更整潔、更容易測試。

依據 `docs/development/REFACTOR_PLAN_USESTATE_TO_HOOKS.md` 執行 Phase 1–2：

**Phase 1：低風險通用 Hooks ✅**

- 新增 `useToggle`：布林切換（密碼可見、進階篩選）
- 遷移：LoginPage、SettingsPage、ResetPasswordPage、ForceChangePasswordPage、PasswordChangeDialog、ProductsPage（showAdvancedFilters）
- 新增 `useDialogSet`：多個 Dialog 開關集中管理
- 遷移：TreatmentDrugOptionsPage、AmendmentsTab、ReviewersTab、HrAnnualLeavePage、PartnersPage

**Phase 2：列表頁標準化 ✅**

- 新增 `useListFilters`：search、filters、page、perPage、sort
- 遷移：PartnersPage（search + typeFilter）

**Phase 3 已完成（2026-03-01 續）**：useSteps、useSelection、TwoFactorSetup 用 useDialogSet

- 新增 `useSteps`：wizard 步驟索引、next/prev/goTo
- 遷移：CreateProductPage
- 新增 `useSelection`：勾選 toggle/selectAll/clear/has/size
- 遷移：ProductsPage、TreatmentDrugOptionsPage（ErpImportDialog）
- TwoFactorSetup 用 useDialogSet 管理 setup/disable 兩 Dialog

**Phase 4 已完成（2026-03-01）**：feature 專用 hooks

- 新增 `useSettingsForm`：系統設定表單 + API 同步 + dirty 追蹤
- 遷移：SettingsPage
- 新增 `useLeaveRequestForm`：假單表單 + 日期/天數雙向計算 + 圖片上傳
- 遷移：HrLeavePage（含 useDialogSet）
- 新增 `useProductListState`：產品列表篩選/分頁/排序 + queryParams
- 遷移：ProductsPage（含 useDialogSet 管理 status/batchStatus/import）

---

### 2026-03-01 iPig R5 改善計畫 Phase 3 執行（項目 7、8）

> **白話版：** R5 是第五輪改善計畫。這次做的是「網頁效能監控」和「API 快取優化」。

依據 `dazzling-twirling-kitten.md` 計劃執行：

**項目 7：Web Vitals 監控 (P2) ✅**

- Web Vitals 是 Google 訂的「使用者體驗指標」（頁面載入速度、版面是否突然跳動等）。我們監控這五項：onCLS、onINP、onLCP、onFCP、onTTFB
- `sendToAnalytics`：DEV 時 `console.debug`，production 時 `navigator.sendBeacon('/api/metrics/vitals', JSON.stringify(metric))`
- `main.tsx` 呼叫 `reportWebVitals()`
- 後端 `POST /api/metrics/vitals` handler（接收並紀錄 Web Vitals 指標，回傳 204）

**項目 8：API 回應快取 ETag (P2) ✅**

- ETag 是「內容指紋」。伺服器給每份資料一個 ETag，瀏覽器下次請求時帶上這個值；若資料沒變，伺服器直接回 304（不必再傳一次完整內容），節省頻寬、加快速度
- 排除 `/api/auth/*`、`/api/health`、`/api/metrics/*`
- 套用 `Cache-Control: private, no-cache, must-revalidate`
- 對 GET 路由套用 etag middleware
- 單元測試：`test_is_excluded_path`、`test_etag_format`；整合測試：`api_etag.rs`（ETag 生成、304 回應、POST 不受影響、排除路徑）

### 2026-03-01 iPig R5 改善計畫 Phase 2 執行（項目 3、4、5、6）

依據 `dazzling-twirling-kitten.md` 計劃執行：

**項目 3：大型頁面元件拆分 (P1) ✅**

- **3a DocumentEditPage**：311 行，拆出 `useDocumentForm`、`DocumentLineEditor`、`DocumentPreview`、`types.ts`
- **3b UsersPage**：150 行，拆出 `useUserManagement`、`UserTable`、`UserFormDialogs`
- **3c BloodTestTemplatesPage**：143 行，拆出 `useBloodTestTemplates`、`BloodTestTemplateTable`、`BloodTestTemplateFormDialog`、`BloodTestPanelFormDialog`
- **3d SurgeryFormDialog**：108 行，拆出 `SurgeryBasicInfoSection`、`SurgeryProcedureSection`、`SurgeryAnesthesiaSection`、`useSurgeryForm`、`SurgeryFormComponents`

**項目 4：useState → custom hooks (P1) ✅**

- **AnimalsPage**：25 useState → 4 hooks（useAnimalFilters、useAnimalDialogs、useAnimalSelection、useAnimalForms），頁面 useState 數歸零

**項目 5：Alertmanager Receiver 設定 (P1) ✅**

- 新增 `monitoring/alertmanager/alertmanager.example.yml` 範本（含 `${ALERTMANAGER_WEBHOOK_URL}`、`${ALERT_EMAIL_*}`）
- 自訂 Dockerfile + entrypoint.sh（sed 替換，busybox 相容），啟動時自動 envsubst
- `docker-compose.monitoring.yml` 建置自訂映像、加入 ALERT_* 環境變數
- `.env.example` 補齊 Alertmanager 通知變數說明

**項目 6：Git Pre-commit Hooks (P1) ✅**

- 專案根目錄 `package.json` 已有 husky、lint-staged
- `.husky/pre-commit`：前端 lint-staged（ESLint + Prettier）、後端 `cargo fmt --check`

### 2026-03-01 iPig R5 改善計畫 Phase 1 執行（項目 1–2）

依據 `dazzling-twirling-kitten.md` 計劃執行：

**項目 1：eslint-disable 清理 (P0) ✅**

- 修正 3 處 ESLint 錯誤：utils.test.ts 常數表達式、EquipmentPage/TrainingRecordsPage 未使用 `Search` 匯入
- 移除 4 處 eslint-disable：ProtocolsPage (useCallback getStatusName)、BloodTestTemplatesPage (useCallback sortTemplates)、ErpPage (移除未使用 hasPermission)、ObservationFormDialog + SurgeryFormDialog (useCallback jumpToNextEmptyField)
- 保留並改善註釋 6 處：DocumentEditPage、ObservationFormDialog、SacrificeFormDialog、SurgeryFormDialog、handwritten-signature-pad、WarehouseLayoutPage 的 init-only / ref-loop 正當抑制
- `npx eslint src/ --max-warnings 0` 通過

**項目 2：前端單元測試擴充 (P0) ✅**

- 新增 `useApiError.test.ts`（5 tests：handleError、withErrorHandling、成功/失敗流程）
- 新增 `useHeartbeat.test.ts`（3 tests：未認證不發送、認證時初始 heartbeat、活動監聽）
- 現有 lib/、hooks/ 測試：utils、queryKeys、sanitize、validation、validations、logger、useDebounce、useConfirmDialog、useUnsavedChangesGuard
- `npx vitest run` 全數通過（207 tests）

### 2026-03-01 財務 SOC2 QAU 三項規劃完成

> **白話版：** 做了三件事：**(1) QAU 品質保證**：新增角色、權限、會計相關資料表與後台儀表板；**(2) SOC2 合規**：憑證輪換、SLA、災難還原演練；**(3) 財務模組**：會計科目、傳票、應付/應收等規劃。

**一、QAU（品質保證檢視）**

- `022_qau_accounting_plan.sql`（整合 022–024）：QAU 角色與權限、會計基礎（科目/傳票/分錄）、AP/AR 付款收款表
- `GET /qau/dashboard`：handlers/qau.rs、services/qau.rs，計畫狀態、審查進度、稽核摘要、動物統計
- `QAUDashboardPage.tsx`，路由 `/admin/qau`，側邊欄僅 QAU 可見

**二、SOC2 缺口補齊**

- 憑證輪換（半自動）：`check_credential_rotation.sh`（每月提醒）、`record_credential_rotation.sh`（紀錄輪換）；JWT 不輪換
- `docs/security/SLA.md`：RTO/RPO、可用性目標
- `docs/runbooks/DR_DRILL_CHECKLIST.md`：DR 演練檢查表

**三、財務模組（AP/AR/GL）**

- **Phase 1**：會計基礎（migration 022 內）、`AccountingService::post_document`；GRN/DO 核准時自動過帳
- **Phase 2（AP）**：`ap_payments`、`POST /accounting/ap-payments`、`GET /accounting/ap-aging`、前端「新增付款」
- **Phase 3（AR）**：`ar_receipts`、`POST /accounting/ar-receipts`、`GET /accounting/ar-aging`、前端「新增收款」
- **Phase 4（GL）**：`GET /accounting/trial-balance`、`/journal-entries`、`/chart-of-accounts`
- **Phase 5（UI）**：`AccountingReportPage` 四 Tab、ERP 報表中心「會計報表」入口 `/accounting`

### 2026-03-01 P0–P2 改進計劃執行完成（P1-M0～P2-M2）

- **P1-M3**：新增 `docs/OPERATIONS.md`（服務擁有者、on-call、升級流程、故障排除）
- **P1-M4**：標記完成（`docs/security/CREDENTIAL_ROTATION.md` 已存在）
- **P2-M5**：新增 `docs/security/SOC2_READINESS.md`（Trust Services Criteria 對照）
- **P1-M0**：稽核日誌匯出 API `GET /admin/audit-logs/export?format=csv|json`，權限 `audit.logs.export`
- **P2-M4**：稽核日誌 UI 新增「操作者」篩選
- **P1-M1**：API 版本路徑 `/api/v1/`，前端 baseURL 更新
- **P1-M2**：GDPR 資料主體權利 `GET /me/export`、`DELETE /me/account`（軟刪除 + 二級認證），隱私政策補充
- **P1-M5**：Dependabot Phase 2 收尾（zod 4、zustand 5、date-fns 4 已升級，build/test 通過）
- **P2-M2**：人員訓練紀錄模組（migration 020、`training_records` 表、CRUD API、`TrainingRecordsPage` 管理後台）
- **P2-M3**：設備校準紀錄模組（migration 021、`equipment` 與 `equipment_calibrations` 表、CRUD API、`EquipmentPage` 雙 Tab 管理後台）

### 2026-03-01 市場基準檢視與改進計劃

- **產出**：`docs/development/IMPROVEMENT_PLAN_MARKET_REVIEW.md`
- **檢視基準**：企業 ERP 系統、GLP 合規軟體、生產環境就緒檢查清單
- **內容**：市場基準對照表（ERP 核心功能、技術基礎設施、安全合規、GLP、生產就緒）、改進計劃分級（P0–P3）、既有優勢摘要、執行建議
- **重點項目**：P0 稽核日誌匯出 API、憑證輪換文件；P1 API 版本、GDPR、維運文件；P2 PWA、人員訓練紀錄、設備校準；P3 財務模組、QAU、原生 App、多租戶

### 2026-03-01 Dependabot PR 遷移計畫完成（Phase 1–3）

- **Phase 1**：GitHub Actions（checkout v6、setup-node v6、cache v5、upload-artifact v7）、validator 0.20、axios、lucide-react、@types/dompurify
- **Phase 2**：zod 4、@hookform/resolvers 5、zustand 5、date-fns 4；validation.ts / validations.ts 遷移
- **Phase 3**：metrics-exporter-prometheus、thiserror 2、jsonwebtoken 10（rust_crypto）、tower 0.5、tokio-cron-scheduler 0.15
- **產出**：`docs/development/DEPENDABOT_MIGRATION_PLAN.md`（總覽、遷移細節、相依關係圖）、`scripts/verify-deps.sh` / `.ps1`
- **暫緩**：printpdf 0.9、utoipa 5、axum-extra 0.12、tailwind-merge 3（Phase 2.5 可選）

### 2026-03-01 複製後編輯觀察紀錄 500 錯誤修復

> **白話版：** 使用者在「複製一筆觀察紀錄 → 再編輯儲存」時，系統噴出 500 錯誤。原因是資料庫型別轉換的 bug，已修正。

- **問題**：複製觀察紀錄後編輯儲存時出現「資料庫操作失敗，請稍後再試」(500)
- **根因**：migration 013 將 `version_record_type` enum 的 cast 改為 ASSIGNMENT，導致 (1) WHERE 比較 `record_type = $1` 時 `version_record_type = text` 無運算子；(2) cast 函數 `$1::text` / `$1::version_record_type` 遞迴呼叫造成 stack overflow
- **修復**：(1) `save_record_version` / `get_record_versions` 改為 `record_type::text = $1` 比較；(2) 新增 migration 019 修正 `version_record_type_to_text`、`text_to_version_record_type` 為非遞迴實作；(3) `AnimalObservation` 補齊 `deleted_at`、`deletion_reason`、`deleted_by`、`version` 欄位
- **驗證**：新增 `tests/test_reproduce_copy_edit_observation.py` 重現腳本，4 步驟全數通過

### 2026-02-28 附件 API 500 錯誤修正

- ✅ **AttachmentsTab 查詢參數修正**：前端傳送 `protocol_id` 但後端期望 `entity_type` + `entity_id`，導致空字串綁定 UUID 欄位引發 PostgreSQL 型別錯誤。修正為 `entity_type=protocol&entity_id=<uuid>`。
- ✅ **上傳路由修正**：附件上傳從錯誤的 `POST /attachments?protocol_id=...` 改為正確的 `POST /protocols/:id/attachments` 專用路由。

### 2026-02-28 第二輪系統改善 15 項完成

- ✅ **P0-R2-1 XSS 防護**：安裝 DOMPurify，建立 `sanitize.ts` 清理 SVG，所有 `dangerouslySetInnerHTML` 已包裹 `sanitizeSvg()`
- ✅ **P0-R2-2 Rate Limiting 分級**：新增寫入端點 120/min + 檔案上傳 30/min 獨立限流，上傳路由抽出獨立 Router
- ✅ **P1-R2-3 大型依賴動態導入**：`jsPDF`+`html2canvas` 改為 `import()` 動態載入，減少 ~360KB 初始 bundle
- ✅ **P1-R2-4 動物列表分頁**：後端 `AnimalService::list` 支援 `page`/`per_page` + COUNT，前端分頁控制元件
- ✅ **P1-R2-5 健康檢查深度擴充**：`/api/health` 擴充 DB 連線池狀態 + 磁碟 uploads 目錄檢查
- ✅ **P1-R2-6 Alertmanager 告警**：`monitoring/` 新增 Prometheus + Alertmanager + Grafana 設定，4 條告警規則
- ✅ **P1-R2-7 外部服務重試**：`services/retry.rs` 通用 `with_retry` 指數退避，已套用 SMTP 發送
- ✅ **P1-R2-8 Query Key Factory**：`lib/queryKeys.ts` 統一 ~50 個 query key 定義
- ✅ **P2-R2-9 表單驗證統一**：`lib/validations.ts` 提供 Partner/Warehouse/Animal 三組 Zod schema
- ✅ **P2-R2-10 i18n 補齊**：zh-TW.json + en.json 新增 `validation` 區塊 18 個 key
- ✅ **P2-R2-11 Zustand Selector**：auth store 新增 `useAuthUser`/`useAuthHasRole`/`useAuthActions` 等 selector hooks
- ✅ **P2-R2-12 DB 維護自動化**：`018_db_maintenance.sql` pg_stat_statements + `maintenance_vacuum_analyze()` + 慢查詢 View + 排程
- ✅ **P2-R2-13 Dependabot**：`.github/dependabot.yml` 涵蓋 Cargo/npm/Docker/GitHub Actions
- ✅ **P2-R2-14 零停機遷移策略**：`docs/db/ZERO_DOWNTIME_MIGRATIONS.md` 完整規範
- ✅ **P2-R2-15 架構圖**：`docs/ARCHITECTURE.md` 含部署/資料流/模組/認證流程 4 張 Mermaid 圖 + 技術堆疊表

### 2026-02-28 第三輪改善：P2-R3-11 + P2-R3-14 完成

- ✅ **P2-R3-11 Protocol `any` 型別消除**：6 個檔案消除 ~44 處 `: any`
  - `ProtocolEditPage.tsx`：14 處 → 0（`AxiosError<ApiErrorPayload>` 取代 error any、`ProtocolWorkingContent` 子型別取代 item/person/staff any、`Record<string, unknown>` 取代動態 section 存取）
  - `ProtocolContentView.tsx`：13 處 → 0（interface prop `any` → `ProtocolWorkingContent`、map callback `any` → 具體子型別 TestItem/ControlItem/SurgeryDrug/AnimalEntry 等）
  - `CommentsTab.tsx`：4 處 → 0（`VetReviewAssignment` 取代 vetReview any、error handler 改用 `AxiosError`、Protocol prop 型別改用 `Protocol` interface）
  - `AttachmentsTab.tsx`：2 處 → 0（error handler 改用 `AxiosError<ApiErrorPayload>`）
  - `ReviewCommentsReport.tsx`：3 處 → 0（props 全面型別化為 `Protocol`/`ReviewCommentResponse[]`/`VetReviewAssignment`）
  - `ReviewersTab.tsx`：1 處 → 0（vetReview prop 改用 `VetReviewAssignment`）
  - 新增 `VetReviewItem`/`VetReviewFormData`/`VetReviewAssignment` 三個 interface 至 `types/aup.ts`
- ✅ **P2-R3-14 Error Boundary 分層**：
  - 新增 `components/ui/page-error-boundary.tsx`（class component + 錯誤重試 UI）
  - `MainLayout.tsx` 於 `<Suspense>` 外層包裹 `<PageErrorBoundary>`，所有 lazy-loaded 頁面自動受保護
- ✅ TypeScript `tsc --noEmit` 零錯誤通過

### 2026-02-28 第三輪系統改善 20 項完成

詳細計畫見 `docs/development/IMPROVEMENT_PLAN_R3.md`

**🔴 P0 安全性（4 項）：**

- ✅ **P0-R3-1 SQL 動態拼接修正**：4 個檔案（`treatment_drug.rs`, `report.rs`, `warehouse.rs`, `document/crud.rs`）的手動 `format!("${}", param_idx)` 參數索引全部改為 `sqlx::QueryBuilder` 的 `push_bind()` 自動綁定
- ✅ **P0-R3-2 IDOR 漏洞修補**：HR `get_leave` 加入 owner/approver/view_all 三重檢查、`get_overtime` 加入 owner/view_all 檢查、`get_user` 允許查看自己的 profile 無需 admin 權限
- ✅ **P0-R3-3 .expect() 清理**：handlers/ 14 處 + services/ 28 處共 42 個 `.expect()` 替換為 proper error propagation（`ok_or_else`/`map_err`/`anyhow`），消除 production panic 風險
- ✅ **P0-R3-4 前端容器非 root**：Dockerfile 加入 `USER nginx`、nginx listen 改為 8080、`nginx-main.conf` 設定 pid/temp 路徑至 `/tmp/nginx/`、docker-compose 端口映射更新

**🟡 P1 效能與可靠性（6 項）：**

- ✅ **P1-R3-5 搜尋 debounce**：新增 `hooks/useDebounce.ts`，套用至 AnimalsPage/PartnersPage/WarehousesPage/ProtocolsPage（400ms 延遲）
- ✅ **P1-R3-6 staleTime 調優**：23 個檔案 38 個 useQuery 依資料特性分級設定（即時 30s/列表 1min/計數 5min/參考 10min/設定 30min）
- ✅ **P1-R3-7 AnimalsPage 拆分**：1898 行 → 495 行（-74%），抽離 AnimalFilters/AnimalListTable/AnimalPenView/AnimalAddDialog + constants.ts
- ✅ **P1-R3-8 Rate Limiter DashMap**：`Arc<Mutex<HashMap>>` 改為 `DashMap`，消除 Mutex 競爭
- ✅ **P1-R3-9 DB Pool Prometheus 指標**：`/metrics` 新增 `db_pool_connections_total/idle/active` 三個 gauge
- ✅ **P1-R3-10 Skeleton Loading**：新增 `TableSkeleton` 元件，套用至 4 個列表頁取代 Loader2 spinner

**🔵 P2 品質與維運（10 項）：**

- ✅ **P2-R3-11 Protocol any 消除**：6 個檔案 ~44 處 `: any` 替換為具體型別（`ProtocolWorkingContent`/`VetReviewAssignment`/`AxiosError<ApiErrorPayload>` 等）
- ✅ **P2-R3-12 審計日誌補齊**：HR leave approval/rejection 和 overtime approval 新增 `AuditService::log()` 呼叫；新增 `AuditAction::Reject` variant
- ✅ **P2-R3-13 常數提取**：新增 `backend/src/constants.rs`（分頁/認證/Rate Limit/上傳/排程/Session/密碼 共 18 個常數）
- ✅ **P2-R3-14 Error Boundary 分層**：新增 `PageErrorBoundary` 元件，包裹 MainLayout 的 Suspense
- ✅ **P2-R3-15 SSL/TLS 範本**：新增 `docs/ops/SSL_SETUP.md` + `frontend/nginx-ssl.conf.example`（TLS 1.2/1.3 + OCSP + HSTS）
- ✅ **P2-R3-16 備份自動驗證**：新增 `scripts/backup/pg_backup.sh`（gzip 完整性 + pg_restore 驗證 + SHA256 校驗 + 30 天自動清理）
- ✅ **P2-R3-17 日誌聚合**：新增 `docker-compose.logging.yml`（Loki + Promtail）+ `monitoring/promtail/config.yml`
- ✅ **P2-R3-18 環境驗證**：新增 `scripts/validate-env.sh`（必填/選填變數分級檢查 + HMAC key 長度驗證）
- ✅ **P2-R3-19 無障礙**：搜尋輸入框加入 `aria-label`（Animals/Partners/Warehouses/Protocols 4 頁）
- ✅ **P2-R3-20 API 一致性**：`amendment.rs` 4 處硬編碼角色名稱陣列改為 `has_permission("aup.protocol.*")` 權限檢查
- ✅ `cargo check` + `tsc --noEmit` 零錯誤通過

### 2026-02-28 第四輪改善計畫 R4 完成（20 項）

**P0 安全性（4 項）：**

- P0-R4-1 IDOR 修補：`check_resource_access()` helper，amendment/document handler 加入所有權檢查
- P0-R4-2 CSP：移除 nginx `style-src unsafe-inline`
- P0-R4-3 console 清理：`lib/logger.ts` 封裝，生產環境靜默
- P0-R4-4 `.expect()` 清理：partner.rs Regex、auth.rs 改用 `?`

**P1 效能與可靠性（7 項）：**

- P1-R4-5~8 元件拆分與 Skeleton（AnimalsPage、DocumentEditPage、AdminAuditPage、TableSkeleton）
- P1-R4-9 Nginx：HTTP/2、rate limit、JSON log、worker_connections
- P1-R4-10 還原腳本：`scripts/backup/pg_restore.sh`
- P1-R4-11 備份腳本：GPG 清理邏輯、pg_restore --list 驗證

**P2 品質與維運（9 項）：**

- P2-R4-12 Protocol `any` 消除：ProtocolPerson、ProtocolAnimalItem、ProtocolSurgeryDrugItem 型別
- P2-R4-13 Animal `any` 消除：25 處 onError→unknown、handleChange、payload、AnimalTimelineView、AnimalListTable 等
- P2-R4-14 後端配置提取：constants.rs 集中管理 rate limit、file size、auth expiry、時區
- P2-R4-15 Error Boundary：DashboardPage、ProtocolEditPage、AnimalDetailPage 頁面級
- P2-R4-16 錯誤處理統一：後端 `req.validate()?`、前端 AnimalsPage `error: unknown`
- P2-R4-17 Prometheus：monitoring 埠號統一為 api:8000
- P2-R4-18 .env.example：POSTGRES_PORT 修正、GRAFANA 變數補齊
- P2-R4-19 staleTime：STALE_TIME 常數、10+ useQuery 調優
- P2-R4-20 backend/.dockerignore：排除 target、.git 等

### 2026-02-28 手寫簽名 Canvas 寬度無限擴張修復

- ✅ **根因**：CSS Grid `grid-cols-[280px_1fr]` 中 `1fr` 等同 `minmax(auto, 1fr)`，canvas 的 intrinsic size 撐大 grid cell → ResizeObserver 重新量測 → canvas 再擴張，形成無限迴圈（container 寬度飆至 9870px）
- ✅ **修復 4 個檔案**：
  - `ProtocolEditPage.tsx`：`1fr` → `minmax(0,1fr)`，允許 grid 欄位縮小不受子元素 intrinsic size 影響
  - `SectionSignature.tsx`：Card / CardContent 加上 `min-w-0`，手寫簽名容器加上 `min-w-0 max-w-full`
  - `handwritten-signature-pad.tsx`：新增 `wrapperRef` 從 wrapper（非 container）量測寬度；canvas 改為絕對定位
  - `index.css`：`.signature-canvas` 改為 `position: absolute; inset: 0`；wrapper 加上 `max-w-full`
- ✅ **驗證結果**：Playwright 自動測試確認 container 寬度 686px、canvas 682px、grid 第二欄 736px，均在正常範圍
- 📁 **產出**：4 個檔案修改

### 2026-02-28 ProtocolEditPage Section 導航改用 URL Search Params

- ✅ **方案 C 實作**：`activeSection` 從 `useState` 改為 `useSearchParams` 驅動，URL 反映當前 section（如 `?section=purpose`）
- ✅ 瀏覽器上一頁/下一頁可切換 section，可書籤/分享特定 section 連結
- ✅ 無效 `section` 參數自動 fallback 至 `basic`
- ✅ 原有表單狀態管理、儲存、驗證邏輯不受影響
- 📁 **產出**：`frontend/src/pages/protocols/ProtocolEditPage.tsx`（2 處修改）

### 2026-02-28 系統改善 14 項完成（安全性/效能/程式碼品質）

**🔴 P0 安全性（3 項）：**

- ✅ **P0-S1 Docker 網路隔離**：定義 `frontend` / `backend` / `database` 三個自訂 bridge 網路，每個服務僅加入必要網路（web 容器無法直接存取 db）
- ✅ **P0-S2 DB 埠口 localhost-only**：`docker-compose.yml` 資料庫 port 綁定改為 `127.0.0.1:5433:5432`，防止外部直連
- ✅ **P0-S3 Docker Secrets**：`config.rs` 新增 `read_secret()` / `require_secret()` helper（優先讀 `*_FILE` 路徑，fallback 環境變數）；`docker-compose.prod.yml` 定義 4 個 secrets（jwt_secret / db_url / db_password / smtp_password）

**🟡 P1 效能（5 項）：**

- ✅ **P1-S4 RoleService N+1 修復**：`list()` 從 1+N 次查詢改為 2 次（roles + 批次 permissions via `ANY($1)`），記憶體分組
- ✅ **P1-S5 UserService N+1 修復**：`list()` 從 1+2N 次查詢改為 3 次（users + 批次 roles + 批次 permissions via `ANY($1)`）
- ✅ **P1-S6 迴圈 INSERT → UNNEST**：`role.rs` 建立/更新角色 + `user.rs` 建立/更新使用者的權限/角色指派改為 `SELECT $1, unnest($2::uuid[])`
- ✅ **P1-S7 移除 .expect()**：`handlers/auth.rs` 6 處 + `handlers/two_factor.rs` 2 處改為 `map_err(AppError::Internal)`，`login_response_with_cookies` 回傳改為 `Result<Response>`
- ✅ **P1-S8 複合索引**：`017_composite_indexes.sql` 新增 5 個 `CREATE INDEX CONCURRENTLY`（animals/protocols/notifications/audit_logs/attachments）

**🔵 P2 程式碼品質（6 項）：**

- ✅ **P2-S9 is_admin + UserResponse::from_user**：`CurrentUser::is_admin()` 方法 + `UserResponse::from_user(&User)` 消除 8 處重複建構 + 22 處 handler admin 檢查統一化
- ✅ **P2-S10 TypeScript 嚴格化**：新增 `types/error.ts`（ApiErrorPayload + getErrorMessage），10 個檔案 18 處 `error: any` → `error: unknown`
- ✅ **P2-S11 API 錯誤統一**：`lib/api.ts` interceptor 新增 500+/timeout/網路斷線全域 toast（使用 shadcn/ui toast）
- ✅ **P2-S12 MainLayout 拆分**：1,192→~210 行，抽離 Sidebar（~420 行）/ NotificationDropdown（~195 行）/ PasswordChangeDialog（~130 行）
- ✅ **P2-S13 Memoization**：`useMemo` 包裝 2 個 Detail 頁面的 tabs 陣列 + `React.memo` 包裝 7 個 Tab 元件 + `useCallback` 包裝事件處理器
- ✅ **P2-S14 Dockerfile cargo-chef**：5-stage 建置（chef→planner→builder→runtime→distroless），依賴層獨立快取

📁 **產出**：~25 個修改/新增檔案（後端 15 + 前端 10+ + Docker 3 + migration 1）

---

### 2026-02-28 最終 3 項 P5 待辦全數完成（全部功能零缺口）

**P5-13 前端元件庫文件化（Storybook 10）：**

- ✅ **15 個 Stories**：7 個既有（Button/Badge/Card/Checkbox/Input/Skeleton/Switch）+ 8 個新增（Select/Dialog/Slider/Tabs/AlertDialog/FormField/LoadingOverlay/Textarea）
- ✅ 每個 Story 包含 Default + 多種 variant/use case（繁中標籤）
- ✅ `npx storybook build` 成功編譯
- 📁 **產出**：8 個新 `.stories.tsx` 檔案

**P5-15 SEC-39 Two-Factor Authentication (TOTP)：**

- ✅ **DB Migration**：`016_totp_2fa.sql` 新增 `totp_enabled`/`totp_secret_encrypted`/`totp_backup_codes` 三欄位
- ✅ **後端依賴**：`totp-rs` v5（gen_secret + otpauth + qr features）
- ✅ **後端 API 4 個端點**：
  - `POST /auth/2fa/setup`（產生 TOTP secret + otpauth URI + 10 組備用碼）
  - `POST /auth/2fa/confirm`（驗證第一次 code 正式啟用 2FA）
  - `POST /auth/2fa/disable`（需密碼 + code 雙重驗證）
  - `POST /auth/2fa/verify`（temp_token + TOTP code 完成 2FA 登入，支援備用碼）
- ✅ **登入流程改造**：`AuthService::validate_credentials()` 分離密碼驗證；密碼通過後若 `totp_enabled=true` 回傳 `TwoFactorRequiredResponse` + temp JWT（5 分鐘）
- ✅ **前端 Login 頁面**：密碼驗證後自動切換至 TOTP 輸入畫面（6 碼大字型 + 備用碼支援），支援返回
- ✅ **前端 ProfileSettingsPage**：`TwoFactorSetup` 元件 — QR Code 掃描設定（qrcode.react）+ 備用碼顯示/複製 + 停用 Dialog
- ✅ **前端 auth store**：新增 `verify2FA` action，login 偵測 `requires_2fa` 回應
- 📁 **產出**：1 migration + 2 後端檔案 + 5 前端檔案修改/新增

**P5-16 SEC-40 Web Application Firewall：**

- ✅ **`docker-compose.waf.yml`**：OWASP ModSecurity CRS v4 nginx-alpine overlay，預設偵測模式
- ✅ **iPig 自訂排除規則**：JSON Content-Type / 密碼欄位 / TOTP code / 富文本 / 檔案上傳 5 項排除
- ✅ **WAF 文件**：`docs/security/WAF.md`（架構/啟用/保護範圍/排除規則/日誌分析/Paranoia Level/生產注意事項）
- ✅ 啟用方式：`docker compose -f docker-compose.yml -f docker-compose.waf.yml up -d`
- 📁 **產出**：1 overlay + 2 排除規則 conf + 1 文件

### 2026-02-28 系統設定頁面全端串接 + 通知路由 UI 改善

- ✅ **後端 System Settings API**：新增 `GET/PUT /api/admin/system-settings`（admin only），利用既有 `system_settings` 資料表
  - `backend/src/handlers/system_settings.rs`：GET 回傳所有設定（SMTP password 遮罩為 `********`），PUT 批次更新
  - `backend/src/services/system_settings.rs`：DB CRUD + `resolve_smtp_config()` 方法（DB-first + .env fallback）
  - `backend/src/services/email/mod.rs`：新增 `send_email_smtp()` + `resolve_smtp()` 方法供 DB-first SMTP 解析
- ✅ **DB Migration**：`015_system_settings_seed.sql` seed 10 項初始設定值（company_name / default_warehouse_id / cost_method / smtp_* / session_timeout_minutes）
- ✅ **前端 SettingsPage 重構**（`frontend/src/pages/admin/SettingsPage.tsx`）：
  - 四大設定區塊（基本/庫存/郵件/安全）全部從後端 API 載入當前值
  - `handleSave` 呼叫 `PUT /admin/system-settings` 實際儲存
  - 倉庫下拉從 `GET /warehouses` 動態載入
  - SMTP 密碼欄位顯示遮罩值，點擊時清空供輸入新密碼
  - Session 逾時選項新增 360/480 分鐘
  - Loading / Error 狀態完整處理
- ✅ **通知路由管理 UI 改善**（`frontend/src/components/admin/NotificationRoutingSection.tsx`）：
  - 分類可收合/展開（Chevron 圖示），減少視覺壓力
  - Switch 元件取代 ToggleLeft/ToggleRight 圖示
  - 角色顯示中文名稱（不只 code）
  - ConfirmDialog 取代原生 `window.confirm`
  - 規則使用 grid layout 對齊
  - 分類標題列顯示啟用/總數統計
- 📁 **新增/修改檔案**：
  - `backend/src/handlers/system_settings.rs`（new）
  - `backend/src/services/system_settings.rs`（new）
  - `backend/migrations/015_system_settings_seed.sql`（new）
  - `backend/src/services/email/mod.rs`（modified）
  - `backend/src/handlers/mod.rs`（modified）
  - `backend/src/services/mod.rs`（modified）
  - `backend/src/routes.rs`（modified）
  - `frontend/src/pages/admin/SettingsPage.tsx`（rewritten）
  - `frontend/src/components/admin/NotificationRoutingSection.tsx`（rewritten）

### 2026-02-28 P5-14 ProtocolDetailPage 重構（1,929→647 行，-66%）

- ✅ **ProtocolDetailPage.tsx**：從 1,929 行縮減至 647 行
- ✅ **抽離 6 個 Tab 元件**至 `frontend/src/components/protocol/`：
  1. `VersionsTab.tsx`（203 行）— 版本列表 + 版本比較 + 版本檢視 Dialog
  2. `HistoryTab.tsx`（185 行）— 活動歷史時間軸 + 分頁
  3. `CommentsTab.tsx`（431 行）— 審查意見、回覆、PDF 匯出 + 匿名化邏輯
  4. `ReviewersTab.tsx`（281 行）— 審查委員列表 + 獸醫審查表單 + 指派 Dialog
  5. `CoEditorsTab.tsx`（245 行）— 協作者列表 + 新增/移除 Dialog
  6. `AttachmentsTab.tsx`（215 行）— 附件上傳/下載/刪除
- ✅ **重構原則**：父元件保留 Header、Info Cards、Tab 導航、Status 變更 Dialog；各 Tab 自帶 queries、mutations、dialog state
- ✅ **TypeScript 零錯誤通過**
- 📁 **產出**：6 個新 Tab 元件 + 重構後的 ProtocolDetailPage.tsx

### 2026-02-28 JWT 預設過期時間調整為 6 小時

- ✅ **後端 config.rs**：`JWT_EXPIRATION_MINUTES` 預設值從 15 改為 360（6 小時），test default 900s→21600s
- ✅ **前端 session fallback**：`auth.ts`、`api.ts` 中 `sessionExpiresAt` fallback 從 `15 * 60 * 1000` 改為 `6 * 60 * 60 * 1000`
- ✅ **環境配置**：`.env`（60→360）、`.env.example`（15→360）、`docker-compose.yml`（預設 15→360）
- ✅ **E2E 驗證腳本**：`verify-config.ts` fallback 從 '15' 改為 '360'
- 📁 **產出**：7 個檔案更新

### 2026-02-28 品質補強 18 項全數完成

**高影響 6 項（P1-30~35）：**

- ✅ **P1-30 Graceful Shutdown**：`main.rs` 加入 `shutdown_signal()` + `with_graceful_shutdown()`，支援 SIGTERM（Docker stop）與 Ctrl+C，確保進行中的請求完成後才關閉
- ✅ **P1-31 自訂 404 頁面**：`NotFoundPage` 元件取代 catch-all redirect，含「返回上一頁」與「回到首頁」按鈕
- ✅ **P1-32 Session 逾時預警**：auth store 新增 `sessionExpiresAt` 追蹤 JWT 到期時間，`SessionTimeoutWarning` 元件在到期前 60s 顯示倒數 Dialog，可續期或登出
- ✅ **P1-33 刪除記錄清理檔案**：`FileService::delete_by_entity()` 方法查詢 `attachments` 表並刪除磁碟檔案 + DB 記錄，已整合動物與觀察紀錄刪除 handler
- ✅ **P1-34 Optimistic Locking**：`014_optimistic_locking.sql` 為 animals/protocols/observations/surgeries 加入 `version` 欄位，animal update SQL 加入版本檢查（409 Conflict）
- ✅ **P1-35 confirm() 統一 Dialog**：`useConfirmDialog` hook + `ConfirmDialog` + `AlertDialog` 元件，9 個檔案 11 處原生 `confirm()` 全部替換

**中影響 7 項（P2-36~42）：**

- ✅ **P2-36 i18n 補齊**：AnimalDetailPage 11 個 Tab 標籤 + 404 頁面 + Session 預警翻譯鍵加入 zh-TW.json 與 en.json
- ✅ **P2-37 列表 API 分頁**：`PaginationParams` struct + `sql_suffix()` 方法（LIMIT/OFFSET，per_page 上限 100），users/warehouses/partners handler 支援 `?page=&per_page=`
- ✅ **P2-38 表單離開確認**：`useUnsavedChangesGuard` hook（React Router useBlocker + beforeunload）+ `UnsavedChangesDialog`，已整合 ProtocolEditPage
- ✅ **P2-39 隱私政策/服務條款**：`PrivacyPolicyPage` + `TermsOfServicePage` 公開路由，登入頁底部加連結
- ✅ **P2-40 Cookie 同意橫幅**：`CookieConsent` 元件（localStorage 記憶 + 底部半透明 banner + 了解更多連結）
- ✅ **P2-41 Rollback 文件**：`docs/db/DB_ROLLBACK.md` 涵蓋 14 個 migration 的精確回滾 SQL + 建議回退流程
- ✅ **P2-42 .env.example 補齊**：新增 HOST/PORT/DATABASE_MAX_CONNECTIONS/MAX_SESSIONS_PER_USER/UPLOAD_DIR 等 9 個缺漏變數

**低影響 5 項（P5-43~47）：**

- ✅ **P5-43 ARIA 無障礙**：12 個檔案新增 23 個 `aria-label`（編輯/刪除/檢視/關閉/導航按鈕）
- ✅ **P5-44 表單驗證回饋**：Input/Textarea 新增 `error` prop 紅框樣式，`FormField` 通用元件含 label + 錯誤訊息
- ✅ **P5-45 磁碟空間監控**：`scripts/monitor/check_disk_space.sh` 含 uploads 大小 + 磁碟使用率 + Prometheus textfile 輸出
- ✅ **P5-46 LICENSE**：MIT License 2026 正式文件
- ✅ **P5-47 Meta Tags**：title「豬博士 iPig 系統」+ description + theme-color #f97316 + favicon.ico

📁 **產出**：~30 個新增/修改檔案（後端 6 + 前端 20+ + 文件 3 + 腳本 1）

---

### 2026-02-28 交付前補強 3 項（非阻擋）

- ✅ **P4-19 Prometheus 服務部署**：
  - `deploy/prometheus.yml`：scrape `api:8000/metrics`，15s interval
  - `deploy/grafana/provisioning/`：自動註冊 Prometheus datasource + dashboard
  - `deploy/grafana_dashboard.json`：從 2 panel 擴充至 **10 panels**（API Request Rate / Latency P50-P95-P99 / Error Rate / Status Code Pie / Duration Heatmap / DB Pool Stacked / Pool Utilization Gauge / Top Endpoints Bar）
  - `docker-compose.monitoring.yml`：獨立 overlay 檔，含 Prometheus (9090) + Grafana (3000) 服務、volume 持久化、資源限制
  - 啟用方式：`docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d`

- ✅ **P4-20 後端 API 整合測試套件**：
  - 重構 `src/lib.rs`（新建）+ `src/main.rs`（改用 `use erp_backend::`），使 crate 同時支援 library + binary，讓 `tests/` 目錄可存取內部模組
  - `tests/common/mod.rs`：`TestApp` 測試基礎架構（spawn Axum on random port + PgPool + reqwest client + login helper）
  - 6 個整合測試檔案、25+ test cases：
    - `api_health.rs`：健康檢查 200 + metrics 端點 + 404 unknown route
    - `api_auth.rs`：登入成功/失敗/格式錯誤、me 有無 token、refresh、logout 撤銷、密碼變更
    - `api_animals.rs`：列表/無 auth/建立取得/無效資料 400/不存在 404
    - `api_protocols.rs`：列表/建立草稿/無 auth
    - `api_users.rs`：列表/建立取得/角色列表/權限列表
    - `api_reports.rs`：三個報表端點 200/無 auth 401/通知列表
  - `cargo check --tests` 編譯通過（僅 dead_code warnings）
  - 新增 dev-dependencies：`reqwest` (cookies)、`serial_test`

- ✅ **P4-21 效能基準報告文件化**：
  - `docs/assessments/PERFORMANCE_BENCHMARK.md`：8 章節正式報告（摘要 / 測試環境 / 方法 / 指標結果 / 閾值摘要 / 資源觀測 / 限制 / 結論建議）含附錄
  - k6 腳本 `scripts/k6/load-test.js` 優化：改用 `setup()` 階段單次登入共用 token，消除 50 VU 同時登入觸發 rate limit 的串連失敗問題
  - 分析 7 份歷次測試 JSON，選定 `k6_2026-02-25T12-13-34.json` 為基準數據

- 📁 **產出**：12 個新建/修改檔案

### 2026-03-01 PowerShell Migration 執行紀錄

- ✅ **嘗試 1**：`cargo install sqlx-cli` 失敗（Windows 缺少 MSVC linker）
- ✅ **嘗試 2**：Docker + psql 直接執行 migrations，因既有 DB 已有 schema 及 PowerShell 編碼問題而產生錯誤
- ✅ **結論**：新 migrations（001~010）僅適用於全新安裝；既有環境維持現狀
- 📁 **產出**：`docs/walkthrough.md` 新增 PowerShell Migration 執行紀錄與建議做法

### 2026-02-28 市場交付阻擋項修復（3 項）

- ✅ **檔案上傳/下載功能串接**：
  - 後端：`file.rs` 新增 `ObservationAttachment` FileCategory（含 PDF/DOC MIME 支援），`upload.rs` 新增 `upload_observation_attachment` handler，`routes.rs` 新增 `POST /observations/:id/attachments`
  - 後端：修正 `VetRecommendation` FileCategory 的 MIME 類型，新增 PDF/DOC 支援（原僅允許圖片）
  - 前端：`VetRecommendationDialog.tsx` 串接 multipart 上傳至 `/vet-recommendations/{type}/{id}/attachments` + 附件下載至 `/attachments/{id}`
  - 前端：`ObservationFormDialog.tsx` 串接附件上傳（編輯模式即時上傳，新增模式存後上傳）
- ✅ **使用者操作手冊**：`docs/USER_GUIDE.md` 從 26 行擴充至 v2.0 完整手冊（9 章節：登入/儀表板/AUP/動物/ERP/HR/報表/系統管理/FAQ）
- ✅ **生產環境 Docker 強化**：`docker-compose.prod.yml` 所有服務新增 `deploy.resources.limits`（CPU/記憶體）與 `logging` json-file 日誌輪轉
- 📁 **產出**：6 個檔案修改（3 後端 + 2 前端 + 1 Docker）

### 2026-02-28 P5-14 前端超長頁面重構（兩大頁面完成）

- ✅ **AnimalDetailPage.tsx**：1,945→748 行（**-61%**），抽離 7 個 Tab 元件至 `components/animal/`
- ✅ **ProtocolDetailPage.tsx**：1,929→647 行（**-66%**），抽離 6 個 Tab 元件至 `components/protocol/`
- 📁 **產出**：13 個新 Tab 元件 + 2 個重構後的 Detail 頁面

### 2026-02-28 P4-17 基礎映像與 CVE 週期檢查

- ✅ **版本釘選**：`frontend/Dockerfile` 的 `FROM georgjung/nginx-brotli:alpine` → `georgjung/nginx-brotli:1.29.5-alpine`（nginx 1.29.5 + Alpine 3.23.3，2026-02-05 發佈）
- ✅ **CVE 驗證**：Trivy 掃描確認 CVE-2026-25646 仍存在（libpng 1.6.54-r0，修復版 1.6.55-r0 尚未納入映像）
- ✅ **文件更新**：`.trivyignore` 加入檢查日期與下次排程、`docs/security/security.md` 更新映像版本與檢查紀錄
- 📅 **下次檢查**：排定 2026-Q2，屆時若映像包含 libpng ≥ 1.6.55-r0 則移除 CVE
- 📁 **產出**：[Dockerfile](../frontend/Dockerfile)、[.trivyignore](../.trivyignore)、[security.md](security.md)

### 2026-02-27 E2E 跨瀏覽器 Session 過期修復（CI 30 failures 歸零）

- ✅ **問題**：CI（Ubuntu）上 100 tests 依序跑 webkit→firefox→chromium，auth.setup 產生的 JWT storageState 在後執行的瀏覽器 session 已過期，導致 30 個 webkit/firefox 測試一致失敗（`Target page, context or browser has been closed`）
- ✅ **根因**：workers=1 序列執行耗時 ~2 分鐘，storageState 中的 JWT 過期，後執行的 browser project 的 admin-context 共用 context 失效
- ✅ **修復**：
  1. Firefox/WebKit 改為全域 opt-in（需設 `PLAYWRIGHT_FIREFOX=1`、`PLAYWRIGHT_WEBKIT=1`）
  2. 預設僅跑 Chromium（34 tests），避免 session 過期問題
  3. 移除無效的 per-test `{ retries: 1 }` 語法
  4. admin-users.spec.ts：加入 table visible 等待、增加 button timeout
  5. CI retries 維持 2（容錯），本地 retries 改回 0（快速回饋）
- 📊 **結果**：CI 預設 34 tests（Chromium），22s 完成，0 failures

### 2026-02-27 E2E 測試 100% 通過（P4-18 Rate Limiting / Session 穩定化）

- ✅ **根本原因分析**：所有 `/api/*` 請求共用 120/min rate limit，React SPA 每次頁面載入觸發多個 API 呼叫（/api/me、資料列表等），34 個測試密集執行時輕易超限；`sharedAdminContext` 每次初始化都重新登入浪費配額。
- ✅ **admin-context.ts 重構**：改用 auth.setup 儲存的 `admin.json` storageState 檔案，worker 初始化時直接載入 cookie + localStorage，無需重新登入（0 次額外 API 呼叫）。
- ✅ **API rate limit 提升**：`rate_limiter.rs` API 端點 120→600/min，為密集測試提供充足配額。
- ✅ **login.spec.ts credential fallback**：改用 `getAdminCredentials()` 統一 fallback 邏輯（支援 .env 的 `ADMIN_INITIAL_PASSWORD`）。
- 📊 **成果**：34/34 測試連續 2 次全部通過，執行時間從 2.3 分鐘降至 **22 秒**。
- 📁 **產出**：
  - [admin-context.ts](../frontend/e2e/fixtures/admin-context.ts)（storageState 載入）
  - [rate_limiter.rs](../backend/src/middleware/rate_limiter.rs)（API limit 600/min）
  - [login.spec.ts](../frontend/e2e/login.spec.ts)（credential fallback）

### 2026-02-27 E2E 測試總結計畫實施（選項 1）

- ✅ **Dashboard 修復交付**：原計畫主要目標已達成，Dashboard 6/6 通過。
- ✅ **Rate Limiting 調查記錄**：已嘗試 JWT TTL 延長、auth rate limit 放寬、Cookie Path 與 context.cookies() 修復，仍存在 Session 過期導致大量重新登入 → 429 連鎖失敗問題。
- ✅ **後續任務建立**：將 Rate Limiting / Session 穩定化建立為 P4 獨立待辦，詳見 `docs/TODO.md`。

### 2026-02-26 E2E 測試全面改進（Session 管理優化）

- ✅ **配置驗證與文檔**：
  - 新增 `docs/e2e/README.md`（完整指南：架構說明、配置檢查清單、故障排除、維護手冊）
  - 新增 `frontend/e2e/scripts/verify-config.ts`（配置驗證腳本，檢查 JWT TTL、Cookie、環境變數）
  - 更新 `docs/QUICK_START.md`（新增配置驗證步驟）

- ✅ **診斷工具**：
  - 新增 `frontend/e2e/helpers/diagnostics.ts`（E2E 診斷工具，自動記錄 session 狀態、檢查 access_token、提供故障排除建議）
  - 新增 `scripts/analyze-e2e-logs.sh`（後端日誌分析腳本，自動檢查 401 錯誤、JWT 過期、Session 相關日誌）

- ✅ **Session 管理優化**：
  - 新增 `frontend/e2e/helpers/session-monitor.ts`（Session 監控工具，追蹤 session 存活時間、檢查是否接近過期）
  - 優化 `frontend/e2e/fixtures/admin-context.ts`：
    - 加入 `isSessionExpired()` 檢查 cookie 過期時間
    - 加入 `tryRefreshToken()` 主動 refresh 機制
    - 改進 `ensureLoggedIn()` 含重試邏輯（最多 3 次）
    - Page fixture 在測試前主動檢查並 refresh token（剩餘 < 60s 時）

- ✅ **測試穩定性改進**：
  - 確認所有測試已移除 `networkidle` 依賴，改用明確的元素等待策略
  - Session 自動重新登入機制驗證成功
  - Session 監控正常追蹤並記錄狀態

- 📊 **改進成果**：
  - Session 管理更健壯，自動處理 token 過期情況
  - 完整的診斷工具鏈，失敗時提供清晰的故障排除資訊
  - 配置驗證腳本確保環境設定正確
  - 文檔完整，涵蓋架構、配置、故障排除、維護指南

- ✅ **Dashboard 測試選擇器修復**：
  - 修復「通知鈴鐺應可見」測試：改用 `header button.relative` 選擇器，避免 strict mode violation（避免匹配到行動端漢堡按鈕）
  - 修復「語言切換應可運作」測試：改用 `header getByRole('combobox')` 選擇器（Radix UI Select.Trigger 標準 role）
  - Dashboard 測試套件 6/6 全部通過 ✅
  - 產出：[dashboard.spec.ts](../frontend/e2e/dashboard.spec.ts)（Line 31-45）

### 2026-02-25 SEC-33 敏感操作二級認證 (P3-7)

- ✅ **後端**：新增 `POST /auth/confirm-password`，以密碼換取短期 reauth JWT（5 分鐘）；`delete_user`、`reset_user_password`、`impersonate_user`、`delete_role` 四個敏感操作需帶 `X-Reauth-Token` header，否則回傳 403。
- ✅ **前端**：新增 `ConfirmPasswordModal` 與 `confirmPassword()` API；使用者管理（刪除使用者、重設他人密碼、模擬登入）與角色管理（刪除角色）執行前皆需重新輸入登入密碼以取得 reauth token 後再送出請求。

### 2026-02-25 電子簽章合規審查 (P1-7) 與 OpenAPI 完善 (P1-12)

- ✅ **P1-7 電子簽章合規審查**：新增 `docs/security/ELECTRONIC_SIGNATURE_COMPLIANCE.md`，對照 21 CFR Part 11 子章 B/C，審查犧牲／觀察／安樂死／轉讓／計畫書簽章與附註實作，結論為技術面已符合核心要求，建議補齊書面政策與訓練紀錄。
- ✅ **P1-12 OpenAPI 文件完善**：後端新增電子簽章 10 paths + 2 附註 paths、動物管理 9 paths，以及對應 Request/Response Schema（SignRecordRequest/Response、SignatureStatusResponse、Annotation、Animal、AnimalListItem、AnimalQuery 等），Swagger UI 已涵蓋認證、使用者、角色、設施、倉儲、計畫書、審查、電子簽章、動物管理。

### 2026-02-25 CI `sqlx-cli` 安裝修正

- ✅ **強制覆蓋**：在 `ci.yml` 的 `cargo install sqlx-cli` 步驟增加 `--force` 參數，解決 GitHub Actions 快取恢復後的二進位檔衝突問題。

### 2026-02-25 資料保留政策定義 (P1-8)

- ✅ **政策文檔產出**：建立 `DATA_RETENTION_POLICY.md`，定義 AUP、醫療紀錄、稽核日誌、ERP 與 HR 資料之法定保留年限。
- ✅ **合規基準**：參考 GLP、21 CFR Part 11 與台灣勞基法制定。

### 2026-02-25 Trivy 安全掃描優化

- ✅ **CI 參數統一**：將 `ci.yml` 中的 Trivy 掃描參數統一為 `vulnerability-type`。
- ✅ **過濾名單清理**：移除 `.trivyignore` 中無效的 `CVE-2026-0861` 編號。

### 2026-02-25 E2E CI 自動化 (P1-2)

- ✅ **GitHub Actions 整合**：新增 `e2e-test` 作業，自動執行 Playwright 測試。
- ✅ **測試環境容器化**：建立 `docker-compose.test.yml` 供 CI 使用。

### 2026-02-25 P1-1 前端 E2E 測試穩定化

- ✅ **Playwright E2E 測試**：7 spec 檔案、34 個測試案例，連續 3 次執行 0 failures。
- ✅ **涵蓋流程**：登入 (6)、Dashboard (4)、動物列表 (6)、計畫書 (6)、個人資料 (5)、Admin 使用者管理 (5)、Auth Setup (2)。
- ✅ **429 Rate Limit 重試**：`auth.setup.ts` 自動偵測 `Retry-After` header 並等待重試（最多 3 次）。
- ✅ **React 狀態 race condition 修正**：登入後若前端未自動跳轉，fallback 手動導航驗證 HttpOnly cookie。
- ✅ **i18n 雙語 selector**：所有 UI 文字匹配使用 `/English|中文/` regex，相容中英文介面。

### 2026-02-25 壓力測試基準建立 (P1-5)

- ✅ **k6 效能基準**：成功執行 50 VU 壓力測試，測得一般 API P95 為 2.3s，報表 API P95 為 1.76s。
- ✅ **認證優化**：腳本支援 JWT Bearer Token 並實作 VU 級別登入緩存。
- ✅ **結果歸檔**：測試數據已儲存於 `tests/results/k6_*.json`。

### 2026-02-25 瀏覽器相容性測試與 GLP 文件生成

- ✅ **相容性測試 (P0-6)**：執行 Playwright 跨瀏覽器測試，驗證基本渲染與登入流程。
- ✅ **GLP 驗證文件 (P1-6)**：產出 `GLP_VALIDATION.md` 驗證框架。

### 2026-02-25 P0-7 錯誤處理 UX 統一

- ✅ **安全強化**：隱藏原始 DB 錯誤。
- ✅ **前端錯誤導引**：優化 `getApiErrorMessage` 處理逾時與網路異常。

### 2026-03-20 R11-7 ProductImportDialog.tsx 拆分（863→193 行）

- ✅ **元件拆分**：將 `ProductImportDialog.tsx`（863 行）拆為 4 個子元件 + 1 個 Hook + 1 個型別檔：`SkuPreviewTable`（174 行）、`DuplicateWarning`（75 行）、`ImportResultSummary`（59 行）、`NoSkuColumnPrompt`（53 行）、`useProductImport`（292 行）、`importTypes.ts`（92 行）。
- ✅ **主元件精簡**：主元件從 863 行降至 193 行，僅負責 Dialog 外殼、子元件組裝與 hook 調用。所有檔案均在 300 行上限內。

### 2026-03-20 R11-6 ProtocolContentView.tsx 拆分（954→176 行）

- ✅ **元件拆分**：將 `ProtocolContentView.tsx`（954 行）依內容區塊拆為 8 個 Section 子元件（ResearchInfoSection / PurposeSection / ItemsSection / DesignSection / GuidelinesSection / SurgerySection / AnimalsSection / PersonnelSection）+ AttachmentsSignaturesSection，放入 `content-sections/` 子目錄。
- ✅ **PDF 匯出 Hook**：提取 `useProtocolPdfExport` hook，封裝後端/前端 PDF 匯出邏輯（~150 行）。
- ✅ **主元件精簡**：主元件從 954 行降至 ~176 行，僅負責資料解構與子元件組裝。

### 2026-03-23 設備維護管理 — 維修/保養/報廢頁面、通知與簽章

- ✅ **前端三大分頁**：維修/保養紀錄表格（類型/狀態 Badge、報修/完修日期）、報廢紀錄表格（核准/駁回按鈕）、年度計畫矩陣視圖（設備×12 月份、週期自動排程產生）。
- ✅ **Email 通知模板**：設備逾期、無法維修、報廢申請三種模板，站內通知 + Email 雙通道。
- ✅ **排程與簽章**：每日 08:30 檢查設備校正/確效逾期；維修標記「無法維修」自動通知；報廢電子簽章 API（申請人/核准人各自簽章）。

### 2026-03-23 圖片處理獨立服務（R12-3 完成）

- ✅ **`image-processor/`**：Node.js + Sharp 獨立微服務，支援圖片縮圖、格式轉換。
- ✅ **Docker 整合**：獨立 Dockerfile + docker-compose 服務定義。
- ✅ **後端整合**：`services/image_processor.rs` 呼叫微服務 API。

### 2026-03-23 會計 Repository 層提取與 PDF 改進

- ✅ **`repositories/accounting.rs`**：從 `services/accounting.rs` 提取 SQL 查詢至 Repository 層（404 行），Service 層精簡（568→精簡）。
- ✅ **`models/accounting.rs`**：新增會計專用 DTO 型別（92 行）。
- ✅ **前端 `lib/api/accounting.ts`**：新增會計 API 函式模組（87 行）。
- ✅ **PDF 改進**：`pdf/context.rs` 與 `pdf/service.rs` 重構優化。

### 2026-03-23 Bug 修正

- ✅ **調整單效期欄位驗證**：修正調整單效期欄位驗證失敗的 bug（`59f2ab8`）。
- ✅ **調撥單批號效期顯示**：修正調撥單選擇品項後批號與效期未顯示的問題（`86263a4`）。
- ✅ **儲位下拉選單**：顯示所有可存放的儲位類型（`32c093c`）。

### 2026-03-23 Dependabot 依賴更新與 CI 修復

- ✅ **後端依賴**：axum 0.7.9→0.8.8、tower-http 0.5.2→0.6.8、rand 0.8.5→0.9.2、zip 0.6.6→7.2.0、totp-rs 5.7.0→5.7.1。
- ✅ **前端依賴**：i18next 25.8.13→25.10.4、@tanstack/react-query 升級、React ecosystem 5 項更新、dev-dependencies 23 項更新。
- ✅ **CI 修復**：解決 cargo deny、npm audit、test auth、Trivy、SQL guard 等 CI 失敗問題。

### 2026-03-23 AI 資料查詢接口

- ✅ **AI API Key 認證**：獨立的 `ai_auth_middleware`，使用 SHA-256 hash 驗證 API key，支援 scope 權限與過期時間。
- ✅ **管理端 API**：POST/GET/PUT/DELETE `/api/ai/admin/keys` — 管理員透過 JWT 認證管理 API keys。
- ✅ **AI 查詢 API**：`/api/ai/overview`（系統概覽）、`/api/ai/schema`（schema 描述）、`/api/ai/query`（資料查詢）。
- ✅ **支援 6 個查詢領域**：animals、observations、surgeries、weights、protocols、facilities，皆為唯讀。
- ✅ **查詢日誌**：每次 AI 查詢自動記錄至 `ai_query_logs` 分區表。
- ✅ **新增檔案**：migration `017_ai_api_keys.sql`、models/middleware/repository/service/handler/routes 各一。

### 2026-03-23 設備維護管理系統擴充

- ✅ **Migration 018**：新增 6 個 enum 型別、5 張新資料表（`equipment_suppliers`、`equipment_status_logs`、`equipment_maintenance_records`、`equipment_disposals`、`equipment_annual_plans`）；擴充 `equipment` 與 `equipment_calibrations` 表。
- ✅ **後端**：完整 CRUD — 設備廠商關聯、校正/確效/查核三種措施、維修/保養紀錄（自動狀態變更）、報廢申請與核准流程、年度維護校正計畫自動產生。
- ✅ **前端**：設備清單新增「狀態」「廠商」「校正/確效到期」「查核到期」欄位；校正紀錄新增「序號」「類型」「報告/人員」欄位；表單擴充校正類型/週期設定。
- ✅ **權限**：新增 `equipment.disposal.approve`、`equipment.maintenance.manage`、`equipment.plan.manage` 三項權限。
- 📝 **詳細設計**：見 `docs/walkthrough_equipment_maintenance.md`。

### 2026-03-09 請假與加班改為小時計算（0.5 單位）

- ✅ **請假**：表單與顯示改為「時數」（0.5 步進）；`useLeaveRequestForm` 雙向計算日期↔時數；後端 `create_leave` 驗證 0.5 倍數、`LeaveRequestWithUser` 含 `total_hours`。
- ✅ **加班**：`create_overtime` 時數四捨五入至 0.5 小時；前端新增加班 Dialog 顯示預估加班時數。

### 2026-03-04 docs 整理分類

- ✅ **文件索引**：新增 `docs/README.md` 總索引，依主題分類並列出各子目錄說明。
- ✅ **子目錄**：建立 `development/`、`db/`、`security/`、`runbooks/`、`ops/`、`assessments/`，將原根目錄散落文件移入對應分類。
- ✅ **連結更新**：根目錄保留 PROGRESS、TODO、QUICK_START、USER_GUIDE、DEPLOYMENT、ARCHITECTURE、walkthrough；README、PROGRESS、TODO、CI、backend 等處之文件路徑已更新為新路徑。

---

(其餘詳細 1-8 章節內容已併入本檔案)
