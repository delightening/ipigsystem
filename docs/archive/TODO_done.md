# TODO 封存 — 已完結輪次（全部 [x]）

> 本檔自 `docs/TODO.md` 於 2026-07-10 封存重整時抽出：**整輪全部完成（0 未完成項）**的輪次移到這裡，保留完整歷史。
> live 待辦清單見 `docs/TODO.md`（只含尚有未完成項的輪次）；逐日變更日誌見 `docs/PROGRESS.md` §9。
> 反向查詢：某輪 detail 在此、狀態摘要在 `docs/TODO.md` 的「待辦統計 → 逐輪歷史台帳」。

---

## 🚨 P0 — 上線前必要 (Production Readiness)

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P0-1 | **CI 自動觸發恢復** | `ci.yml` push/pull_request 觸發恢復，限定 main 分支；加入 `--locked` flag | [x] |
| P0-2 | **SQL 字串拼接殘留修復** | `core.rs:139` 已為參數化查詢；`data_import.rs` 表名/欄名來自白名單 + `debug_assert` 防護 | [x] |

---

## 🟡 P1 — 上線前強烈建議 (Quality & Compliance)

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P1-1 | **前端 E2E 測試 (Playwright)** | 7 spec / 34 tests，含 429 重試 + race condition 修正 | [x] |
| P1-2 | **E2E CI 自動化** | `docker-compose.test.yml` + GitHub Actions 整合（依賴 P1-1） | [x] |
| P1-7 | **電子簽章合規審查** | 21 CFR Part 11 或等效法規合規審查 | [x] |
| P1-8 | **資料保留政策** | 定義各類紀錄的法定保留年限 | [x] |
| P1-12 | **OpenAPI 文件完善 (≥90%)** | 擴展其餘端點的 Schema 與 Path 定義 | [x] |
| P1-30 | **Graceful Shutdown** | `main.rs` 加入 `tokio::signal` + `with_graceful_shutdown()` | [x] |
| P1-31 | **自訂 404 頁面** | `NotFoundPage` 元件取代 catch-all redirect | [x] |
| P1-32 | **Session 逾時預警** | N/A — proactive refresh (80% TTL) + 401 interceptor 已覆蓋；倒數 Dialog 無實際價值 | N/A |
| P1-33 | **刪除記錄時清理檔案** | `FileService::delete_by_entity()`，連帶清理 attachments 表與磁碟檔案 | [x] |
| P1-34 | **Optimistic Locking** | animals/protocols/euthanasia/amendments/users/observations 六表已有 version 欄位 + service 層 409 Conflict 檢查（migration 072） | [x] |
| P1-35 | **原生 confirm() 統一為 Dialog** | `useConfirmDialog` hook + `ConfirmDialog` + `AlertDialog` 元件 | [x] |

---

## 🔴 P2 — 中優先 (品質 / 合規 / UX)

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P2-36 | **i18n 硬編碼中文補齊** | AnimalDetailPage Tab 標籤 + 404/Session 預警翻譯鍵 | [x] |
| P2-37 | **列表 API 分頁** | `PaginationParams` + `sql_suffix()`，users/warehouses/partners 支援分頁 | [x] |
| P2-38 | **表單離開前確認** | `useUnsavedChangesGuard` hook + `UnsavedChangesDialog` 元件 | [x] |
| P2-39 | **隱私政策 / 服務條款頁面** | 靜態頁面，公開路由 `/privacy` `/terms` | [x] |
| P2-40 | **Cookie 同意橫幅** | `CookieConsent` 元件，localStorage 記憶同意狀態 | [x] |
| P2-41 | **DB Migration Rollback 文件** | `DB_ROLLBACK.md` 涵蓋 14 個 migration 的回滾 SQL | [x] |
| P2-42 | **`.env.example` 補齊** | 新增 9 個缺漏環境變數 | [x] |
| P2-43 | **倉庫管理頁面重構** | 拆分組件，補全倉庫 CRUD 與佈局編輯 | [x] |

---

## 🔵 P3 — 低優先 (資安 / 基礎設施)

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P3-1 | **SEC-33：敏感操作二級認證** | 高危操作要求重新輸入密碼確認 | [x] |
| P3-2 | **Gotenberg HTTP Timeout 設定** | `services/gotenberg.rs`：已加 `connect_timeout(5s)` + `timeout(60s)`，避免 Gotenberg 無回應時 async task 永久 hang。2026-04-20 commit `3849f684`（E-2）。 | [x] |

---

## 🟣 P4 — 中期品質提升 (測試 / 文件 / CI)

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P4-1 | **基礎映像與 CVE 週期檢查** | 每季檢查 nginx-brotli tag；2026-02-28 升級 1.29.5-alpine；**2026-05-15 升級 1.31.0-alpine3.23**（新 mainline series；1.29.x 在 1.31 釋出後等於 EOL；含 7 個 nginx core CVE 修補：CVE-2026-42945 critical rewrite RCE / 42946 / 42934 / 42926 / 40460 / 40701 / 27654）；下次 Q3 review | [x] |
| P4-2 | **E2E Rate Limiting / Session 穩定化** | admin-context 改用 storageState；rate limit 120→600/min；34/34 通過 | [x] |
| P4-3 | **Prometheus 服務部署** | `docker-compose.monitoring.yml` + Grafana provisioning（10 panels） | [x] |
| P4-4 | **後端 API 整合測試** | 6 個整合測試檔案 + `TestApp` 測試基礎架構 | [x] |
| P4-5 | **效能基準報告文件化** | `PERFORMANCE_BENCHMARK.md` 正式報告 + k6 腳本優化 | [x] |
| P4-6 | **前端 nginx-brotli 映像重建（Alpine 安全更新）** | `georgjung/nginx-brotli:1.31.0-alpine3.23`（建置 2026-05-23）openssl 3.3.3-r0 及 libpcre2 10.43-r0 已有 Alpine 安全修補（openssl 3.5.6 / libpcre2 10.46）；目前以 `.trivyignore` 暫緩 7 個 CVE（2 CRITICAL + 5 HIGH），截止 2026-07-01。修復方式：自建 `Dockerfile` 加 `RUN apk upgrade --no-cache`，或等待 georgjung 重建後升版 tag（現有 1.31.0 與 1.31.1 為同一 digest，升 tag 無效）。來源：PR #542 Trivy CI 失敗診斷（2026-06-01）。**2026-06-10 完成**：georgjung base 已重建（自帶 pcre2 10.47 / openssl 3.5.6 / libpng 1.6.58 / zlib 1.3.2）+ Dockerfile 加 `apk upgrade libxml2`（2.13.9-r1）→ frontend 12 個 CVE 全修，`.trivyignore` 清空 frontend 條目。 | [x] |

---

## ⚪ P5 — 長期演進

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P5-1 | **前端元件庫文件化** | Storybook 10 建置，15 個 Stories | [x] |
| P5-2 | **前端超長頁面重構** | AnimalDetailPage -61%、ProtocolDetailPage -66%，各抽離 6-7 個 Tab 元件 | [x] |
| P5-3 | **SEC-39：Two-Factor Authentication** | TOTP 2FA 全端實作（totp-rs + QR Code + 備用碼） | [x] |
| P5-4 | **SEC-40：Web Application Firewall** | WAF 改由 Cloudflare WAF 處理，已移除 ModSecurity overlay | [x] |
| P5-5 | **ARIA 無障礙標籤** | 12 個檔案新增 23 個 `aria-label` | [x] |
| P5-6 | **表單即時驗證回饋** | `FormField` 通用元件含 label + 錯誤訊息 | [x] |
| P5-7 | **磁碟空間監控告警** | `check_disk_space.sh` + Prometheus textfile 輸出 | [x] |
| P5-8 | **LICENSE 檔案** | MIT License，2026 iPig System Contributors | [x] |
| P5-9 | **index.html Meta Tags** | title + description + theme-color + favicon | [x] |
| P5-10 | **useState → Custom Hooks 重構規劃** | Phase 1–2 完成：useToggle / useDialogSet / useListFilters | [x] |

---

## 🔴 P2-R3 — 第三輪改善（品質與維運）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P2-R3-11 | **Protocol `any` 型別消除** | 6 個檔案消除 ~44 處 `: any`，改用具體介面 | [x] |
| P2-R3-14 | **Error Boundary 分層** | 新增 `PageErrorBoundary` 元件，捕捉 lazy-loaded 頁面錯誤 | [x] |

---

## 🟢 P0–P2 改進計劃（市場基準檢視，2026-03-01）

> 依據 `docs/IMPROVEMENT_PLAN_MARKET_REVIEW.md` 完成項目。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| P1-M0 | **稽核日誌匯出 API** | `GET /admin/audit-logs/export?format=csv\|json`，權限 `audit.logs.export` | [x] |
| P1-M1 | **API 版本路徑** | `/api/v1/` 前綴，前端 baseURL 更新 | [x] |
| P1-M2 | **GDPR 資料主體權利** | `GET /me/export`、`DELETE /me/account`，隱私政策補充 | [x] |
| P1-M3 | **維運文件 OPERATIONS.md** | 服務擁有者、on-call、升級流程、故障排除 | [x] |
| P1-M4 | **憑證輪換文件** | `docs/security/CREDENTIAL_ROTATION.md` 已存在 | [x] |
| P1-M5 | **Dependabot Phase 2 收尾** | zod 4、zustand 5、date-fns 4 已升級 | [x] |
| P2-M2 | **人員訓練紀錄模組** | migration 010 內含 training_records 表、CRUD API、TrainingRecordsPage | [x] |
| P2-M3 | **設備校準紀錄模組** | migration 021、equipment + equipment_calibrations、EquipmentPage | [x] |
| P2-M4 | **稽核日誌 UI 使用者篩選** | AuditLogsPage 新增「操作者」篩選 | [x] |
| P2-M5 | **SOC2_READINESS.md** | Trust Services Criteria 對照文件 | [x] |

---

## 🟣 R4-100 — 邁向 100% 目標（依據 IMPROVEMENT_PLAN_R4 §7）

> 詳見 [IMPROVEMENT_PLAN_R4.md](archive/improvement-plans/IMPROVEMENT_PLAN_R4.md) §7。兩軌可並行。

### 7.1 核心業務邏輯覆蓋率 100%

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R4-100-T1 | **product service 單元測試** | ProductService 核心邏輯 + 5–8 個測試 | [x] |
| R4-100-T2 | **partner service 單元測試** | PartnerService 核心邏輯 + 5–8 個測試 | [x] |
| R4-100-T3 | **user/role service 單元測試** | UserService、RoleService 可提取邏輯 + 測試 | [x] |
| R4-100-T4 | **animal 核心 services 單元測試** | animal/core, observation, medical 等 | [x] |
| R4-100-T5 | **protocol/document/hr services 單元測試** | 分批補齊 protocol/*, document/*, hr/* | [x] |
| R4-100-T6 | **cargo-tarpaulin 覆蓋率量測** | CI 中量測行覆蓋率並設門檻 | [x] |

### 7.2 API 文件（OpenAPI）100% 端點文件化

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R4-100-O1 | **products handler OpenAPI** | CRUD + import + with-sku 全端點 | [x] |
| R4-100-O2 | **partners handler OpenAPI** | CRUD + import + generate-code 全端點 | [x] |
| R4-100-O3 | **documents/storage_location OpenAPI** | documents CRUD + submit/approve/cancel | [x] |
| R4-100-O4 | **SKU handler OpenAPI** | categories, subcategories, generate, validate, preview | [x] |
| R4-100-O5 | **animal 子模組 handler OpenAPI** | observation, surgery, weight, vaccination 等 | [x] |
| R4-100-O6 | **HR/notifications/admin handler OpenAPI** | leave, overtime, attendance, notifications, audit | [x] |
| R4-100-O7 | **reports/accounting/treatment_drugs 等 OpenAPI** | 其餘端點補齊 | [x] |

---

## 🟠 R6 — 第六輪改善計劃（2026-03）

> 依據 `docs/PROGRESS.md` 專案評估產出。重點：前端可維護性、useState 重構延續、元件品質。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R6-1 | **useState → hooks 擴展** | 5 個高複雜頁面 useState 重構，Phase 5 完成 | [x] |
| R6-2 | **useDateRangeFilter / useTabState** | 建立 2 個 hook 並套用至 5 個頁面 | [x] |
| R6-3 | **Skeleton DOM nesting 修正** | InlineSkeleton `<div>` 改 `<span>` | [x] |
| R6-4 | **財務模組 Phase 2–5 評估** | AP/AR/GL 後續階段評估，依業務需求排程 | [x] |
| R6-5 | **Dependabot Phase 2.5 依賴評估** | printpdf 0.9、utoipa 5 等升級可行性評估 | [x] |
| R6-6 | **資料庫輸出與歷史重新填寫** | 匯出 API + 歷史預填表單 | [x] |
| R6-7 | **日曆功能審視與重構** | 元件拆分、Hooks 抽象、後端 Trait 解耦 | [x] |
| R6-8 | **設施管理 Migration 補建** | 6 張表 CREATE TABLE migration 新增 | [x] |
| R6-9 | **採購單未入庫通知** | 排程檢查 + 手動觸發 API + 狀態標籤 | [x] |
| R6-10 | **採購入庫品項篩選** | GRN 僅能選擇 PO 內已核准但未入庫品項 | [x] |

---

## 🔒 R7 — 第七輪改善（安全性原始碼審視，2026-03-08）

> 依據 `docs/archive/improvement-plans/IMPROVEMENT_PLAN_R7.md` 全面原始碼審視發現。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R7-1 | **SQL 拼接修復** | `data_import.rs` `format!()` SQL 改為參數化查詢 | [x] |
| R7-2 | **密碼洩露修復** | `create_admin.rs` 不再將密碼明文印至 stdout | [x] |
| R7-3 | **TRUST_PROXY 預設值** | `config.rs` `trust_proxy` 預設改為 `false` | [x] |
| R7-4 | **ETag 常數化** | 改用 `constants::ETAG_VERSION` 取代硬編碼 | [x] |
| R7-5 | **Auth Rate Limit 降低** | 認證端點 rate limit 100→30/min | [x] |

---

## 🔧 R8 — 代碼規範重構（2026-03，掃描自動產出）

> 來源：01a-1 目錄掃描 + 01a-2 風格採樣。依優先序排列，高→低。

### 🔴 高優先（架構層）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R8-1 | **`routes.rs` 依業務域拆分** | 拆成 routes/animal.rs 等子 Router + routes/mod.rs 組裝 | [x] |
| R8-2 | **`main.rs` 啟動邏輯提取** | 提取至 `startup/` 模組 | [x] |
| R8-3 | **建立 `repositories/` 層** | 遷移重複 SQL 至 repositories/ | [x] |
| R8-4 | **`utils/access.rs` → `services/access.rs`** | 權限檢查移至 service 層 | [x] |

### 🟠 中優先（模組/元件層）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R8-5 | **`services/animal/core.rs` 拆分** | 684 行→拆分或提取至 repository 層 | [x] |
| R8-6 | **`App.tsx` Route 元件拆離** | 4 個內聯元件移至獨立檔案 | [x] |
| R8-7 | **`lib/api.ts` 依業務域拆分** | 拆為 client.ts + 業務域 API 檔案 + index.ts | [x] |

### 🟡 低優先（細節/一致性）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R8-8 | **`AnimalsPage/ProtocolsPage` 拆分** | 超過 300 行上限，提取子元件 | [x] |
| R8-9 | **型別 import 路徑統一** | 改從 `@/types/*` import，移除未使用 import | [x] |
| R8-10 | **內嵌常數移至 `constants.ts`** | statusColors 等常數移至 lib/constants/ | [x] |
| R8-11 | **chrono import 位置修正** | 函式體內 `use` 移至檔案頂部 | [x] |

---

## 🔒 R9 — 安全與品質修復（2026-03-15，程式碼審查產出）

> 依據程式碼審查發現的安全漏洞與品質問題。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R9-1 | **IDOR 漏洞修復** | attachment 加入 entity_type 資源級權限檢查 | [x] |
| R9-2 | **上傳 handler 去重** | 抽取通用 `handle_upload()`，upload.rs 606→420 行 | [x] |
| R9-3 | **DB 錯誤碼修正** | 23505→409、23503/23502/23514→400 | [x] |
| R9-4 | **歡迎信安全改善** | `send_welcome_email` 改用密碼重設連結取代明文密碼 | [x] |
| R9-5 | **ERP/HR 整合測試覆蓋** | 完成：erp-inventory + erp-grn + hr-overtime + hr-attendance + file-upload 共 5 個 E2E spec | [x] |

### R9 審查—已知漏洞擱置（開發階段擱置，上線前必做）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R9-C1 | ~~生產環境 WAF 改為 On~~ | WAF 改由 Cloudflare WAF 處理，ModSecurity overlay 已移除 | [x] |
| R9-C2 | **CI 密碼改 GitHub Secrets** | `.github/workflows/ci.yml` 中 JWT_SECRET、DEV_USER_PASSWORD、ADMIN_INITIAL_PASSWORD 改為 GitHub Secrets 並輪替 | [x] |

---

## 🔒 R10 — 程式碼審查 Medium/Low（2026-03-15）

> 依據 `docs/2026_March15_code_review_1.md`，Medium/Low 納入待辦追蹤。

### Medium Severity

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R10-M1 | **Rate limiter 改 Redis** | 單機部署暫不需要，推遲至多節點部署時 | 推遲 |
| R10-M2 | **N+1 修正** | 確認已用 LEFT JOIN + 子查詢，無 N+1 | [x] |
| R10-M3 | **大檔案串流驗證** | MIME 預檢 + 欄位級大小檢查 | [x] |
| R10-M4 | **unwrap 精簡** | 已清零（0 處 unwrap） | [x] |
| R10-M5 | **CSRF 強化** | Signed Double Submit Cookie + 8 個新測試 | [x] |
| R10-M6 | **useUserManagement Zod** | createUser/updateUser Zod schema 驗證 | [x] |
| R10-M7 | **file-upload MIME** | ALLOWED_MIME_TYPES 白名單 + 副檔名檢查 | [x] |
| R10-M8 | **Session timeout 強化** | 推遲，依合規需求決定 | 推遲 |
| R10-M9 | **Alert 門檻** | CPU/Memory/P95/Error rate/Disk 門檻收緊 | [x] |
| R10-M10 | **Prometheus/Grafana 認證** | 確認已安全（環境變數密碼 + 本機綁定） | [x] |

### Low Severity / Suggestions

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R10-L1 | **auth handler 拆分** | 734→7 檔，每檔 ≤227 行 | [x] |
| R10-L2 | **auth service 拆分** | 1006→6 檔，每檔 ≤292 行 | [x] |
| R10-L3 | **signature 拆分** | handler 560→7 檔，service 899→4 檔 | [x] |
| R10-L4 | **product service 拆分** | 832→3 檔 | [x] |
| R10-L5 | **外部 error tracking** | 推遲至上線後 | 推遲 |
| R10-L6 | **Cookie consent 實際阻擋** | 雙按鈕重寫，Google Fonts 動態注入 | [x] |
| R10-L7 | **密碼複雜度** | ≥10 字元 + 大小寫 + 數字 + 黑名單 + 強度指示器 | [x] |
| R10-L8 | **Watchtower 輪詢間隔** | 30→3600 秒 | [x] |
| R10-L9 | **login_events 複合索引** | migration 016 新增 2 個複合索引 | [x] |
| R10-L10 | **JSONB schema validation** | 5 個驗證函式 + 11 個測試 | [x] |

---

## 🔧 R11 — 技術債掃描 + Git 修復（2026-03）

> 來源：2026-03-14 靜態分析掃描 + Git 環境修復。依違反 CLAUDE.md 代碼規範嚴重程度排列。
> 後端函數上限 50 行，前端元件上限 300 行（JSX return 80 行），Hook 上限 300 行。

### Git 與環境配置修復

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R11-0 | **Git 分支衝突修復** | 解決本地與遠端分支領先/落後問題，設定 `pull.rebase true` 策略，清理 `.git/index.lock` 與 `templetes/` 衝突目錄 | [x] |

### 🔴 高優先（後端極長函數 >100 行）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R11-1 | **`pdf/service.rs` 拆分** | 578 行→依章節拆出子函數 | [x] |
| R11-2 | **`import_export.rs` 拆分** | import_basic_data 327 行 + import_weight_data 172 行→輔助函式 | [x] |
| R11-3 | **`services/product.rs` 拆分** | 6 個長函數→CSV/Excel parser 獨立模組 | [x] |
| R11-4 | **`handlers/signature.rs` 拆分** | 簽署驗證邏輯移至 services/signature.rs | [x] |
| R11-5 | **`services/accounting.rs` 拆分** | post_sr/post_do/post_grn 提取子函式 | [x] |

### 🔴 高優先（架構違規：Handler 直接 SQL）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R11-19 | **Handler 層 98 處直接 SQL 清除** | 21+ 個檔案遷移至 service/repository | [x] |
| R11-20 | **Repository 層擴展** | 新增 protocol/animal/hr/user_preferences repository | [x] |

### 🟠 中優先（前端超大元件 >600 行）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R11-6 | **`ProtocolContentView.tsx` 拆分** | 870 行→依內容區塊拆為子元件 | [x] |
| R11-7 | **`ProductImportDialog.tsx` 拆分** | 863 行→預覽/映射/錯誤各自獨立 | [x] |
| R11-8 | **`usePermissionManager.ts` 拆分** | 853 行→categories/search/mutation 三個 hook | [x] |
| R11-9 | **`AccountingReportPage.tsx` 拆分** | 838 行→4 個 Tab 子元件 | [x] |
| R11-10 | **`HrLeavePage.tsx` 拆分** | 837 行→表單/表格/餘額子元件 | [x] |
| R11-11 | **`BloodTestTab.tsx` 拆分** | 811 行→套餐/輸入/歷史子元件 | [x] |
| R11-12 | **`DashboardPage.tsx` 拆分** | 805 行→提取 useDashboardData hook | [x] |
| R11-13 | **`DocumentLineEditor.tsx` 拆分** | 723 行 + 10 處 any→子元件 + 具體型別 | [x] |
| R11-14 | **`useDocumentForm.ts` 拆分** | 717→303 行，提取 useDocumentLines + useDocumentSubmit | [x] |

### 🟡 低優先（前端元件 300–600 行 & 細節問題）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R11-15 | **中大型元件逐步拆分** | 10 個元件全部 ≤300 行（平均 -80%） | [x] |
| R11-16 | **重複常數合併** | STORAGE_CONDITIONS 提取至 lib/constants/product.ts | [x] |
| R11-17 | **剩餘 `any` 型別消除** | 3 個檔案 any→AxiosError/具體型別 | [x] |
| R11-18 | **後端中長函數清理** | auth.rs 4 個 50-66 行函數→提取子函式 | [x] |
| R11-21 | **try-catch → TanStack Query** | 25 處改 useMutation，27 處合理保留 | [x] |
| R11-22 | **源碼 TODO 註解清理** | stocktake 類別篩選 + MyProjectDetailPage 動物查詢 | [x] |

---

## 🟢 R12 — 長期演進項目（已評估未排程，2026-03-20）

> 來源：各評估文件與安全審查建議。視業務需求排程。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R12-1 | **Dependabot Phase 2.5 升級** | utoipa 5、axum-extra 0.12、tailwind-merge 3 等升級完成 | [x] |
| R12-2 | **財務模組 Phase 2–5 實作** | 推遲：Phase 1 自動過帳 + 帳齡報表已涵蓋日常需求 | ⏸️ |
| R12-3 | **圖片處理獨立服務** | `image-processor/` Node.js 服務（Sharp）+ Docker 整合 | [x] |
| R12-4 | **剩餘硬編碼色彩清理** | 748→112 處（-85%），剩餘為規範內或 Canvas 色彩 | [x] |
| R12-5 | **RHF + Zod 表單遷移** | 27 檔 useForm、18 個 Zod schema，CRUD 覆蓋率 100% | [x] |
| R12-6 | **子系統色相實際套用** | Sidebar active → `bg-subsystem-*` 動態色彩 | [x] |
| R12-7 | **CSRF Token 客戶端刷新** | 403 偵測 → 刷新 cookie → 自動重試 | [x] |

---

## 🎨 R13 — UI 一致性與設計規範（2026-03-26）

> 來源：DESIGN.md §15 按鈕規範。UI 元素一致性改善。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R13-1 | **PageHeader 按鈕高度統一** | 完成：34 檔 48 個 Button 統一 `size="sm"`（h-9）。DESIGN.md §15 | [x] |

---

## 📄 R14 — AUP 計畫書 PDF 輸出修正（2026-03-26）

> 來源：使用者回饋，PDF 輸出格式需對齊官方紙本範本。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R14-1 | **PDF 封面標題頁格式修正** | header 字間距、small caps、sponsor/facility 加框線、移除 `=` 分隔、版權固定底部 | [x] |
| R14-2 | **PDF 試驗人員表格格式修正** | 訓練欄每行一筆（`<br>` 分行）、半形括號、欄寬 45% 訓練欄、`safe` filter | [x] |

---

## 🔍 R15 — Code Review 發現（Claude + Codex 交叉審查，2026-03-27）

> 來源：Claude Code Review + OpenAI Codex (GPT-5.4) 獨立審查，針對未提交變更（email 測試、PO 重算、庫存展開行、stock service product_id 篩選）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R15-1 | **展開行數量不匹配（未分配庫存遺漏）** | 概覽模式父行用 stock_ledger 含未分配庫存，但 BatchDetailRows 查 storage_location_inventory 不含未分配 → 數量不一致誤導倉管。Codex 發現，P2 | [x] |
| R15-2 | **PO 重算半完成風險** | `recalculate_all_po_receipt_status` 逐筆開 tx，中途失敗前面已 commit 不會 rollback。Claude+Codex 共同發現，P2 | [x] |
| R15-3 | **expandedRows 不隨 filter 重置** | 切換倉庫/關鍵字篩選時展開狀態殘留，可能對應到不同行。Codex 發現，P2 | [x] |
| R15-4 | **展開行不傳遞 batchFilter** | BatchDetailRows API 呼叫只傳 warehouse_id + product_id，忽略使用者輸入的 batchFilter。Codex 發現，P2 | [x] |
| R15-5 | **Email 引號可能破壞含引號名稱** | display name 加雙引號後，若 from_name 含引號（如 `ACME "QA"`）會造成 lettre parse 失敗；中文 UTF-8 需驗證。Codex 發現，P2 | [x] |
| R15-6 | **recalculate 權限太寬鬆** | 使用 `erp.document.approve` 而非 admin 權限，此維護型 endpoint 應限 admin。Codex 發現，P2 | [x] |
| R15-7 | **Stock service DRY 違規** | 抽出 `SliFilterBuilder` 共用 keyword/product/batch filter 建構邏輯。Claude 發現，Low | [x] |
| R15-8 | **send_test_email handler 超 50 行** | email body 移至 `EmailService::send_test_email`，handler 精簡為 ~35 行。Claude 發現，Low | [x] |
| R15-9 | **`let _ = idx` 抑制 unused 警告** | stock.rs 兩處改為最後一個 filter 後統一放置 + 加註解。R15-4 順便修正 | [x] |
| R15-10 | **BatchDetailRows key 使用 array index** | 改用 `storage_location_id + batch_no` 組合。R15-1 順便修正 | [x] |
| R15-11 | **InventoryPage.tsx 超 300 行** | 拆分為 InventoryPage (220 行) + components/InventoryRow.tsx (262 行)。Claude 發現，Low | [x] |

---

## 🔍 R16 — 全專案 Code Review (2026-03-29)

> 5 面向平行審查：Backend 安全、Frontend 安全、Backend 品質、Frontend 品質、CI/測試覆蓋
> CRITICAL 2 / HIGH 23 / MEDIUM 22 / LOW 11

### 第一批 — 安全 + 功能 Bug（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R16-1 | **Auth 查詢錯誤靜默吞掉** | `handlers/protocol/` 13+ 處 `.unwrap_or((false,))` 改用 `?` 傳播錯誤，避免 DB 故障遮蔽為 403。CRITICAL | [x] |
| R16-2 | **Content-Disposition header injection** | `handlers/upload.rs:466` + 12 處 export handler 檔名未跳脫，改用 RFC 5987 percent-encode。HIGH | [x] |
| R16-3 | **稽核日誌 PDF XSS** | `useAuditLogExport.ts:54-62` document.write 未 HTML 跳脫，加入 `escapeHtml()` 函式。HIGH | [x] |
| R16-4 | **window.open 缺 noopener** | `VetRecommendationDialog.tsx:85` 補 `'noopener,noreferrer'`。HIGH | [x] |
| R16-5 | **Query key 不匹配快取 bug** | `useLeaveMutations.ts:25` invalidates `'hr-balance-summary'` 但實際 key 是 `'hr-balance-summary-expiring'`，改用 `queryKeys.hr.balanceSummary`。HIGH | [x] |
| R16-6 | **window.location.reload() 強制刷新** | `useDocumentSubmit.ts:168`, `DocumentDetailPage.tsx:171` 改用 `queryClient.invalidateQueries()`。HIGH | [x] |

### 第二批 — 架構 + 安全加固（P1-P2）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R16-7 | **Handler 層直接寫 SQL（授權部分）** | 授權查詢已集中至 `services/access.rs`。protocol/crud, review, export, pdf_export, amendment 已改用。CRITICAL（部分完成：授權查詢） | [x] |
| R16-8 | **3 套重複 check_protocol_access** | 合併至 `services/access.rs`（require_protocol_view_access, require_protocol_related_access 等 9 函式）。HIGH | [x] |
| R16-9 | **Swagger UI 無認證暴露** | `startup/server.rs:76` production 關閉或加 auth gate。HIGH | [x] |
| R16-10 | **動態 table name 無白名單** | `services/signature/access.rs:98-145` 加 allowed_tables 驗證。HIGH | [x] |
| R16-11 | **CSRF 可被 env var 關閉** | `DISABLE_CSRF_FOR_TESTS` 加 production guard，拒絕非 dev 環境啟用。MEDIUM | [x] |
| R16-12 | **缺 HSTS header** | `startup/server.rs` 加 `Strict-Transport-Security`，gate on `cookie_secure`。MEDIUM | [x] |
| R16-13 | **CI 硬編碼 fallback 密碼** | `ci.yml:411-468` 移除 fallback，secrets 必填。HIGH | [x] |

### 第三批 — 品質改善（P2-P3）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R16-14 | **角色碼魔術字串** | `hr/dashboard.rs`, `scheduler.rs`, `protocol/crud.rs` 角色碼移至 `constants.rs`。HIGH | [x] |
| R16-15 | **scheduler.rs 函數過長** | `start()` 235 行、`generate_monthly_report` 138 行。拆分 helper + 子函式。HIGH | [x] |
| R16-16 | **services/stock.rs 超 800 行** | 942 行，拆分 inventory/ledger 模組。HIGH | [x] |
| R16-17 | **613 處硬編碼 Tailwind 色彩 token** | 88 個元件/頁面，替換為 CSS Variable token。HIGH（規模大） | [x] |
| R16-18 | **5 個元件超 300 行** | HrAttendancePage(460), ObservationFormDialog(457), SacrificeFormDialog(427), AnimalEditPage(385), RolesPage(362)。抽出 hooks + 子元件。HIGH | [x] |
| R16-19 | **PageErrorBoundary 僅覆蓋 5/40+ routes** | 在 `MainLayout` 層統一包裹或逐一補齊。HIGH | [x] |
| R16-20 | **HR query key 未使用 queryKeys factory** | `HrAttendancePage`, `HrLeavePage` 硬編碼 query key string，遷移至 `queryKeys.hr.*`。HIGH | [x] |
| R16-21 | **Zustand store 直接 mutation** | `client.ts:112` `sessionExpiresAt` 直接賦值改用 `setState()`。MEDIUM | [x] |
| R16-22 | **format!() 拼接動態 SQL** | `services/stock.rs:471,499,530,608` 改用 `sqlx::QueryBuilder`。MEDIUM | [x] |
| R16-23 | **Array index 作 React key** | BloodTestFormDialog, VetReviewForm, HrAnnualLeavePage 等 5 處改用穩定 ID。MEDIUM | [x] |
| R16-24 | **直接 import axios 繞過中央 client** | `useAnimalsMutations.ts`, `useUserManagement.ts` 改用 `@/lib/api`。LOW | [x] |
| R16-25 | **console.debug 未限 dev-only** | `webVitals.ts:13` 改用 `logger.debug()` 或 gate `import.meta.env.DEV`。LOW | [x] |

### 第四批 — CI/測試改善（P2-P3）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R16-26 | **GitHub Actions 版本標籤不存在** | `actions/checkout@v6` 等改為正確版本 v4 或 SHA pin。HIGH | [x] |
| R16-27 | **Backend coverage threshold 僅 2%** | `tarpaulin --fail-under 2` 提高至合理值或整合 integration test 覆蓋。HIGH | [x] |
| R16-28 | **CI 無 ESLint job** | frontend-check 加入 `npx eslint src --max-warnings=0`。MEDIUM | [x] |
| R16-29 | **E2E 僅測 read path** | 擴充至少 1 個完整 create+submit flow（animal, protocol, user）。MEDIUM | [x] |
| R16-30 | **unsafe-guard 只 warning 不 block** | `ci.yml:97` `::warning::` 改為 `exit 1` 或要求 `// SAFETY:` 註解。MEDIUM | [x] |
| R16-31 | **Edge case 測試不足** | 缺少 refresh token replay、暴力破解 rate limit、檔案上傳安全、分頁邊界、SQL injection in search 等 18+ 項。MEDIUM | [x] |

---

## 🔒 R17 — CSO 安全審計發現（2026-03-29）

> 來源：gstack /cso 全面安全審計（14 phase），對比 2026-03-25 基準。0 CRITICAL / 0 HIGH / 5 MEDIUM / 1 LOW。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R17-1 | **CI 日誌檔含測試密碼** | `logs_61488804168/` 目錄含明文測試密碼已提交至 git，需 `git filter-repo` 移除 + 加 `logs_*/` 到 `.gitignore`。MEDIUM | [x] |
| R17-2 | **Web 容器綁定 0.0.0.0** | `docker-compose.yml:159` web service 未限制 `127.0.0.1`，對外暴露 port 8080。prod overlay 已修正但基礎 compose 未改。MEDIUM | [x] |
| R17-3 | **CSP unsafe-inline + unsafe-eval** | `nginx.conf:22` script-src 含 `'unsafe-inline'`（Cloudflare）+ `'unsafe-eval'`（Vite）。已接受風險，DOMPurify 為補償控制。MEDIUM | 已接受 |
| R17-4 | **/metrics 端點預設無認證** | Prometheus metrics 公開暴露，需設定 `METRICS_TOKEN` 或限制內網存取。LOW | [x] |

> R16-9（Swagger UI 暴露）、R16-26（Actions 未 SHA 釘選）已在 R16 追蹤，不重複列入。

### R17 詳細實作計畫

<details>
<summary>R17-1：CI 日誌檔含測試密碼</summary>

**問題**：`logs_61488804168/` 目錄含 16 個檔案（安全/測試日誌），可能含明文測試密碼，已提交至 git history。

**步驟**：
1. 安裝 `git filter-repo`：`pip install git-filter-repo`
2. 備份 repo：`cp -r .git .git.bak`
3. 移除 git history 中的 logs 目錄：
   ```bash
   git filter-repo --path logs_61488804168/ --invert-paths
   ```
4. 加入 `.gitignore`：
   ```
   # CI/CD log artifacts
   logs_*/
   ```
5. 驗證：`git log --all --full-history -- logs_61488804168/` 應無結果
6. Force push（需確認遠端無其他人在用）：`git push --force-with-lease`
7. 通知所有開發者重新 clone

**風險**：force push 會改變 commit hash，需協調其他分支。
**前置條件**：確認此 repo 無其他人正在工作中的分支。
</details>

<details>
<summary>R17-2：Web 容器綁定 0.0.0.0</summary>

**問題**：`docker-compose.yml:159` web service ports 為 `"${WEB_PORT:-8080}:8080"`（綁 0.0.0.0），`docker-compose.prod.yml:47` 已修正為 `"127.0.0.1:${WEB_PORT:-8080}:8080"`，但基礎 compose 未改。

**步驟**：
1. 修改 `docker-compose.yml` web service：
   ```yaml
   ports:
     - "127.0.0.1:${WEB_PORT:-8080}:8080"
   ```
2. 同步檢查其他 service 的 port binding（API backend、PostgreSQL）是否也綁 0.0.0.0
3. 驗證：`docker compose up -d` → `ss -tlnp | grep 8080` 確認只綁 127.0.0.1
4. 確認 CI docker-compose.test.yml 不受影響（CI 可能需要 0.0.0.0）

**影響範圍**：僅開發/基礎 compose，prod overlay 已正確。
</details>

<details>
<summary>R17-4：/metrics 端點預設無認證</summary>

**問題**：`handlers/metrics.rs:54-97` 已有 `METRICS_TOKEN` Bearer 認證邏輯，但環境變數未設定時端點公開。`config.rs` 未定義此變數，`.env.example` 也未列出。

**步驟**：
1. 在 `.env.example` 新增：
   ```
   # Prometheus metrics authentication (recommended for production)
   # METRICS_TOKEN=your-secure-random-token-here
   ```
2. 在 `config.rs` Config struct 新增 `metrics_token: Option<String>` 欄位，從 `METRICS_TOKEN` 讀取
3. 修改 `handlers/metrics.rs` 改讀 `state.config.metrics_token` 而非直接 `std::env::var`（統一 config 管理）
4. **可選加固**：如果 `cookie_secure = true`（即 production）且 `METRICS_TOKEN` 未設定，回傳 403 並 log warning
5. 在 `OPERATIONS.md` 補充說明

**影響範圍**：僅 /metrics 端點，不影響其他功能。Prometheus scrape config 需加 Bearer token header。
</details>

---

## 🫀 R18 — Heartbeat 自動化維護（2026-03-29）

> 來源：`docs/heartbeatImprovement.md`。透過 Claude Code `/schedule` 定期排程持續維護程式碼品質、安全性與功能完整性。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R18-1 | **每日分段 Code Review 排程** | 10 天一輪迴，每天 review 一個模組區塊（安全、品質、TODO/FIXME、CLAUDE.md 合規），產出報告至 `docs/heartbeat/` | [x] |
| R18-2 | **每日健康檢查排程** | cargo test + clippy + npm audit + cargo deny + build + E2E，產出 health report | [x] |
| R18-3 | **月度架構審查排程** | 每月 1 日深度掃描：量化指標、重複程式碼、依賴健康度、測試覆蓋率 | [x] |
| R18-4 | **Heartbeat 報告目錄建立** | 建立 `docs/heartbeat/` 目錄 + README.md | [x] |

### R18 詳細實作計畫

<details>
<summary>R18-4：Heartbeat 報告目錄建立（先做）</summary>

**步驟**：
1. 建立目錄結構：
   ```
   docs/heartbeat/
     README.md          # 系統說明、報告命名規則、連結索引
   ```
2. README.md 內容：
   - Heartbeat 系統概述
   - 報告類型說明（daily review / health check / monthly architecture）
   - 檔案命名規則（`YYYY-MM-DD.md` / `health-YYYY-MM-DD.md` / `architecture-YYYY-MM.md`）
   - 嚴重度定義（Critical / High / Medium / Low）
3. 加入 `.gitignore` 排除過舊報告（可選）：`docs/heartbeat/` 保留最近 30 天

**前置條件**：無。
</details>

<details>
<summary>R18-1：每日分段 Code Review 排程</summary>

**使用工具**：Claude Code `/schedule` 建立 remote trigger

**排程設定**：
- **頻率**：週一至週五，每日一次
- **Cron**：`0 8 * * 1-5`（每天早上 8:00）

**Prompt 模板**：
```
在 C:\System Coding\ipig_system 執行 Heartbeat 每日 Code Review。

