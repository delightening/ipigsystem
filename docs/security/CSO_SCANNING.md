# CSO 安全審計紀錄

> 本文件記錄歷次 CSO（Chief Security Officer）自動化安全掃描結果。
> JSON 報告存於 `.gstack/security-reports/`（gitignored）。

---

## 2026-05-29（後續）— 20 輪掃描剩餘較低嚴重度發現 follow-up（<8/10）

> #512 已修掉 5 類 HIGH（A-E）。本 PR 處理 deep-sweep 剩餘的 sub-threshold / defense-in-depth 項。
> 修復前逐項對「含 #512/#511 的最新 main」核對現況，剔除已修 / 不適用者。

| # | 嚴重度 | 缺口 | 處置 |
|---|--------|------|------|
| 1 | LOW/MED | document line `qty` / `unit_price` DTO 無範圍驗證（#512 D 只修了 AP/AR；document 因 ledger 有 `<=0` 補償而當時跳過）→ 負數量可反向污染庫存 | `DocumentService::validate_line_qty_price` helper：移動單據 `qty>0`、ADJ `qty!=0`（帶號）、STK 計數允許 0、`unit_price>=0`。create + update 兩條路徑都套用，附單元測試 |
| 2 | MED 5-6/10 | 前端 `GuidelinesSection.ref.url` + `CalendarView.htmlLink` 直接進 `<a href>`，未過 `safeHref()` → latent XSS（需可寫入 + 點擊） | 兩處 `href` 包 `safeHref()`（擋 `javascript:` / `data:`） |
| 6 | MED | signature bridge `payload`（含明文密碼/簽名）`consume` 後未清，無限期 at-rest 殘留（且無 cron 清理） | **止血**：`consume` 讀走 payload 後立即 `payload = NULL`。完整 column 級加密另開 PR |

### 核對後不在本 PR 處理

| # | 原發現 | 結論 |
|---|--------|------|
| 3 | `audit_hmac_key` <44 字元 silently None → fail-open | **已修（過時發現）**：現行 main 的 `config_check.rs`（R63-B9）已把 `audit_hmac_key.is_none()` 計入 `warn_count`，`main.rs` R30-23 在 `is_production()` 下 `warn_count>0` 即 `exit(1)`。即 production 已 fail-closed。原發現基於 `9390c59e` 舊基準 |
| 5 | euthanasia `vet_user_id`≠`pi_user_id` 無 SoD 守衛 | **政策決定，不做**：單人 xeno 獸醫場景，強制 vet≠PI 會擋掉合法單人流程；靠 audit log 事後可追 |
| 4 | webhook `is_safe_webhook_url` SSRF / IPv6 | **不適用**：現行 main 無通用 webhook sender（僅 inbound alertmanager webhook，非 SSRF 面） |
| 6b | signature bridge 完整 column 級加密 | **另開 PR**：需金鑰管理 + migration + 相容舊資料；本 PR 僅止血 |

---

## 2026-05-29 — 20 輪深度掃描（R15-R34）發現之 5 類 IDOR/驗證缺口修復

> 接續 `security/cso-deep-sweep` 分支的 20 輪掃描記錄。本 PR 修復其中 5 類真實發現
> （前 14 輪聚焦 `/admin/` 授權；R15-R34 逐模組查 object-level 授權 / IDOR）。

| # | 嚴重度 | 缺口 | 修復 |
|---|--------|------|------|
| A | HIGH 9/10 | `vet_advice.rs` create/update **零授權**（delete 已有、create/update 漏）→ 跨計畫竄改獸醫建議 | 加 `require_permission!` + `require_animal_access`（與 delete 一致；update 由紀錄 id 反查 animal_id） |
| B | HIGH 8/10 | observation/surgery/weight/vaccination/blood_test 的 update/delete/copy/mark 只檢 `require_permission!`，缺 `require_animal_access` → 跨計畫改他人醫療紀錄 | 12 個 handler 補 `require_animal_access`；新增 4 個 `get_*_animal_id` resolver（surgery/weight/vaccination/blood_test）到 `access.rs` |
| C | HIGH 9/10 | `cancel_leave` 缺 owner scoping → 任何人取消他人請假（已核准者連帶動餘額） | 加 owner-or-`hr.leave.manage` 檢查（與 update/delete_leave 一致） |
| D | HIGH | AP 付款 / AR 收款 amount **無驗證**（可負/零）→ 污染複式分錄 | 加 `amount > 0` 驗證（document line qty/price 已有 service 層 `<=0` 補償，不重複） |
| E | MED 8/10 | equipment `approve_disposal` 缺 SoD → 同時持 manage + approve 者可自核報廢 | 加 `applied_by != approver` 守衛（與簽章路徑 `sign_disposal_approver_tx` 一致） |

