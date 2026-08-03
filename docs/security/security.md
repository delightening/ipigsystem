# 安全性紀錄

本文件記錄專案中已評估的漏洞與處置方式，供稽核與後續追蹤使用。

---

## 合規對照與政策文件索引 (R41-7, 2026-05-11)

| 文件 | 主題 | 下次複查 |
|---|---|---|
| [`NICS_COMPLIANCE_AUDIT_2026-05.md`](NICS_COMPLIANCE_AUDIT_2026-05.md) | 對照行政院《資通安全責任等級分級辦法》附表十 / NICS RFP 附件1 之 self-audit；普級 100%、中級 ~85%、高級 ~70% | **2026-11-11**（半年一次）|
| [`../assessments/DB_AT_REST_ENCRYPTION_2026-05.md`](../assessments/DB_AT_REST_ENCRYPTION_2026-05.md) | R41-8 DB at-rest 加密評估：結論採 Windows BitLocker；其他方案不追 | 重大架構變動時 |
| [`PASSWORD_POLICY.md`](PASSWORD_POLICY.md) | 密碼政策；說明本系統依 NIST SP 800-63B 對附表十「定期更換 / 歷史紀錄」之主動偏離與補償控制 | 重大政策變動時 |
| [`DATA_RETENTION_POLICY.md`](DATA_RETENTION_POLICY.md) | 各類紀錄之保留年限；§6 新增稽核日誌容量分區政策（R41-3）| 每年 |
| [`HMAC_VERSIONING.md`](HMAC_VERSIONING.md) | 稽核日誌 HMAC chain 版本管理（legacy / canonical）| 重大 schema 變動時 |
| [`AUDIT_REDACTION.md`](AUDIT_REDACTION.md) | DataDiff 敏感欄位脫敏機制 | — |
| [`THREAT_MODEL.md`](THREAT_MODEL.md) | 系統威脅模型 | 重大架構變動時 |
| [`ELECTRONIC_SIGNATURE_COMPLIANCE.md`](ELECTRONIC_SIGNATURE_COMPLIANCE.md) | 21 CFR Part 11 電子簽章合規 | — |
| [`SESSION_LOGOUT_MANAGEMENT.md`](SESSION_LOGOUT_MANAGEMENT.md) | Session 與登出管理 | — |
| [`SOC2_READINESS.md`](SOC2_READINESS.md) | SOC 2 準備度評估 | — |

---

## R22 自動 IP block 串接驗證 (R41-6, 2026-05-11)

對應 NICS 附表十「系統與資訊完整性 / 系統監控」要求，本系統的「攻擊偵測 → 自動封鎖」鏈路驗證如下（grep + 程式碼追蹤）：

### 已串接的觸發點

| 觸發場景 | 觸發位置 | auto_block 呼叫 | gate / 控制項 |
|---|---|---|---|
| **Auth rate limit 持續升級** | `middleware/rate_limiter.rs:426` | IP 封 1 小時，reason=`R22-1_ratelimit` | 同 IP 在窗口期內超過閾值 → critical alert + auto_block |
| **IDOR probe 偵測** | `middleware/response_logger.rs:170-172` | (a) user-level block; (b) IP-level block | gate by `idor_auto_block_enabled` (security_alert_config) |
| **Honeypot 端點命中** | `handlers/honeypot.rs:121` | IP 即時封鎖 | 預設啟用，6 個假端點 |

### 共用 service

`backend/src/services/ip_blocklist.rs::auto_block(pool, ip, reason, alert_id, description, hours)`

- 寫入 `ip_blocklist` 表（IP + expires_at + reason + 連結 security_alert）
- 後續所有 request 經 `middleware/ip_blocklist.rs` 檢查 → 命中即 403 拒絕
- 失敗時 log warn 不 panic（`tracing::error!("[R24-1] auto_block {ip} failed")`)

### 控制旗標

`AlertThresholdService::idor_auto_block_enabled` 讀取 `security_alert_config` 表的 `idor_auto_block_enabled` 欄（預設 1=啟用），允許 ops 在需要時臨時關閉自動封鎖（保留偵測但停止行動）。

### 限制 / 已知 gap

- **暴力登入失敗 (brute force) ≠ 直接觸發 auto_block**：5 次失敗鎖 30 分鐘是**帳號層級**鎖定（不是 IP 層級）。若同一 IP 攻擊多個帳號，會走 `rate_limiter.rs` 路徑（同 IP 短時間多個失敗 request → rate limit → 升級告警 → auto_block）。鏈路完整但路徑較長。
- **整合測試覆蓋**：grep `backend/tests/` 無直接 `IpBlocklistService` 整合測試（屬於 happy path 驗證 gap）。但 unit test 涵蓋 service 層（`services/ip_blocklist.rs` 內部 test）。

### 結論