今天是 {date}，根據以下排程表判斷今天是 D 幾：
  D1: handlers/auth/ + middleware/ + services/auth/（認證安全）
  D2: handlers/protocol/ + services/protocol/（IACUC 審查流程）
  D3: handlers/animal/ + services/animal/（動物管理）
  D4: handlers/hr/ + services/hr/ + services/calendar/（HR 模組）
  D5: ERP 相關 handlers + services（庫存、採購、倉儲）
  D6: services/notification/ + email/ + pdf/ + repositories/（通知、PDF、Repository）
  D7: 剩餘 services + models/（審計、設備、簽章等）
  D8: frontend pages/protocols/ + animals/ + amendments/
  D9: frontend pages/admin/ + hr/ + dashboard/ + auth/
  D10: frontend pages/erp/ + inventory/ + master/ + documents/ + reports/ + 共用 components/

計算方式：(工作天數 % 10) + 1 = 今天的 D 值

檢查項目：
1. 函數長度 ≤ 50 行、圈複雜度 ≤ 10、巢狀 ≤ 3 層
2. SQL injection（字串拼接 SQL）、權限檢查完整性、unwrap() 殘留
3. TODO/FIXME/HACK 列表
4. CLAUDE.md 架構分層合規

產出報告寫入 docs/heartbeat/YYYY-MM-DD.md，格式依 heartbeatImprovement.md。
不要自動修復，僅報告發現。
```

**驗收條件**：每天產出一份 markdown 報告，包含發現問題數和嚴重度分布。
</details>

<details>
<summary>R18-2：每日健康檢查排程</summary>

**使用工具**：Claude Code `/schedule` 建立 remote trigger

**排程設定**：
- **頻率**：每日（含週末）
- **Cron**：`0 7 * * *`（每天早上 7:00，比 code review 早 1 小時）

**Prompt 模板**：
```
在 C:\System Coding\ipig_system 執行 Heartbeat 每日健康檢查。

依序執行以下命令並記錄結果：

1. Backend 編譯：cd backend && cargo build --release 2>&1
2. Backend lint：cargo clippy -- -D warnings 2>&1
3. Backend 測試：cargo test 2>&1
4. Backend 安全掃描：cargo deny check advisories 2>&1
5. Frontend 編譯：cd frontend && npm run build 2>&1
6. Frontend 安全掃描：npm audit 2>&1
7. Migration 檢查：列出 backend/migrations/ 目錄確認命名順序

產出報告寫入 docs/heartbeat/health-YYYY-MM-DD.md，格式依 heartbeatImprovement.md。

注意：
- E2E 測試需要 Docker（PostgreSQL），如環境不支援則跳過並標記
- 記錄每項的 pass/fail + 具體錯誤訊息
- 如果 CVE 為 HIGH/CRITICAL，在報告頂部加 ⚠️ 警告
```

**前置條件**：
- Rust toolchain 已安裝（`cargo`、`clippy`）
- Node.js 已安裝（`npm`）
- `cargo-deny` 已安裝（`cargo install cargo-deny`）
</details>

<details>
<summary>R18-3：月度架構審查排程</summary>

**使用工具**：Claude Code `/schedule` 建立 remote trigger

**排程設定**：
- **頻率**：每月 1 日
- **Cron**：`0 9 1 * *`

**Prompt 模板**：
```
在 C:\System Coding\ipig_system 執行 Heartbeat 月度架構審查。

深度檢查以下面向：

1. CLAUDE.md 規範合規
   - 掃描 handlers/ 中是否有直接寫 SQL 的檔案（應在 repositories/）
   - 掃描 services/ 中是否有建構 HTTP response 的程式碼（應在 handlers/）
   - 掃描 utils/ 中是否 import AppState（禁止）
   - 掃描 models/ 中是否 import 其他層（禁止）

2. 量化指標
   - 列出所有 > 50 行的 Rust 函數
   - 列出所有 > 300 行的 React 元件（.tsx）
   - 列出所有 > 6 個 Props 的 React 元件
   - 列出所有 > 5 個參數的 Rust 函數

3. 重複程式碼
   - 掃描相同 SQL SELECT 出現 ≥ 2 處
   - 掃描相同驗證邏輯 ≥ 2 處

4. 依賴健康度
   - 列出 Cargo.toml 中可升級的依賴
   - 列出 package.json 中可升級的依賴
   - 標記 major version behind 的依賴

5. 測試覆蓋
   - 計算 handler 數量 vs 整合測試數量
   - 標記無測試的關鍵 handler

產出報告寫入 docs/heartbeat/architecture-YYYY-MM.md，格式依 heartbeatImprovement.md。
與上月報告對比（如存在），標記趨勢（改善/惡化/持平）。
```

**驗收條件**：每月產出一份包含量化指標和趨勢的架構審查報告。
</details>

---

## 🎫 R19 — 客戶邀請制入口（2026-03-29）

> 來源：`docs/clientsAccess.md`。讓外部客戶透過一次性邀請連結自助註冊，提交 IACUC 計劃書。

### Phase 1：邀請後台

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R19-1 | **invitations migration** | `invitations` 表 + pending email UNIQUE index | [x] |
| R19-2 | **邀請 Backend** | model + handler + service（建立/列表/撤銷/重新發送），含 Email 已註冊→重設密碼、已邀請→重新發送邏輯 | [x] |
| R19-3 | **邀請 Email 模板** | HTML + plain text，含一次性連結 | [x] |
| R19-4 | **邀請管理前端頁面** | Admin 建立 Dialog（只需 Email + 可選組織）、送出後顯示可複製連結、列表 + 狀態篩選 | [x] |
| R19-5 | **邀請權限設定** | `invitation.create/view/revoke/resend` → IACUC_STAFF, SYSTEM_ADMIN | [x] |

### Phase 2：客戶自助註冊

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R19-6 | **公開 verify/accept endpoints** | verify 回傳 token 狀態 + Email；accept 建帳 + 自動分配 PI 角色 + 回傳 JWT | [x] |
| R19-7 | **客戶註冊頁面** | `/invite/{token}` 頁面：驗證連結→填寫資料→設定密碼→自動登入→導向「我的計劃書」 | [x] |
| R19-8 | **錯誤處理頁面** | 連結過期/已使用/無效 → 友善提示頁面 | [x] |

### Phase 3：客戶介面

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R19-9 | **客戶 Sidebar 簡化** | PI 角色 sidebar 只顯示「我的計劃書」+ 個人設定 | [x] |
| R19-10 | **計劃書狀態 Timeline UI** | 視覺化顯示計劃書審查進度（6 階段） | [x] |
| R19-11 | **審查意見通知** | 審查進度變更時 Email + 站內通知客戶 | [x] |

### Phase 4：測試與上線

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R19-12 | **邀請流程 E2E 測試** | 建立→接受→登入→提交計劃書完整流程 | [x] |
| R19-13 | **權限隔離測試** | 客戶不可存取其他人資料、不可存取 Admin/HR/ERP | [x] |
| R19-14 | **安全測試** | Token 暴力破解、過期處理、重複使用防護 | [x] |

### R19 詳細實作計畫

<details>
<summary>R19-1：invitations migration</summary>

**檔案**：`backend/migrations/0XX_invitations.sql`（接在最後一個 migration 之後）

**SQL**：
```sql
CREATE TABLE invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    organization VARCHAR(255),
    invitation_token VARCHAR(255) UNIQUE NOT NULL,
    invited_by UUID NOT NULL REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    created_user_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 同一 Email 只能有一筆 pending 邀請
CREATE UNIQUE INDEX idx_invitations_email_pending
    ON invitations (email) WHERE status = 'pending';

-- Token 查詢索引
CREATE INDEX idx_invitations_token ON invitations (invitation_token);

-- 過期清理用索引
CREATE INDEX idx_invitations_expires_at ON invitations (expires_at)
    WHERE status = 'pending';
```

**注意**：不需要 `role_ids` 欄位，角色固定 PI。
</details>

<details>
<summary>R19-2：邀請 Backend（model + handler + service）</summary>

**新增檔案**：

1. **`backend/src/models/invitation.rs`**
   ```rust
   // DB entity
   pub struct Invitation { id, email, organization, invitation_token, invited_by, status, expires_at, accepted_at, created_user_id, created_at, updated_at }

   // Request DTOs
   pub struct CreateInvitationRequest { email: String, organization: Option<String> }

   // Response DTOs
   pub struct InvitationResponse { ...全欄位..., invite_link: String, invited_by_name: String }
   pub struct CreateInvitationResponse { invitation: InvitationResponse, invite_link: String }

   // 錯誤類型
   pub enum InvitationError { EmailAlreadyRegistered, AlreadyInvited { invitation_id: Uuid }, TokenInvalid, TokenExpired, TokenUsed }
   ```

2. **`backend/src/services/invitation.rs`**
   ```rust
   pub struct InvitationService;
   impl InvitationService {
       // 建立邀請
       pub async fn create(db, email, organization, invited_by, base_url) -> Result<CreateInvitationResponse, AppError> {
           // 1. 檢查 users 表 email 是否已存在 → AppError::Conflict("EmailAlreadyRegistered")
           // 2. 檢查 invitations 表是否已有 pending → AppError::Conflict("AlreadyInvited")
           // 3. generate_crypto_random_token(64) → base64url 編碼
           // 4. INSERT INTO invitations
           // 5. spawn(send_invitation_email) — 非同步不阻塞
           // 6. 回傳 invitation + invite_link
       }

       // 列出邀請（支援 status 篩選 + 分頁）
       pub async fn list(db, status_filter, page, per_page) -> Result<PaginatedResponse<InvitationResponse>>

       // 撤銷邀請
       pub async fn revoke(db, invitation_id) -> Result<()>
           // UPDATE status = 'revoked' WHERE status = 'pending'

       // 重新發送（更新 token + 重設 expires_at + 重發 Email）
       pub async fn resend(db, invitation_id, base_url) -> Result<CreateInvitationResponse>
           // 1. 檢查 status = 'pending'
           // 2. 產生新 token，更新 expires_at = now + 7d
           // 3. 重發 Email + 回傳新連結

       // 驗證 token
       pub async fn verify(db, token) -> Result<VerifyResponse>
           // 回傳 { valid, email, organization, reason }

       // 接受邀請
       pub async fn accept(db, token, req: AcceptInvitationRequest) -> Result<(User, AuthTokens)>
           // 1. 驗證 token (pending + 未過期)
           // 2. UserService::create(email from invitation, ...)
           // 3. RoleService::assign_role(user_id, PI_ROLE_ID)
           // 4. UPDATE invitation status='accepted', accepted_at, created_user_id
           // 5. generate_auth_tokens(user) → 自動登入
           // 6. audit_log("invitation_accepted", ...)

       // 排程：過期清理（可加入 scheduler.rs）
       pub async fn expire_stale(db) -> Result<u64>
           // UPDATE status='expired' WHERE status='pending' AND expires_at < now()
   }
   ```

3. **`backend/src/handlers/invitation.rs`**
   ```rust
   // 需認證（IACUC_STAFF / SYSTEM_ADMIN）
   pub async fn create_invitation(State, Extension(user), Json(req)) -> Result<Json<CreateInvitationResponse>>
   pub async fn list_invitations(State, Extension(user), Query(params)) -> Result<Json<PaginatedResponse>>
   pub async fn revoke_invitation(State, Extension(user), Path(id)) -> Result<StatusCode>
   pub async fn resend_invitation(State, Extension(user), Path(id)) -> Result<Json<CreateInvitationResponse>>

   // 公開（無需認證）
   pub async fn verify_invitation(State, Path(token)) -> Result<Json<VerifyResponse>>
   pub async fn accept_invitation(State, Json(req)) -> Result<Json<AcceptResponse>>
   ```

4. **`backend/src/routes/invitation.rs`**
   ```rust
   pub fn admin_routes() -> Router {
       Router::new()
           .route("/invitations", post(create).get(list))
           .route("/invitations/:id", delete(revoke))
           .route("/invitations/:id/resend", post(resend))
   }
   pub fn public_routes() -> Router {
       Router::new()
           .route("/invitations/verify/:token", get(verify))
           .route("/invitations/accept", post(accept))
   }
   ```

**修改檔案**：
- `backend/src/routes/mod.rs`：註冊 invitation routes（admin 在 protected_routes、public 在 public_routes）
- `backend/src/models/mod.rs`：加 `pub mod invitation;`
- `backend/src/services/mod.rs`：加 `pub mod invitation;`
- `backend/src/handlers/mod.rs`：加 `pub mod invitation;`
- `backend/src/services/scheduler.rs`：加入每日過期清理 job（`0 4 * * *`）

**accept endpoint 的回應**：
```json
{
    "user": { "id": "...", "email": "...", "display_name": "..." },
    "access_token": "eyJ...",
    "refresh_token": "..."
}
```
前端收到後寫入 cookie/store，直接導向 `/my-projects`。
</details>

<details>
<summary>R19-3：邀請 Email 模板</summary>

**新增檔案**：`backend/src/services/email/invitation.rs`

**函式**：
```rust
pub async fn send_invitation_email(
    smtp_config: &SmtpConfig,
    to_email: &str,
    invite_link: &str,
    expires_at: &str,  // 格式化的日期字串
) -> Result<()>
```

**Email 模板**（`resources/templates/email/invitation.html`）：
- 複用現有 Email 模板風格（inline CSS、公司 logo CID、響應式）
- 內容：
  - 標題：邀請您加入實驗動物管理平台
  - 功能說明（提交 AUP、追蹤進度、線上溝通）
  - CTA 按鈕：「完成註冊」→ `{invite_link}`
  - 過期提示：`⏰ 此連結將於 {expires_at} 到期`
  - 聯絡資訊（037-433789）
  - Plain text fallback 版本

**參考**：複用 `services/email/auth.rs` 的 `send_welcome_email()` 結構。
</details>

<details>
<summary>R19-4：邀請管理前端頁面</summary>

**新增檔案**：

1. **`frontend/src/pages/admin/InvitationsPage.tsx`**（≤300 行）
   - 使用 `PageHeader`（標題 + 「新增邀請」按鈕）
   - 使用 `DataTable` 顯示邀請列表
   - 欄位：Email、組織、狀態 badge、邀請人、建立時間、到期時間、操作
   - 狀態篩選 Tab：全部 / Pending / Accepted / Expired / Revoked
   - 操作按鈕：重新發送（pending）、撤銷（pending）
   - 分頁

2. **`frontend/src/pages/admin/components/InvitationCreateDialog.tsx`**（≤200 行）
   - React Hook Form + Zod 驗證
   - 欄位：Email（必填）、組織（選填）
   - 送出成功後切換為「成功狀態」：
     - 顯示「✅ 邀請已送出至 xxx@xxx.com」
     - 顯示可複製的連結 + 📋 複製按鈕（`navigator.clipboard.writeText`）
     - 過期時間提示
   - 錯誤處理：
     - `EmailAlreadyRegistered` → 提示「此 Email 已有帳號」+ 連結到使用者管理
     - `AlreadyInvited` → 提示「已邀請過」+ 「重新發送」按鈕

3. **`frontend/src/lib/api/invitation.ts`**
   ```typescript
   export const invitationApi = {
     create: (data: { email: string; organization?: string }) => client.post('/invitations', data),
     list: (params: { status?: string; page?: number }) => client.get('/invitations', { params }),
     revoke: (id: string) => client.delete(`/invitations/${id}`),
     resend: (id: string) => client.post(`/invitations/${id}/resend`),
   }
   ```

4. **`frontend/src/types/invitation.ts`**
   ```typescript
   export interface Invitation { id, email, organization, status, invited_by_name, expires_at, accepted_at, created_at }
   export type InvitationStatus = 'pending' | 'accepted' | 'expired' | 'revoked'
   ```

**修改檔案**：
- `frontend/src/App.tsx`：加入 `/admin/invitations` 路由
- Sidebar 導航：在 Admin section 加入「邀請管理」項目
- `frontend/src/lib/api/index.ts`：匯出 `invitationApi`
</details>

<details>
<summary>R19-5：邀請權限設定</summary>

**修改檔案**：`backend/src/startup/permissions.rs`

**新增權限**：
```rust
// 在 permissions 定義區加入
("invitation.create", "建立客戶邀請"),
("invitation.view", "查看邀請列表"),
("invitation.revoke", "撤銷邀請"),
("invitation.resend", "重新發送邀請"),
```

**分配角色**：
- `IACUC_STAFF`：invitation.create + view + revoke + resend
- `SYSTEM_ADMIN`：invitation.create + view + revoke + resend

**其他角色不可見邀請管理頁面**。

**前端**：Sidebar 根據 `invitation.view` 權限顯示/隱藏「邀請管理」。
</details>

<details>
<summary>R19-6：公開 verify/accept endpoints</summary>

**verify endpoint**：`GET /api/invitations/verify/{token}`
- 無需認證，加 rate limiter（10 次/分鐘/IP）
- 回應：
  ```json
  // 有效
  { "valid": true, "email": "wang@hospital.org", "organization": "台大醫院" }
  // 已使用
  { "valid": false, "reason": "already_accepted" }
  // 已過期
  { "valid": false, "reason": "expired" }
  // 不存在
  → 404
  ```

**accept endpoint**：`POST /api/invitations/accept`
- 無需認證，加 rate limiter（5 次/分鐘/IP — 更嚴格防暴力破解）
- Request body：
  ```json
  {
      "invitation_token": "a8f3...x9z",
      "display_name": "王大明",
      "phone": "0912345678",
      "organization": "台大醫院",
      "password": "SecurePass123!",
      "position": "主治醫師",
      "agree_terms": true
  }
  ```
- 驗證：
  - `invitation_token`：查 DB，狀態必須 pending + 未過期
  - `display_name`：1-100 字元
  - `phone`：9-10 位數字
  - `password`：≥ 10 字元（複用現有密碼規則，含大小寫 + 數字）
  - `agree_terms`：必須 true
- 成功後：
  1. 建立 user（`must_change_password = false`）
  2. 分配 PI 角色
  3. 更新 invitation（status=accepted）
  4. 產生 JWT access_token + refresh_token
  5. 回傳：user 資訊 + tokens
  6. 設定 HttpOnly cookie（與現有 login 一致）
</details>

<details>
<summary>R19-7：客戶註冊頁面</summary>

**新增檔案**：`frontend/src/pages/auth/InvitationAcceptPage.tsx`

**路由**：`/invite/:token`（公開路由，無需認證）

**流程**：
```
頁面載入
  → useEffect: GET /api/invitations/verify/{token}
  → 成功 (valid=true)：顯示註冊表單，Email 預填（readonly）
  → 失敗 (valid=false)：顯示錯誤頁面（R19-8）

使用者填寫表單
  → React Hook Form + Zod 驗證
  → 欄位：
    - Email（readonly，從 verify 回傳）
    - 姓名*（display_name）
    - 電話*（phone）
    - 組織*（organization，從 verify 預填，可修改）
    - 職稱（position，選填）
    - 密碼*（含強度指示器）
    - 確認密碼*
    - □ 同意服務條款（連結到 /terms）
  → 送出：POST /api/invitations/accept

成功回應
  → 將 tokens 寫入 auth store
  → 設定 cookie
  → navigate('/my-projects')
  → toast.success('歡迎加入！')
```

**UI 設計**：
- 使用與 LoginPage 相同的佈局風格（居中卡片）
- 公司 logo + 標題「完成註冊」
- 表單 ≤ 250 行，提取 Zod schema 到 validation.ts
</details>

<details>
<summary>R19-8：錯誤處理頁面</summary>

**在 InvitationAcceptPage.tsx 中處理**（不需獨立檔案）：

```
token 不存在 (404)   → 「此邀請連結無效，請聯繫管理員」
已使用 (accepted)    → 「此邀請已使用，如忘記密碼請」→ 連結到 /forgot-password
已過期 (expired)     → 「此邀請已過期，請聯繫管理員重新發送」
已撤銷 (revoked)     → 「此邀請已被撤銷，請聯繫管理員」
```

每種狀態顯示友善圖示 + 說明 + 操作建議。
</details>

<details>
<summary>R19-9：客戶 Sidebar 簡化</summary>

**修改檔案**：`frontend/src/components/layout/Sidebar.tsx`（或同層導航元件）

**邏輯**：
```typescript
// 判斷是否為「純客戶」（只有 PI 角色，無其他管理角色）
const isClientOnly = user.roles.length === 1 && user.roles[0].code === 'PI';

if (isClientOnly) {
    // 只顯示：
    // - 我的計劃書 (/my-projects)
    // - 個人設定 (/profile)
    // 隱藏所有 Admin、HR、ERP、動物管理、報表 section
}
```

**注意**：如果 PI 同時有其他角色（如 EXPERIMENT_STAFF），則顯示完整 sidebar。這個邏輯確保內部人員不受影響。
</details>

<details>
<summary>R19-10：計劃書狀態 Timeline UI</summary>

**新增元件**：`frontend/src/components/protocol/ProtocolTimeline.tsx`

**顯示在**：`MyProjectDetailPage.tsx` 頂部

**視覺設計**：水平進度條，6 個節點

```
[Draft] ─── [Submitted] ─── [Pre-Review] ─── [Vet Review] ─── [Committee] ─── [Approved]
  ●            ●               ●               ○               ○              ○
  完成          完成            進行中

  ● = 已完成（綠色）
  ◉ = 進行中（藍色脈動）
  ○ = 未到達（灰色）
  ✕ = 退回修改（橙色，顯示在對應階段）
```

**狀態對應**：
- Draft → 節點 1
- Submitted → 節點 2
- Pre_Review / Pre_Review_Revision_Required → 節點 3
- Vet_Review / Vet_Revision_Required → 節點 4
- Under_Review / Revision_Required / Resubmitted → 節點 5
- Approved / Approved_With_Conditions → 節點 6
- Rejected / Suspended / Closed → 特殊狀態標記

**資料來源**：`protocol.status`（已有）+ `protocol_activities`（狀態轉移列 `to_value IS NOT NULL`，顯示各階段時間戳）
</details>

<details>
<summary>R19-11：審查意見通知</summary>

**修改檔案**：`backend/src/services/notification/protocol.rs`

**新增通知事件**：
| 事件 | 通知對象 | 通道 |
|------|---------|------|
| 計劃書狀態變更 | PI（protocol owner） | Email + 站內 |
| 新審查意見 | PI | Email + 站內 |
| 退回修改 | PI | Email + 站內（含修改建議摘要） |
| 核准 | PI | Email + 站內（含 IACUC 編號） |

**Email 模板新增**：`resources/templates/email/protocol_status.html`
- 動態內容：計劃書標題、新狀態、審查意見摘要（如有）
- CTA 按鈕：「查看詳情」→ `{base_url}/my-projects/{protocol_id}`

**現有基礎**：`services/notification/protocol.rs` 已有通知框架，只需新增 PI 對象的觸發邏輯。
</details>

<details>
<summary>R19-12 / R19-13 / R19-14：測試</summary>

**R19-12 E2E 測試**：`frontend/e2e/invitation.spec.ts`
```
test('完整邀請流程', async () => {
    // 1. Admin 登入 → 建立邀請
    // 2. 取得邀請連結
    // 3. 開新 context → 訪問邀請連結
    // 4. 填寫註冊表單 → 提交
    // 5. 驗證自動登入 → 看到「我的計劃書」
    // 6. 驗證可建立新計劃書
})