驗證：
- `cargo check --tests`：0 errors
- `cargo clippy --all-targets -- -D warnings`：0 warnings
- `admin_authz_guard` guard test：1 passed
- CI（PR #512）：16/16 checks 綠（含 `cargo test` 整合測試，確認新增 `require_animal_access` 不誤擋合法存取）

**Review 強化（CodeRabbit / Gemini 採納）**：
- 4 個 `get_*_animal_id` resolver 補 `AND deleted_at IS NULL`（與既有 `get_vet_advice_record_animal_id` 一致，避免 soft-deleted 紀錄反查 animal_id）。
- 缺口 C（cancel_leave 授權）下沉至 `HrService::cancel_leave`，handler 不再持 SQL + 授權邏輯（符 CLAUDE.md §4）。
- 缺口 D（AP/AR amount 驗證）下沉至 `AccountingService::create_ap_payment` / `create_ar_receipt`，service 層為唯一邊界。
- cancel_leave 通知以「請假當事人」display_name 為主體（主管代取消時不再誤標取消者）。

---

## 2026-05-28（下午）— 8 輪多面向掃描（Round 7-14），5 項修復 + 2 項待裁定

### 掃描概要

| 項目 | 數值 |
|------|------|
| 輪次 | Round 7-14（8 輪，各輪聚焦不同面向避免重複） |
| 修復 | 5 項程式碼修復落地 + 2 項待使用者裁定 |
| 模式 | Round 8 為 comprehensive（2/10），其餘 daily（8/10） |

### 各輪聚焦面向與結果

| 輪次 | 聚焦 | 結果 |
|------|------|------|
| Round 7 | 分支 diff（HMAC chain fix） | CLEAN — 2 候選（timing/CLI）皆 filter |
| Round 8 | Comprehensive（2/10 gate） | 4 低信心項；修 1（unbounded limit），2 待裁定 |
| Round 9 | 前端 React/TS | **1 修復** — latent stored-XSS（href 注入） |
| Round 10 | SQL/DB 層 | CLEAN — 動態 SQL 全走白名單/introspection |
| Round 11 | 業務邏輯授權 | **2 修復** — reject_leave / reject_overtime state machine bug |
| Round 12 | Secrets / 基礎設施 | **1 待裁定** — Prometheus 預設密碼 |
| Round 13 | Auth / session / crypto | CLEAN — ES256 pin、reuse detection、2FA 不可繞過 |
| Round 14 | 輸入驗證 / 檔案上傳 | **1 修復** — 分頁無上限 + page 溢位 panic |

### 已修復項目

| # | 嚴重度 | 檔案 | 修復 |
|---|--------|------|------|
| 1 | HIGH | `services/hr/leave.rs:616` | `reject_leave` 加 PENDING* 狀態守衛（防已核准請假被翻 REJECTED 且餘額不回補） |
| 2 | HIGH | `services/hr/overtime.rs:750` | `reject_overtime` 加 pending_* 狀態守衛 + 自核駁回守衛（防幽靈補休餘額） |
| 3 | MEDIUM | `EuthanasiaChairArbitrationPanel.tsx:165` | latent stored-XSS：`href={attachment_path}` 改用 `safeHref()` scheme 白名單；後端加 `validate_attachment_path` |
| 4 | LOW | `services/stock/ledger.rs:531`、`handlers/accounting.rs:91` | 報表 limit 加 `.clamp(1, MAX_PAGE_SIZE)` |
| 5 | LOW | `services/notification/{crud,alert,report}.rs` | 分頁 per_page 加 clamp + page 用 saturating_mul（防 overflow-checks panic DoS） |

### 待使用者裁定（未自動修復）

| # | 嚴重度 | 項目 | 為何不自動修 |
|---|--------|------|-------------|
| 6 | MEDIUM (9/10) | `monitoring/prometheus/web.yml:18` Prometheus 預設密碼 `prometheus-dev`（已 commit 進 git） | 需動 `secrets/`（CLAUDE.md 要求明確同意）；需輪換憑證且舊值已 burned。bound 127.0.0.1 故需 local foothold/SSRF |
| 7 | MEDIUM (6/10) | MCP `notify_secretary` 無收件人白名單 | 行為變更（限制收件人可能擋掉合法用途），需使用者決策 |