R22 auto-block 鏈路**已完整串接**並在 prod 運行；R41-6 結論為 **PASS（文件補強型）**。新增整合測試可作為 R41 follow-up 工作項，但非合規 gap。

---

## Rust 依賴漏洞（cargo audit）

CI 已設定 `cargo audit --ignore` 排除下列項目，以下為評估結論。

### RUSTSEC-2023-0071（rsa 0.9.10）

| 項目 | 說明 |
|------|------|
| 漏洞 | Marvin Attack：透過時序側通道潛在的金鑰恢復 |
| 依賴路徑 | sqlx-mysql（transitive）→ rsa |
| 專案使用 | 本專案僅使用 sqlx 的 **postgres** feature，未使用 mysql |
| 處置 | CI 以 `--ignore RUSTSEC-2023-0071` 排除；上游 sqlx 無修復版本 |
| 風險 | 低 — mysql 驅動未被編譯進最終二進位檔 |

### RUSTSEC-2024-0370（proc-macro-error）

| 項目 | 說明 |
|------|------|
| 漏洞 | proc-macro-error 已不再維護 |
| 依賴路徑 | utoipa → utoipa-gen → proc-macro-error |
| 處置 | CI 以 `--ignore RUSTSEC-2024-0370` 排除；追蹤 utoipa 上游更新 |
| 風險 | 低 — 僅在編譯期使用，不影響執行期 |

### Yanked crates（js-sys, wasm-bindgen）

| 項目 | 說明 |
|------|------|
| 說明 | 間接依賴的 js-sys、wasm-bindgen 曾被 yank |
| 處置 | CI 執行 `cargo update` 以取得非 yanked 版本 |
| 風險 | 低 — 更新後應可排除 |

---

## 前端依賴漏洞（OSV scanner）

CI job「🔒 Security: pnpm audit」以 `osv-scanner` 掃 `frontend/pnpm-lock.yaml`，
政策為**任一已知漏洞即 fail**。豁免清單於 `frontend/osv-scanner.toml`，
每條均須附理由與 `ignoreUntil` 到期日；以下為評估結論。

### GHSA-mh99-v99m-4gvg（brace-expansion 5.0.7）— 已修復

| 項目 | 說明 |
|------|------|
| 漏洞 | brace-expansion ReDoS（CVSS 7.5 High） |
| 依賴路徑 | transitive（工具鏈相依） |
| 處置 | **已修復**：`package.json` 的 `pnpm.overrides` 加 `"brace-expansion": ">=5.0.8"`，lockfile 升至 5.0.8 |
| 風險 | 已消除 |

### GHSA-qwww-vcr4-c8h2（react-router 7.18.1）— 豁免

| 項目 | 說明 |
|------|------|
| 漏洞 | React Router: RSC Mode CSRF Bypass Allows Action Execution Before 400 Response（CVSS 4.0 / 7.1 High） |
| 影響範圍 | react-router 7.12.0 ≤ v < 8.3.0；本專案 7.18.1（經 react-router-dom 引入） |
| 專案使用 | 前端為 Vite 打包的**純 client-side SPA**，未使用 RSC、無 server action、無 SSR entry → 漏洞所在的程式路徑不存在 |
| 處置 | 列入 `frontend/osv-scanner.toml` 豁免，`ignoreUntil = 2026-10-31` 強制複審 |
| 為何不升級 | 上游僅在 **8.3.0** 修復，無 7.x backport。v7→v8 為 major bump，牽動全站路由行為，回歸風險遠高於此漏洞的實際暴露（本專案為零） |
| 風險 | LOW — 攻擊面不存在；另有 CSP 與既有 CSRF 防護 |
| 長期作法 | 待 react-router v8 升級另案評估（需完整路由回歸測試）；升級後移除本豁免 |

---

## CVE-2026-42945（nginx rewrite 模組堆緩衝區溢位）

### 摘要

| 項目 | 說明 |
|------|------|
| CVE | CVE-2026-42945 |
| 等級 | Critical（heap buffer overflow） |
| 元件 | nginx core rewrite module（影響 NGINX Plus 與 NGINX Open Source） |
| 觸發條件 | 未認證攻擊者送出特製 HTTP request；伺服器需跑特定 rewrite 配置；ASLR 關閉時才有 RCE 風險，否則為 worker crash |
| 上游修補版本 | nginx 1.31.0（mainline）及對應穩定分支 |
| 本系統處置 | **已修補** — 2026-05-15 `frontend/Dockerfile` 升級至 `georgjung/nginx-brotli:1.31.0-alpine3.23` |
| Disclosure → 部署時間差 | 約 1 週（記錄此次回應 SLA 作為下次基準） |

### 暴露評估

- **frontend 映像**（唯一對外 nginx 入口，位於 `frontend/Dockerfile`）：
  - 升級前：`1.29.5-alpine`（脆弱）
  - 升級後：`1.31.0-alpine3.23`（已修）