test('重複邀請處理', async () => { /* 已邀請 Email → 提示 */ })
test('過期連結處理', async () => { /* 過期 token → 友善提示 */ })
```

**R19-13 權限隔離測試**：`backend/tests/api_invitations.rs`
```rust
#[test] async fn pi_cannot_access_admin_pages() { /* GET /api/users → 403 */ }
#[test] async fn pi_cannot_see_other_protocols() { /* GET /api/protocols → 只回傳自己的 */ }
#[test] async fn pi_cannot_access_erp() { /* GET /api/products → 403 */ }
#[test] async fn pi_cannot_access_hr() { /* GET /api/hr/attendance → 403 */ }
```

**R19-14 安全測試**：`backend/tests/api_invitations.rs`
```rust
#[test] async fn brute_force_token_rate_limited() { /* 10+ requests → 429 */ }
#[test] async fn expired_token_rejected() { /* 設定過期 → 400 */ }
#[test] async fn used_token_rejected() { /* 已 accept → 400 */ }
#[test] async fn revoked_token_rejected() { /* 已 revoke → 400 */ }
#[test] async fn invalid_token_404() { /* 不存在 → 404 */ }
```
</details>

---

## 🛡️ R22 — 攻擊偵測與主動告警（2026-04）

> 建立完整的入侵偵測管線：被動記錄 → 智慧告警 → 主動推送 → 長期可觀測性。
> 依據 Security Audit Report (2026-04-14) 偵測盲區分析，補齊 rate limit、403 權限拒絕、主動通知三大缺口。
> 參照：`docs/security/SECURITY_AUDIT_REPORT.md`、`docs/archive/compliance-reports/COMPLIANCE_DELIVERY_SUMMARY.md` §10

### 22-A 層 1：被動記錄 — 讓事後鑑識有資料（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R22-1 | **Rate limit 事件寫入 DB** | `middleware/rate_limiter.rs` 觸發時呼叫 `AuditService::log_security_event()`，4 tier 全覆蓋 | [x] |
| R22-2 | **AI key rate limit 事件記錄** | `ai_auth.rs` deactivated/expired/rate_limited 三事件寫入 DB | [x] |
| R22-3 | **403 Permission denied 記錄** | `response_logger.rs` middleware 攔截 403 回應寫入 DB | [x] |
| R22-4 | **Account lockout 事件記錄** | `login.rs` lockout 觸發時寫入 DB | [x] |

### 22-B 層 2：智慧告警 — 自動產生 security_alerts（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R22-5 | **Auth rate limit 升級告警** | 同一 IP 超過閾值 → critical alert + 去重 + 主動通知 | [x] |
| R22-6 | **IDOR 探測偵測** | 同一 user 超過閾值 403 → critical alert + 去重 + 主動通知 | [x] |
| R22-7 | **Brute force alert 去重** | `check_brute_force()` 加 30 分鐘去重（同 `global_mass_login` 模式） | [x] |
| R22-8 | **告警閾值設定化** | `security_alert_config` 表 + `AlertThresholdService` 60s cache | [x] |

### 22-C 層 3：主動推送 — 即時通知管理者（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R22-9 | **通知管道抽象層** | `SecurityNotifier::dispatch()` 從 `security_notification_channels` 讀取啟用管道 | [x] |
| R22-10 | **Email 通知實作** | 複用現有 SMTP + HTML 模板，收件人從 channel config_json 讀取 | [x] |
| R22-11 | **LINE Notify 整合** | POST notify-api.line.me + `LINE_NOTIFY_TOKEN` env var | [x] |
| R22-12 | **Webhook 通用管道** | POST JSON payload 到 config_json.url，10s timeout | [x] |
| R22-13 | **排程掃描未處理告警** | `scheduler.rs` 每 6 小時掃描 open + >24h alert 重送通知 | [x] |

### 22-D 額外考量：可觀測性與蜜罐（P2）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R22-14 | **集中式 Log 收集評估** | `docs/r22-log-aggregation.md` — 推薦 Loki（Grafana 同 stack） | [x] |
| R22-15 | **Grafana 安全 Dashboard** | 待 Loki 部署後建立 LogQL dashboard（依賴 R22-14 Phase 2） | ⏸️ |
| R22-16 | **蜜罐端點（Honeypot）** | 6 個假端點（/.env, /wp-login.php 等），觸發 critical alert + 通知，回傳 404 | [x] |
| R22-17 | **Admin Audit 頁面 — 安全事件 Tab** | 前後端完成，11 種 event_type 篩選，SecurityEventsTab 元件 | [x] |
| R22-18 | **Docker log driver 設定** | `docker-compose.prod.yml` api log rotation 50m/5 + tag | [x] |

---

## 🎨 R23 — 全站 Table UI 一致性升級（2026-04）

> 以 ProductTable 為黃金標準，將全站 ~100 個 Table 元件統一至相同容器樣式、header 色彩、row 狀態、
> loading/empty 元件，以及 Tier A 頁面的 mobile card fallback。
> 所有顏色均使用 CSS Variable token，禁止硬編碼色彩。

### Batch 0 — DataTable 共用元件修正（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-0 | **DataTable 基礎樣式升級** | `data-table.tsx` container→`rounded-lg bg-card overflow-hidden [&>div]:overflow-x-hidden`；header→`bg-muted/50 hover:bg-muted/50` | [x] |

### Batch 1 — Master & Inventory Tables（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-1a | **PartnerTable 樣式升級** | container / header / row-states / mobile card | [x] |
| R23-1b | **DocumentTable 樣式升級** | container / table-fixed / header / 取消 doc→`bg-destructive/5` / mobile card | [x] |
| R23-1c | **BloodTestTemplateTable 升級** | container / 替換自製 SortIndicator→`SortableTableHead` / skeleton | [x] |
| R23-1d | **StockLedgerPage 升級** | container / header / skeleton | [x] |

### Batch 2 — Animals & Admin Core Tables（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-2a | **AnimalListTable 全面升級** | 移除 Card wrapper；containerRef / computeWidths（11 欄）；SortableTableHead；mobile AnimalCard | [x] |
| R23-2b | **UserTable 升級** | container / 替換 getSortIcon+button→SortableTableHead / 移除 bg-white | [x] |
| R23-2c | **AuditLogTable 升級** | container / header / skeleton | [x] |

### Batch 3 — Master Pages + Protocol Tabs（P2）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-3a | **BloodTest Pages 升級** | BloodTestPanelsPage / BloodTestPresetsPage | [x] |
| R23-3b | **WarehousesPage / ProtocolsPage / AnimalSourcesPage 升級** | Tier A full treatment | [x] |
| R23-3c | **Protocol Tabs 升級（5 files）** | AmendmentsTab / AttachmentsTab / CoEditorsTab / ReviewersTab / VersionsTab | [x] |

### Batch 4 — Admin Pages & Config Tabs（P2）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-4a | **Admin Tier A 頁面升級（4 files）** | InvitationsPage / ManagementReviewPage / ChangeControlPage / RiskRegisterPage | [x] |
| R23-4b | **Admin Config Tabs 升級（~8 files）** | DepartmentTab + AuditActivitiesTab + AuditAlertsTab + AuditSessionsTab + RoutingTable + QA 相關頁 | [x] |

### Batch 5 — Reports + HR Tables（P3）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-5a | **Reports 頁面 Table 升級（9 files）** | container / header / token-only row colors | [x] |
| R23-5b | **Reports Tab 元件升級（5 files）** | JournalEntries / TrialBalance / ProfitLoss / ApAging / ArAging | [x] |
| R23-5c | **HR Tables 升級（non-DataTable files）** | ConflictsTab / AttendanceHistoryTab 等 | [x] |

### Batch 6 — Animal Detail Tabs + 剩餘（P3）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R23-6a | **MyProjects / MyAmendments 升級** | Tier A full treatment | [x] |
| R23-6b | **Animal Detail Tabs 升級（8 tabs）** | BloodTestTab / ObservationsTab / WeightsTab / VaccinationsTab / SurgeriesTab / PathologyTab / PainAssessmentTab / VetRecommendationsTab | [x] |
| R23-6c | **Protocol content-section Tables** | PersonnelSection / CommentsTableView | [x] |

---

## 🛡️ R24 — Observability 補強與 IP-level Safety Gate（2026-04）

> 延伸 R22 攻擊偵測管線：補齊 4 項 gap（IP 自動封鎖 / 生產 Loki / Alertmanager infra 通知 / Grafana 安全 dashboard）。
> 盤點後確認 ipig_system 已有 80% observability 基礎（R22 完整攻擊偵測 + 4 種通知管道），本輪僅補剩餘缺口。
> 詳細計畫與決策紀錄：`docs/OBSERVABILITY_PLAN.md`
> 已作廢方案：獨立 dash 服務（`C:\System Coding\ipig-dashboard\DASH_SPEC.md`，保留作決策紀錄）

### 24-A IP-level Safety Gate（P0）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R24-1 | **IP blocklist + 自動封鎖 middleware** | `migrations/031_ip_blocklist.sql`（UUID+INET+partial unique index）；`middleware/ip_blocklist.rs` 掛於 `api_middleware_stack` 最外層（涵蓋 /api/v1 所有子路由；`/metrics`、`/api/health`、honeypot 於 /api/v1 外層 bypass）；來源 IP 復用 `middleware/real_ip.rs::extract_real_ip_with_trust`；整合 R22-6 IDOR probe（`response_logger.rs`）/ R22-5 auth ratelimit 升級（`rate_limiter.rs`）/ R22-16 honeypot → 自動封 IP；`/admin/audit/ip-blocklist` 路由 + AdminAuditPage 「IP 黑名單」Tab | [x] |

### 24-B 生產環境可觀測性（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R24-2 | **Loki + Promtail 生產部署** | `docker-compose.prod.yml` 新增 Loki + Promtail services（複用 `monitoring/promtail/config.yml`，加 relabel 只收 `ipig-(api\|web)`、加 `environment=prod` 靜態 label）；Loki 30d 保留（`storage.tsdb.retention.time` 需於 Loki config 設定，此輪用預設）；解鎖 R22-15 | [x] |

### 24-C 告警與儀表板（P2）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R24-3 | **Alertmanager infra 通知啟用** | `alertmanager.yml` default/critical receiver 改為 webhook → `http://api:3000/api/webhooks/alertmanager`（Bearer token 防護）；新增平檔 `handlers/alertmanager_webhook.rs`，轉 payload 為 `SecurityNotification` 呼叫 R22 `SecurityNotifier::dispatch()`；`Config::alertmanager_webhook_token` 從 env 讀取 | [x] |
| R24-4 | **Grafana security dashboard** | 新增 `deploy/grafana_security_dashboard.json`（6 panel：Alerts 時間線 / Active Blocklist / Top IPs / Login Anomaly / Honeypot Hits / 403 Rate via Loki）；`provisioning/datasources/loki.yml` + `postgres.yml` 新增；`migrations/032_grafana_readonly.sql` 建 `grafana_readonly` role + GRANT SELECT；`docker-compose.yml` Grafana 掛載新 dashboard JSON | [x] |

---

## 🔒 R25 — 安全基礎設施補強（2026-04-20）

> 延伸 E-系列安全審計：補齊 5 項 CI / infra / 監控層面的 gap。
> 來源：安全審計後續建議（N-1 ~ N-5）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R25-1 | **Trivy 容器掃描加入 CI** | 每次 build 掃 image CVE；現在只有 `cargo audit` 管 Rust 依賴，缺少 OS/base image 層級掃描；加入 `.github/workflows/` trivy-scan job，critical/high 自動 fail | [x] 已存在於 ci.yml:382-432 |
| R25-2 | **security.txt（RFC 9116）** | `/.well-known/security.txt` 提供漏洞回報聯絡管道；AI agent 與安全研究員標準查找點；可由 nginx 靜態服務或後端路由回傳 | [x] |
| R25-3 | **CSP report-uri 端點** | 目前 CSP 只攔截不回報；新增 `POST /api/v1/csp-report` 端點收集真實 XSS 嘗試，寫入 `security_alerts` 或獨立 log table | [x] |
| R25-4 | **Secret scanning in CI** | 加入 `git-secrets` 或 `truffleHog` 掃 commit，防止 API key / token 意外進版控；整合至 GitHub Actions pre-push 或 PR check | [x] gitleaks-action |
| R25-5 | **DB 查詢 statement timeout** | sqlx pool 有 `acquire_timeout`，但個別 query 沒有 statement timeout；長查詢可能打滿 pool；於 `DATABASE_URL` 加 `options=--statement_timeout%3D30000` 或在 pool 建立後執行 `SET statement_timeout` | [x] after_connect hook |

---

## 🔄 R26 — Service-driven Audit 重構延伸待辦（2026-04-21 審查報告產出）

> 對應 `docs/reviews/2026-04-21-rust-backend-review.md` 與 `plan-for-the-critical-validated-pebble.md`
> PR #1 INFRA 完成後發現的延伸優化項；主功能未壞，這些是「更穩健」升級。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R26-1 | **長 Scheduler job 升級為 `tokio::select!` 中斷式** | PR #177 完成：`monthly_report` / `db_analyze` / `calendar_sync` 等長 job 升級為 `tokio::select!` 中斷式；併同 `main.rs` shutdown grace period 與安全中斷點 | [x] |
| R26-2 | **HMAC chain 每日驗證 cron** | 完成：`services/audit_chain_verify.rs` + `scheduler.rs::register_audit_chain_verify_job`（每日 02:00 UTC）+ `SecurityNotifier::dispatch` 斷鏈告警；payload 大小限制（top 20 IDs）；`AUDIT_CHAIN_VERIFY_ACTIVE` env 旗標；3 單元測試 | [x] |
| R26-3 | **現有 handler 遷移至 `log_activity_tx`**（97 call sites / 27 handler 檔） | 完成：animals 49（PR #4a-4g）+ user 8 + product 7 + sku 5 + partner/warehouse/equipment 12 + role/ai/auth/hr 12 + 其他 ≈ 全部遷移；跨越 PR #156/162-184/188/191 共計 20+ 個 PR | [x] |
| R26-4 | **舊 `log_activity(&pool, ...)` 最終移除** | 完成：`AuditService::log_activity` 舊版已刪除；`compute_and_store_hmac` 舊版已合併；零 deprecated 警告（`cargo clippy --all-targets -- -D warnings` 綠燈） | [x] |
| R26-5 | **(已完成) migration 036 changed_fields 聯集修正** | 對應 PR #154：stored proc fallback 由 JSONB EXCEPT 改為 UNION + `IS DISTINCT FROM`，正確偵測「被刪除的 key」。 | [x] |
| R26-6 | **HMAC chain 版本化 + 儲存後雜湊** | PR #170 完成：新增 `user_activity_logs.hmac_version SMALLINT`（`1`=legacy string-concat、`2`=length-prefix canonical）；verifier 依 version 分流；DataDiff 的 changed_fields 避免 stored proc fallback 路徑 | [x] |
| R26-7 | **Dead code 11 處逐一 review & 清理** | 完成：PR #173 刪除 8 處真死碼；本次清理剩餘 3 處（`IdxfMeta.format_version` + `ManifestTable.columns` 改為 `_`-prefix serde rename；`QUARTERLY_OVERTIME_LIMIT` 移除未用法規常數）；services 模組樹零 `#[allow(dead_code)]` | [x] |
| R26-8 | **完整 `ProtocolService::change_status` Service-driven 重構** | PR #188 完成：`change_status_tx` 將 10+ DB 操作、numbering、4 helper fn（assign_primary_reviewer/assign_vet_reviewer/record_activity/PartnerService::create_tx）納入單一 tx；跨服務原子性已建立 | [x] |
| R26-9 | **Audit redact allowlist for medical entities** | PR #175 完成：`CareRecord` / `VetAdviceRecord` / `AnimalObservation` 等醫療自由文字 entity 明確標記 `AuditRedact` impl（空 impl 需文檔證明無敏感欄位） | [x] |
| R26-10 | **Vet advice upsert 並發安全 + SDD audit** | PR #174 完成：`delete_vet_advice_record` 加 FOR UPDATE 鎖定；upsert pattern 補 SELECT FOR UPDATE；完整 SDD audit | [x] |
| R26-11 | **IDOR service-layer authz** | PR #176 完成：handler 直接 SQL 檢查身份下沉到 service 層；`services/access.rs` 集中授權 helper | [x] |
| R26-12 | _（保留編號）_ | 規劃階段曾預留為「edge case 修補」，後續實際工作均歸入 R26-13/14；保留編號維持歷史軌跡 | [x] |
| R26-13 | **storage_location 庫存 upsert 原子性 + audit** | PR #197 完成：原 `INSERT ... ON CONFLICT DO UPDATE` 無 before snapshot；改為 SELECT FOR UPDATE + 顯式 INSERT/UPDATE 分支 + `log_activity_tx` 在同一 tx 寫 audit | [x] |
| R26-14 | **Audit redaction 對照文檔 + CI guard** | PR #198 完成：`docs/security/AUDIT_REDACTION.md` 對照表（明確 redact / default empty / 不進 diff / 不存在 entity 分類）+ `.github/workflows/ci.yml::audit-redaction-guard`（find + awk 掃 FromRow struct 含敏感欄位） | [x] |
| R26-15 | **auth/login + logout 事件補 audit log** | 2026-05-26 完成 PR #490：LOGIN_SUCCESS (User actor) / LOGIN_FAILED (Anonymous actor) / LOGOUT (User actor) 三個事件補入 `user_activity_logs`，使用 `log_activity_oneshot`，含 IP + UA RequestContext。HMAC chain Anonymous 用 SYSTEM_USER_ID 對齊 CLAUDE.md 規範 | [x] |

---

## 🔧 R27 — E2E 修復後的代碼品質改善（2026-04-24 全面代碼審查）

> 對應 PR #200、#201 E2E 測試修復後的全面代碼審查結果
> 優先級均為 LOW，無阻擋項，可後續漸進式改進

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R27-1 | **Dockerfile CMD 可讀性改善** | `frontend/Dockerfile:72` 超長 CMD（240+ 字元）可考慮提取為獨立 shell 腳本；當前功能正確但後續維護時更易理解。LOW。**已完成 PR #217 `d291c7d4`** — 抽到 `frontend/docker-entrypoint.sh` | [x] |
| R27-2 | **生環境 API_BACKEND_URL 驗證** | `frontend/Dockerfile:72` envsubst 應驗證 `${API_BACKEND_URL}` 非空，避免生成無效 nginx 配置；CI 環境由 docker-compose.test.yml 保證，生環境應加額外檢查。LOW。**已完成 PR #217 `d291c7d4`** — `docker-entrypoint.sh` 內 fail-fast 驗證 | [x] |
| R27-3 | **auth_middleware 函式拆分** | `backend/src/middleware/auth.rs` `auth_middleware` ~90+ 行（含註解），超過 ≤60 寬鬆上限。建議拆 `validate_jwt(state, token) -> Claims`（token 提取 + ES256 decode + audience/issuer + jti 黑名單）+ `load_permissions(state, claims) -> Vec<String>`（admin 旁路 + try_get_with single-flight + 錯誤映射）。來源：CodeRabbit PR #210 outside-diff Major。LOW。**已完成 PR #218 `4757d16a`** — `validate_jwt` (L132) + `load_permissions` (L172) 已抽出 | [x] |
| R27-4 | **middleware SQL 下放至 repository** | `backend/src/middleware/auth.rs` 內含 4-table JOIN（permissions JOIN role_permissions JOIN user_roles JOIN roles）+ `check_user_active_status` 的 SELECT，違反 CLAUDE.md 「Middleware 禁業務邏輯」「Repository 封裝 SQL」分層。建議移至 `repositories/user.rs`：`list_permission_codes_by_user` + `find_user_active_status_by_id`。同 SELECT 也能被 `services/access.rs` 復用。來源：CodeRabbit PR #210。LOW。**已完成 PR #218 `4757d16a`** — 兩 SQL 已搬到 `repositories/user.rs` | [x] |
| R27-5 | **permission_cache 觀測指標** | `backend/src/middleware/auth.rs` 的 moka cache 沒有 hit/miss/eviction 計數，無法判斷 capacity 10,000 是否足夠、TTL 5min 是否合適。建議在 `try_get_with` 包 wrapper 取 `entry_count()` / `weighted_size()` 並推到既有 `metrics_handle` (Prometheus)。來源：CodeRabbit PR #210。LOW。**已完成 PR #222 `822b6ac3`** — `ipig_permission_cache_requests_total{result, is_admin}` counter 已上 | [x] |
| R27-6 | **admin 路徑帳號狀態 cache** | `backend/src/middleware/auth.rs::check_user_active_status` 對 admin 每請求查 DB（admin 不走 perm cache）。雖 admin 數量小，但屬均勻優化機會：把 admin 也納入 `try_get_with`（cache 空 Vec），或單獨 `Cache<Uuid, ()>` 快取狀態檢查結果。來源：Gemini PR #210 Medium。LOW。**已完成 PR #218 `4757d16a`** — 所有使用者（含 admin）皆走 `try_get_with` single-flight | [x] |
| R27-7 | **amendment::classify 函式拆分** | `backend/src/services/amendment/workflow.rs::classify` ~111 行（>60 寬鬆上限）。Major 與 Minor 分支可拆 `classify_minor_with_signature_tx` + `classify_major_with_reviewers_tx`，主函式僅做驗證 + 分流。來源：CodeRabbit PR #205 outside-diff Major。LOW。**已完成 PR #220 `e91ae9b4`** — minor / major helper 已抽出，主函式 ~40 行 | [x] |
| R27-8 | **C2 R7 已獨立修補** | record_decision 終態守衛已由 PR #213 (`glp/c2-extra-decision-terminal-guard`) 處理，本項僅作紀錄追蹤；PR #213 合併後可關閉。LOW | [x] |
| R27-9 | **amendment record_decision 重複查 status** | `backend/src/services/amendment/workflow.rs::record_decision` 終態守衛 SELECT FOR UPDATE 已取得 `current_status`；隨後呼叫的 `check_all_decisions_tx` 內部又重新查一次（`get_by_id_raw` 等）。同 tx 內可省一次往返，把 `current_status` 作為參數傳進 `check_all_decisions_tx`。來源：Gemini PR #216 Medium。LOW。**已完成 PR #220 `e91ae9b4`** — `current_status` 已作為 param 傳入（L587） | [x] |
| R27-10 | **animal observation create handler 重複 get_by_id** | `backend/src/handlers/animal/observation.rs::create_animal_observation`（L109 + L139）對同一 animal 重複呼叫 `AnimalService::get_by_id`。可單次查詢後傳遞。來源：Gemini PR #216 Medium。LOW。**已完成 PR #221 `69024390`** — emergency + abnormal 兩條路徑共用單次 fetch | [x] |

---

## 🔍 R30 — 三軸 Code Review 後續（併發 / 操作日誌 / GLP 合規，2026-04-28）

> 來源：`docs/codeReviewFindings.md`（三 agent 平行掃描，已逐項以 codebase 驗證）。
> 三軸交叉最弱點為 `euthanasia` 模組 → 必須最先。階段順位 A → D → C → B → E+F → G → H → I（A 為 pattern 驗證 PR，做完必停）。

### A. Euthanasia 三軸補強（CRITICAL，pattern 驗證 PR，做完必停）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-1 | **`euthanasia.rs` 套 R26 pattern**：`pi_approve` (line 167) / `pi_appeal` (line 217) / `chair_decide` (line 312) 改為 `tx + SELECT … FOR UPDATE + version 樂觀鎖` | 已實作：三 fn 全部 `tx + FOR UPDATE`（services/euthanasia.rs:269/490/628）含 `R30-A` 標註 | [x] |
| R30-2 | **`euthanasia.rs` 補 audit-in-tx** | 已實作：`AuditService::log_activity_tx` 出現於 line 126/302/436/578/709，3 fn 全覆蓋 | [x] |
| R30-3 | euthanasia 通知改 outbox 或同 tx 寫入 | PR-A + PR-B 完成：(A) [`docs/design/r30-3-event-outbox.md`](design/r30-3-event-outbox.md) + migration 050 event_outbox + `services/outbox/` 模組 + `bin/outbox_worker.rs` + `Dockerfile.outbox-worker` + docker-compose service。(B) `EuthanasiaService::approve_timeout_order_tx`/`_appeal_tx` 抽 service fn — UPDATE + audit + in-app notification + email outbox 四件事同 tx；`check_expired_orders` 收斂為 thin loop；`NotificationService::create_notification_tx` 加 _tx 變體；`utils::html_escape::html_escape_minimal` 通用 helper；開發者指南 [`docs/dev/notification-and-outbox.md`](dev/notification-and-outbox.md) | [x] |
| R30-4 | **euthanasia 高敏感操作（execute / appeal）強制簽章** | 已實作：`SignatureService::sign_record_tx` 於 line 321/596/727 三 fn 全覆蓋 | [x] |

### B. Protocol body lost update（HIGH）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-5 | **`services/protocol/core.rs:343-399` UPDATE 加 version optimistic lock** | 已實作：core.rs:390-440 `FOR UPDATE` + `version = version + 1` + `AND version = $6` 守門 | [x] |
| R30-6 | **前端 mutation 統一帶 version** | 已實作：`types/aup.ts:178-180`、`types/animal.ts:449-450`、`types/amendment.ts:81-83/106-108` 三 interface 皆有 `version?: number` | [x] |

### C. 簽章系統升級 §11.200（CRITICAL，每個子 PR 後必停）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-7 | **`signature_data` 改 HMAC-SHA256 + 集中密鑰** | 已實作：`signature/mod.rs:184-221` v2 HMAC-SHA256（`HmacSha256::new_from_slice`）+ 共用 `AUDIT_HMAC_KEY`，缺 key 時 fail loud | [x] |
| ~~R30-8~~ | ~~`sign_record` 強制 2FA（密碼 + TOTP）~~ | **使用者決定跳過 (2026-04-28)**：admin 已強制 TOTP（R26-1）；簽章流程已支援密碼+手寫雙因子；本機構非 FDA submission 等級，§11.300 single-factor 即足夠。現況聲明於 traceability matrix。 | ✅ accepted as-is |
| R30-9 | **`electronic_signatures` 加入 audit chain + invalidate 寫 audit** | **完成**：R30-9a chain hash v3 + sig fingerprint（PR #308 merged）；R30-9b invalidate handler / route / UI / 權限（migration 052 + InvalidateSignatureDialog） | [x] |
| R30-10 | **`signatures.meaning TEXT NOT NULL`** | 已實作：migration `043_signature_meaning.sql` 加入 `signature_meaning` ENUM + `electronic_signatures.meaning` 欄（§11.50(a)(3)） | [x] |

### D. Audit log 顯示與匯出（MEDIUM，稽核可見度高）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-11 | **`handlers/audit.rs:169` CSV 時區改 GMT+8** | 已實作：handlers/audit.rs:179 `with_timezone(&tz_taipei)` + header 加 `(Asia/Taipei)` 標註 | [x] |
| R30-12 | **CSV 匯出補 before/after + changed_fields 欄位** | 已實作：handlers/audit.rs:171-173 CSV header 已含「變更欄位 / 變更前 / 變更後」3 欄 | [x] |
| R30-13 | **前端 diff 顯示 key-by-key + highlight `changed_fields`** | 已實作：`ActivityLogDetailDialog.tsx:40` `highlighted` 標旗 + line 100 `ring-1 ring-status-warning-text/40` 強調 changed_fields；line 262 元件接 `changedFields` prop | [x] |
| R30-14 | **Audit log 自由文字搜尋** | 已實作：`models/audit.rs:217-219` `pub query: Option<String>`（ILIKE entity/actor/event/ip） | [x] |
| ~~R30-15~~ | ~~`AuditLogTable` 套 container-queries / 卡片化~~ | **使用者決定跳過 (2026-04-28)**：audit log 是後台管理頁面，桌機使用為主；既有表格沒 truncate（符合偏好）；窄螢幕橫向卷軸影響微小，不阻擋業務。日後若有需要再開 backlog。 | ✅ accepted as-is |

### E. Soft-delete + retention + IDXF 補表（CRITICAL）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-16 | **blood_test_items append-only 修正流程** | 已實作 D3：migration 047 加 supersede 4 欄 + BEFORE UPDATE/DELETE triggers（GLP §11.10(c)/§11.70）；service `correct_item_with_reason` 含 BLOOD_TEST_ITEM_CORRECT audit；前端 `CorrectBloodTestItemDialog` + `BloodTestItemHistoryDialog`。Panel/preset join table 為純 M:N 關聯保留 hard DELETE，PANEL_TEMPLATE_CHANGE audit 移至 R30-41 backlog | [x] |
| R30-17 | **新增跨表 retention policy 表 + 排程** | 已實作：migration `044_data_retention_policies.sql` 建表 | [x] |
| R30-18 | **IDXF 漏 19 表補齊 + 覆蓋率測試** | 已實作：`data_export.rs:235-240` `INTENTIONALLY_EXCLUDED_TABLES` + line 544-556 覆蓋率測試「migration 中有表未列入 EXPORT_TABLE_ORDER 也未列入 EXCLUDED 即 fail」 | [x] |
| R30-19 | **`data_export.rs::include_audit` 預設改 true** | 已實作：`data_export.rs:36 include_audit: true` | [x] |

### F. Append-only DB 防護（HIGH，與 E 同 PR 為佳）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-20 | **`user_activity_logs` 補 BEFORE DELETE trigger** | 已實作：migration `041_audit_signature_immutability_triggers.sql:22-39` BEFORE DELETE trigger | [x] |
| R30-21 | **`electronic_signatures` 加 immutability trigger** | 已實作：migration `041_audit_signature_immutability_triggers.sql:47-99` BEFORE UPDATE + BEFORE DELETE 雙 trigger | [x] |

### G. IQ/PQ + 變更控制（HIGH）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-22 | **`/api/internal/version` endpoint** | 已實作：`handlers/version.rs::get_internal_version` + `routes/admin.rs:13-14` 掛載 `/admin/internal/version`（admin-only JWT） | [x] |
| R30-23 | **`startup/config_check.rs` production fail-fast** | 已實作：`main.rs:96-104` config_warn_count > 0 && is_production() → exit(1)；config_check.rs 改回傳 warn_count 由 caller 決定 | [x] |
| R30-24 | **啟動 schema/role/permission self-test** | 已實作：`startup/db_self_test.rs` 全檔（system_user / SYSTEM_ADMIN+GUEST role / permissions 非空 / 關鍵 column 存在）+ `main.rs:111-122` production fail-fast | [x] |
| R30-25 | **amendment 加 `EFFECTIVE` 終態 + `effective_from`** | 25a schema-only PR #292 已 merged；25b/c workflow + UI 完成：service `mark_effective` (tx + FOR UPDATE + 守 APPROVED/ADMIN_APPROVED + 守 effective_from IS NULL + audit-in-tx HMAC chain + status_history)、handler `POST /amendments/:id/effective`（沿用 `aup.protocol.change_status` 權限）、AmendmentsTab 加「標記生效」按鈕 + effective_from 顯示 + window.confirm guard。Tests: cargo check / clippy / test --lib 444 passed / tsc / eslint 全綠 | [x] |
| R30-26 | **migration `down.sql` 模板** | 已實作：`backend/migrations/down/` 目錄 + README.md 模板，新 migration（041~046）均附對應 down 檔 | [x] |
| R30-27a | **role/permission 變更簽章（backend + flag）** | service create/update/delete 加 `require_signature` + `MutationSignaturePayload`；`config.role_signature_required` 預設 false；密碼 + 手寫雙因子（sign_record_tx）；canonical_role_content 含 op/code/perms hash 防 create↔update 重放 | [x] |
| R30-27b | **role/permission 簽章 frontend dialog** | `RoleSignatureDialog`（密碼 + handwriting canvas）+ `useSystemFeatures` hook + `GET /api/v1/system/features` 端點；create / update / delete 三流程依 flag 條件開 dialog；prod 切 ROLE_SIGNATURE_REQUIRED=true 才 enforce | [x] |
| R30-27c-1 | **手寫簽 phone bridge backend** | migration 047 `signature_bridge_sessions` 表（5min TTL + 單次使用 token）+ 4 endpoints (start auth / status auth / consume auth / submit public token-bearer)；session 在 owner-only + token-bearer 雙重保護下傳遞 payload | [x] |
| R30-27c-2 | **手寫簽 phone bridge frontend** | 已實作：(1) `lib/api/system.ts` 加 4 個 bridge API（start / status / consume / public submit）；(2) `pages/sign/MobileSignPage.tsx` 公開頁 `/sign/:id?token=...&purpose=...`，密碼 + 手寫 → public submit；(3) `RoleSignatureDialog` 加「桌機簽 / 手機簽」切換 — 進入手機模式自動 startBridge → 顯示 QR (qrcode.react) + 純文字 fallback URL → 2s 輪詢 status，COMPLETED 時 consume payload 自動 onSubmit；(4) `RolesPage` 推導 `purpose` (role.create/update/delete) 傳入 dialog；(5) `App.tsx` 掛 `/sign/:id` 公開路由 + publicPaths 加 `/sign`。Tests: tsc / eslint 全綠 | [x] |
| R30-28 | **`config.audit_chain_verify_active` production 預設改 true** | 已實作：`config.rs:313 parse_bool_env_default_true("AUDIT_CHAIN_VERIFY_ACTIVE")` | [x] |