> 另：Round 8 webhook IPv6 SSRF（4/10，admin-configured）、login 2FA 計數器無 advisory lock（5/10）、email 正規化不一致（3/10）皆為低信心，列入 backlog 不阻擋。

### 新增 safeHref 防護

`frontend/src/lib/sanitize.ts` 新增 `safeHref()`：僅允許 same-origin 相對路徑（/...）與 http(s) URL，其餘回傳 undefined。任何把 API 資料放入 `<a href>` 的地方應使用此函式。

---

## 2026-05-28 — 6 輪深度掃描，20 個 handler 權限漏洞修復

### 掃描概要

| 項目 | 數值 |
|------|------|
| 輪次 | 6（5 輪發現問題 + 1 輪驗證乾淨） |
| 模式 | daily（8/10 confidence gate） |
| 掃描範圍 | 全 14 phase（P0-P14） |
| 修復 handler 數 | 20 個函式，橫跨 7 個檔案 |
| 最終狀態 | CLEAN |

### Root Cause

`/admin/` 路由沒有 route-level 的 admin middleware。所有權限檢查全靠每個 handler 函式自己做（`require_permission!` 或 `is_admin()`）。漏掉的 handler 等於對所有已登入使用者完全開放。

偵測模式：`Extension(_current_user)`（帶底線）= 取出 user context 但從未檢查權限。

### 各輪次明細

#### 第 1 輪（R63 CSO 初始掃描）

| # | 嚴重度 | 檔案 | 函式 | 問題 |
|---|--------|------|------|------|
| 1 | HIGH | `handlers/notification_routing.rs` | 6 個 handler | 零權限檢查，任何人可 CRUD 通知路由規則 |
| 2 | MEDIUM | `handlers/config_check.rs` | `get_config_warnings` | 配置診斷對所有人開放（洩漏地理圍籬、密碼強度） |

修復：`require_admin()` / `is_admin()` gate。

#### 第 2 輪（variant analysis — 同 pattern 全面搜索）

| # | 嚴重度 | 檔案 | 函式 | 問題 |
|---|--------|------|------|------|
| 3 | HIGH | `handlers/audit.rs:412-561` | 8 個 handler（含 3 個 mutation） | `force_logout_session`：任何人踢任何 session |
| | | | | `resolve_security_alert` / `bulk_resolve`：任何人消除安全警報 |
| | | | | 5 個 read handler 洩漏登入事件、session、警報資料 |
| 4 | HIGH | `handlers/hr/balance.rs:80` | `adjust_balance` | 任何人調整任何人的假期餘額 |
| 5 | HIGH | `handlers/hr/attendance.rs:273` | `correct_attendance` | 任何人竄改任何人的出勤紀錄 |

修復：audit handler 加 `require_permission!(audit.logs.view)`；HR handler 加 `is_admin() || has_permission()` gate。

#### 第 3 輪（info disclosure — 讀取端點無權限檢查）

| # | 嚴重度 | 檔案 | 函式 | 問題 |
|---|--------|------|------|------|
| 6 | MEDIUM | `handlers/notification.rs:174` | `list_scheduled_reports` | 所有人看到全部排程報表（含其他人的設定） |
| 7 | MEDIUM | `handlers/notification.rs:234` | `list_report_history` | 所有人看到報表歷史（含 file_path 洩漏） |
| 8 | MEDIUM | `handlers/hr/dashboard.rs:61` | `get_dashboard_calendar` | 所有人看到誰在請假（HR 敏感資訊） |
| 9 | MEDIUM | `handlers/hr/dashboard.rs:85` | `list_staff_for_proxy` | 所有人看到員工 PII（email、電話、訓練紀錄） |

修復：scheduled_reports 加 owner 過濾；report_history 加 admin gate；dashboard 加 `hr.attendance.view_all`；staff 加 `hr.leave.create` 權限。

#### 第 4 輪 — 驗證乾淨

0 findings。所有修復確認到位。

#### 第 5 輪 — 深度掃描（其他漏洞類型）

檢查 SQL injection、`unwrap()` panic、TOCTOU、path traversal。全部乾淨。

#### 第 6 輪 — 最終驗證

確認 8 個白名單 `_current_user` 全部對齊。0 violations。

### 安全防護措施

#### Guard Test：`tests/admin_authz_guard.rs`

自動化測試，掃描所有 `src/handlers/**/*.rs` 的 `Extension(_current_user)` pattern。