- **rewrite directive 用法盤點**：

  | 檔案 | 行 | 內容 | 風險評估 |
  |---|---|---|---|
  | `frontend/nginx.conf` | 160 | `rewrite ^ /llms.txt last;` | LOW — 無正則捕獲組（capture group）、無使用者控制的 input；與 CVE PoC 所需的「特製 capture + 變數展開」pattern 不符 |
  | `frontend/nginx-ci.conf` / `nginx-ssl.conf.example` | — | 無 rewrite | — |

- **rewrite-equivalent**（`if`、`return`、`try_files`）：所有 `try_files` 均為靜態檔 fallback；`if` 僅一處比對 Accept header，無動態 rewrite 字串組裝。
- **VulnCheck Canaries 觀察到主動利用**：本系統 rewrite 用法不符 CVE 所需的「特定 rewrite 配置」，但仍以升級 binary 為主要修補方式（最徹底）。

### 後續監控

- **Trivy CI scan**（`.github/workflows/ci.yml:481`）對 frontend image 持續掃描，nginx 套件 CVE 退步將在 PR 階段擋下。
- **基底映像追蹤**：`georgjung/nginx-brotli` tag 更新由 P4-1（每季）+ 重大 CVE alert 兩條路徑驅動。
- **回應流程**：見 [`../runbooks/nginx-cve-response-sop.md`](../runbooks/nginx-cve-response-sop.md)。

### 驗證指令（部署後一次性確認）

```bash
# 1. 容器內 nginx 版本
docker exec ipig-web nginx -v
# 預期：nginx version: nginx/1.31.0

# 2. 從外部看 server header（server_tokens off 應該只回 "nginx"，不帶版本）
curl -sI https://<domain> | grep -i ^server

# 3. ASLR 啟用狀態（host 層）
cat /proc/sys/kernel/randomize_va_space
# 預期：2（full randomization）— 若為 0，即使 nginx 已修補也應修正 host
```

---

## CVE-2026-25646（libpng 堆緩衝區溢位）

### 摘要

| 項目 | 說明 |
|------|------|
| CVE | CVE-2026-25646 |
| 元件 | libpng 1.6.54-r0（位於 frontend 映像之基礎映像，修復版 1.6.55-r0） |
| 類型 | 堆緩衝區溢位 |
| 目前處置 | 列入 `.trivyignore`，不修復 |
| 最後檢查 | 2026-05-15 — 升級至 `georgjung/nginx-brotli:1.31.0-alpine3.23`（新 mainline series，含 7 個 nginx core CVE 修補），libpng 狀態 Trivy 重掃驗 |

### 適用範圍

- **映像**：frontend（`frontend/Dockerfile`）
- **基礎映像**：`georgjung/nginx-brotli:1.31.0-alpine3.23`（Alpine 3.23.x, nginx 1.31.0）

### 採用 .trivyignore 之原因

- 修復需在映像內執行 `apk upgrade` 以更新 libpng。
- 該映像內 nginx 的 **Brotli 動態模組**（`.so`）為預編譯產物，與基底 Alpine 的 glibc/ABI 綁定；執行 `apk upgrade` 會更新核心套件，導致與既有 Brotli 模組 **ABI 不相容**，nginx 啟動時無法載入模組而失敗。
- 因此在此映像中「只升級 libpng」與「保留 Brotli 功能」無法同時達成，故暫時以忽略 CVE 方式處理。

### 風險評估：LOW

- 前端映像僅負責提供 **靜態資源**（HTML / JS / CSS 等），不對使用者上傳的 PNG 進行解析或處理。
- libpng 漏洞通常需攻擊者能提供惡意 PNG 並由受影響程式解析才會觸發；本服務不具此攻擊面，故評估為低風險。

### 長期作法