### H. 漏 audit 路徑補齊（MEDIUM）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-29 | **`services/protocol/core.rs::create / update` 補 audit** | 已實作：core.rs:391 `R30-29: tx + FOR UPDATE before snapshot + audit-in-tx + 完整 before/after diff` | [x] |
| R30-30 | **`handlers/animal/sudden_death.rs` 補 audit** | 已實作：依 R26 service-driven pattern，audit 收進 `services/animal/medical.rs:482` `AuditService::log_activity_tx`（SUDDEN_DEATH，tx 內 + animal 狀態變更同 tx）；handler line 38 已加註說明 | [x] |
| R30-31 | **accounting 全路徑補 audit** | 已實作：services/accounting.rs grep `log_activity` 命中 2 處 | [x] |
| R30-32 | **`services/animal/import_export.rs` 補 audit（service-driven 一致性）** | 已實作：services/animal/import_export.rs grep `log_activity` 命中 2 處 | [x] |
| R30-33 | **`services/animal/vet_patrol.rs` 接 `log_activity_tx`** | 已實作：services/animal/vet_patrol.rs grep `log_activity` 命中 3 處 | [x] |

### I. GLP 文件補完（DOCUMENTATION，可平行 code 階段）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-34 | **`docs/glp/traceability-matrix.md`** | 已實作：`docs/glp/traceability-matrix.md` 已建立 | [x] |
| R30-35 | **AmendmentStatus mermaid 流程圖 + IACUC SOP 對齊** | 已實作：`docs/glp/amendment-sop.md` 已建立 | [x] |
| R30-36 | **GLP record-lock 5 表選擇理由文件化** | 已實作：`docs/glp/record-lock-rationale.md` 已建立 | [x] |
| R30-37 | **HMAC chain 斷鏈處理 runbook** | 已實作：`docs/runbooks/audit-chain-broken-runbook.md`（GLP §11.10(e) 完整性告警 OnCall SOP，含值班處理紀錄表 §6） | [x] |
| R30-38 | **DR drill 年度演練紀錄表** | 已實作：`docs/runbooks/dr-drill-records.md` 已建立 | [x] |
| R30-39 | **`training` 模組與 §11.10(i) 訓練紀錄 SOP 對照** | 已實作：`docs/glp/training-records-sop.md` 已建立 | [x] |

### J. R29 follow-up（從 PR #258 衍生）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R30-40 | **R29-5b：v4 deprecated class rename codemod** | 已實作：原 67 處 → 0；最後 1 處 `flex-shrink-0` → `shrink-0`（`DataExportImportCard.tsx:192`） | [x] |
| R30-41 | **panel/preset template 變更 audit 補齊**（R30-16 follow-up） | 已實作：`services/animal/blood_test.rs` 兩處 join table 重設前後快照成員清單，發 `PANEL_TEMPLATE_CHANGE` audit：(1) `update_blood_test_template` 當帶 `panel_id` 時 snapshot 該 template 的 panel_ids before/after；(2) `update_blood_test_panel_items` snapshot 該 panel 的 template_ids before/after（取代原 PANEL_UPDATE empty diff）。新增 `PanelMembershipSnapshot` / `TemplateMembershipSnapshot` 兩個 audit-only struct + `AuditRedact` impl。Tests: cargo check / clippy --lib --all-targets / cargo test --lib 444 passed | [x] |
| R30-42 | **動物/計劃書/藥物批號/人員/QA/SOP 紀錄改永久保留**（R30-17 follow-up）| migration 048：32 表 UPDATE delete_strategy='never'（動物業務 14 + 試劑批號 3 + 人員 6 + 供應商 1 + QA 4 + SOP/文件控管 4），並補 animal_blood_test_items / animal_sudden_deaths 兩筆新 policy。原 044 「全 20 年」依據 OECD §8 最低條文解，對異種器官移植研究機構不合用；並消除 animal_blood_tests retention cascade 撞 047 trigger 的風險。維持 20 年純營運：設備 / 設施 / 環境 / 管理 / Audit / 邀請 / 倉位 / 一般文件 / 帳務 / 通知 / AI 查詢 | [x] |

### R30 風險與停機規則
- **R30-1~4 完成後必停**：使用者驗證 euthanasia 三軸 pattern 可複製
- **R30-7~10 簽章每個子 PR 後必停**：21 CFR §11 屬高風險不可逆改動
- **R30-16~19 soft-delete schema 變更前必停**：DB schema 不可逆
- **R30-20~21 immutability trigger 於 staging 先測一輪再推 production**

### R30 預估

- 9 階段 + R29 follow-up = 40 項，總預估 125-177 小時（約 4-6 週全職）。

---

## 📄 R32 — PDF 生成重做（2026-04-30）

> **背景**：當前兩條 PDF 路徑都根本性地壞 ——
> (1) 後端 `backend/src/services/pdf/service.rs`（1,236 行 `printpdf` 手刻）：`render_paragraph` 用 `chars.chunks(45)` 硬切字元、`render_table_row` 用 `text.chars().take(max_chars - 1) + "…"` 硬截斷儲存格、無 widow/orphan 控制、無 `section header + 內容` 跨頁綁定、無 page header/footer/頁碼；
> (2) 前端 `useProtocolPdfExport.ts` fallback：`html2canvas` 把 DOM 拍成點陣圖塞 jsPDF，**文字變成圖片**（無法 Ctrl+F、無法 OCR、無法被 GLP 稽核工具解析、檔案 1-2MB/頁、放大字級會糊）。
>
> **目標**：對齊業界主流（Stripe / Shopify / HubSpot / Notion / Linear / FDA 法規文件全採用），用 **HTML+CSS Paged Media 透過瀏覽器排版引擎產 PDF**，砍掉 1,236 行手刻 + 前端 `html2canvas` fallback。

### A. 已敲定決策（2026-04-30）

| # | 決策 | 結論 | 含意 |
|---|---|---|---|
| R32-D1 | 階段策略 | **(b) 兩階段** — 階段 1 print stylesheet + Ctrl+P；階段 2 headless Chromium | 階段 1 立即止血；print stylesheet 不算白做（階段 2 直接複用） |
| R32-D2 | 自動化需求 | **暫時不做，但保留架構空間** | 階段 1 暫不需要 headless；架構設計**不可阻斷**未來導入路徑（前端頁面要支援 `?print=1` query param、避免依賴 user session 才能渲染、style 不依 hover/viewport） |
| R32-D3 | 範圍 | **4 種報表**：(1) Protocol AUP 計畫書、(2) 病歷資料（Animal observations / treatments / weights / vaccinations / blood test / pain）、(3) 手術資料彙整（Surgeries / Sacrifice / Pathology）、(4) Audit log | 階段 1 全部做 print stylesheet；階段 2 全部走 headless |
| R32-D4 | Headless Chromium hosting（階段 2 才用）| **(b) 獨立 chrome service container** | 隔離好（chrome 崩潰不影響 backend）+ 資源獨立調 memory；多一個容器但值得 |
| R32-D5 | GLP 永久存證 | **(c) 完整方案**：PDF 存 attachments + audit log + HMAC hash + 整合 `electronic_signatures.meaning`（21 CFR §11.50）| 影響 schema 與 endpoint 設計；階段 2 才上線（階段 1 純 client-side 列印無 server-side artifact） |
| R32-D6 | 分頁痛點優先級 | **(e) 全部都痛** | print stylesheet 一次設好：表格 / 孤行 / section header / 中英混排全部處理 |

### B. 業界方案對比（決策參考）

| 選項 | 機制 | 重做工程量 | 排版品質 | 一鍵下載 | 自動化 | Docker +size | 文字可搜尋 |
|---|---|---|---|---|---|---|---|
| **A. Headless Chromium** (`chromiumoxide` / `puppeteer`) | Rust 後端啟 chrome → loadURL(前端 view?print=1) → `Page.printToPDF` | 中（2-4 週）| ⭐⭐⭐⭐⭐ | ✅ | ✅ | +200MB | ✅ |
| **B. WeasyPrint Python service** | 多開 Python 容器，HTML+CSS Paged Media → PDF | 中 | ⭐⭐⭐⭐ | ✅ | ✅ | +80MB | ✅ |
| **C. Typst CLI subprocess** | 重寫所有模板為 Typst markup | **大**（全部模板重寫）| ⭐⭐⭐⭐⭐ | ✅ | ✅ | +10MB | ✅ |
| **D. 前端 print stylesheet + Ctrl+P** | 加 `@media print` CSS + `@page` rules，使用者按列印另存 | 小（1-2 週）| ⭐⭐⭐⭐ | ❌ 要 Ctrl+P | ❌ | 0 | ✅ |
| **E. 改良 printpdf** | 抽 layout DSL（wrap_text / paginate / table）| 大 | ⭐⭐ | ✅ | ✅ | 0 | ✅ |
| 現況 1（printpdf 手刻 1,236 行）| — | — | ⭐ | ✅ | ✅ | 0 | ✅ |
| 現況 2（html2canvas → jsPDF）| — | — | ⭐ | ✅ | ❌ | 0 | **✗ 圖片**|

**業界主流**：A（Stripe / Shopify / HubSpot / Notion / Linear / 大多數 FDA 法規文件 platform）。

**對 GLP 合規 + 已有 React 前端 + 小團隊維護的脈絡**：建議排序 **A > D > C > B > E**。

### C. 任務分解（v3 — 2026-05-03 校正後）

> **重大轉向**（2026-05-03）：從 HTML→PDF 路徑（CSS Paged Media / chromiumoxide / Gotenberg）整體轉向 **docx template fill + LibreOffice headless**。
>
> 三件決策性事實：
> 1. 使用者**不在乎** Web ↔ PDF 同源（接受雙軌維護）
> 2. **需要即時頁碼計算 + 自訂分頁演算法**（Word 是 word processor 本職，HTML 解法在邊角不穩）
> 3. **字型授權閃避**（OS 字型 + Word 渲染 = 免標楷體 / Times 商業授權）
>
> **R32-2 ~ R32-15 v1/v2 任務全部 obsolete**。新計畫見下方 R32-A1 ~ R32-A9。詳見 [`qa/r32-pdf-baseline.md` §9](qa/r32-pdf-baseline.md)。

#### 既有任務（v3 obsolete 清單，保留歷史）

> **目標**：使用者按 Ctrl+P 即可印出排版正確的 PDF。零後端改動、零新依賴、零部署風險。
> **架構守則（為階段 2 留路）**：列印渲染**不依賴 hover state**；接受 `?print=1` query param（強制展開折疊 / 收起 sidebar）；不依 viewport size 切換內容。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R32-1 | **盤點所有 PDF 生成入口 + 現況痛點 + v3 校正計畫** | 已產出 `docs/r32-pdf-baseline.md`（260+ 行）— 4 條既有路徑（printpdf 手刻 / html2canvas / Gotenberg+HTML format / pdf-service Jinja2）全部不盡人意；2026-04-30 v2 校正計畫 + 2026-05-03 v3 計畫（docx template fill）| [x] |
| R32-2 | **Print stylesheet baseline (`frontend/src/styles/print.css`)** | `@page { size: A4; margin: 20mm }` + `@media print { ... }` 全域：(a) 隱藏 nav/sidebar/topbar/floating actions；(b) `orphans: 3; widows: 3`；(c) `h1,h2,h3 { page-break-after: avoid; break-after: avoid-page }`；(d) `table { page-break-inside: avoid; break-inside: avoid }`；(e) `tr { page-break-inside: avoid }`；(f) `word-break: keep-all; overflow-wrap: break-word`（中英混排）；(g) `* { print-color-adjust: exact; -webkit-print-color-adjust: exact }`（保留 status badge 顏色）。整合進 `App.tsx` 一次 import | [~] v3 obsolete |
| R32-3 | **`?print=1` query param 機制**（為階段 2 鋪路）| `usePrintMode()` hook：(a) 自動展開所有 collapsible section；(b) 隱藏 dialog/popover/tooltip；(c) 隱藏 search bar/filter chips（已套用值改顯示為 metadata 區塊）；(d) sidebar 預設收起；(e) 強制 light theme（避免 dark mode 印出深底浪費墨）。同時供使用者手動列印（無 query）也能取得相近效果 | [~] v3 obsolete |
| R32-4 | **Protocol 頁 print 樣式** | `pages/protocols/ProtocolDetailPage.tsx` + 9 個 Tab 元件：每 section（資金來源/PI/sponsor/第 1~N 節）`page-break-inside: avoid`；表格 `page-break-inside: avoid`；附件清單頁碼引用；首頁加封面 metadata（標題/計畫編號/產出時間/列印者） | [~] v3 obsolete |
| R32-5 | **病歷資料 print 樣式** | Animal detail 各 Tab（Observations / Treatments / Weights / Vaccinations / BloodTest / Pain / Personnel / Reviewers / Attachments）— 每筆紀錄 `page-break-inside: avoid`；每 Tab 強制 `page-break-before: always`；連續多筆同類紀錄不拆 | [~] v3 obsolete |
| R32-6 | **手術彙整 print 樣式** | `SurgeriesTab.tsx` + `SacrificeFormDialog` + `PathologyTab` + `AmendmentsTab` — 手術步驟序列保整段；簽名 SVG (`dangerouslySetInnerHTML` + `sanitizeSvg`) print friendly（黑白可讀）；安樂死資料節錄附 `electronic_signatures.meaning`（21 CFR §11.50） | [~] v3 obsolete |
| R32-7 | **Audit log print 樣式** | `pages/admin/audit/...`（含 `useAuditLogExport.ts`）— 表格 `thead { display: table-header-group }`（跨頁重複表頭）；每頁印頁碼；列印區段加篩選條件 metadata（時間範圍/actor/event_type） | [~] v3 obsolete |
| R32-8 | **回歸驗證（階段 1）** | D3 4 種報表各跑 5 個 baseline 樣本（含跨頁/大表格/中英混排）→ Ctrl+P 另存 PDF → 人工比對。**接受標準**：(1) 文字可 Ctrl+F；(2) 表格無切半；(3) section header 無孤立；(4) 中英混排不錯位；(5) 簽章 SVG 黑白可辨識。產出 `docs/r32-stage1-validation.md` | [~] v3 obsolete |
| R32-9 | **使用者教學文件** | `docs/USER_GUIDE.md` 新增「列印報表」章節：哪些頁支援列印 / Ctrl+P 操作步驟 / 紙張方向 / 印章與簽名注意事項 | [~] v3 obsolete |

#### v3 計畫任務（R32-A1 ~ R32-A9，~3-4 週全職）

> **架構**：React detail page（web 原生 UI 不變）→ 按「預覽 PDF / 下載 docx / 下載 PDF」按鈕 → Backend Rust 蒐集資料 → Python `pdf-service`（docxtpl fill `templates/*.docx`）→ LibreOffice headless（docx → pdf）→ 回 binary。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R32-A1 | **Python service 重寫**（`pdf-service`） | docxtpl + python-docx 已實裝；DOCX_REGISTRY entries: aup_protocol, medical_record, surgery, review_result, review_reply（部分尚未 wire 到 backend handler，見 A8e/A8h）。Jinja2 HTML REGISTRY 仍剩 blood_test（A8h 範本未做） | [x] |
| R32-A2 | **docx → pdf 透過 Gotenberg LibreOffice**（架構優化）| **不**自裝 LibreOffice — 改呼叫既有 `gotenberg/forms/libreoffice/convert` endpoint。零新依賴、零容器膨脹、與既有 html_to_pdf 路徑對稱。`docx_renderer.docx_to_pdf(bytes, filename)` 包 httpx POST | [x] |
| R32-A2b | **Gotenberg 中文字型** | 自建 image `services/gotenberg/Dockerfile` FROM gotenberg/gotenberg:8 加 Noto CJK TC + AR PL UMing/UKai 開源明楷 + Liberation 英文 + fc-cache；docker-compose `build:` 改 `image: ipig-gotenberg-cjk:8`；驗證 AUP / patrol PDF 嵌入 NotoSansCJKtc + 無 `.notdef`。已知限制：標楷體 mapping 待 fontconfig alias、xlsx 用了 sc subset（後續微調）| [x] |
| R32-A3 | **Templates 變數化 + wire-up + Word fidelity** | 把 `templates/*.docx` 改成 docxtpl 變數格式：(1) AUP 計畫書、(2) 病歷總表、(4) 手術紀錄表、(5) audit log + vet_patrol xlsx（R32-A3b 130 pens 含 F01-F06 zone）。每份產出搭配 `schemas/<doc_type>.py` Pydantic schema。完成內容：infra（templatize.py 4 passes + lock_template.py + size_overrides + 巢狀 table 遞迴 + nested tbl/permStart 修正）+ 6 docx schema/mapping + vet_patrol xlsx + smoke_real_data DB→render + AUP 字體對齊（標楷體 / Times New Roman / 大標前換頁 / TOC field 偵測）+ end-to-end wiring（pdf-service adapters + DOCX/XLSX_REGISTRY + backend handlers + frontend buttons）+ Word COM daemon 100% Word-fidelity PDF（services/word-convert/ + token auth + readiness probe + COM 自癒 + WORD_CONVERT_DOC_PASSWORD 解鎖受保護 docx）+ 5 docx 鎖密碼 433789 + vet/QA 視覺驗證 5 docx + xlsx F zone 完成 + 多輪 bot review 採納（gemini 3 + coderabbit 9+11+8 條 quick wins）| [x] |
| R32-A4 | **Backend Rust handler** | 已實裝（aup/medical/surgery/review_result/project_medical 全 wire-up 完成；audit-log 範本已備但無現成匯出 endpoint，見 A8i）| [x] |
| R32-A5 | **Frontend 預覽 / 下載 UI** | AUP `PdfExportButtons` 預覽 + 下載 docx/PDF；vet_patrol PDF 預覽 dialog；surgery 下載 PDF 圖示按鈕；project_medical / medical_record 走既有 ExportDialog | [x] |
| R32-A6 | **GLP 永久存證**（D5 = c）| `pdf_artifacts` 表 schema migration + 產 PDF 後寫此表 + `attachments` + `user_activity_logs` + 整合 `electronic_signatures.meaning` 已完成（PR #318）| [x] |
| R32-A7 | **砍舊路徑** | **完成**（PR #341 + #343 merged 2026-05-07）：砍 `services/pdf/{service.rs, context.rs, mod.rs}` ~1450 行 + `printpdf` Cargo dep + `pdf-service/app/templates/{blood_test.html, _base.css}` Jinja2 路徑 + `backend/resources/fonts/NotoSansSC-Regular.ttf` 17MB 字型。`gotenberg.html_to_pdf` 殘餘呼叫等 A8f / A8h（外部 blocker）才能砍 | [x] |
| R32-A8a | **medical_record v3 wire-up** | 單動物病歷 PDF（v3 docx → Word COM）；handler `pdf_export.rs::export_animal_medical_pdf` 從 Gotenberg HTML 改 v3；adapter 翻譯 enum + 合併 timeline + 格式化 | [x] |
| R32-A8b | **surgery v3 wire-up** | 手術紀錄 PDF；新 endpoint `GET /surgeries/:id/export-pdf-v3`；handler + service aggregator + adapter（vital_signs JSONB 展開 + pain_assessments from care_medication_records）| [x] |
| R32-A8c | **review_result v3 wire-up** | 審核結果 PDF（召集人手寫簽名）；handler 改 v3；adapter 將 review_comments 依 stage 彙整入 revision_opinions | [x] |
| R32-A8d | **project_medical v3 wire-up** | N 動物 → 1 合併 PDF（pypdf merge）；pdf-service 新 endpoint；兩個 handler 分支（pdf_export + import_export）都改 v3。同步刪 `export_protocol_pdf` legacy v1 + project_medical / medical_record Tera 模板 | [x] |
| R32-A8e | **review_reply v3 wire-up** | 範本 templates/review_reply.docx + schema (secretary_items + 12-dimension vet_review + committee_1~4) + adapter (`pdf-service/app/adapters/review_reply.py`) + service aggregator (`services/protocol/review.rs::get_review_reply_export_data` ~190 行；helper：fetch_review_comments / extract_review_metadata / build_vet_review_items / build_secretary_items / build_committee_items 含一審+二審 reviewer × item_no 配對) + handler `export_review_comments` + frontend `CommentsTab.tsx` 下載 button 全部到位（PR #332 落地）；legacy 250 行 Tera 路徑已移除 | [x] |
| R32-A8f | **vet_patrol_report HTML→docx** | **2026-05-10 拆出到 R39**。原假設「等 vet/QA 加變數」已過時 — `templates/vet_patrol.docx` 16 個 docxtpl placeholder 已加好（companion / vet_name / patrol_date_display / categories loop / photos batch(2)）。剩下純 wire-up 工作，獨立成 R39 章節追蹤。 | [→ R39] |
| R32-A8g | **warehouse v3** | **完成**（PR #341 merged 2026-05-07）：8 欄明細表（儲位代碼/儲位名稱/產品名稱/規格/批號/數量/單位/效期，per-row code/name 不合併）+ Pillow PNG 平面圖（粗體+CJK/ASCII 空格+矩形 wrap+水平置中+200mm）+ 結構配色對齊前端 LayoutDiagram + 砍`services/pdf/service.rs` 1450 行 + `printpdf` dep（PR #343 final purge） | [x] |
| R32-A8h | **blood_test docx** | **完成**（PR #341 merged 2026-05-07）：6 欄 per-item flat（檢查日期/項目/檢驗值/參考值/異常/建立者）+ schema/adapter + DOCX_REGISTRY + `/render-blood-test` endpoint + 新 service `list_blood_test_export_rows`（INNER JOIN 含 R30-16 superseded filter）+ handler cutover + frontend `BloodTestTab.tsx`「下載 PDF」按鈕。HTML REGISTRY 與 blood_test.html 已隨 PR #343 砍 | [x] |
| R32-A8i | **audit_log PDF 匯出** | **完成**（PR `feat/r32-a8i-audit-log-pdf`，2026-05-07）：admin audit logs 頁面「匯出 PDF」按鈕從 client-side HTML+window.print() 改 backend `/admin/audit/activities/export-pdf` (docxtpl audit_log.docx + Word COM/Gotenberg LibreOffice)；新增 pdf-service adapter + endpoint + service client method + handler `export_activity_logs_pdf` + payload assembler `build_audit_log_payload` (counts user/admin/failure)，與其他 R32 報表架構一致 | [x] |
| R32-A8j | **export_protocol_pdf_v2 → v3 cutover** | **完成**（PR `feat/r32-a8gh-warehouse-blood-test-docx`，2026-05-07）：frontend `useProtocolPdfExport` 切 `/export-aup-v3?format=pdf`；砍 v2 handler (264 行) + 3 個 translate_ helpers (84 行) + route + `protocol.html` / `partials/header.html` / `partials/footer.html` Tera 模板 + `utils/pdf_pages.rs` + `lopdf` Cargo dep。client-side html2canvas+jsPDF fallback 也移除 | [x] |
| R32-A8 | **回歸驗證 + GLP 合規驗證** | 4 種報表 × 3 樣本 → 預覽 + 下載 + 比對 templates 範本；GLP 維度：PDF/A 合規、metadata、HMAC chain 驗證、字型完整性。本地驗證（`scripts/validate_pdfs.py` AUP+patrol 字型+size+無 .notdef = ✅）+ Word COM PDF 含 DFKaiShu-SB-Estd-BF（真標楷體）+ 5 docx 鎖密碼 + `docs/r32-validation.md` 報告完成 + vet/QA 視覺驗證所有範本通過。User 選擇 skip staging，直接於正式環境（ipigsystem.asia cloudflare tunnel）測試 — 4 報表×3 樣本 + GLP HMAC 由實務操作中觀察 | [x] |
| R32-A9 | **使用者教學文件** | `docs/USER_GUIDE.md` 新建（含 PDF 匯出章節：操作、簽章、字型、FAQ）+ 新建 `docs/dev/docx-template-guide.md`（給工程師 / vet / QA 學 docxtpl 變數語法 + Pydantic schema 對應規則 + Backend Rust handler 範例 + R32-A2b 中文字型方案） | [x] |

#### 階段 2 — Headless Chromium service（v3 obsolete，保留歷史）

> **觸發條件**：D2 改成「需要自動化」（scheduler / API 下載 / email 附 PDF / GLP 存證）。階段 1 完成後保留以下任務在 backlog。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R32-10 | **獨立 chrome service container** | 新增 `services/chrome/` 容器，base image **釘選版本** `browserless/chromium:1.62-chrome-stable`（避免 `:latest` 無預警更新破壞 CI 重現性）或自建（`--no-sandbox --disable-gpu --disable-dev-shm-usage --font-render-hinting=none`）；docker-compose 加 service；資源限制 `memory: 1G cpu: 0.5`；Dependabot watch 此 image 與 `chromiumoxide` crate | [~] v3 obsolete |
| R32-11 | **Backend chromiumoxide 整合** | `Cargo.toml` 加 `chromiumoxide` + `tokio` feature；新 module `services/pdf_v3/`；client 透過 CDP 連到 chrome container；error handling（chrome 崩潰自動重連） | [~] v3 obsolete |
| R32-12 | **Service token 機制（system-pdf-render）+ audit 區分** | `middleware/auth.rs` 加新 token 類型；TTL 5 分鐘、scope = `pdf:read:protocol/animal/surgery/audit:<id>`；對應 `ActorContext::System { reason: "pdf-render" }`；不能用於 mutation。**Audit 區分**（GLP 對齊）：(a) **使用者發起的匯出請求** = 主匯出事件，必寫 `user_activity_logs`（event_type = `PDF_EXPORT_REQUESTED`，actor = User）；(b) **headless chromium 對 backend 的內部資源請求**（list animals / fetch protocol body）= 不寫 audit（避免渲染洪水汙染 audit chain）。token 內帶 parent request UUID，後端用此判斷免重複 audit | [~] v3 obsolete |
| R32-13 | **新 endpoint `/api/v1/{資源}/:id/export-pdf-v3`** | 4 個 endpoint（protocol / animal-medical / surgery-summary / audit-log）；流程：產生 service token → 透過 CDP `Network.setExtraHTTPHeaders` 把 token 放 `Authorization: Bearer ...` header（**禁止**放 query string，避免洩漏到 nginx access log）→ call chrome service `Page.printToPDF` with internal URL `http://frontend:8080/{資源}/:id?print=1`（用 docker service name，不是 `https://internal`）→ 回 binary。**Token 不出現在任何 URL / query / referrer header** | [~] v3 obsolete |
| R32-14 | **GLP 永久存證 (D5 = c)** | schema migration 新增 `pdf_artifacts` 表（id / resource_type / resource_id / pdf_blob_hash / generated_by / generated_at / electronic_signature_id FK / hmac_chain_link）；產 PDF 後寫此表 + `attachments` + `user_activity_logs` + 整合 `electronic_signatures.meaning`（21 CFR §11.50「I confirm this PDF represents the official record at time of export」） | [~] v1/v2 → R32-A6 |
| R32-15 | **砍舊路徑** | 階段 2 staging 驗證一週後：刪 `backend/src/services/pdf/service.rs`（1,236 行）+ 移除 `printpdf` / `lopdf` 依賴；刪 `useProtocolPdfExport.ts::exportFromClient` html2canvas fallback + 移除 `html2canvas` / `jspdf` npm 依賴；保留新版 `useExportPdf` 只呼後端 v3 endpoint | [~] v1/v2 → R32-A7 |

### R32 風險與停機規則

- **R32-1 盤點完成後必停**：若發現意料外的 PDF 入口（PROGRESS.md / scheduled jobs / email template），先回報補進範圍
- **階段 1 完成必停**：等使用者實際用一週、收集回饋，再決定 D2 是否升級進階段 2
- **R32-10 PoC（chrome container 跑得起來、能渲染中文字型）必停**：headless chromium 在 docker 的 shm size / font loading / zombie process 問題多，PoC 不過關不繼續
- **R32-14 schema migration 必停**：跨 PR 邊界 + DB schema 變更 + GLP 合規路徑（依 CLAUDE.md 高風險分流）
- **R32-15 砍舊路徑必停**：等 staging + 1 週實際使用驗證才刪

### R32 預估

| 階段 | 任務 | 預估 |
|---|---|---|
| ~~階段 1（v1/v2）~~ | ~~R32-1 ~ R32-9~~ | **v3 obsolete** — 詳見 [qa/r32-pdf-baseline.md §9](qa/r32-pdf-baseline.md) |
| ~~階段 2（v1/v2）~~ | ~~R32-10 ~ R32-15~~ | **v3 obsolete** |
| **v3 主線**（2026-05-03 校正後）| R32-1 完成 + R32-A1 ~ R32-A9（9 項）| **~3-4 週全職**（docx template fill + Gotenberg LibreOffice） |
| **總計（v3）** | **9 項** + 已完成 R32-1 | **~3-4 週全職** |

**v3 vs v1/v2 工程量比較**：v1 5-7 週 → v2 4.5-5.5 週（含字型授權）→ **v3 3-4 週**（templates 已存在 + 字型問題消失 + 不做 print stylesheet）

### R32 對應 memory

- `feedback_no_table_truncate.md`：表格儲存格禁止 truncate — 現況 `printpdf` `chars.take(max_chars - 1) + "…"` 直接違反；R32-2 改用 `word-break / overflow-wrap`
- `feedback_dev_tooling_html.md`：視覺探索主動製作 HTML 工具 — R32-2/4/5/6/7 過程做 print preview HTML 工具方便試 page-break / orphans / 中英混排

---

## 🔒 R33 — 滲透測試 follow-up（2026-05-06）

> **背景**：2026-05-06 daily mode CSO 4 findings（guest_guard middleware / fail-closed webhook / ct-eq tokens / pdf-service token check）已 merge（PR #337）。後續 comprehensive mode 5 條 TENTATIVE 提醒，全部 LOW/INFO 級，列入此 backlog 視排程處理。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R33-1 | **CSRF middleware 改讀 `extensions::<CurrentUser>()`** | 目前 `middleware/csrf.rs:61-70` 自解 JWT payload 取 `sub`（不驗簽章）。Defense-in-depth 改用 auth middleware 已驗過的 CurrentUser，避免未來 layer 順序錯亂時出現可被忽略的 trust gap。Confidence 6/10，雙層防禦下不可利用 | [x] 2026-05-14 PR #393 |
| R33-2 | **AI client `reqwest::Client` 共用** | `services/protocol/ai_review.rs:328` 每次審查 `Client::new()` — TLS handshake 浪費。改 `OnceLock<Client>` 或放 AppState。**性能 finding，非安全**（PR #339 merged 2026-05-07） | [x] |
| R33-3 | **CSP report endpoint 限流加固** | `routes/mod.rs:131` `/api/v1/csp-report` 未認證、僅 api rate limiter 保護。可灌 audit log。Handler 入口加 16KB body cap，超過 drop + warn log（仍回 204 per CSP 規範）（PR #339 merged 2026-05-07） | [x] |
| R33-4 | **JWT access-token 短 expiration A/B 測試** | ~~目前 360 分鐘（6h）偏長。建議 staging 試 60min access + 7d refresh~~ → 2026-05-16 PR #428 直接落地 15min（比原提案 60min 更短，NIST AAL2 對齊），配合 sliding session 五部曲 UX 無影響 | [x] 2026-05-16 PR #428 |
| R33-5 | **Audit HMAC key 輪換路徑文件化**（accepted risk） | 已有 `hmac_version` 欄位（R26-6）保留未來路徑；GLP 21 CFR §11 合規下 key 換代意味歷史紀錄無法 verify — trade-off 已記入 `docs/security/HMAC_VERSIONING.md`，無代碼動作，僅追蹤 | [accepted] |