- 每個 match 必須在白名單內（經 CSO 審計確認為 read-only reference data）
- 新 handler 使用 `_current_user` → 測試紅燈
- 白名單（8 個）：`list_low_stock_alerts`、`list_expiry_alerts`、`get_system_features`、`get_pending_count`、`list_blood_test_templates`、`list_blood_test_panels`、`list_blood_test_presets`、`list_animal_sources`

```bash
cargo test --test admin_authz_guard
```

### 乾淨面向（無發現）

| Phase | 檢查項目 | 狀態 |
|-------|---------|------|
| P2 | 密碼 / API key 洩漏（git history） | CLEAN — .env gitignored，無 AKIA/sk-/ghp_ |
| P3 | 供應鏈（Cargo.toml + cargo audit） | CLEAN — rsa 只有 advisory（未使用 RSA） |
| P4 | CI/CD pipeline | N/A — 無 GitHub Actions |
| P5 | Docker 基礎設施 | CLEAN — 非 root 容器、localhost 綁定、Docker Secrets |
| P6 | Webhook 認證 | CLEAN — alertmanager 用 constant-time 比對 |
| P7 | LLM / AI 安全 | CLEAN — system prompt server-side、output JSON parse |
| P8 | Skill 供應鏈 | CLEAN — 無 repo-local skills |
| A02 | 加密 | CLEAN — ES256 JWT、Argon2 密碼 |
| A03 | Injection | CLEAN — 全部 SQLx parameterized |
| A04 | 設計缺陷 | CLEAN — rate limit、account lockout |
| A05 | 配置 | CLEAN — strict CORS、CSP with nonce、HSTS |
| A07 | 認證 | CLEAN — refresh rotation、reuse detection、2FA |
| A09 | 日誌 | CLEAN — HMAC chain audit、tamper-evident |
| A10 | SSRF | CLEAN — 無使用者可控 URL |

---

## 2026-05-27 — 9 輪深度掃描（R63 原始審計）

### 掃描概要

| 項目 | 數值 |
|------|------|
| 輪次 | 9（約 20 個 agent） |
| 修復項目 | 20 項直接 commit + 9 項 PR #503 + 3 項 R63-A（GLP 合規） |
| 範圍 | 60+ 安全面向 |

### 主要修復（直接 commit to main）

見 `docs/PROGRESS.md` §9 條目 `2026-05-27 CSO 綜合安全審計`。

涵蓋：CSRF double-submit、rate limit 5 層、honeypot 偵測、CSP nonce、
session idle timeout、HMAC chain 強化、Docker security_opt、Nginx hardening 等。

### R63-B（PR #503）

9 項安全強化：admin trigger 加權限、DEFAULT PRIVILEGES 收窄、SEED_DEV_USERS 強化、
Google Calendar timeout、multipart 檔案數限制、soft-delete PII 清除、
metrics rate limit、honeypot DashMap 清理、config_check 補齊。

### R63-A（GLP 合規，2026-05-28 完成）

- A1：24 個 GLP mutation 全面加 `log_activity_tx` audit logging
- A2：文件核准 + 變更核准加 `SignatureService::sign_record_tx` 電子簽章
- A3：`role_training_requirements` hard DELETE 改 soft-delete

### R63-C（Deferred 10 項，2026-05-28 掃清）

- C3：scheduler `pg_advisory_lock` leader election
- C5：GLP list 加 LIMIT 200
- C6：移除 `tera` dead dependency
- C7：leave Decimal 純算消除 f64 round-trip
- C8：SKU regex `OnceLock`
- C9：TEST_USER_PASSWORD 改 `read_secret()`
- C1/C2/C4/C10：確認已修或 N/A

---

## 報告檔案索引

| 檔案 | 日期 | 模式 | Findings |
|------|------|------|----------|
| `.gstack/security-reports/2026-05-28-082000.json` | 2026-05-28 | daily | 2（notification_routing + config_check） |
| `.gstack/security-reports/2026-05-28-084500.json` | 2026-05-28 | daily | 3（audit ×8 + balance + attendance） |
| `.gstack/security-reports/2026-05-28-090000.json` | 2026-05-28 | daily | 0（final clean） |
| `.gstack/security-reports/2026-05-28-093000.json` | 2026-05-28 | daily | 0（branch diff clean） |
| `.gstack/security-reports/2026-05-28-100000.json` | 2026-05-28 | mixed | 7（5 修復 + 2 待裁定；Round 7-14 多面向） |