- 追蹤基礎映像 [georgjung/nginx-brotli](https://hub.docker.com/r/georgjung/nginx-brotli/tags) 或上游 Alpine 是否釋出已修補 libpng 的新版。
- 當有更新版基礎映像可用時，升級基礎映像並從 `.trivyignore` 移除此 CVE。

### 方案 D 已採納：圖片處理分離原則

本專案**已採納方案 D**，作為架構原則：

- **frontend 映像**僅負責提供靜態資源（HTML / JS / CSS / 靜態資產），**不解析、不處理**使用者上傳的 PNG 或其他圖片格式。
- 若有**解析或處理使用者上傳圖片**的需求（例如縮圖、驗證、轉檔、OCR），必須由**獨立服務**實作；該服務使用可安全執行 `apk upgrade` 的基底映像（例如 `nginx:alpine`、`alpine`、或官方語言 runtime 映像），以確保 libpng 等依賴可及時修補，且不影響 frontend 的 Brotli 與現有建置。

如此可維持攻擊面隔離：frontend 維持低風險與 .trivyignore 現狀，需處理不可信圖片的工作集中在可升級的單一服務。

#### 未來新增「圖片處理服務」時之實作指引

| 項目 | 建議 |
|------|------|
| **基底映像** | 使用可安全 `apk upgrade` 的映像（如 `nginx:alpine`、`python:alpine`、`node:alpine` 等），建置時執行 `apk upgrade` 以取得 libpng 等安全更新。 |
| **職責** | 僅負責圖片相關操作：縮圖、格式轉換、尺寸/格式驗證、必要時病毒/惡意檔掃描。不負責一般靜態檔託管。 |
| **介面** | 由後端 API 或 BFF 呼叫（上傳檔先到後端，後端再轉交此服務處理），或透過佇列非同步處理；前端不直連此服務。 |
| **部署** | 獨立容器/服務，可與現有 docker-compose 或 K8s 並存；Trivy 掃描此映像時不應再依賴 .trivyignore 之 CVE-2026-25646（因可升級修補）。 |
| **文件** | 新服務需有簡短 README 與 Dockerfile 註解，註明「本服務可執行 apk upgrade，用於隔離圖片解析攻擊面」。 |

---

## 若採積極修復之處置選項

若未來風險接受度改變（例如需通過嚴格合規掃描、或前端開始處理使用者上傳圖片），可考慮以下其中一種作法。

### 選項 A：改用已修補之基礎映像（首選）

- **作法**：等待或選用已修補 libpng 的 `georgjung/nginx-brotli:alpine` 新 tag，將 `frontend/Dockerfile` 的 `FROM` 改為該 tag。
- **優點**：無需改架構，Brotli 與安全性更新兼得。
- **缺點**：依賴上游維護者釋出更新。

### 選項 B：自建 nginx + Brotli 映像

- **作法**：以官方 `nginx:alpine` 或 `alpine` 為基底，在 Dockerfile 中自行編譯 nginx 與 Brotli 模組；在**同一建置流程內**先 `apk upgrade` 再編譯，使 Brotli 與升級後的系統 ABI 一致。
- **優點**：可完全控制何時執行 `apk upgrade`，並保留 Brotli。
- **缺點**：需維護自建映像與建置腳本，建置時間較長。

### 選項 C：捨棄 Brotli，改用官方 nginx:alpine

- **作法**：將基礎映像改為 `nginx:alpine`，在 Dockerfile 中執行 `apk upgrade`，僅使用 nginx 內建 gzip，不再使用 Brotli。
- **優點**：可立即取得 libpng 等套件更新，設定簡單。
- **缺點**：失去 Brotli 壓縮，靜態資源壓縮率略降。

### 選項 D：分離靜態服務與潛在受影響元件（**已採納**）

- **作法**：若未來有「必須解析使用者上傳 PNG」的需求，改為在**其他服務**（例如獨立縮圖服務）處理，該服務使用可安全升級的基底映像；frontend 仍僅提供靜態檔，不解析 PNG。
- **優點**：攻擊面隔離，frontend 維持現狀與 Brotli。
- **缺點**：需額外服務與維運。
- **狀態**：本專案已採納此原則；詳見上文「方案 D 已採納：圖片處理分離原則」及未來新增圖片服務之實作指引。

### Pros / Cons 比較表

| 維度 | A. 改用已修補基礎映像 | B. 自建 nginx + Brotli | C. 捨棄 Brotli | D. 分離服務 |
|------|------------------------|-------------------------|-----------------|-------------|
| **Pros** | 不改架構；Brotli 與修補兼得；改動最小（只改 FROM） | 不依賴上游；可隨時 apk upgrade；保留 Brotli | 可立即修補；設定簡單；官方映像維護佳 | 攻擊面隔離；frontend 與 Brotli 不變；僅在「要解析 PNG」時才需加服務 |
| **Cons** | 依賴上游釋出更新，時程不可控 | 需維護自建映像與編譯腳本；建置時間長；升級 nginx/OpenSSL 時可能需重編 | 失去 Brotli，壓縮率略降、傳輸量略增 | 僅在「有解析 PNG 需求」時有意義；多一個服務要部署與維運 |
| **實作成本** | 低 | 高 | 低 | 中（依是否已有縮圖/圖片服務） |
| **可執行時機** | 待上游出新 tag | 隨時 | 隨時 | 當需求出現時 |

---

*最後更新：2026-05-19 — 新增 CVE-2026-42945（nginx rewrite RCE）section 與暴露評估；基礎映像 2026-05-15 已升級至 `1.31.0-alpine3.23`（涵蓋 7 個 nginx core CVE）。CVE-2026-25646（libpng）仍依 .trivyignore 暫不處理，下次檢查排定 2026-Q3。*