---

## 🔧 R34 — Codebase 50 項技術債分批清理（2026-05-07）

> **背景**：2026-05-07 進行 backend / frontend / pdf-service 三層 codebase audit 共 50 項候選。逐項辯證後 TAKE 23 / LEAVE 18 / DEFER 9（詳見 [`PROGRESS.md` §9 2026-05-07](PROGRESS.md#9-最新變更動態)）。本 R34 將 22 落地 TAKE 排成 6 個 PR（R34-7 後續 push back 為 SKIP，故有 22 而非 23）+ 9 DEFER 條觸發條件追蹤。
>
> **設計原則**：
> 1. **R26 service-driven pattern 對齊** — handler IDOR / 權限 / 內嵌 SQL 統一下沉 service（PR A 是 R26 模式延伸）。
> 2. **跨 PR 邊界必停**（依 CLAUDE.md「執行紀律」）— 每 PR 完成 cargo test + commit 後停下，由使用者批 push / merge。
> 3. **Surgical Changes** — 每個 hunk 都對應 R34-N，不順手刪 dead code（DEFER #18 排到 R27 cleanup sprint）。
> 4. **i18n / 風格一致性** — backend 中文錯誤訊息對齊（amendment 模組 memory 規範），frontend 不破壞既有 design token。
>
> **總工程量估**：22 TAKE × 平均 1-2h = **~30-40h** 全職；分 6 PR × 跨 ~3 週逐 PR 推進（與 R32 / R33 follow-up 並行）。

### R34 PR 規劃（6 個）

#### 📦 PR A — Backend handler service 化（高優先 / mid risk）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R34-1 | **HR dashboard SQL → `repositories/hr.rs`** | 新建 `repositories/hr.rs::find_attendance_stats`；handler ~30 行 → ~12 行；同步使用 `DEFAULT_TIMEZONE` | [x] |
| R34-2 | **Amendment is_pi → `AmendmentService::check_is_pi`** | `services/amendment/crud.rs` 新增 helper；handler 三處（create/update/submit）改用 service。query 用 runtime `query_scalar` 避開 SQLX_OFFLINE cache 重建 | [x] |
| R34-3 | **Amendment IDOR → `access::require_protocol_related_access`** | `get_amendment` 改 helper — 比原本只查 user_protocols 更廣（PI / co-PI / reviewer / vet_reviewer 全涵蓋），潛在 access fix | [x] |
| R34-4 | ~~**document handler IDOR 下沉 service**~~ | **SKIP**：`DocumentService::check_access` 已是 service pure fn，handler 兩步呼叫（fetch + check）是清楚分離。再合併屬過度抽象 | [skip] |
| R34-5 | **`unwrap_or(0.0)` → `Option<f64>`** | repositories/hr.rs SQL 移除 `COALESCE(SUM, 0)` 保留 NULL；`AttendanceStat.overtime_hours: Option<f64>`；handler serialize 為 JSON null | [x] |
| R34-6 | **amendment 中文錯誤訊息對齊** | 7 處英文 → 中文（create/update/submit PI 檢查 + get IDOR + start_review / decision / change_status / mark_effective 權限檢查） | [x] |

**PR A 邊界**：6 commits，動到 handlers + services + repositories；屬「動到 handlers / middleware / routes 層」分類 → 必須 `rtk cargo test --all-targets` 全綠；估 6-8h。

#### 📦 PR B — Backend infra / 一致性（低風險 easy wins）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R34-7 | ~~**PaginationQuery / PaginationParams 合併**~~ | **2026-05-07 push back → SKIP**：`PaginationQuery`（必選+預設 page=1/per_page=20）與 `PaginationParams`（雙 Optional，不給回全部）語義不同 — 前者用於強制分頁 endpoint，後者用於 backward-compat。合併會改行為。降級 LEAVE | [skip] |
| R34-8 | **`MAX_FILENAME_LENGTH=255` 補註解** | `utils/validation.rs:4` 加一行 `/// NTFS / ext4 / Linux NAME_MAX = 255`，避免未來人員誤改 | [x] |
| R34-9 | **trim → validate 順序文件化** | `utils/validation.rs` 模組層 `//!` doc 加 validate-after-trim 慣例（4 fn 行為盤點）；ear_tag 因 `parse::<u32>()` 自然拒絕空白；filename 反而禁止 trim（前後空白本身可疑）。不寫 helper（4 fn 行為差異不適合單一抽象） | [x] |
| R34-10 | **`AT TIME ZONE 'Asia/Taipei'` 常數化** | `handlers/hr/dashboard.rs:42` 改用既有 `constants::DEFAULT_TIMEZONE`（已存在於 line 47），format! 注入；DEFAULT_TIMEZONE 為 `&'static str` compile-time constant 無 SQL injection 風險 | [x] |

**PR B 邊界**：4 commits，純 infra / models / utils → `rtk cargo test --lib` 即可；估 2h。

#### 📦 PR C — Frontend Dashboard 重構（mid-high risk，使用者面）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R34-11 | **Dashboard 常數集中** | `BREAKPOINTS` / `COLS` 從 DashboardPage 移到 `components/dashboard/widgetConfig.ts` 為 `GRID_BREAKPOINTS` / `GRID_COLS_BY_BREAKPOINT`（與 GRID_ROW_HEIGHT、DEFAULT_DASHBOARD_LAYOUT 同檔，集中為單一 source） | [x] |
| R34-12 | **`hasErpPermission` 改 store selector** | DashboardPage 改用 `useAuthStore((s) => s.hasRole(...) \|\| ...)` 派生 selector — 只在 user.roles / permissions 真變動才重算，避免 last_login_at 等欄位 refresh 觸發整 dashboard re-render | [x] |
| R34-13 | ~~**DashboardPage JSX 拆元件**~~ | **SKIP**：實測 79 行（line 229-308）剛好低於 CLAUDE.md「JSX ≤ 80 行」門檻，未真正違規。renderWidget switch 35 行屬另類技術債，留 R34-15 後續批次處理 | [skip] |
| R34-14 | ~~**Widget 直接 `useAuthStore()`**~~ | **SKIP-NA**：grep 確認 7 widget 中只有 RoleWelcomeGuide 用 auth；其他 widget 不傳 auth props，沒有 prop drilling 可省 | [skip] |
| R34-15 | ~~**`AVAILABLE_WIDGETS` 陣列化**~~ | **DEFER**：完整 widget registry 需動 6 個 parallel maps（permissions/categories/names/descriptions/constraints/optionsConfig）+ renderWidget switch；單一 PR 風險 > 收益。改列 R34-D10 觸發條件：等下一個新 widget 提案時一併重構 | [defer] |
| R34-16 | **`availableWidgets` `useMemo` 化** | 驗證完成 — `DashboardPage.tsx` 既有 `availableWidgets`/`visibleWidgets` 已是 useMemo，無 unnecessary re-render（audit 觀察錯誤） | [x] |

**PR C 邊界**：6 commits，動到 frontend 核心頁面；不跑 `npm run build`（依 memory `feedback_no_prod_build`）— 改 vite dev + 手動 QA（`/qa` skill）+ Storybook 預覽；估 8-12h。

#### 📦 PR D — Frontend hooks 穩定化（低風險）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R34-17 | **`useListFilters` 回傳物件 `useMemo` 包穩** | `useListFilters.ts:43-58` 13 欄位 plain object 每 render 都新 reference；用 `useMemo` 穩 reference（deps：6 state + 2 stable callback） | [x] |
| R34-18 | ~~**`useListFilters.reset()` 提供**~~ | **已實作**：`resetFilters` 已存在於 `useListFilters.ts:35-41`，audit 觀察錯誤 | [skip] |
| R34-19 | ~~**`useSelection` `initialIds` 移除**~~ | **2026-05-07 push back → SKIP**：grep 證實只測試使用（5 處 `__tests__/hooks/useSelection.test.ts`）；移除需重寫 5 個 test，default `[]` 零成本，違反 CLAUDE.md §10「surgical changes」原則 | [skip] |

**PR D 邊界**：3 commits，純 hooks 改動，影響小；vite dev server 跑既有頁面不破即可；估 2h。

#### 📦 PR E — Auth Zustand persist 版本化（**高風險 / 必停 ask**）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R34-20 | **Zustand persist `version` + `migrate`** | `stores/auth.ts` 加 `version: 1` baseline + `migrate: (persisted, _version) => persisted` no-op；上方詳註下次 bump 流程（if version === 1 → transform）。**不 bump version**（依使用者裁定）— 範本已就位，下次 partialize shape 改動才實際升 version | [x] |

**PR E 邊界**：1 commit + 文件 + e2e test 模擬升級；**動到使用者持久化狀態 → 屬「不可逆操作」需使用者明確同意才 push**（依 CLAUDE.md「執行紀律」）；estimate 3h。先做 R34-20 範本但**不 bump version**，下一輪 AuthState 改動才實際 bump。

#### 📦 PR F — PDF service hardening（低-中風險）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R34-21 | **`DOCX_CONVERTER_TIMEOUT` env 化** | `pdf-service/app/main.py` 新增 `_get_word_convert_timeout()` 讀 env；`httpx.Timeout(connect=10, read=DOCX_CONVERTER_TIMEOUT)`；非數值 fallback 120 不 crash；同套用到 `_docx_to_pdf_word_first` + `_xlsx_to_pdf_excel_first` | [x] |
| R34-22 | **Word→Gotenberg fallback unit test** | 建立 pdf-service 測試 infra（`requirements-dev.txt` + `pytest.ini` + `tests/`）；新增 7 case：RequestError fallback / HTTPStatusError raise / 非 PDF magic raise / URL 空跳過 daemon / timeout default / custom env / invalid env fallback | [x] |

**PR F 邊界**：2 commits，pdf-service 獨立模組；docker compose pdf-service 重啟驗證 + pytest；估 2h。

### R34 DEFER 9 項追蹤（trigger conditions）

| # | DEFER 項目 | 觸發條件（何時 promote 進 backlog） |
|---|---|---|
| R34-D1 (#1) | 重複 DELETE/POST 路由別名 | grep 前端 `axios.post(.../delete)` / fetch POST 確認**無**呼叫端後才能刪；獨立 1 commit PR |
| R34-D2 (#5) | 權限檢查模式統一 `require_permission!` | 完成 PR A（觸及處已對齊）後盤點剩餘 ~20 處手寫；分 R34 後續或 R35 批次處理 |
| R34-D3 (#18) | `cargo machete` / dead_code 清理 | 列入 R27 cleanup sprint backlog；對齊 CLAUDE.md §10「任務無關 dead code 不順手刪」 |
| R34-D4 (#20) | `get_animal_info_from_observation/_from_surgery` 合併 | 先實測 record_type enum 分支是否讓 SQL 更醜（兩 table 結構差異）；不醜才合 |
| R34-D5 (#23) | 共用 `ErrorResponse` JSON 形狀 | 先 grep 統計 `serde_json::json!({...})` 在 handler 的所有出現；超過 5 處不同 shape 才動 |
| R34-D6 (#26) | Auth store 拆 slice | 跑 React Profiler 確認 auth 變動觸發大量 re-render 才動；目前 baseline 未測 |
| R34-D7 (#44) | Zustand selector ESLint 規則 | PR C 完成後（觸及處已 selector 化）盤點：若仍有 ≥10 處全店訂閱才寫 ESLint custom rule |
| R34-D8 (#46) | Jinja2 環境集中 `app/templates.py` | 三 renderer (renderer.py / docx_renderer.py / xlsx_renderer.py) template 路徑與 filter 集合 diff；交集 ≥80% 才合併 |
| R34-D9 (#49) | `PdfConversionError(code, message)` | 等真出現需要分類錯誤的場景（前端要區分 timeout / template / convert / unknown）才動；目前 RuntimeError → FastAPI 自動 500 已夠 |
| R34-D10 (R34-15) | Dashboard `AVAILABLE_WIDGETS` 陣列化 | 等下一個新 widget 加入時一併重構：合併 6 parallel maps（permissions/categories/names/descriptions/constraints/optionsConfig）+ 取代 renderWidget switch；現一次重構需要一個工作天，與 widget 增加時的天然重做契機合併更划算 |
| R34-D11 (coderabbit) | `ROLE_REVIEWER` 從 `VIEW_ALL_ROLES` 移除 | system-wide policy question — `services/access.rs:30` `VIEW_ALL_ROLES` 含 `ROLE_REVIEWER`，意味任何 reviewer 角色經 `has_protocol_view_all` 旁路 5 個 access helper（不只 amendment）。產品確認語義後再做：是否所有 reviewer 應 view-all（IACUC oversight 角色定位）或僅指派時可見（assignment-based）。**R34-3 沿用此既有 helper，未引入新行為**，只是讓 amendment 也受影響 |
| R34-D12 (coderabbit) | `AmendmentService::require_pi_or_admin` helper 抽取 | 3 個 amendment handler（create/update/submit）有相同 `is_admin\|\|check_is_pi` + Forbidden 訊息差動詞。抽 helper 受 CLAUDE.md「handler 禁含條件式權限判斷」鼓勵，但目前 3 行條件 + 中文訊息可讀性 OK，refactor 為 helper 沒有 behavior change，列為 cleanup 而非 fix |
| R34-D13 (coderabbit) | `list_staff_for_proxy` / `list_internal_users_for_balance` SQL 下沉 repo | `handlers/hr/dashboard.rs:86-153` 2 個 fn 仍含 inline `sqlx::query_as`；`list_internal_users_for_balance` 的 admin 排除條件與 `list_attendance_stats_by_date_range` 重複。R34-1 only 處理 `get_attendance_stats`，未動到這兩個（本 PR 範圍外）。下個 HR 改動順手做 |
| R34-D14 (coderabbit) | `ADMIN_EMAIL` / `ROLE_SYSTEM_ADMIN` / `ROLE_ADMIN` 常數抽取 | `repositories/hr.rs` + `handlers/hr/dashboard.rs:list_internal_users_for_balance` 共有 `'admin@ipigsystem.asia'` / `'SYSTEM_ADMIN'` / `'admin'` 散落。CLAUDE.md「魔術字串必須 const」要求集中至 `crate::constants` 並改 bind 參數注入。需配合 D13 一起做 |
| R34-D15 (coderabbit) | `auth.ts persist migrate` 加 Zod safeParse | `stores/auth.ts:275` migrate 直接回 persisted；CLAUDE.md「驗證統一用 Zod schema」要求 — 但 `lib/validation.ts` 目前無 `authPersistedSchema`。先建 schema → 再 migrate validate → 失敗 fallback safe default。下個 auth 改動順手做 |
| R34-D16 (coderabbit, R33 scope) | `csp_report` body limit 路由層套 | `csp_report_handler` 收 `body: Bytes` 已被全域 30MB limit 緩衝，handler 內 16KB 檢查只能擋 JSON parse 不能擋記憶體。應在 `routes/mod.rs` csp_report 路由套 `DefaultBodyLimit::max(CSP_REPORT_MAX_BYTES)`。**屬 R33-3 follow-up，非 R34 scope** |

### R34 風險與停機規則

- **跨 PR 邊界必停**：每 PR commit 完停下，等使用者批 push / merge
- **PR A 屬 handler 層**：`rtk cargo test --all-targets` 全綠才 commit；需本地 Postgres
- **PR B 屬 infra 層**：`rtk cargo test --lib` 綠燈即可
- **PR C 屬使用者面 frontend**：vite dev server 手測 + `/qa` skill；**禁止跑 `npm run build`**（memory `feedback_no_prod_build`）
- **PR E 高風險**：persist version bump 等同強制使用者重登；**push 前必須使用者明確 OK**
- **DEFER trigger 達標**：promote 為新 R34-N 條目，不是直接做

### R34 預估

| PR | 項目數 | 工時估 | 風險 | 測試需求 |
|---|---|---|---|---|
| PR A — handler service 化 | 6 | 6-8h | mid | cargo test --all-targets |
| PR B — infra 一致性 | 4 | 2h | low | cargo test --lib |
| PR C — Dashboard 重構 | 6 | 8-12h | mid-high | vite dev + /qa |
| PR D — hooks 穩定化 | 3 | 2h | low | vite dev |
| PR E — Auth persist version | 1 | 3h | **high** | e2e + 使用者 ack |
| PR F — pdf-service hardening | 2 | 2h | low-mid | pytest + docker restart |
| **總計** | **22** | **23-29h** | — | — |

### R34 對應 memory

- `feedback_no_unwrap_or_on_db_queries.md` → R34-5
- `feedback_no_sql_in_handlers.md` → R34-1, R34-2, R34-3
- `user_timezone_gmt8.md` → R34-10
- `feedback_no_prod_build.md` → PR C/D 測試方式
- `feedback_integration_branch_strategy.md` → 6 PR 是否走 `integration/r34` 長期分支待確認（取決於使用者偏好）

---

## 🔐 R37 — `.env` 明文密碼遷移到 Docker Secrets（2026-05-09）

> 來源：2026-05-09 R36 設定過程中審視 `.env`，發現 9 處明文密碼/token 殘留。違反 `feedback_no_plaintext_passwords.md` 規則。
>
> **背景**：codebase 早已實作 `read_secret()`（`backend/src/config.rs:47`）支援 `<NAME>_FILE` 路徑模式，但 `.env` 內仍多項以明文存。
>
> **執行門檻**：每筆獨立 PR；最高優先 R37-1 (HMAC) ≤ 1 週內完成，其他 ≤ 1 個月內收斂。

### R37-A. Critical（HMAC chain 完整性）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R37-1 | 🔴 **AUDIT_HMAC_KEY → secret file** | **2026-05-09 完成**：建 `secrets/audit_hmac_key.txt`（同值，無 chain 中斷風險）+ compose top-level secret + api `AUDIT_HMAC_KEY_FILE` env + .env 移除明文。`config.rs:317` 既有 `read_secret()` 直接生效。 | [x] |

### R37-B. High（admin / smtp 密碼）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R37-2 | 🟠 **ADMIN_INITIAL_PASSWORD → secret file** | **2026-05-09 完成**：建 `secrets/admin_initial_password.txt` + compose top-level secret + api `ADMIN_INITIAL_PASSWORD_FILE` env + .env 移除明文。`config.rs:345` 既有 `read_secret()` 直接生效。 | [x] |
| R37-3 | 🟠 **GRAFANA_ADMIN_PASSWORD → __FILE** | **2026-05-09 完成**：Grafana 原生支援 `GF_SECURITY_ADMIN_PASSWORD__FILE`（不需動 grafana.ini）。建 `secrets/grafana_admin_password.txt` + grafana volume mount + 改 compose env。**⚠️ 沿用舊 `admin123` 弱密碼，後續手動輪換為強密碼**（編輯該檔 → 重啟 grafana → 更新 Bitwarden）。 | [x] |
| R37-4 | 🟠 **GRAFANA_SMTP_PASSWORD + ALERT_SMTP_PASSWORD → secret file** | **2026-05-09 完成**：發現實際運作架構已是 Plan B（Grafana 用 `GF_SMTP_PASSWORD__FILE` 從 `secrets/grafana_smtp_password.txt` 讀；Alertmanager `docker-entrypoint.sh` 從 `/run/secrets/alert_smtp_password` 讀）。`.env:113/121` 為 vestigial 死代碼從未被讀取。已撤銷該死代碼 Gmail app password (`tajr azwc pmac lyxs`)，並從 `.env` 移除兩行，留註解標明真實 secret 路徑。 | [x] |

### R37-C. Medium（service-to-service tokens）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R37-5 | 🟡 **IMAGE_PROCESSOR_TOKEN → secret file** | **2026-05-09 完成**：`image-processor/src/config.js` 加 `readSecret()` helper（Node.js 版 _FILE pattern）；建 `secrets/image_processor_token.txt`；compose api + image-processor 兩端 mount + `IMAGE_PROCESSOR_TOKEN_FILE` env。 | [x] |
| R37-6 | 🟡 **PDF_SERVICE_TOKEN → secret file** | **2026-05-09 完成**：`pdf-service/app/config.py` 加 `_read_secret()` helper（Python 版 _FILE pattern）；建 `secrets/pdf_service_token.txt`；compose api + pdf-service 兩端 mount + `PDF_SERVICE_TOKEN_FILE` env。 | [x] |
| R37-7 | 🟡 **ALERTMANAGER_WEBHOOK_TOKEN → secret file + 加 `_FILE` 支援** | **2026-05-09 完成**：`config.rs:367` 從 `env::var()` 改 `read_secret()`；建 `secrets/alertmanager_webhook_token.txt`（已存在）+ compose top-level secret + api `ALERTMANAGER_WEBHOOK_TOKEN_FILE` env + .env 移除明文。 | [x] |
| R37-8 | 🟡 **WORD_CONVERT_TOKEN → secret file** | **2026-05-09 拆分到 R38**：使用者回報 PDF 字體 / 格式不符合既有 docx 範本，需把 Word daemon 變主路徑（取代 Gotenberg）。原本只 token 搬家不夠，整個 Word daemon 啟用是基礎建設變更 → 升格為 R38 章節。R38-4 包含原 R37-8 token 搬家。 | [→ R38-4] |

### R37-D. Low / cleanup

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R37-9 | 🟢 **GUEST_PASSWORD 直接刪** | **2026-05-09 完成**：刪 `.env:80` `GUEST_PASSWORD=guest`；順便整個 `seed` service 從 `docker-compose.yml` 移除（GUEST role 已棄用，create_guest 必然 silent fail，浪費啟動資源）。Guest 已轉型為 demo 功能，不再透過此 seed 路徑。 | [x] |
| R37-10 | 🟢 **`.env.example` 對齊** | **2026-05-09 完成**：5 處改 commented-out 並指向 `secrets/<name>.txt` 檔案 + 對應 `_FILE` env + 連結 `secrets-management.md`。修了 ADMIN_INITIAL_PASSWORD / AUDIT_HMAC_KEY / PDF_SERVICE_TOKEN / GRAFANA_ADMIN_PASSWORD / ALERTMANAGER_WEBHOOK_TOKEN。 | [x] |
| R37-11 | 🟢 **runbook**: `docs/runbooks/secrets-management.md` | **2026-05-09 完成**（PR #362 review follow-up）：完整盤點 16 個 secret 檔（既有 11 + R37 新增 5）+ 11-step fresh deploy SOP + 輪換週期表 + 外洩撤銷流程 + 三語讀取機制對照。 | [x] |
| R37-12 | 🟡 **image-processor 死代碼移除（不是修 token gap）** | **2026-05-09 完成（選項 A）**：grep 全 `backend/src/handlers/` 確認 0 處呼叫 `image_processor.process()` → 整個服務是 dead code。執行 cleanup：移除 docker-compose service / 砍 `image-processor/` 整個目錄 / 刪 `services/image_processor.rs` / 從 AppState/lib.rs/main.rs 移除欄位 / config.rs 刪 image_processor_url / 刪 secret 檔。Cargo check + clippy 全綠。YAGNI — 真要圖片處理時再加。`system_settings.rs::REDACTED_SETTING_KEYS` 保留 `image_processor_token` 條目作 audit log 歷史保護。 | [x] |

### R37 對應 memory

- `feedback_no_plaintext_passwords.md` → **本輪整輪的執行依據**
- `project_guest_role_deprecated.md` → R37-9 直接刪而非遷移

### R37 風險與停機規則

- **R37-1 是 critical 必先做**：HMAC key 洩漏的時間窗越短越好，建議 1 週內完成 + 同時輪替（產新 key、`secrets/audit_hmac_key.txt` 寫新值、舊 audit 已用舊 key 簽過所以保留，新 audit 從此用新 key）。輪替方式可參考 `docs/security/HMAC_VERSIONING.md`。
- **R37-4 必先撤銷舊 Gmail app password 再做遷移**：因 token 已在 `.env` 待過數週，必須假設已外洩。Gmail 帳號 → app passwords → revoke → generate new → 寫入 secret。
- **R37 全部完成後**：`.env` 內應只剩**非機密**的設定（host / port / 開關 flag / GPS 座標等）。

---

## 📄 R38 — Word COM Daemon 取代 Gotenberg 主路徑（2026-05-09 立案）

> 來源：使用者回報 PDF 字體 / 格式不符合既有 docx 範本（Gotenberg LibreOffice 渲染與 Word 原生渲染存在差異），R37-8 review 過程中決定升格為獨立章節。
>
> **目標**：把 docx → PDF 主路徑從 Gotenberg LibreOffice 改為 Windows Word COM daemon，達到與 Word 原生開檔相同的字體 / 排版保真度。Gotenberg 降為 fallback。
>
> **非目標**（已釐清不可行）：Docker 啟動 Word daemon — Word COM 是 Windows-only API，需要 Word 安裝 + Windows desktop session，無法在 Linux container 跑。**daemon 必須是 host process**。

### R38-A. 設計階段（先做，必須有 design doc 才動 code）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R38-1 | **Design doc**: `docs/plans/word_daemon_takeover.md` | **2026-05-10 完成**。重大發現：R32-A3 收尾時 daemon 程式碼 + install script + pdf-service fallback 已**全部實作完成**，使用者抱怨的原因是 **daemon 沒在 prod host 上跑**（沒人執行 install_service.ps1）。Doc 改寫為 4-Phase activation plan：A 跑起來 / B observability / C token 遷移 / D 範本驗證。 | [x] |
| R38-2 | **抓現況**：盤點現有 Word daemon | **2026-05-10 完成**（design doc §2）：`services/word-convert/server.py` 302 行成熟 daemon（Word + Excel + COM error recovery + pre-warm + 受密碼保護 docx 解鎖）。 | [x] |
| R38-3 | **使用者決策點**：lifecycle 模式 | **2026-05-10 完成**（design doc 採既有 lifecycle = always-on daemon + lazy Word + COM error recovery，無需改設計）。 | [x] |

### R38-B. 實作階段（依 design doc 4 Phase）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R38-A1 | **Phase A — Daemon Activation**（**這個解使用者抱怨，Day 1 必做**）| **2026-05-10 完成**：daemon 跑起來在 Windows host（Word 16.0），Task Scheduler `ipig-word-convert` state=Running，token 同步 `secrets/word_convert_token.txt` (64 hex chars) + `.env WORD_CONVERT_TOKEN`，pdf-service 容器驗證可達 daemon (`docker exec ... urllib.request` health check 回 200)。順便強化 `install_service.ps1`：自動從 `secrets/word_convert_token.txt` 讀 token 寫進 task env（不用每次手動 export）；R37-9 orphan seed container 也順手清掉。 | [x] |
| R38-B1 | **Phase B — Observability** | **2026-05-10 完成**：`metrics.py` 加 `pdf_path_used_total{path,doc_format}` counter + main.py 在所有 success / fallback 路徑 inc。Prometheus 加 `PdfDaemonFallbackHigh` (>10% 1h, warning) + `PdfDaemonFallbackCritical` (>50% 15m, critical) alert rules。daemon silent fallback 從此可觀察。 | [x] |
| R38-D1 | **Phase D — Font Validation** | **2026-05-10 infra 完成 + R38 章節 wrap up**：`docs/runbooks/word_daemon_validation.md` 5 章 SOP；`scripts/r38_validation/run_batch.py` 批次跑器；9 份 fixture + 18 份 PDF（`output/{word,gotenberg}/`）已產出。剩視覺評分屬日常 QA 工作流，非 R38 工程任務 → 標為 deferred ad-hoc。Prod daemon 自上線 fallback rate 0%（Prometheus 觀察），daemon 路徑可信。任何具體範本顯示異常時再回頭做局部視覺比對 + 修範本。 | [→ ad-hoc] |
| R38-C1 | **Phase C — Token Secret Migration（原 R37-8）**| **2026-05-10 完成**：`pdf-service/app/config.py` 加 `word_convert_token: str = _read_secret("WORD_CONVERT_TOKEN")`；compose pdf-service 加 `word_convert_token` secret + `WORD_CONVERT_TOKEN_FILE` env，移除明文 `WORD_CONVERT_TOKEN`；top-level secrets 加 `word_convert_token: file: ./secrets/word_convert_token.txt`；`.env` 移除明文。host install_service.ps1 已從 R38-A1 起讀同一個檔，兩端值保證一致。 | [x] |
| R38-9 | **Runbook 補強**：troubleshooting + validation SOP | **2026-05-10 完成**：`services/word-convert/README.md` Troubleshooting 章涵蓋 R38-A1 實際遇到的所有問題（fail-closed token / access denied / cmd window / health 503 / fallback rate 高 / 重新部署 SOP）；新增 `docs/runbooks/word_daemon_validation.md` 5 章字體驗證 SOP（R38-D1 用）。 | [x] |
| ~~R38-5~~ | ~~daemon 程式碼強化~~ | **2026-05-10 廢案**：`server.py` 已成熟（pre-warm / COM error recovery / token / 受密碼保護 docx 全有），不需動。R38-D1 範本驗證若發現 bug 才回頭改。 | [-] |
| ~~R38-6~~ | ~~Windows Service 安裝腳本~~ | **2026-05-10 廢案**：`install_service.ps1` 已存在（Task Scheduler 登入觸發 + 失敗重啟）。 | [-] |
| ~~R38-7~~ | ~~pdf-service fallback gating~~ | **2026-05-10 廢案**：`_docx_to_pdf_word_first` 已實作（connection error → fallback / HTTP 4xx-5xx → raise）。 | [-] |

### R38 風險與停機規則

- **R38-1 design doc 必先**：daemon lifecycle 影響整個架構，沒 design 直接做 = 重做風險高。
- **R38-4 R37-8 token 必須跟 daemon 啟用同步**：daemon 都還沒接通就先動 token = 無意義改動。
- **R38-8 字體驗證必須跑完所有既有範本**：不能只測一兩份範例。每份範本實際資料 + 邊界 case（長表格、CJK 字、特殊符號）都要驗。
- **Fallback 必須保留**：daemon 隨時可能 host crash / Word update 升級不相容 / 授權過期，pdf-service 必須能自動降級到 Gotenberg。

### R38 對應 memory

- `feedback_no_plaintext_passwords.md` → R38-4 `secrets/word_convert_token.txt`
- `vet_patrol-template-locked` / `vet_patrol-docx-locked` → R38-8 既有範本不可動，只能驗證渲染結果

### R38 與 R37 關係

R37-8 原本是 R37 secrets migration 的一部分，但實作過程中發現「Word daemon 啟用」是基礎建設變更，遠超 secret 搬家範圍。**R37-8 拆分**：
- 「token 改 secret file」部分 → 改 R38-4（與 daemon 啟用同步上線）
- 「Word daemon 啟用」原始設計 → 升格為 R38 整章

---

## 🛡️ R41 — NICS 資通系統防護基準合規 gap（2026-05-11 立案）

> **來源**：對照行政院《資通安全責任等級分級辦法》附表十 + NICS RFP 範本附件1。詳見 `docs/security/NICS_COMPLIANCE_AUDIT_2026-05.md`。
> **實施計畫**：`docs/plans/r41_nics_compliance.md`（Phase A 文件 / B SAST / C 後端，估計 ~10.5h，4 PR）。
> **自評等級**：以「普級」為基準（單人筆電研究室系統，無法定遵循義務）。普級已達 ~92%，本輪 backlog 補完 4 個 PARTIAL 即達標。
> **不追項目**：SOC 24x7 / FIPS 140-2 / RTO 8h 熱備援 / 委外條款 — 均對 solo 系統 over-spec。
> **下次複查**：2026-11-11（半年一次）

| # | 項目 | 說明 | 對應構面 | 狀態 |
|---|------|------|---------|------|
| R41-1 | **後端閒置 session 強制 revoke** | Migration 062 加 `refresh_tokens.last_used_at`；`Config::auth_idle_timeout_minutes` 預設 30；`services/auth/session.rs::refresh_token` 檢查 idle 後 revoke + return `session_idle_timeout`；`AUTH_IDLE_TIMEOUT_MINUTES` env var。對齊普級「帳號管理」閒置鎖定要求。 | 存取控制 | [x] |
| R41-2 | **HMAC chain 驗證主動告警** | `audit_chain_verify.rs` cron + security_alert + SecurityNotifier dispatch 全部就緒；旗標 `AUDIT_CHAIN_VERIFY_ACTIVE` 預設 false，待 ops 在 staging 驗證 ≥7 天後啟用（運維任務，非開發）。對齊「稽核處理失敗回應」。 | 事件日誌 | [x] |
| R41-3 | **Audit table 容量分區政策文件化** | `DATA_RETENTION_POLICY.md` §6 + Prometheus `AuditLogTableSizeWarning/Critical` + `bin/audit_archive` skeleton。對齊「稽核儲存容量」。 | 事件日誌 | [x] |
| R41-4 | **密碼政策偏離 NIST 之依據文件化** | `docs/security/PASSWORD_POLICY.md` 落地，明列政策設定、NIST SP 800-63B §5.1.1.2 引用、補償控制對應表。 | 識別與鑑別 | [x] |
| R41-5 | **SAST 自動化納入 CI** | `.github/workflows/ci.yml` 新增 `semgrep-sast` job（p/rust + p/typescript + p/owasp-top-ten + p/secrets ruleset），`continue-on-error: true` non-blocking baseline。對齊「SDLC-測試」中級要求。 | 系統獲得 | [x] |
| R41-6 | **R22 入侵自動 IP block 串接收尾驗證** | grep 確認 `IpBlocklistService::auto_block` 已在 rate_limiter / response_logger (IDOR) / honeypot 三處串接；`security.md` 新增「R22 自動 IP block 串接驗證」段落記錄鏈路。對齊「系統監控」。 | 系統完整性 | [x] |
| R41-7 | **本 audit 文件納入 security index** | `docs/security/security.md` 新增「合規對照與政策文件索引」段落，9 個文件連結 + 半年複查排程（2026-11-11）。 | SDLC-需求 | [x] |
| R41-8 | **DB at-rest encryption 評估**（低優先） | `docs/assessments/DB_AT_REST_ENCRYPTION_2026-05.md` 結論採 Windows BitLocker；其他方案不追。實際啟用為後續單獨任務（建議 2026-06 與下次 DR drill 同時段）。 | 系統與通訊保護 | [x] |

---

## 🔔 R46 — refresh_token_reuse 告警降噪 + UX 強化（2026-05-13 立案）

> **背景**：R35-15 已實作 reuse detection（PR #359，`d42287d1`）— 觸發整 family revoke + critical security_alert。但實際運行**多數為 false alarm**（browser 多分頁併發 rotation、行動裝置斷網重試、瀏覽器上下頁快取、雙擊 race）；當前 alert 又只顯示 raw UUID，秘書看不出是誰也判斷不了真偽，告警價值被稀釋。
>
> **目標**：降誤報 + 提升可判讀性，讓 critical alert 真的代表 critical 事件。

### R46-A. 降誤報（優先）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R46-1 | Race window grace period | refresh_tokens 表加 `rotated_at`（normal_rotation 寫入時間戳）。reuse detection 時，若 `now() - rotated_at <= 5s` 視為 race condition（同分頁/同 client 併發），**不觸發 family revoke、不寫 alert**，僅 tracing warn + counter 累計（觀察基期）。超過 5s 才視為真 reuse。 | [x] 2026-05-14 PR #384 |
| R46-2 | 同 IP + 同 UA 降級 | 真 reuse 之外，比對 reused token 的請求 IP / UA 與 family 最近一次 normal_rotation 的 IP / UA：完全相同 → severity 從 `critical` 降到 `warning`（token 沒離開使用者裝置，較可能是 browser bug）；不同 → 維持 `critical`（疑似 token 外流）。 | [x] 2026-05-14 PR #384 |
| R46-3 | False-positive 觀察期 | 2026-05-26 觀察完成：5/19-5/20 有 ~30 筆 REFRESH_TOKEN_REUSE（多為 warning 級多 Tab 競爭 false positive），5/21 起 **完全歸零**。R46-1/2 grace window + R57 per-tab idle 有效消除噪音。結論：不需進一步放寬，維持現況 | [x] |

### R46-B. UX 強化（降噪後做）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R46-4 | description 補 username | `handle_refresh_token_reuse` 先 SELECT users 拿 username/display_name，description 改成 `User {display_name} ({username}) 的 refresh token...`，秘書一眼能看出是誰。 | [x] 2026-05-14 PR #384 |
| R46-5 | context_data 補上下文 | 加入 `username` / `last_login_ip` / `last_user_agent` / `reused_ip` / `reused_user_agent` / `time_since_rotation_secs`，前端 dialog 直接呈現。 | [x] 2026-05-14 PR #384 |
| R46-6 | 前端 SOP 面板 | `AuditAlertDetailDialog.tsx` 針對 `alert_type = refresh_token_reuse` 顯示固定處理 SOP：① 系統已自動 revoke family（無需手動）② 通知該 user ③ 強制改密碼 ④ 檢查 IP log。降低秘書認知負擔。 | [x] 2026-05-14 PR #384 |
| R46-7 | 跳轉使用者詳情 | dialog 內 `相關使用者 ID` 區塊加按鈕「查看此使用者」→ 跳到 admin/users 該 user 編輯頁，方便快速處置（強制下線 / 改密碼 / 看登入歷程）。 | [x] 2026-05-14 PR #384 |

### R46 風險與停機規則

- R46-1 grace window 數值（5s）為初值，2 週觀察後再調；過長會放過真 reuse、過短繼續誤報。
- R46-2 IP/UA 比對需要保留 family 最近 rotation 的 IP/UA → 需要 schema 新增欄位或 join `user_activity_logs`，擇一後在 design doc 寫死。
- 降噪實作前**不刪除既有 critical 告警**，避免漏掉真 reuse；先並行（critical 不變，新增「降級為 warning」分支）觀察。

### R46 對應 memory / PR

- PR #359 (`d42287d1`) R35-15 — 既有 reuse detection 實作
- `backend/src/services/auth/session.rs::handle_refresh_token_reuse`
- `frontend/src/pages/admin/components/AuditAlertDetailDialog.tsx`

### R46 預估

- R46-A 降噪 3 項：~6h（含 migration + 觀察期收尾）
- R46-B UX 4 項：~4h
- 合計 ~10h，可拆 2 個 PR（A → B）

---

## 🐷 R47 — 可用豬隻快速查詢（庫存盤點，2026-05-13 立案，2026-05-14 落地 PR #386）

> **背景**：規劃新 protocol 時，vet 需要知道「手上現有可用豬，符合年紀區間（例如 24-30 月齡）+ 體重區間的有幾頭、公母比例如何」才能決定是否能開新計畫。目前動物列表頁缺月齡 / 體重區間 filter，也沒有統計列，每次都得手動數 — 痛點。
>
> **目標**：動物列表頁加 advanced filter（性別 / 月齡區間 / 體重區間）+ header 統計列（N 頭 / ♂ x ♀ y）+ Excel 匯出。

### R47 規格決策（2026-05-13 final，已與 vet 兩輪對齊）

| 項目 | 決策 |
|------|------|
| 「可用豬隻」status 條件 | `Unassigned`（純庫存）+ `Completed`（實驗完成存活）兩個 status **無條件可用**；`InExperiment` 視 toggle 決定（見下）；排除 `Euthanized` / `SuddenDeath` / `Transferred` / `is_deleted=true` |
| 「包含飼養計畫 000」toggle | 預設 **off**：只列 Unassigned + Completed；**on**：額外加上 `InExperiment` 且 `protocols.protocol_no = '000'` 的豬。其他 protocol 中的 `InExperiment` 豬永遠視為佔用、不列入 |
| 動物 ↔ 計畫關聯 | `animals.iacuc_no = protocols.iacuc_no`（隱式關聯，無 FK constraint）；查詢用 LEFT JOIN |
| 飼養計畫識別 | `protocols.protocol_no = '000'` 硬編（R47 不過度設計；未來若多個飼養計畫再改 boolean 欄位） |
| 月齡計算 | `birth_date` 動態算月齡（floor 取整數月），filter 用月齡區間（min, max） |
| 體重取值 | `weight_records` 該豬最近一筆；**> 40 天視為過期 → 直接排除**（不出現在結果與 Excel）；統計列下方提示「另有 N 頭因體重過期未列入」 |
| Filter 位置 | 動物列表頁加 advanced filter panel（折疊式） |
| 統計列 | 「符合條件：N 頭　♂ x　♀ y」+ 品種分佈 chip（Minipig / White / LYD / Other 各 count）|
| 權限 | 沿用 `animal.read` 既有權限，**不新增 permission**（有看動物列表權限的人都能用）|
| Excel 匯出 | 欄位：品種 / 耳號 / 性別 / 出生日 / 月齡 / 最近體重 / 量測日 / 棟舍 / 欄位（pen），9 欄；**不含**來源 |

### R47 順帶發現（不在本任務範圍，記給後續）

- `backend/src/services/access.rs:218-224` `get_animal_protocol_id` 函式寫 `SELECT protocol_id FROM animals`，但 `animals` 表**沒有 `protocol_id` 欄位**（實際關聯走 `iacuc_no`）。若函式被呼叫到會 SQL error。需獨立調查是否 dead code 或 stale 引用 → 列入 R-backlog（不在 R47 動）。

### R47-A. Backend

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R47-1 | Repository / query 函式 | `services/animal/core/query.rs` 新增 `list_available_with_filter`：`animals LEFT JOIN protocols ON animals.iacuc_no = protocols.iacuc_no` + `LATERAL JOIN weight_records`（最近一筆 + `measured_at >= NOW() - INTERVAL '40 days'`，無則排除）。WHERE：`is_deleted=false` + status IN (`unassigned`, `completed`) OR (status='in_experiment' AND `protocol_no='000'` AND `include_breeding=true`)。支援 filter：`sex`、`age_months_min/max`（用 `birth_date` 計算 `EXTRACT(MONTH FROM AGE(birth_date))`）、`weight_min/max`、`include_breeding` boolean | [x] |
| R47-2 | Service + handler | `services/animal/core/query.rs::list_available_pigs` + handler `handlers/animal/animal_core.rs::list_available_pigs`；route `GET /api/animals/available?...&export=xlsx`。export 旗標切到 xlsx 路徑 | [x] |
| R47-3 | Excel export | 用 `rust_xlsxwriter` 寫 8 欄；header bold；row freeze；檔名 `available_pigs_{YYYYMMDD_HHMMSS}.xlsx`（棟舍/欄位合併 "A03"）| [x] |
| R47-4 | 統計回應 | API 回應結構：`{ animals: [...], summary: { total, male, female, by_breed: { Minipig, White, LYD, Other }, excluded_weight_expired: N } }` | [x] |

### R47-B. Frontend

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R47-5 | Advanced filter panel | `pages/animals/AvailablePigsPage.tsx`（獨立頁 `/animals/available`）：性別 select + 月齡 min-max + 體重 min-max + 包含飼養計畫 000 toggle（預設 off）| [x] |
| R47-6 | 統計列 | chip 區：`符合 N 頭 / ♂ x / ♀ y` + 品種分佈 chip；debounce 300ms 即時更新 | [x] |
| R47-7 | 匯出 Excel 按鈕 | axios responseType=blob + Content-Disposition 解析檔名 | [x] |
| R47-8 | 體重過期提示 | 統計列下方小字：「另有 N 頭因體重資料 > 40 天未列入」（>0 才顯示）| [x] |

### R47 風險與停機規則

- 「protocol 編號 000 = 飼養計畫」目前是 convention，code 無 enforce；R47-1 query 寫死 `protocol_no = '000'` 風險低（規範清楚），若未來有多個飼養計畫再 migration 加 `is_breeding_protocol` boolean → 列為 R47 future deferred，不在本任務動。
- 「40 天」硬編碼為閾值；之後若需調整，抽到 `constants.rs::WEIGHT_FRESHNESS_DAYS = 40`，現階段先寫 const。
- Filter 全留空時等同「全部可用豬」一覽，不可一次回 > 1000 筆 → pagination 既有機制沿用即可。
- 動物 ↔ 計畫關聯走 `iacuc_no` 隱式連結（非 FK），有 NULL 情況：純庫存豬 `iacuc_no IS NULL` 是正常的；查詢用 LEFT JOIN 處理。

### R47 對應 memory / 路徑

- `xenotransplantation-vet` — 一隻一隻照顧研究豬，filter 用月齡 / 性別 / 體重區間符合異種移植情境
- `backend/src/services/animal/core/query.rs`（新增 `list_available_pigs`）
- `backend/src/handlers/animal/animal_core.rs`（新增 handler）
- `backend/src/services/animal/utils.rs` 或新檔 `excel_export.rs`（xlsx writer）
- `frontend/src/pages/animals/AnimalsPage.tsx`（advanced filter + 統計列 + export button）
- `frontend/src/lib/api/animal.ts`（new）或 inline TanStack Query 呼叫

### R47 預估

- R47-A backend 4 項：~4h（含 xlsx export + tests）
- R47-B frontend 4 項：~3h
- 合計 ~7h，1 個 PR 可做完

---

## 🛡️ R48 — Tiered 安全偵測改善（2026-05-14 立案，靈感來自 ATR）

> **背景**：閱讀 [Agent-Threat-Rule/agent-threat-rules](https://github.com/Agent-Threat-Rule/agent-threat-rules) 後評估 iPig 既有安全 infra（middleware / audit / HMAC chain）可借鏡的 pattern。完整討論見 `docs/security/TIERED_DETECTION_RFC.md`。
>
> **目標**：以最低成本引入 ATR 三個 pattern 的前兩個（誠實標註偵測極限 + SARIF 整合），規則資料化部分列入 backlog。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R48-1 | Alert template 加偵測極限說明 | 在 R46 refresh_token_reuse alert / IDOR probe / honeypot 等告警的文檔 / Grafana panel 加上「預期 false-positive 率」+ 已知 evasion scenario，降低半夜誤判風險。**2026-05-20 完成**：新增 `docs/security/DETECTION_LIMITS.md` — 9 個 `SEC_EVENT_*` 對照表 + REFRESH_TOKEN_REUSE 三階段啟發式 FP scenario + 維運半夜 SOP 決策樹 | ✅ |
| R48-2 | CI workflow 加 SARIF upload | 2026-05-26 完成 PR #492：gitleaks + Trivy SARIF → GitHub Security tab。cargo-audit deferred（無原生 SARIF） | [x] |
| R48-3 | 規則資料化評估（deferred） | rate limit / honeypot path / IDOR pattern 抽 `config/security_rules.yml` + hot-reload — 需求未到不主動推進，等 1 年內若調整次數 ≥ 3 再啟動 | 暫緩 |
| R48-4 | RFC 連結到 THREAT_MODEL.md | `docs/security/THREAT_MODEL.md` 加 reference 到 `TIERED_DETECTION_RFC.md`（單向：威脅模型 → 偵測方法論）。**2026-05-20 完成**：THREAT_MODEL.md §8「相關文件」新增表，連 TIERED_DETECTION_RFC / DETECTION_LIMITS / HMAC_VERSIONING / AUDIT_REDACTION 四份 | ✅ |

### R48 預估

- R48-1：0.5h（純文件）
- R48-2：1h（CI YAML）
- R48-4：0.1h
- R48-3：deferred，看實際需求頻率
- 合計近期可做：~2h

---

## 👤 R49 — Guest mode 全面修整（2026-05-14 落地 PR #390）

> **背景**：使用者於 guest mode 巡訪時發現 `/vet-patrol-reports` white screen 崩潰；後續系統性審查發現多個 ⚠ silent empty / ❌ 完全擋 的頁面。經討論定政策：⚠ → demo 唯讀；❌ → 編輯頁直接擋 redirect dashboard。

### R49 政策

| 類別 | 修改前 | 修改後 |
|---|---|---|
| Admin 頁（users/roles/settings）| 硬重導 dashboard | 顯示既有 demo（按鈕灰）|
| QAU 系列（5 條 route）| `guestBlock=true` 整頁擋 | 顯示 DEMO_QAU_*（demo data 早已存在）|
| 編輯/送審頁 | 可進不能存 + toast | 完全 redirect dashboard（按鈕級 GuestHide 已存在）|
| Silent 空表 | 空白無資料 | 補 demo data |

### R49 落地

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R49-1 | /vet-patrol-reports 崩潰修補 | exactRoutes 加 EMPTY_ARRAY，防止 `reports.map()` 對物件呼叫 | [x] |
| R49-2 | /animals/available demo data | 8 隻 demo 豬（minipig/white/lyd 各幾隻）+ summary | [x] |
| R49-3 | /hr/training-records demo data | 5 筆訓練紀錄（vet/staff/pi 各一些）| [x] |
| R49-4 | /messaging demo data | 3 threads + 7 messages + 3 thread detail exactRoutes | [x] |
| R49-5 | GuestBlock route wrapper | 新元件 `components/auth/GuestBlock`，guest → Navigate to /dashboard | [x] |
| R49-6 | 編輯頁包 GuestBlock | 6 條 route：protocols/products/documents/animals 的 new/edit + animal-field-corrections | [x] |
| R49-7 | Admin 3 頁解鎖 | 移除 /admin/users / /admin/roles / /admin/settings 的硬重導 | [x] |
| R49-8 | QAU 5 條解鎖 | 移除 guestBlock=true，沿用既有 demo data | [x] |
| R49-9 | ProductsPage 按鈕 GuestHide | 新增產品按鈕補包 GuestHide（DocumentsPage 既有）| [x] |
| R49-10 | Prod web rebuild | `docker compose up -d --build web` 完成 + healthy | [x] |

### R49 對應路徑

- `frontend/src/components/auth/GuestBlock.tsx`（新）
- `frontend/src/lib/guest-demo/messaging.ts`（新）
- `frontend/src/lib/guest-demo/admin.ts`（+DEMO_TRAINING_RECORDS）
- `frontend/src/lib/guest-demo/animals.ts`（+DEMO_AVAILABLE_PIGS）
- `frontend/src/lib/guest-demo/routes.ts`（連線新 demo）
- `frontend/src/App.tsx`（admin 解鎖 + QAU 解鎖 + 編輯頁 GuestBlock）
- `frontend/src/pages/master/ProductsPage.tsx`（GuestHide 補洞）

---

## 🧹 R50 — Post-R49 穩定性 follow-ups + 安全 advisory 維運（2026-05-14 立案）

> **背景**：R49 guest mode 上線後，prod observation 與 dogfooding 找出 4 個獨立議題；同期 RustSec 發布 lettre 0.11.21 Boring TLS advisory（與我們無關但 CI 紅燈）。彙整於此追蹤。

### R50 落地

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R50-1 | R33-1 CSRF middleware 改讀 `extensions::<CurrentUser>()` | 移除自解 JWT payload 的 trust gap、middleware 順序 csrf→auth 改為 auth→csrf。PR #393 | [x] |
| R50-2 | R49 guest-mode 4 個 UX/crash bug + RolesPage demo permissions | RolesPage crash null-safe + 出勤管理按鈕 disabled + 修正審核 sidebar 隱藏 + 新增計劃書 fieldset disabled + DEMO_PERMISSIONS 18 項。PR #394（已採納 Gemini selector subscribe fix） | [x] |
| R50-3 | unusual_login 三階段降噪（A dedup + B 首次登入跳過 + D admin info severity）+ deploy-prod.ps1 script | services/login_tracker.rs：30 分鐘 user dedup / 非 admin 首次登入略過 new_device / admin 僅 unusual_time 降為 info。PR #395 | [x] |
| R50-4 | RUSTSEC-2026-0141 lettre Boring TLS advisory ignore | 本專案 lettre features = `tokio1-native-tls`、未啟用 boring-tls，bug 路徑不適用。deny.toml ignore + rationale comment（對齊 RUSTSEC-2026-0097 既有 pattern）。PR #396 | [x] |

### R50 風險與停機規則

- R50-4 採 ignore 而非 upgrade：若未來新增 SMTP backend 切換 boring-tls，需移除此 ignore 重新評估
- R50-3 B/D 整合測試受 `check_unusual_time` 時鐘依賴限制無法穩定 mock，已記入 PR 為 future follow-up（refactor check_unusual_time 接受 `DateTime<Utc>` 注入）
- R50-1 中第三方 CSRF middleware 改順序屬安全相關 — 雙層防禦下不可利用，但需 manual smoke test verify

### R50 對應路徑

- `backend/src/middleware/csrf.rs`（R50-1）
- `backend/src/routes/mod.rs`（R50-1 middleware order）
- `frontend/src/pages/admin/RolesPage.tsx`（R50-2 null-safe）
- `frontend/src/lib/guest-demo/admin.ts`（R50-2 DEMO_PERMISSIONS / DEMO_ROLES）
- `frontend/src/pages/hr/components/TodayClockTab.tsx`（R50-2 + Gemini selector fix）
- `frontend/src/pages/protocols/ProtocolEditPage.tsx`（R50-2 fieldset disabled）
- `frontend/src/components/layout/sidebarNavConfig.ts`（R50-2 sidebar hide）
- `backend/src/services/login_tracker.rs`（R50-3 三階段降噪 + is_admin_user helper）
- `backend/tests/api_login_tracker.rs`（R50-3 A dedup 整合測試）
- `scripts/deploy-prod.ps1`（R50-3 solo operator redeploy）
- `backend/deny.toml`（R50-4 RUSTSEC-2026-0141 ignore）

---

## 🚀 R51 — Auto-deploy watcher（prod 自動套用 main，2026-05-14 立案，2026-05-15 落地）

> **背景**：solo operator + prod-on-laptop + Cloudflare Tunnel 公開暴露。merge 到 main 後若靠人工 `git pull && docker compose up`，「12 小時一個洞」的響應時間不夠。R51 補上 pull-based watcher（Task Scheduler 每 5 分鐘觸發），自動完成 fetch / build / restart。

### R51 落地

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R51-1 | watcher script + 安裝器 | `scripts/auto-deploy-watcher.ps1`（lock file + git fetch/compare + 呼叫 deploy-prod）+ `scripts/install-auto-deploy.ps1`（Task Scheduler 註冊：每 5 分鐘 + Highest run level + Interactive logon）。PR #399 | [x] |
| R51-2 | watcher EAP push/pop bootstrap fix | 第一次自部署失敗：deploy-prod 子進程 stderr 觸發 NativeCommandError。watcher 端 `$ErrorActionPreference = "Continue"` 包覆 invoke + Tee-Object。PR #402 | [x] |
| R51-3 | deploy-prod 全 script EAP=Continue + LASTEXITCODE | docker compose build stderr 也會觸發 NativeCommandError，watcher 端包覆無效。改 deploy-prod.ps1 整個 script EAP=Continue + 所有 `git rev-parse` 後加 `$LASTEXITCODE` check（Gemini HIGH 抓的避免 silent empty SHA）。PR #404 | [x] |
| R51-4 | End-to-end 驗證 trivial commit | PR #404 落地後 watcher 已就緒但仍有 bootstrap chicken-egg。PR #405 用 App.tsx 註解 trivial change 觸發 watcher → 觀察 `[INFO] Deploy 成功。` + container fresh timestamps，首次完整 pipeline 成功 | [x] |

### R51 風險與停機規則

- Watcher 用 Task Scheduler 而非 service：重啟筆電 Interactive logon 後才會跑（非 boot persistence），solo 場景可接受
- EAP=Continue 後手動 `$LASTEXITCODE` check 是新規範 — 未來改 deploy script 任何 git command 必須對齊
- Bootstrap 問題：改 watcher / deploy-prod 自己的 PR 不能用 watcher 驗證，必須手動跑一次再 merge 觸發 trivial commit 驗

### R51 對應路徑

- `scripts/auto-deploy-watcher.ps1`
- `scripts/install-auto-deploy.ps1`
- `scripts/deploy-prod.ps1`（EAP=Continue + LASTEXITCODE checks）

---

## 🔐 R52 — SHA-pin 第三方 GitHub Actions（supply chain hardening，2026-05-14 落地 PR #398）

> **背景**：「12 小時一個洞」的新聞促成 CSO posture audit。第三方 GH Actions 用 tag 是供應鏈隱患（tag 可被推到惡意 commit）。SHA-pin 第三方僅，first-party `actions/*` / `docker/*` 不 pin（整生態被攻破時改 SHA 也救不了，徒增 maintenance cost）。

### R52 落地

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R52-1 | SHA-pin 4 個第三方 GH Actions | `dtolnay/rust-toolchain` / `gitleaks/gitleaks-action` / `EmbarkStudios/cargo-deny-action` / `pnpm/action-setup` 全改 commit SHA + comment 記版本。PR #398 | [x] |
| R52-2 | dtolnay/rust-toolchain SHA-pin 需顯式 `with: toolchain: stable` | dtolnay 用 branch name 當預設 toolchain，SHA-pin 後失去訊號 → CI 紅燈。每處呼叫加 `with: toolchain: stable` 修復。PR #398（同 commit）| [x] |

### R52 風險與停機規則

- 升版第三方 action 需手動更新 SHA + comment — Dependabot 不會自動跟（規範：每月人工 review 一次 commit history）
- First-party 不 pin 是 trade-off：若 GH 自己被入侵 SHA-pin 也擋不住，反而 maintenance overhead 過高

### R52 對應路徑

- `.github/workflows/ci.yml`
- `.github/workflows/codeql.yml`

---

## 🧹 R54 — 前端 dead-vars 清理（2026-05-15 立案）

> **背景**：PR #407 CI tsc check 警告抓出 3 個 unused vars（warning，非 error，CI 不擋）。獨立小 PR 清理，與其他工作不衝突。

| # | 項目 | 位置 | 狀態 |
|---|------|------|------|
| R54-1 | unused `t` | `frontend/src/pages/animals/VetPatrolReportListPage.tsx:38` | [x] PR #415 |
| R54-2 | unused `groupedData` | `frontend/src/pages/animals/AnimalsPage.tsx:129` | [x] PR #415 |
| R54-3 | unused `e` | `frontend/src/components/animal/AnimalPenReport.tsx:46` | [x] PR #415 |
| R54-4 | ESLint `@typescript-eslint/no-unused-vars` warning → error | `frontend/eslint.config.js`；升級後同類 dead var 立即擋 CI，不再靠人工掃。順帶清掉 App.tsx:158 / VetPatrolReportDialog.tsx:495 兩個 unused eslint-disable directive | [x] PR #415 |

R54 落地 2026-05-15：5 problems → 0 problems，eslint rule 升 error 防將來再漏。

---

## 🧹 R55 — print-pdf cutover follow-ups（2026-05-15 立案）

> **背景**：PR #420 (`feat/print-pdf-cutover`) 把 PDF stack 從三件式（pdf-service + gotenberg + word-convert daemon）切成單一 `services/print-pdf/` (FastAPI + WeasyPrint)。Backend `PdfServiceClient` 不改一行，但 `GotenbergClient` 變成 0-caller dead code，留給後續 surgical cleanup。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R55-1 | **移除 GotenbergClient dead code** | 2026-05-17 落地：`gotenberg.rs` 整檔刪；`services/mod.rs` + `lib.rs` pub use 清掉；`main.rs` 不再 construct + `AppState.gotenberg` 欄位移除；`config.rs` `gotenberg_url` 欄位 + env read + test default 刪；`auth/tests.rs` + `tests/common/mod.rs` test fixture 同步；`PdfServiceClient::{render, render_docx}` 兩個 0-caller 方法刪；`.env.example` `GOTENBERG_URL` 區塊刪。cargo check / clippy / test --lib (492 pass) 全綠。 | [x] |
| R55-2 | **nginx resolver + 變數化 proxy_pass** | 2026-05-16 部署實戰修：api `--force-recreate` 後拿新 IP，但 web nginx upstream 是用 hostname `api:8000` 寫死，nginx 只在啟動時 resolve 一次 → 全 API 502 持續 8 分鐘直到 `docker restart web`。修法：`frontend/nginx.conf` 加 `resolver 127.0.0.11 valid=10s ipv6=off;` + 把 `proxy_pass ${API_BACKEND_URL};` 改成 `set $api_upstream "${API_BACKEND_URL}"; proxy_pass $api_upstream$request_uri;`。已隨 PR #420 提交並部署驗證。 | [x] |
| R55-3 | **恢復 X-Internal-Token 驗證** | 2026-05-17 落地：`main.py` 新增 `verify_internal_token` FastAPI dependency（`hmac.compare_digest` constant-time check），attach 到所有 `/render-*` + `/api/render` 端點；`/health` / `/api/sample` / `/api/preview` / `/static` 保留匿名。token 從 `PDF_SERVICE_TOKEN` 或 `PDF_SERVICE_TOKEN_FILE` 讀（與 backend 同模式），空值 → no-op 給 dev pass-through；docker-compose `print-pdf` 服務 mount `pdf_service_token` secret（與 api 同檔）。驗證：no-token→401 / wrong-token→401 / correct-token→200；smoke test 11/11 PASS。 | [x] |
| R55-4 | **刪除舊 pdf-service / word-convert 源碼樹** | 2026-05-26 完成 PR #489：刪除 `services/gotenberg/`（Dockerfile + 10 fonts）+ `services/word-convert/`（server.py + install scripts + watchdog）。XlsxRenderFormat 確認已無 daemon caller | [x] |
| R55-5 | **清掉孤兒 pdf metrics alert / dashboard** | 2026-05-26 完成 PR #489：移除 Prometheus orphan scrape job `ipig-pdf-service` + 2 alert groups (ipig_pdf_path_alerts + pdf_daemons, 6 rules) + Grafana `pdf-daemons.json` dashboard | [x] |
| R55-6 | **review_reply 移除 forced page-break + visual_audit / compare_pdf 工具** | 2026-05-17 落地：`templates/review_reply.html` 砍掉 `h2.section { page-break-before: always; }` 與 `.first` 配對 → SAMPLE 從 6 頁變 3 頁，與 reference 範例 3 頁對齊。同時新增 `_tools/visual_audit.py` (PyMuPDF rasterize + 並排 HTML) 與 `_tools/compare_pdf.py`（pypdf 文字 diff）— 後續 review_result / medical_record / aup_protocol 視覺對齊用。Reference 是 scanned PDF 沒 text，用 visual_audit.py 開瀏覽器並排檢驗。 | [x] |

---

## 🔄 R57 — Sliding Session follow-ups（2026-05-16 立案）

> **背景**：2026-05-16 PR #428 sliding session 五部曲完成（A1 15min TTL + A2 proactive + B1 BroadcastChannel + C1 retry + D1 visibility）。實作過程 + 後續 backlog scan 浮出以下相關 cleanup / 對齊 / dead code 候選，獨立 R57 追蹤避免 PR #428 scope creep。

> **設計原則**：所有 R57 項目均為**獨立可選**，無時程壓力；下一次相關區域變動時順手做。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R57-1 | **SESSION_TIMEOUT_MS 對齊 idle_timeout（從 6h → 30min）** | `frontend/src/stores/auth.ts:11` `SESSION_TIMEOUT_MS = 6 * 60 * 60 * 1000` 原本對應 access TTL 6h；A1 改 15min 後此值語意只剩 `SessionTimeoutWarning` 警示倒數的基準。但 idle 30min 早就踢人 → warning 永遠不會 fire（dead UX）。修法：對齊 `auth_idle_timeout_minutes`（30 min），或乾脆移除 `SessionTimeoutWarning` 元件（idle 過期會自然 logout） | [x] 2026-05-18 完成（直接移除，非對齊；F3） |
| R57-2 | **`SessionTimeoutWarning` 元件評估存廢** | 觸發條件 `sessionExpiresAt - 60s` 在新模型下實際走不到（heartbeat keep alive → 不會 idle 6h；真 idle 30min 就被踢）。是 R57-1 的延伸 — 對齊後若仍無用就刪 | [x] 2026-05-18 刪除（F3） |
| R57-3 | **`dev/SECURITY_AUDIT_REPORT.md:159` 6h 描述過時** | Line 159 仍寫 "Access Token TTL: 6 hours (env: `JWT_EXPIRATION_MINUTES=360`)"。下次 security audit 時順手改成 15min | [x] 2026-05-18 完成 — 更新全部 5 個 TTL 數字 + 加 sliding session overhaul 註解 |
| R57-4 | **`docs/spec/architecture/01_ARCHITECTURE_OVERVIEW.md:202` Access Token 預設過時** | 該行寫「預設 6h / 360 分鐘」。架構文件 stale，下次架構文件更新時對齊 15min | [x] 2026-05-18 完成 — Access Token 預設 6h→15min、Refresh 7d→30d |
| R57-5 | **`docs/plans/r41_nics_compliance.md:160` JWT 6h 過時** | 該行寫「JWT 6h expiry」。屬 R41 歷史紀錄性質，可考慮加註「2026-05-16 已縮短至 15min」尾註而非直接改（保留 audit trail） | [x] 2026-05-18 完成 — 加 2026-05-18 sliding session overhaul 註解，保留 audit trail |
| R57-6 | **`backend/migrations/003_notifications.sql:236` session_timeout_minutes 預設 360 過時** | `system_config` 表插入預設值 `'360'`，與新 access TTL 15min 完全不符。雙軌問題（DB system_config vs env AUTH_IDLE_TIMEOUT_MINUTES），需先釐清哪個生效，再決定：(a) 新 migration UPDATE 預設值；(b) 移除 DB 軌只用 env；(c) 文件化雙軌語意分離 | [x] 2026-05-18 完成 — 走 (a)，migration 068 改 360→480；同時 scheduler 連線 cleanup_expired 讓 DB 軌真實 fire（F4+F6） |
| R57-7 | **`SettingsPage.tsx` session timeout 選項含 360/480 分鐘過時** | 管理員設定頁仍提供 6h / 8h 選項（可從 coverage HTML 看到 `<SelectItem value="360">`）。對齊 R57-6 修完後同步修選項 | [x] 2026-05-18 完成 — select 已含 480 option，順便修 stale helper text（原寫「需重啟」實際 5min cron 自動套用）+ fallback constants 360→480 |
| R57-8 | **`Frontend: tsc check` CI job 命名 misleading** | `.github/workflows/ci.yml:545` job 叫 "Frontend: tsc check" 但實際同時跑 tsc + vitest。PR #424/#425 紅燈時讓人誤以為 tsc 錯，實際是 test 紅。修法：拆兩個 job（tsc / vitest）或改名 "Frontend: typecheck + tests" | [x] 2026-05-25 完成 — 改名 "Frontend: tsc + eslint + vitest"（PR #488） |
| R57-9 | **`docs/security/SESSION_LOGOUT_MANAGEMENT.md:64` SESSION_TIMEOUT_MS 描述過時** | 該行說明「前端逾時顯示用（6 小時）」。R57-1 改完 SESSION_TIMEOUT_MS 後同步改 | [x] 2026-05-18 重寫整個 §3.3 設定參數表 + 加 §五變更歷史（F8） |
| R57-10 | **smoke test 自動化框架評估** | 本次 cutover 想做本地 smoke test 但 prod-on-laptop 無 port 隔離 → 完整 sandbox 風險高放棄；改靠 post-cutover 真環境 dogfooding。長期建議建立 `docker-compose.smoke.yml` 用 -p sliding-smoke project + 變數化 port + 獨立 DB volume 的 smoke 標準範式，未來大改動可重複用 | [~] deferred — 無時程壓力，下次大改動時評估 |
| R57-11 | **`R34-D15` auth.ts persist migrate Zod safeParse 仍未觸發** | sliding session 沒改 `partialize` shape（accessTokenExpiresAt 明確不持久化），原 trigger「下個 auth 改動順手做」未實質滿足。等下次真改 persist shape（bump version）時必做 — 對應 R57 與 R34 雙重追蹤 | [x] N/A — R58 已全面移除 Zod，persist migrate 為 no-op pass-through，無 safeParse 可觸發 |
| R57-12 | **`R34-D6` Auth store 拆 slice trigger 強化** | `useAuthStore()` 全 store 訂閱出現在 **15 處** components / hooks（grep 確認），原 R34-D6 trigger「跑 React Profiler 確認」未動。Sliding session 後 `accessTokenExpiresAt` 每 12 min 更新一次 → 這 15 處全 rerender。雖然各 component 自己幾乎 noop，但 React reconciliation 仍跑一遍。**升級建議**：proactively 替換為已有的 `useAuthUser` / `useAuthIsAuthenticated` / `useAuthHasRole` / `useAuthHasPermission` / `useAuthIsGuest` / `useAuthActions` selectors（auth.ts:286-317 已備好），不必開新 selector | [~] deferred — 74 files blast radius 大，無時程壓力 |
| R57-13 | **`Date.now() + expires_in * 1000` 五處重複（小 DRY）** | `stores/auth.ts` 在 login / verify2FA / impersonate / stopImpersonating / refreshSession 五處重複 `Date.now() + expires_in * 1000`。可抽 helper `computeAccessExpiry(expires_in: number)` 或 inline 為時間單位常數。**Cosmetic / 維護性 ≤ 微改善**，下次 auth 改動順手 | [x] 2026-05-25 完成 — 抽出 `expiresInToTimestamp()` helper，6 處全替換（PR #488） |
| R57-14 | **Sliding session 缺 Playwright E2E 覆蓋** | 目前單元測試（vitest）覆蓋 hook + lib 邏輯，但**沒有 real browser end-to-end**：BroadcastChannel 跨 tab 行為 / visibilitychange 真實事件 / setTimeout 在 tab 背景的 throttle 行為 / network throttle 下的 retry 路徑都只有 jsdom mock。**真實驗證仍依賴 cutover 後手動 dogfooding**。建議：加 1-2 個 Playwright scenarios（multi-tab + slow network），跑進 CI `🧪 E2E: Playwright` job | [~] deferred — 無時程壓力，手動 dogfooding 暫夠用 |

### R57 對應 memory

- [[rtk-vitest-exit-code-strict]] — R57-8 CI job 命名問題源於 rtk 顯示 PASS 但 exit 1 的誤判
- [[integration-branch-strategy]] — R57 條目均為**獨立可選**，未來下次相關 PR 順手做不必再開 integration

### R57 風險與停機規則

- 無高風險項目；全部為 cleanup / doc / UX polish
- R57-6（migration 預設值雙軌）需先釐清語意才能動，**先 surface 給使用者裁定後**再排
- 其餘可獨立 1-2 commit PR

---

## 🧹 R58 — 前端 lib Zod 移除（2026-05-17 立案 + 落地）

> **背景**：
> - R31-10 CSP enforce cutover 移除 `'unsafe-eval'`，但 Zod 4 升級後內部 `Function('')` feature probe 撞 CSP → audit log + console noise。
> - 使用者 2026-05-17 決議「縮緊 CSP 不動」+「檢討 Zod 必要性」→ 結論：**Zod 對本 codebase 殺雞用牛刀**（14 個 callsite，多數簡單 1-3 欄位表單），改 React Hook Form native `register('field', { required, pattern, ... })` + 少量 helper 即可。
>
> **編號說明**：原本 R58-1 列「Handler 命名 codebase-wide refactor」為 defer，但實作時拆出獨立的 **R59** 章節追蹤，此處已 dedupe，不再重複列。Handler 命名見 R59-1。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R58-2 | Zod 移除 Phase 1：LoginPage | 2026-05-17 落地。`pages/auth/LoginPage.tsx` zod → RHF native `register` + `pattern: EMAIL_PATTERN`，UX 等價。**Proof-of-concept**，使用者 review pattern 後啟動 Phase 2-N | [x] |
| R58-3 | Zod 移除 Phase 2：bulk repoint getApiErrorMessage callers | 88 個 callsite 把 `import { getApiErrorMessage } from '@/lib/validation'` 改 `from '@/lib/apiError'`（新 file，零 zod 依賴），切斷透過 validation.ts 拖入 zod 的鏈路 | [x] |
| R58-4 | Zod 移除 Phase 3：所有 form callsites | (a) auth/profile 4 forms（Forgot/Reset/ForceChange/Profile），(b) authBroadcast safeParse → type guard，(c) 15 schema-using forms（HrAnnualLeave/Ar/Ap/AnimalEdit/AnimalSources/Warehouses/CreateAiKey/BloodTest*/usePartnerForm 等），(d) 19 admin/HR/blood-test 剩餘 callsites。**逐步 commit**，每批驗 RHF register + validate cross-field 模式 | [x] |
| R58-5 | Zod 移除 Phase 4：final cleanup | (1) `InvalidateSignatureDialog` schema.parse → inline validate fn，(2) 刪 `lib/validation.ts`（480 行）+ 2 個 schema test 檔，(3) 加 `__tests__/lib/apiError.test.ts`（從 validation.test.ts port `getApiErrorMessage` 11 tests），(4) `pnpm remove zod @hookform/resolvers` + 重生 lockfile。Zod 現僅是 eslint-plugin-react-hooks transitive dep（build-tool，非 bundle） | [x] |

> **狀態（2026-05-17）**：R58-2 ~ R58-5 全部落地，~130 個 callsite 從 zodResolver 遷移到 RHF native rules / hand-rolled type guards，`lib/validation.ts` + schema test 檔已刪除，`zod` + `@hookform/resolvers` 已從 package.json 移除。Handler 命名 refactor 由 R59-1 接手追蹤。
>
> **Pattern 摘要**：
> - 簡單表單：`register('field', { required, pattern: { value, message }, minLength, validate })`
> - Cross-field（密碼比對 / 日期區間）：`validate: (value, formValues) => value === formValues.other \|\| '訊息'`
> - 非 `register` 控制的欄位（Select / Checkbox group）：hidden `<input>` 配 register，或 submit handler `setError('field', { message })` early-return
> - Runtime 解析（如 BroadcastChannel message）：hand-rolled type guard
> - 型別：手動 `type Form = { ... }` 取代 `z.infer`

---

## 🧹 R59 — Handler 命名約定 codebase-wide refactor（2026-05-17 立案）

> **背景**：R53-4 PR #444 CodeRabbit Major review 指出 handler 命名不符 CLAUDE.md spec
> （`get_*` / `post_*` / `put_*` / `delete_*`）。但本專案多數既有 handler（如 `animal/source.rs`
> 的 `create_animal_source` / `list_animal_sources`、`animal/vet_advice.rs`、`animal/byproduct_sample.rs`
> 等）都用 `create_*` / `list_*` / `update_*` / `delete_*` 風格。Spec 與實作漂移已久。
>
> **編號說明**：原本立案為 R57，但 main 已有 R57（Sliding Session）；2026-05-17 PR #451 又用了 R58（Zod 移除），故順延為 R59。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R59-1 | 全 codebase handler 命名統一 | 2026-05-26 完成 PR #491 — 選 (b) 修 CLAUDE.md spec 配合既有 `list_` / `create_` / `get_` / `update_` / `delete_` 風格（不加 HTTP method 前綴）。新增 Handler 函式命名慣例表 + 領域動詞範例。零 code 改動 | [x] |

---

## 🔒 R63 — CSO 綜合安全審計（2026-05-27，9 輪深度掃描）

### R63-A：GLP 合規修復（獨立 PR）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R63-A1 | **GLP 24 個 mutation 加 audit logging** | `handlers/glp_compliance.rs` + `services/glp_compliance.rs` 全部 create/update/delete/approve 零 audit。21 CFR Part 11 §11.10(e) 違規。需用 service-driven `log_activity_tx` pattern | [x] |
| R63-A2 | **GLP 批准加電子簽章** | `approve_controlled_document` (:109) 和 `approve_change_request` (:275) 缺 `SignatureService::sign_record_tx`。§11.100 要求 | [x] |
| R63-A3 | **training_requirement hard DELETE 改 soft-delete** | `:415` 直接 DELETE 無 audit 無 tombstone，§11.10(e) 禁止遮蔽舊紀錄 | [x] |

### R63-B：安全強化（另一 PR）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R63-B1 | **Admin trigger 加權限檢查** | `handlers/notification.rs:264-331` 4 個 trigger + `calendar.rs:83` 加 `is_admin()` 檢查 | [x] PR #503 |
| R63-B2 | **DEFAULT PRIVILEGES 收窄** | migration 075 revoke grafana_readonly 自動授權所有未來表 | [x] PR #503 |
| R63-B3 | **SEED_DEV_USERS 強化 config_check** | `config_check.rs` 加 SEED_DEV_USERS 非 HTTPS 環境警告 | [x] PR #503 |
| R63-B4 | **Google Calendar client 加 timeout** | `google_calendar.rs` 加 connect_timeout(5s) + timeout(30s) | [x] PR #503 |
| R63-B5 | **Multipart 檔案數限制** | `upload.rs` 加 MAX_FILES_PER_REQUEST = 20 | [x] PR #503 |
| R63-B6 | **Soft-delete PII 全清** | `user.rs` 擴大匿名化：display_name/phone/phone_ext/org/position | [x] PR #503 |
| R63-B6a | **R63-B6 收窄：保留 display_name（記錄者歸屬）** | 刪除不再抹 `display_name`（屬 GLP 歸屬資料，對齊 AUDIT_LOGGING.md）；email/phone/org 仍匿名化；migration 124 自 USER_DELETE audit 回填既有已刪除帳號名字 | [x] |
| R63-B7 | **`/api/metrics/vitals` 加 rate limit** | vitals 從 health route 獨立，加 `api_rate_limit_middleware` | [x] PR #503 |
| R63-B8 | **Honeypot DashMap 加清理** | 加 10K 上限 + 過期 entry 自動清理 | [x] PR #503 |
| R63-B9 | **config_check 補齊** | 加 AUDIT_HMAC_KEY 未設定警告 | [x] PR #503 |

### R63-C：Deferred（低風險 / 環境限制）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R63-C1 | **Webhook SSRF DNS rebinding** | 掃描確認：系統無 webhook 功能，N/A | [x] N/A |
| R63-C2 | **Upload MIME magic-byte 驗證** | 掃描確認：`FileService::validate_magic_number` 已實作 magic-byte 檢查 | [x] 已有 |
| R63-C3 | **Scheduler leader election** | `pg_try_advisory_lock` session-level，多 instance 只有一個跑排程 | [x] |
| R63-C4 | **External service circuit breaker** | 掃描確認：`connect_timeout(5s) + timeout(30s)` 已存在於 R63-B PR #503 | [x] 已有 |
| R63-C5 | **GLP list endpoints 加分頁** | `find_reference_standards` / `find_monitoring_points` / `find_training_requirements` 加 LIMIT 200 安全上限 | [x] |
| R63-C6 | **Dead dependency tera 移除** | Cargo.toml 移除 `tera = "1"`，全檔無引用 | [x] |
| R63-C7 | **Leave Decimal→f64 round-trip** | `deduct_comp_time` 改純 Decimal 運算，消除 f64 round-trip | [x] |
| R63-C8 | **SKU regex per-call compile** | `sku.rs` 兩處 `Regex::new` 改 `OnceLock` 一次編譯 | [x] |
| R63-C9 | **TEST_USER_PASSWORD 改用 read_secret** | `config.rs` TEST_USER_PASSWORD + DEV_USER_PASSWORD 改 `read_secret()` 支援 Docker Secrets | [x] |
| R63-C10 | **Backup restore 自動驗證** | ops drill 項，`audit_archive` skeleton 已存在（R41-3A），非程式碼變更 | [x] N/A |

---

## 🐷 R70 — 動物紀錄計畫前置需求落實（2026-06-15 立案）

> 來源：本 PR（#704）隨附之《動物紀錄計畫前置需求分類規範》§四 Follow-up。規格界定「哪些動物紀錄須動物已指派至已核准計畫(AUP)才能建立」+ 角色讀寫目標模型，但**系統現況尚未強制**。落實涉及收緊（PI/IACUC/VET）+ 放寬（未指派動物的基礎紀錄）權限，**資安敏感、須獨立 PR + 安全評估**，三條風險不一，建議先做最安全的 R70-1。規格見 `docs/training/動物紀錄計畫前置需求分類規範.md`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R70-1 | **紀錄類型前置檢查** | service 層對「需計畫」紀錄（手術／犧牲採樣／疼痛評估／病理／觀察「試驗」性質）驗證動物 `iacuc_no` 非空，否則拒絕；「免計畫」（體重／疫苗／血檢／觀察異常·觀察／基本資料）不受擋。只擋新建、不動既有資料。先寫 acceptance test → 紅 → 實作 → 綠。**enforce 硬擋 vs 軟導入(warning) 需使用者拍板** | [x] PR #712 |
| R70-2 | **角色讀寫收緊** | PI、IACUC 委員/主席 → 動物資料**唯讀**（移除寫入路徑）；獸醫師 → 僅保留獸醫建議/建議單、巡場報告、轉讓獸醫評估、安樂死單、vet-read 標記，其餘唯讀。對齊 `services/access.rs::require_animal_access`。高風險收緊、須安全評估 | [x] PR #713 |
| R70-3 | **放寬基礎紀錄權限** | 讓可寫角色（試驗人員/admin/執行秘書）能對**未指派計畫**的動物建立「免計畫」紀錄。與 R70-1 互補 | [x] PR #713 |
| R70-4 | **能力評鑑 result 欄補 CHECK 約束** | `016_glp_compliance.sql` 能力評鑑 `result` 欄無 `CHECK IN (...)`，可寫任意字串（#704 reviewer 發現）。補列舉約束（migration）。低優先、與本主題無耦合 | [x] PR #713 |
| R70-5 | **動物紀錄讀寫存取分層 + 查無此豬 404** | 依權限矩陣：內部 staff（具 `animal.animal.view_all`）可跨計畫**讀取**動物紀錄，寫入仍限自己計畫；PI/CLIENT 收緊為僅自己計畫（取代 #713 `require_animal_access_basic` 的「存在即放行」）。新增 `require_animal_read_access`，24 讀取端點切換；兩守衛先驗動物存在 → 不存在一律 404「動物不存在」（修正 #713 Gemini 建議 2：view_all 短路後回空集合）。`tests/api_animal_read_access.rs` 6 測試 | [x] PR #716 |

---

## 🔍 R71 — 「核准」按鈕運作邏輯盤點 follow-up（2026-06-16 立案）

> 來源：本輪「核准按鈕運作邏輯盤點」，報告見 `docs/audit/approval-buttons-inventory-2026-06-16.md`。盤點 9 類 IN-SCOPE 核准動作（排除 GLP 受控文件 / HR 請假·加班 / 動物移轉 / 設備報廢 / 安樂死）。核心發現：合規防護兩極化 — ERP 單據 / GLP 變更請求 / 設備維護驗收防護完整，但**動物欄位修正、PI 邀請、設備閒置核准**幾無防護（無交易 / 無 audit / 無併發守衛 / `is_admin()` 硬編碼權限）。R71-1~3 屬**資安/合規敏感、建議各自獨立 PR + 安全評估**。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R71-1 | **動物欄位修正核准補 audit + 交易原子性** | `services/animal/field_correction.rs:147 review` 核准會直接改動物 identity 欄位（耳號/出生日期/性別/品種，`apply_correction:207`）卻**無 audit、無 tx（改動物與標記申請非原子）、無 FOR UPDATE**，權限用 `is_admin()` 硬編碼。改為單一 tx 包裹 + `log_activity_tx`（記 before/after DataDiff）+ `SELECT FOR UPDATE` + 改 `require_permission!`。**合規風險最高項**。先寫 acceptance test（核准後 user_activity_logs 有對應 entry）→ 紅 → 實作 → 綠 | [x] |
| R71-2 | **PI 帳號邀請核准寄送補 audit + service 下沉** | `handlers/protocol/pi_provision.rs:101 approve_send_pi_invite` 業務邏輯 + raw SQL 混在 handler（違反分層）、**無 tx、無 audit**、`is_admin()` 硬編碼。下沉 service 層 + tx 包裹（SELECT FOR UPDATE → 產 reset token → 寄信 → 標記 sent）+ `log_activity_tx`（寄送開通信為敏感動作）。並發冪等保護 | [x] |
| R71-3 | **設備閒置申請核准補 tx/audit/ActorContext** | `services/equipment.rs:1847 approve_idle_request` 為同檔離群者：**無 tx、無 FOR UPDATE、無 audit、未用 ActorContext**（SELECT→UPDATE idle_request→UPDATE equipment→INSERT status_log 各自對 pool 散打）。比照同檔 `review_maintenance_record`（tx + FOR UPDATE + `log_activity_tx` + `require_user()`）對齊 | [x] |
| R71-4 | **Amendment 決議補全域 audit chain** | `record_amendment_decision`（`workflow.rs:530`）與 `classify`（`:304`）終態僅寫 `amendment_status_history` + 簽章表，**未寫 user_activity_logs/HMAC chain**（對比 `mark_effective` ✅ 與 protocol 狀態變更 ✅）。最核心的核准/否決決議反而 audit 薄弱。補 in-tx `log_activity_tx`；另修 REVISION 分支 history actor 用 `SYSTEM_USER_ID` 而非觸發者（`workflow.rs:656`）的歸因失真 | [x] |
| R71-5 | **Amendment 泛型狀態變更 history 移入 tx** | `change_amendment_status`（`workflow.rs:690`）的 `record_status_change` 在 `tx.commit()` **之後**才用 pool 寫 history（`:756→758`）→「狀態已變、歷程遺失」窗口。將 history 寫入移入同 tx（比照 `mark_effective`） | [x] |
| R71-6 | **GLP management_review 核准守衛 + 結案報告/管理審查簽署流程** | `update_management_review`（`glp_compliance.rs:467`）`status=COALESCE($4,status)` **無 RELEASE_STATUSES 守衛**，持 perm 者可經泛型 PUT 直接設 status 並寫 `approved_at`（`migrations/016:249`），繞過簽核 → 潛在 SoD 漏洞。先比照 change_request/study_report 補發布狀態守衛；正式 `sign_study_report`/管理審查簽署流程為已知 follow-up（`glp_compliance.rs:1218-1220`） | [x] |
| R71-7 | **Protocol 核准與電子簽章耦合不變式** | `change_protocol_status`（`status.rs:24`）推進到 APPROVED 不寫簽章（簽章走獨立端點 `/signatures/protocol/:id`），無不變式保證「已核准必有簽章」，與 amendment 終態自動簽章不一致。評估是否強制耦合或加 APPROVED→簽章前置守衛。另 `Protocol.version` 樂觀鎖欄位閒置未用（`protocol.rs:124`） | [x] |
| R71-8 | **前端核准權限 gate 機制統一** | 前端三套混用：`hasPermission(token)`（GLP/設備/Amendment 生效）vs role 字串比對（Protocol/ERP）vs **完全無前端 gate**（PI 邀請 `PiAccountInvitesTab.tsx:88`、動物欄位修正 `AnimalFieldCorrectionsPage.tsx:181`）。統一為 `hasPermission`；#5/#8 補前端 gate。code-only | [x] |
| R71-9 | **前端核准鈕補防連點 disable** | `ChangeControlPage.tsx:181`（GLP 核准鈕）與 `IdleTabContent.tsx:93-97`（設備閒置 icon 鈕）無 `disabled={mutation.isPending}`，可連點。補 disable + spinner。code-only | [x] |
| R71-10 | **前端核准鈕補確認對話框 + 駁回填原因** | Protocol 核准（僅 Select 對話框）與其他核准動作（ERP 倉庫/最終核准、GLP、設備閒置、動物欄位修正批准）皆**未採用標準確認對話框**（部分無確認、部分確認方式非標準）；設備閒置駁回固定送 `'駁回'`（`EquipmentPage.tsx:321`）未提供填寫 UI。補 `useConfirmDialog` + 駁回原因輸入。需確認哪些屬高風險須確認（產品決策）。〔2026-06-16 拍板〕高風險+ERP/GLP 4 項加確認框（Protocol/動物欄位修正/ERP 最終核准/GLP），設備閒置（低風險）不加；動物欄位修正拒絕原因改必填、設備閒置駁回補 `window.prompt` 原因（PR #734） | [x] |
| R71-11 | **核准按鈕 i18n 去硬編碼** | ERP 單據（`DocumentDetailPage.tsx:391`）、GLP 變更請求（`ChangeControlPage.tsx:182`）、PI 邀請（`PiAccountInvitesTab.tsx:89`）、動物欄位修正（`AnimalFieldCorrectionsPage.tsx:193`）的按鈕文字與 toast 為硬編碼中文，改走 `t()`。〔2026-06-16 不適用〕經查 4 頁 100% 硬編碼中文、零 i18n（`useTranslation`/`t()` 皆 0）；皆為**內部管理/運維頁、非客戶用**（使用者裁定不需 i18n）。button-only i18n 會造成 partial-i18n 不一致（reviewer bot 已警告），故**不實作** | [x] |
| R71-12 | **確認 Amendment 決議前端 UI 是否缺漏** | 後端 `record_amendment_decision`（`/amendments/:id/decision`）、`change_amendment_status`（`/amendments/:id/status`）存在，型別亦定義（`types/amendment.ts:128-129`），但前端**零呼叫端**（已 grep 確認）。需確認審查決議是否經其他 UI 路徑（如共用 protocol 審查介面）或尚未實作決議 UI。先盤點確認再決定是否補實作。〔2026-06-16 盤點完成〕**確認缺漏**：`/amendments/:id/decision`、`/amendments/:id/status` 前端**零呼叫端**；前端 amendment 動作僅 create/submit/markEffective（`AmendmentsTab`），`MyAmendmentsPage` 唯讀。後端 workflow + `amendment_decision_recorded` 通知存在（決議有設計）但 reviewer 決議介面未建。**補實作屬獨立功能**（reviewer 投票 APPROVE/REJECT/REVISION + 分類 + 意見整合），非 R71 quick-follow-up → 列 backlog 待產品決策 | [x] |

> **待產品/合規拍板（未逕自立案為實作項）**：(1) 二級認證是否擴及 Protocol 核准 / ERP 單據最終核准（目前僅設備維護驗收有簽章+密碼）；(2) 各核准動作是否補 `version` 樂觀鎖（現全採悲觀鎖派）；(3) §1 流程層級排除假設 — GLP 變更請求 / 設備閒置·維護 / 動物欄位修正是否應比照相鄰排除項一併排除。
>
> **〔2026-06-16 拍板〕**：(1) 二級認證 → **延後**（不綁本輪）；(2) 鎖策略 → **採悲觀鎖**（R71-1~3 用 `SELECT FOR UPDATE`，本輪不補 `version`）；(3) 流程排除 → **逐項決定**：動物欄位修正（R71-1）/ 設備閒置（R71-3）/ GLP 守衛（R71-6）**納入並完成**（PR #722/#724/#725），HR 請假·加班 + 安樂死 **另開新盤點輪**（已盤點，見下方 R72）。

---

## 🔍 R72 — 「核准」按鈕盤點 Round 2：HR + 安樂死 follow-up（2026-06-16 立案）

> 來源：盤點 Round 2，報告見 `docs/audit/approval-buttons-inventory-round2-hr-euthanasia-2026-06-16.md`。承接 R71 收尾後指定「另開新盤點輪」的 HR 請假·加班核准 + 安樂死核准/申訴。核心發現：**兩塊後端防護大致健全**（安樂死已於 R30 達 GLP 級完整；HR 具 tx/鎖/稽核/狀態守衛），缺口集中在**前端**（gate/防連點/確認框）+ HR 核准通知。⚠️ 初掃曾誤判「HR 加班核准無 409 → race」，經人工驗證為誤報（`FOR UPDATE` 已序列化並發）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R72-1 | **安樂死前端核准鈕補 gate + 防連點 + 終決確認框** | 後端已完整（R30）；前端 `EuthanasiaPendingPanel.tsx` / Chair 仲裁面板：(a) PI 核准/申訴/Chair 三鈕無 `hasPermission`/`hasRole` 前端 gate；(b) PI 核准/申訴/Chair 鈕無 `disabled={mutation.isPending}` 防連點；(c) 終決性動作（核准/Chair 決定）無二次確認框。補齊。code-only frontend。〔2026-06-16 完成〕Chair 仲裁面板補 `hasRole('IACUC_CHAIR')` gate（非主席不取資料/不顯示）+ 動作鈕防連點；PI 面板防連點已有、核准走簽章板、申訴有原因框、僅顯示本人單據（隱性 gate）故不動（PR #736） | [x] |
| R72-2 | **HR 請假/加班前端核准鈕補 gate + 確認框** | `LeavePendingApprovalsTab.tsx` / `PendingApprovalsTabContent.tsx`（加班）核准鈕無前端權限 gate、無確認對話（防連點 `disabled` 已有）。補 `hasPermission` gate + `useConfirmDialog`。可與 R71-8~11 前端統一批次合併處理。〔2026-06-16 完成〕確認框：請假/加班核准·駁回補 `useConfirmDialog`（含並發守衛，PR #736）。gate：HR 核准授權為 role + 部門主管關係（無 permission code），改採**後端逐列 `can_approve` 旗標**（依 status + 角色/部門主管計算、含禁自審），前端逐列 gate 核准/駁回鈕（PR #738）| [x] |
| R72-3 | **HR 請假/加班核准補核准結果通知** | `approve_leave` / `approve_overtime` 核准後未發通知給申請人（僅 `submit_*` 時有 `notify_*_submitted`）。申請人不知核准結果、可能重複申請。補 fire-and-forget 通知（比照 submit 路徑）；查詢申請人 email 時須檢查 `is_active = true` 且 `deleted_at IS NULL`（不寄給停用/已刪除帳號，GDPR）。〔2026-06-16 完成〕`notify_leave_approved`/`notify_overtime_approved`（applicant-targeted + GDPR active 檢查），handler 於**最終核准**（APPROVED / approved）後 tokio::spawn 發送；請假通知用中文假別（PR #737）| [x] |
| R72-4 | **HR 核准權限風格一致化（評估）** | `approve_leave`/`approve_overtime` 權限為 handler 內 `is_admin()`/`ROLE_ADMIN_STAFF`/部門主管硬編碼判斷，非 `require_permission!`。與全站不齊。評估改細粒度權限（如 `hr.leave.approve`/`hr.overtime.approve`，需新增權限 seed）或維持現狀。低風險。〔2026-06-16 結論〕**維持 role-based**（不新增 permission）—— HR 核准含「部門主管-of-申請人」關係，非靜態角色/permission 可表達；改由 R72-2 的後端 `can_approve` 旗標暴露授權結果（PR #738），達成前後端一致 | [x] |

> **待產品/合規拍板（未逕自立案）**：HR 請假/加班核准是否需電子簽章？安樂死/GLP record 因 21 CFR §11 需簽章，但 HR 屬一般行政審批、非 GLP raw data，**傾向不需**；待產品/合規確認。

---

## 🐞 R74 — PR #744 預覽一致化期間挖到的既有 bug（2026-06-17 立案）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R74-1 | **AUP「匯出 Word」下載損毀 .docx** | print-pdf `/render-aup/from-working-content` 自 WeasyPrint 化以來**無視 `format` 參數、永遠回傳 PDF**；`ProtocolDetailHeader`「匯出 Word」按鈕下載到 `.docx` 副檔名但內容為 PDF 的損毀檔。**已採方案 (b)（PR #745，2026-06-17 merged+部署 prod）**：移除按鈕 + backend docx 分支（理由：Word 本質無法與 PDF pixel-perfect，再做等於再養一套會分岔的模板） | [x] |

---

## 🔒 R76 — 計畫書草稿可見性 + 執秘內容唯讀（2026-06-24 使用者回報）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R76-1 | **草稿可見性收緊（修 EXPERIMENT_STAFF 看到他人草稿）** | `list_protocols`/`ProtocolService::list` view_all 分支改「非草稿全覽 + 草稿僅 PI/SD/成員或監督角色（IACUC_STAFF/IACUC_CHAIR/admin）可見」；編輯/送出收緊為 admin/PI/SD（`can_edit_protocol`/`submit_protocol` 移除 view_all·edit-perm·CLIENT·CO_EDITOR 路徑）；執秘 seed 移除 edit/submit（migration 105）但保留 SD 指派（`authorize_update` 欄位感知）。`ProtocolListItem.can_edit` 供前端 gating。對齊原始 spec §4.1。詳見 PROGRESS §9 2026-06-24。測試 `api_protocol_draft_visibility` + 既有授權測試更新 | [x] |
| R76-2 | **CO_EDITOR 角色完整拆除** | **已完成（2026-06-24，stacked PR on #791）**：移除 `protocol_role` enum 的 CO_EDITOR（migration 106 重建 enum + 刪既有成員列）、assign/list/remove handler+route+service、DTO、`aup.coeditor.assign` 權限、前端 `CoEditorsTab` + 狀態變更流程。行政預審前置條件改「須已指派 SD」；通知改 PI+SD。**保留** `protocol_activity_type` 的 `COEDITOR_*`（歷史稽核）。後端 35 測試綠、前端 tsc/eslint clean。i18n 死字串留 trivial follow-up | [x] |

---

## 🐷 R79 — 動物預約與試驗規劃（2026-07-01 立案，①b-2 預定客戶 + ③ 體重報表合併）

> 背景：匯入體重後續 ①b-2「預定客戶」與 ③「體重報表」討論後**合併為一個大功能**——執行秘書一頁看全場動物**按試驗分組**、**需求 vs 已預約/已分配缺口**，把未分配動物**兩段式（預約 → 正式分配）**配到試驗（已核准讀 protocol / 規劃中讀新表 planned_experiments）；搜尋（體重/年齡）多選批次配對缺口；備註可改、體重唯讀；只未分配可預約、分配進實驗自動清。權限：執行秘書 + 管理員。設計 + mockup + 分階段計畫：`docs/design/animal-reservation/`；決策見 memory `animal-reservation-planning`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R79-1 | **Phase 0 — schema（#829 / migration 117）** | 新表 `planned_experiments`（unit/description/demand_count/protocol_id）+ `animals` 加 `reserved_protocol_id`/`reserved_planned_experiment_id`（二擇一 CHECK、僅未分配、分配自動清）+ 部分索引；data_export 納入。已合併並部署 prod（migration 撞號事故對帳後）。 | [x] |
| R79-2 | **Phase 1 — planned_experiments CRUD** | model DTO + repository + service + handlers + routes（`GET/POST /planned-experiments`、`PUT/DELETE /:id`）；權限秘書+管理員；service-driven audit。已合併 #837。 | [x] |
| R79-3 | **Phase 2 — 預約 + 正式分配 + 搜尋** | reserve/unreserve endpoint（批次 `animal_ids`、校驗未分配）；正式分配重用既有 `POST /animals/batch/assign` 並清空 reservation；搜尋 `GET /animals/reservable`（體重/週齡/性別，只回未分配未預約）。已合併 #839。 | [x] |
| R79-4 | **Phase 3 — 規劃分組查詢** | `GET /reservation-planning`：union 已核准 protocols（需求讀申請動物數）+ planned_experiments，各帶 demand/reserved_count/assigned_count + 動物 rows。已合併 #840。 | [x] |
| R79-5 | **Phase 4 — 規劃頁前端** | 新頁（sidebar + 權限 gate）：分組表 + summary + 新增預定試驗 + 搜尋配對 modal（多選批次）+ 兩段式操作 + 備註（v1 唯讀）+ 體重唯讀；RWD 走 `/system_table_chats`。已合併 #841。 | [x] |
| R79-6 | **Phase 5 — 全場活豬清冊改造** | 重新定位：頁改「全場活豬按計劃分配清冊」。(a) 置頂「未分配備用池」sticky 面板（篩選/多選批次預約）(b) 顯示全場活豬（unassigned/in_experiment/completed，排除 euthanized/sudden_death/transferred）(c) 空的已核准計劃也顯示露缺口（自動排除 Closed/Suspended）(d) completed 計入缺口、pills 拆 實驗中/已完成 (e) orphan catch-all 組接非顯示計畫的活豬 (f) 備註整格 inline 編輯（PATCH /animals/:id/remark，audited）。設計 + 預覽 `docs/table-preview-ReservationPlanningTable.html`。已合併 #845（未部署）。 | [x] |
| R79-7 | **計畫結案防呆** | `change_status_tx` 轉 `Closed` 前檢查該計畫無存活動物（`in_experiment`/`completed`/`unassigned`，含 `reserved_protocol_id` earmark），否則拒絕（先犧牲/轉讓/解約）+ TOCTOU 行鎖。已合併 #846（未部署）。 | [x] |

---

## 變更紀錄（封存，不再新增——變更日誌統一記錄於 `docs/PROGRESS.md` §9）

| 2026-03-26 | 🧠 Claude：R13 更新計畫全面完成 — P0 CI 觸發恢復（P0 歸零）；P1 品質強化（49 Vitest 測試、4 元件 Props 合併、4 audit 色彩 token、CSRF 419）；P2 中優先（FormField 12 檔統一、StatsCard 共用元件、請假日期時區修復、UserEditDialog 單一資料源重構）；P3 長期演進（Dependabot 2.5 utoipa5/axum-extra0.12/tw-merge3、QA browser scripts、E2E 8→12 specs +18 tests）；R12-1 完成、R12-2 暫緩。待辦 5→2。 |
| 2026-03-25 | 🧠 Claude：gstack 全面審查 + Simplify 重構 — Code Review（/review）8 auto-fix + 4 user-approved（deleteResource data 遺失、Retry-After NaN、overtime validation、stale closure、hidden tab bypass、canEditProtocol）；安全審計（/cso）92/100 → 4 項修復（AI rate limit 強制、Cargo.lock 追蹤、CI script injection、/metrics auth）；Simplify（DataTable 7 檔、StatusBadge 7 檔、FilterBar 4 檔、檔案拆分 5→19 檔、watch() 優化 4 檔、formatDate 統一 4 檔）；zodResolver 型別修復 7 檔。待辦 5→5。 |
| 2026-03-25 | 🧠 Claude：RHF+Zod 全面遷移完成 + UI 債清零 — **RHF+Zod** 從 1 檔擴展到 17 檔（Auth 3 頁 + Master 5 頁 + Admin UserForm 3 dialog + AnimalEdit + ApAging + ArAging + WarehouseLayout + Partner + HR 2），新增 10 個 Zod schema 到 validation.ts。**PageHeader** 35 頁遷移。**PageTabs** 9 頁遷移（含 AdminAudit hook 重構）。**EmptyState** 24 檔（19 TableEmptyRow + 11 standalone）。**i18n** 28 處修復跨 15 檔。**a11y** 93 處修復跨 43 檔（73 aria-label + 20 input label）。設計合規度 ~92%。 |
| 2026-03-25 | 🧠 Claude：RHF+Zod 延伸遷移 + DataTable 套用 + Protocol Tab URL 同步 — Partner 表單遷移到 RHF+Zod（`partnerFormZodSchema`，欄位級錯誤顯示，移除手寫 regex 驗證）；HR 5 個列表元件遷移到 DataTable（MyLeaves/AllRecords/PendingApprovals/MyOvertime/PendingOT，移除手寫 Table+Skeleton+Empty）；ProtocolDetailPage 9 個 Tab 從 useState 遷移到 PageTabs URL sync（支援瀏覽器前進/後退/分享連結）；刪除 ProtocolTabNav.tsx（已廢棄）。 |
| 2026-03-25 | 🧠 Claude：R12-4~R12-7 全部完成 — 硬編碼色彩從 748→112（-85%，含 auditLogs 58 處、Auth 表單 85 處、constants 12 處、ErpWidgets 17 處）；HR Leave/Overtime 表單遷移至 React Hook Form + Zod（欄位級驗證錯誤顯示）；Sidebar 子系統色相動態套用（NavItem.subsystem → bg-subsystem-* active 色）；CSRF Token 客戶端自動刷新機制（403 偵測 → GET /auth/me 刷新 cookie → 重試）。待辦 9→5。 |
| 2026-03-24 | 🧠 Claude：UI 一致性重構與設計系統合規 — 新增 5 個共用框架元件（PageHeader/FilterBar/PageTabs/DataTable/StatusBadge）；語義化色彩系統（6 組 status token + 5 子系統色相，Light/Dark 雙主題）；硬編碼色彩從 748→262 處（-65%）；HR 模組全面重構（4 頁遷移 PageHeader+PageTabs、Tab URL 同步、移除 window.location.reload）；ERP/動物管理/Admin/報表/文件模組批次清理；Backend 安全掃描 92/100。新增 R12-4~R12-7 待辦。待辦 5→9。 |
| 2026-03-23 | 🧠 Claude：設備維護管理系統擴充 — Migration 018 新增 6 enum + 5 張新資料表；後端完整 CRUD（廠商/校正確效查核/維修保養/報廢/年度計畫）；前端三個新分頁（維修保養/報廢/年度計畫矩陣）；Email 通知模板 + 排程逾期檢查 + 報廢電子簽章。AI 資料查詢接口 — Migration 017、API Key SHA-256 認證、6 個查詢領域（animals/observations/surgeries/weights/protocols/facilities）、查詢日誌。圖片處理獨立服務 `image-processor/` 上線（R12-3 完成）。會計 Repository 層提取（`repositories/accounting.rs`）。多項 Bug 修正：調整單效期欄位驗證、調撥單批號效期顯示、儲位下拉選單。Dependabot 依賴更新（axum 0.8.8、tower-http 0.6.8、rand 0.9.2、zip 7.2.0、i18next 25.10.4 等）。CI 修復（cargo deny、npm audit、Trivy、SQL guard）。待辦 6→5。 |
| 2026-03-23 | 🧠 Claude：R9-C2 CI 密碼改 GitHub Secrets — `ci.yml` 和 `docker-compose.test.yml` 中的 JWT_SECRET、DEV_USER_PASSWORD、ADMIN_INITIAL_PASSWORD 改為 GitHub Secrets 參照（`CI_JWT_SECRET`、`CI_ADMIN_PASSWORD`、`CI_DEV_PASSWORD`）。DB 密碼維持硬編碼（CI 臨時容器，風險極低）。待辦 7→6。 |
| 2026-03-21 | 🧠 Claude：R10 程式碼審查 17/20 完成 — M2 確認無 N+1、M3 MIME 預檢+欄位級大小檢查、M4 unwrap 已清零、M5 CSRF Signed Double Submit Cookie、M6 Zod 驗證、M7 MIME 白名單、M9 Alert 門檻收緊、M10 確認已安全；L1 auth handler 拆分（734→7 檔）、L2 auth service 拆分（1006→6 檔）、L3 signature 拆分（1459→11 檔）、L4 product service 拆分（832→3 檔）、L6 Cookie consent 重寫、L7 密碼 10 字元+黑名單、L8 Watchtower 3600s、L9 login_events 索引、L10 JSONB 驗證。M1/M8/L5 推遲。待辦 27→7。 |
| 2026-03-21 | 🧠 Claude：R11 技術債全部清零 — R11-15 中大型元件拆分（10 個元件全部降至 ≤300 行，平均縮減 -80%）；R11-21 前端 try-catch 重構（25 處改為 useMutation，27 處合理保留）；R11-22 源碼 TODO 清理（stocktake 類別篩選實作、MyProjectDetailPage 動物查詢實作）。待辦統計 30→27。 |
| 2026-03-20 | 🧠 Claude：未追蹤項目納入 TODO — P0-R12-1 CI 自動觸發恢復、P0-R12-2 SQL 字串拼接殘留修復、R11-22 源碼 TODO 註解清理、R12-1/R12-2/R12-3 長期演進項目（Dependabot 2.5 升級/財務模組 Phase 2–5/圖片處理獨立服務）。待辦統計 25→31。 |
| 2026-03-15 | 🧠 Claude：R9 安全與品質修復 — R9-1 IDOR 漏洞修復（`download_attachment`/`list_attachments` 加入 entity_type 權限檢查）、R9-2 上傳 handler 去重（抽取 `handle_upload()` 通用函式，606→420 行）、R9-3 DB 錯誤碼修正（23505→409、23503/23502/23514→400）。R9-4 歡迎信安全改善、R9-5 ERP/HR 整合測試待後續排程。 |
| 2026-03-15 | 🧠 Claude：Git 歷史紀錄深度清理 — 徹底移除被誤傳進 Git 的 `.venv` 目錄（體積過大）與 `old_ipig.dump`（敏感資料）。使用 `git-filter-repo` 重寫倉庫歷史，移除檔案足跡並減小倉庫體積。更新 `.gitignore` 確保未來不再追蹤。 |
| 2026-03-15 | 🧠 Claude：單據頁面標題顯示優化 — 修正「建立新的undefined」問題。當類型未定時顯示「建立新的單據」。優化「新增/編輯」描述文字。 |
| 2026-03-14 | 🧠 Claude：SSE 安全警報 Cloudflare 524 Timeout 修復 — 後端 `sse.rs` 心跳從 `.text("")` 改為 `.comment("heartbeat")` 並間隔從 30s 縮至 15s；前端 `useSecurityAlerts.ts` 加入指數退避重連（5 次，2s→32s），連線成功重置計數器。 |
| 2026-03-14 | 🧠 Claude：儀表板 Widget 捲動體驗優化 — 統一所有 Dashboard Widget 的樣式，確保 `CardContent` 具備 `flex-1 overflow-auto` 捲動條，且 `Card` 標題固定不隨內容捲動。涵蓋「我的計畫」、「動物用藥」、「請假餘額」、「醫事評論」及所有 ERP 內嵌 Widget。 |
| 2026-03-14 | 🧠 Claude：修復 `010_treatment_drug_final.sql` 編碼問題 — 修正非 UTF-8 亂碼內容，確保資料庫遷移能順利通過 Docker 建置。 |
| 2026-03-14 | 🧠 Claude：R4-100-T5 protocol/document/hr 服務單元測試完成 — protocol/numbering 提取 `parse_no_sequence`/`format_protocol_no` + 8 測試；protocol/status 測試 `validate_protocol_content` 7 測試；hr/leave 測試 `is_half_hour_multiple`/`effective_hours` 7 測試；hr/overtime 提取 `overtime_multiplier`/`comp_time_hours_for_type`/`calc_hours_from_minutes` + 8 測試；hr/attendance 測試 `is_ip_in_ranges`/`attendance_status_display` 8 測試；hr/balance 提取 `compute_leave_expiry` + 4 測試；document/grn 提取 `next_seq_from_last_no`/`receipt_status_label` + 8 測試。共 50 個新單元測試，cargo check --tests 通過。 |
| 2026-03-14 | 🧠 Claude：R4-100-T6 cargo-tarpaulin CI 覆蓋率量測 — ci.yml 新增 `backend-coverage` job，`SQLX_OFFLINE=true` 僅跑 lib 單元測試，`--fail-under 25` 設定門檻，產出 XML 報告並上傳為 artifact（保留 14 天）。 |
| 2026-03-14 | 🧠 Claude：品項選擇與單據關連優化 — (1) 在新增明細彈窗加入動態品類篩選（Tabs）；(2) 修正 GRN 來源單據選擇邏輯與 API 400 報錯，確保僅能選擇匹配供應商且已核准的 PO；(3) 修復 Inventory Low-Stock API 500 報錯；(4) 修正 `poReceiptStatus` 未傳遞至 `DocumentLineEditor` 導致待入庫明細未顯示的漏洞。 |
| 2026-03-14 | 🧠 Claude：品項選擇品類篩選優化 (已修正實作) — 在新增明細彈窗加入動態品類篩選（ Tabs），修正調用錯誤 API 的問題，整合 `useSkuCategories` 並修改庫存 API 以支援 `category_code` 過濾，大幅提升 UX。 |
| 2026-03-14 | 🧠 Claude：採購入庫品項篩選強化 — 修正 `GRN` 品項篩選邏輯。新增「來源採購單」選擇 UI 與連動篩選，修正 `poReceiptStatus` 查詢參數，確保 GRN 僅能選擇關聯 PO 之待入庫品項並自動帶入數據。 |
| 2026-03-14 | 🧠 Claude：單據頁面 UI 體驗優化 (V2) — 隱藏銷貨單/出庫單重複的客戶下拉選單；為調撥單新增來源與目標儲位的批次套用功能；將表頭儲位選擇重新標註為「批次套用儲位 (選填)」，並實作新增明細時自動繼承批次儲位的優化，提升同一採購單多儲位的輸入彈性。 |
| 2026-03-14 | 🧠 Claude：修復單據編輯頁面儲位選單問題 — 修正「批次套用儲位」選單選取後 UI 未更新標籤的問題，透過新增 `batchStorageLocationId` 狀態實現正確的 UI 綁定。 |
| 2026-03-14 | 🧠 Claude：專屬計畫載入效能優化 — 擴展 `PO`/`PR` 單據類型的計畫載入觸發條件，解耦 Loading 狀態並解決 UI 始終顯示「載入中」的問題。 |
| 2026-03-14 | 🧠 Claude：庫存導向式品項挑選 — 強化後端 `get_on_hand` API 以支援批號效期細項；改造前端明細挑選彈窗，在涉及現有庫存的單據中自動顯示庫存清單，並實現品項、批號、效期與儲位的一鍵填充。 |
| 2026-03-13 | 🧠 Claude：單據欄位規範調整與邏輯增強 — 實作依單據類型動態切換欄位必填與可見性（倉庫、貨架、計畫、供應商）、實作批號效期強制校驗、IACUC 銷貨警告、庫存流水計畫追蹤。 |
| 2026-03-13 | 🧠 Claude：前端編譯錯誤修復 — 修正 `DocumentEditPage.tsx` 漏掉了 `setFormData` 的解構問題，恢復前端 `npm run build` 與 Docker 建置。 |
| 2026-03-13 | 🧠 Claude：測試基礎設施修復 — 修正 `backend/tests/common/mod.rs` 中 `ensure_admin_user` 函數參數遺漏問題，恢復整合測試代碼編譯。 |
| 2026-03-13 | 🧠 Claude：採購單未入庫通知與狀態顯示 — 實作 `notify_po_pending_receipt` 邏輯、每日 09:00 排程、手動觸發 API；前端新增 `receipt_status` 型別支援與單據列表彩色狀態標籤。 |
| 2026-03-13 | 🧠 Claude：ERP 庫存管理與視覺體驗優化 — 解決「庫存查詢」下拉選單透明重疊問題（引入 Popover.Portal + Glassmorphism）；重塑 Empty State 與表格 Layout；新增「未分配庫存查詢」端點與前端支援；下拉選單穩定性優化；Migration 整合清理。 |
| 2026-03-10 | 🧠 Claude：系統內所有電話欄位（使用者、交易夥伴、動物來源、AUP 計畫主持人/資助者）新增選填「分機」欄位，同步更新前後端型別定義、資料庫 Migration、PDF 產生邏輯與 UI 輸入框。 |
| 2026-03-10 | 🧠 Claude：AUP 計畫主持人電話新增「分機」欄位，同步修復前端類型定義 (phone_ext) 與 `CreateProductPage.tsx` 缺失的 `useEffect` 匯入，確保 Docker 編譯通過。 |
| 2026-03-09 | 🧠 Claude：重構動物服務模組，將 AnimalService 拆分為 9 個專屬 Service，提升代碼組織與可測試性。 |
| 2026-03-09 | 📄 請假管理動作成功後自動重新整理頁面，確保餘額與狀態完全同步。 |
| 2026-03-09 | 📄 API 規格文件全面對齊程式碼（第二輪）— 轉讓端點修正、移除未實現端點、補齊 care-records/treatment-drugs/SSE 等 12 組未記錄端點、ENUM/權限代碼修正、設施遷移待辦新增 |
| 2026-03-08 | 🔒 R7 安全審視完成 — R7-P0 SQL injection 修復、R7-P1 密碼洩露/TRUST_PROXY 修復、R7-P4 ETag 常數化/Auth rate limit 降低；文件全面對齊程式碼 |
| 2026-03-02 | 📄 文件同步：PROGRESS.md 更新至 v5（2026-03-02 動物欄位修正申請）；Profiling_Spec 規格同步；R6 待辦統計校正 |
| 2026-03-01 | 🧠 Claude：R6 第六輪改善全部完成 — R6-4 產出 `docs/assessments/R6-4_FINANCE_PHASE2_5_ASSESSMENT.md`；R6-5 產出 `docs/assessments/R6-5_DEPENDABOT_PHASE25_ASSESSMENT.md` |
| 2026-03-01 | 🧠 Claude：R6 第六輪改善執行 — R6-1 EquipmentPage/TrainingRecordsPage；R6-2 useDateRangeFilter、useTabState 建立並套用 8 頁；R6-3 InlineSkeleton 改 span |
| 2026-03-01 | 🧠 Claude：建立 R6 第六輪改善計劃 — R6-1 useState→hooks 擴展、R6-2 useDateRangeFilter/useTabState、R6-3 Skeleton DOM 修正、R6-4 財務模組評估、R6-5 Dependabot Phase 2.5 評估。依據專案評估產出 |
| 2026-03-01 | 🧠 Claude：財務 SOC2 QAU 三項規劃完成 — QAU 角色/儀表板（022、GET /qau/dashboard、QAUDashboardPage）；SOC2 憑證輪換腳本、SLA.md、DR_DRILL_CHECKLIST；財務 AP/AR/GL（023–024、AccountingService、AccountingReportPage）。詳見 `docs/PROGRESS.md` §9 |
| 2026-03-01 | 🧠 Claude：P0–P2 改進計劃全部完成 — P1-M0 稽核匯出 API、P1-M1 API 版本、P1-M2 GDPR、P1-M3 OPERATIONS.md、P1-M4 憑證輪換、P1-M5 Dependabot；P2-M2 人員訓練紀錄、P2-M3 設備校準、P2-M4 稽核 UI 使用者篩選、P2-M5 security/SOC2_READINESS.md。詳見 `docs/development/IMPROVEMENT_PLAN_MARKET_REVIEW.md` |
| 2026-02-28 | 🧠 Claude：第三輪系統改善 20 項（P0-R3-1~4 安全 + P1-R3-5~10 效能 + P2-R3-11~20 品質/維運）— SQL QueryBuilder 統一/IDOR 修補/expect() 清理/非 root 容器/搜尋 debounce/staleTime 調優/AnimalsPage 拆分/DashMap Rate Limiter/DB Pool 指標/Skeleton Loading/Protocol any 消除/審計日誌/常數提取/Error Boundary/SSL 範本/備份驗證/Loki 日誌/環境驗證/無障礙/API 一致性。詳見 `docs/development/IMPROVEMENT_PLAN_R3.md` |
| 2026-02-28 | 🧠 Claude：第二輪系統改善 15 項（P0-R2-1~2 安全 + P1-R2-3~8 效能/可靠性 + P2-R2-9~15 品質/維運）— DOMPurify XSS 防護/Rate Limiting 分級/jsPDF 動態導入/動物列表分頁/健康檢查深度擴充/Alertmanager 告警/SMTP 重試/Query Key Factory/Zod 表單驗證/i18n 補齊/Zustand Selector/DB 維護自動化/Dependabot/零停機遷移策略/架構圖。詳見 `docs/development/IMPROVEMENT_PLAN_R2.md` |
| 2026-02-28 | 🧠 Claude：系統改善 14 項（P0-S1~S3 安全性 + P1-S4~S8 效能 + P2-S9~S14 品質）— Docker 網路隔離/DB 埠口/Secrets + N+1 修復/批次 INSERT/移除 .expect()/複合索引 + is_admin()/UserResponse 提取/TypeScript 嚴格化/API 錯誤統一/MainLayout 拆分/Memoization/cargo-chef。詳見 `docs/development/IMPROVEMENT_PLAN_R1.md` |
| 2026-02-28 | 🧠 Claude：完成最終 3 項 P5 待辦 — (1) P5-13 Storybook 15 個 Stories；(2) P5-15 TOTP 2FA 全端實作（後端 totp-rs + 4 API + 登入流程 + 備用碼，前端 QR Code + TOTP 驗證 + Profile 管理）；(3) P5-16 WAF OWASP ModSecurity CRS v4 overlay 部署 + 自訂排除規則 |
| 2026-02-28 | 🧠 Claude：系統設定全端串接 — 後端新增 `GET/PUT /admin/system-settings` API + 10 項 DB seed；前端 SettingsPage 四大區塊（基本/庫存/郵件/安全）全部從 API 載入與儲存；通知路由管理 UI 改善（收合分類/Switch/角色名稱/ConfirmDialog/grid layout）|
| 2026-02-28 | 🧠 Claude：P5-14 ProtocolDetailPage 重構 1,929→647 行（-66%），抽離 VersionsTab/HistoryTab/CommentsTab/ReviewersTab/CoEditorsTab/AttachmentsTab 6 個元件至 `components/protocol/` |
| 2026-02-28 | 🧠 Claude：JWT 預設過期時間從 15 分鐘調整為 360 分鐘（6 小時），更新後端 config / 前端 session fallback / .env / docker-compose 等 7 個檔案 |
| 2026-02-28 | 🧠 Claude：完成 18 項品質補強計畫 — **高影響 6 項**：P1-30 Graceful Shutdown / P1-31 自訂 404 頁面 / P1-32 Session 逾時預警 / P1-33 刪除記錄清理檔案 / P1-34 Optimistic Locking / P1-35 confirm() 統一 Dialog。**中影響 7 項**：P2-36 i18n 補齊 / P2-37 API 分頁 / P2-38 表單離開確認 / P2-39 隱私政策 / P2-40 Cookie 同意 / P2-41 Rollback 文件 / P2-42 .env 補齊。**低影響 5 項**：P5-43 ARIA 標籤 / P5-44 驗證回饋 / P5-45 磁碟監控 / P5-46 LICENSE / P5-47 Meta Tags。|
| 2026-02-28 | 🧠 Claude：完成交付前補強 3 項 — (1) P4-19 Prometheus + Grafana 部署（`docker-compose.monitoring.yml` + `deploy/prometheus.yml` + Grafana provisioning + 10-panel dashboard）；(2) P4-20 後端 API 整合測試（`lib.rs` 重構 + `TestApp` infra + 6 個測試檔 25+ test cases，`cargo check --tests` 通過）；(3) P4-21 效能基準報告（`docs/assessments/PERFORMANCE_BENCHMARK.md` 8 章節正式報告 + k6 腳本 setup() token sharing 優化）。|
| 2026-02-28 | 🧠 Claude：解決 3 個市場交付阻擋項 — (1) 獸醫建議/觀察紀錄檔案上傳下載串接完成（後端新增 `ObservationAttachment` FileCategory + `/observations/:id/attachments` 路由，前端 VetRecommendationDialog 與 ObservationFormDialog 串接 multipart 上傳與下載）；(2) USER_GUIDE.md 從 26 行擴充至完整操作手冊（9 章節含 AUP/動物/ERP/HR/報表/系統管理/FAQ）；(3) docker-compose.prod.yml 補齊所有服務的 CPU/記憶體限制與 json-file 日誌輪轉。|
| 2026-02-28 | 🧠 Claude：完成 P5-14 前端超長頁面重構 — AnimalDetailPage 1,945→748 行（-61%），抽離 7 個 Tab 元件至 `components/animal/`（Observations/Surgeries/Weights/Vaccinations/Sacrifice/AnimalInfo/PathologyTab），TypeScript 零錯誤通過。 |
| 2026-02-28 | 🧠 Claude：完成 P4-17 基礎映像與 CVE 週期檢查 — Dockerfile 版本釘選至 `georgjung/nginx-brotli:1.29.5-alpine`（Alpine 3.23.3），Trivy 掃描確認 CVE-2026-25646 仍存在（libpng 1.6.54-r0→需 1.6.55-r0），.trivyignore 保留並更新註解，下次 Q2 檢查。 |
| 2026-02-27 | 🧠 Claude：完成 P4-18 E2E Rate Limiting / Session 穩定化 — admin-context 改用 storageState 檔案免重複登入、API rate limit 120→600/min、login.spec credential fallback。34/34 連續通過、22s 完成。 |
| 2026-02-27 | 🧠 Claude：E2E 測試總結計畫實施 — 新增 P4-18 Rate Limiting/Session 穩定化待辦；`docs/e2e/README.md` 故障排除 §5 補充 Session 過期導致 429 連鎖失敗說明。 |
| 2026-02-25 | 🧠 Claude：完成 P3-7 SEC-33 敏感操作二級認證 — 後端 confirm-password + reauth token，前後端刪除使用者／重設密碼／模擬登入／刪除角色皆需重新輸入密碼確認。 |
| 2026-02-25 | 🧠 Claude：完成 P1-7 電子簽章合規審查（21 CFR Part 11），新增 `docs/security/ELECTRONIC_SIGNATURE_COMPLIANCE.md`。 |
| 2026-02-25 | 🧠 Claude：完成 P1-12 OpenAPI 完善 — 新增電子簽章（10 paths + 2 附註）、動物管理（9 paths）及對應 Schema。 |
| 2026-02-25 | 🧠 Claude：修正 CI `sqlx-cli` 安裝錯誤，增加 `--force` 以應對快取衝突。 |
| 2026-02-25 | 🧠 Claude：完成 P1-8 資料保留政策 (Data Retention Policy) 定義。 |
| 2026-02-25 | 🧠 Claude：修正 CI Trivy 掃描參數一致性並清理 `.trivyignore` 無效編號。 |
| 2026-02-25 | ⚡ Flash：完成 P1-5 後端壓力測試基準建立 (k6)，已遷移至 PROGRESS.md。 |
| 2026-02-25 | 🧠 Claude：P1-1 E2E 穩定化 — 429 rate limit 重試、React state race condition fallback、連續 3 次 0 failures。 |
| 2026-02-25 | 🧠 Claude：P1-1 Playwright E2E 測試擴充（7 spec, 34 tests, auth setup + 6 critical flows）。 |
| 2026-02-25 | 🧹 整理：將 P0-6, P0-7, P1-6 已完成項目遷移至 `PROGRESS.md`。 |
| 2026-02-25 | ⚡ Flash 任務第二波：完成 P0-6 跨瀏覽器相容性驗證、P1-6 GLP 驗證文件 (IQ/OQ/PQ) 生成。 |
| 2026-02-25 | ⚡ Flash 任務第一波：完成 Brotli、具名隧道腳本、CI/CD DB 整合、操作手冊與 Grafana 分配。 |
| 2026-02-25 | 🏷️ AI 標註：新增建議使用的 AI 模型標註。 |
