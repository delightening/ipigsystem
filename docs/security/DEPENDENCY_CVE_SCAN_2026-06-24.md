# iPig System 依賴 CVE 滲透測試掃描報告（2026-06-24）

> **日期**：2026-06-24
> **範圍**：全端**依賴套件已知漏洞（CVE / RUSTSEC / GHSA）**掃描——Rust 後端、React 前端、根目錄 npm（@sentry/react）、根目錄 Python（uv.lock）、print-pdf 服務（requirements.txt）
> **方法**：`cargo-audit`（離線 RustSec advisory-db）、`pnpm audit`、`npm audit`、`pip-audit`（PyPI advisory）
> **授權**：使用者自我滲透測試（dev 環境），授權「報告 + 全部修補」
> **補齊**：本次補上 `PENTEST_ASSESSMENT_2026-06.md` 中「依賴 CVE 掃描因環境無網路未能執行，列為待 CI 驗證」的缺口。

---

## 1. 總評

掃了 5 個依賴生態系，共發現 **21 個可修復漏洞**（分布在 3 個生態系）已**全部修補**；Rust 後端另有 1 個 medium 漏洞 + 3 個警告，**上游皆無修復版本**，經分析皆不在可利用路徑，列為「已知接受風險」。

| 生態系 | 掃描工具 | 掃描前 | 修補後 | 狀態 |
|---|---|---|---|---|
| 前端 `frontend/` (pnpm) | `pnpm audit` | 0 | 0 | ✅ 本來就乾淨 |
| 根目錄 npm（`@sentry/react`） | `npm audit` | 2（1 high, 1 mod） | 0 | ✅ 已修 |
| 根目錄 Python（`uv.lock`） | `pip-audit` | 8（6 套件） | 0 | ✅ 已修 |
| print-pdf 服務（`requirements.txt`） | `pip-audit` | 11（2 套件） | 0 | ✅ 已修 |
| 後端 `backend/` (Cargo.lock) | `cargo-audit` | 1 vuln + 3 warn | 1 vuln + 3 warn | ⚠️ 上游無修復，接受風險 |

---

## 2. ✅ 已修補（21 項）

### 2.1 根目錄 npm `@sentry/react`（2 項）

| 套件 | 漏洞 | 嚴重度 | 修補 |
|---|---|---|---|
| `picomatch` ≤2.3.1 | GHSA-3v7f-55p6-f55p（POSIX 字元類別方法注入）、GHSA-c2c7-rcm5-vvqj（extglob ReDoS） | 🔴 High | `npm audit fix` 升級傳遞依賴 |
| `yaml` 2.0.0–2.8.2 | GHSA-48c2-rrv3-qjmp（深層巢狀 YAML 造成 Stack Overflow） | 🟡 Moderate | `npm audit fix` 升級傳遞依賴 |

**修補方式**：`npm audit fix --package-lock-only`（只更新 `package-lock.json`）。
**⚠️ 附帶發現**：`@sentry/react` 在 `frontend/src`、`index.html`、`public/` **全域查無任何 import**，疑為未使用的殘留依賴。已**保留**（移除依賴屬高風險決策，依 CLAUDE.md 須使用者裁定）。**建議**：若確認未使用，整個根目錄 npm 專案（`package.json` + `package-lock.json`）可移除，連帶消除此攻擊面。→ 待裁定。

### 2.2 根目錄 Python `uv.lock`（8 項 / 6 套件）

| 套件 | 漏洞 ID | 修補前 → 後 | 性質 |
|---|---|---|---|
| `requests` | CVE-2026-25645 | 2.32.5 → 2.34.2 | 直接依賴 |
| `python-dotenv` | CVE-2026-28684 | 1.2.1 → 1.2.2 | 直接依賴 |
| `idna` | PYSEC-2026-215 | 3.11 → 3.18 | 傳遞依賴 |
| `urllib3` | PYSEC-2026-141 / -142 | 2.6.3 → 2.7.0 | 傳遞依賴 |
| `pygments` | CVE-2026-4539 | 2.19.2 → 2.20.0 | 傳遞（dev/pytest） |
| `pytest` | CVE-2025-71176 | 9.0.2 → 9.1.1 | dev 依賴 |

**修補方式**：`uv lock --upgrade`（`pyproject.toml` 的版本下限已涵蓋，無須改 `pyproject.toml`）。

### 2.3 print-pdf 服務 `requirements.txt`（11 項 / 2 套件）

| 套件 | 漏洞 ID | 修補前 → 後 |
|---|---|---|
| `pypdf` | CVE-2026-48156 / -48155 / -48735 / -49461 / -49460 / -54531 / -54530 / GHSA-jm82-fx9c-mx94（共 8 項） | 6.11.0 → 6.13.3 |
| `python-multipart` | CVE-2026-53540 / -53539 / -53538（共 3 項） | 0.0.28 → 0.0.31 |

**修補方式**：直接修改 `requirements.txt` 釘選版本。
**⚠️ 待驗證**：print-pdf 為獨立 Docker 服務，本機無 weasyprint 系統函式庫無法跑起，需 **CI / Docker build 驗證**新版相容性。

---

## 3. ⚠️ 後端 Rust（上游無修復，接受風險）

### 3.1 🟡 `rsa` 0.9.10 — RUSTSEC-2023-0071（Marvin Attack，CVSS 5.9 medium）

> **🔴 2026-06-24 更正**：本節初版宣稱「rsa 程式碼路徑不被執行 / 不可利用」**有誤**，已依原始碼覆核更正如下。

- **來源**：`jsonwebtoken` v10 的 `rust_crypto` feature 傳遞引入。
- **上游狀態**：**無修復版本**（`Solution: No fixed upgrade is available!`）。
- **可達性（更正）**：**rsa 程式碼路徑會被執行**。使用者登入 JWT 確為 ES256（`middleware/auth.rs:141`），但 `services/google_calendar.rs:558` 以 **RS256** + `EncodingKey::from_rsa_pem` 簽 Google Calendar service-account JWT 換取 access token，會走 `rsa` crate 的 RSA 私鑰簽章。（另 `two_factor.rs` 的 `Algorithm::SHA1` 是 TOTP 雜湊，與 rsa 無關。）
- **可利用性分析（更正）**：**路徑可達，但不符 Marvin 威脅模型前提**。Marvin 為對 RSA 私鑰運算的時序側通道，利用前提是攻擊者能反覆對**可控輸入**觸發私鑰運算並量測細粒度時序。此處運算為「以系統自有金鑰簽系統自產、固定結構的 claims，伺服器端對外呼叫 Google」，攻擊者無法提交選擇密文、無逐次時序 oracle → 實務**風險低**。殘餘風險為 service-account 私鑰外洩（金鑰保管問題，與 Marvin 無關）。
- **處置**：**接受風險，維持 ignore**。曾 spike 評估改 `jsonwebtoken` 為 `aws-lc-rs` 後端（實測見 `docs/plans/dependency-maintenance-remediation-plan-2026-06-24.md` WS-4）：切換可讓 binary 不含 rsa、RS256 改用常數時間實作，**但 rsa 仍留在 `Cargo.lock`（jsonwebtoken 選用依賴），CI 的 lockfile-based `cargo-audit` 仍會 flag → ignore 拿不掉**；且需為 aws-lc-sys 在 Dockerfile 補裝 cmake/build-essential（否則 Docker build 失敗）。成本/風險高於收益（原風險已低），**不採用**。

### 3.2 ⚪ `rand` 0.8.5 與 0.9.2 — RUSTSEC-2026-0097（unsound 警告）

- **問題**：「使用 custom logger 搭配 `rand::rng()` 時 unsound」。
- **上游狀態**：**0.8.5 與 0.9.2 兩個版本皆被標記**，升級無法解決。
- **處置**：接受風險（警告級，本專案未使用受影響的 custom logger 組合）。

### 3.3 ⚪ `proc-macro-error2` 2.0.1 — RUSTSEC-2026-0173（unmaintained 警告）

- **來源**：`validator` 0.20 的 `validator_derive` 引入（`validator` 0.20 為最新版、所有 0.19+ 版皆依賴它，無版本可擺脫）。
- **性質**：build-time proc-macro 傳遞依賴，已不再維護。無漏洞、零執行期攻擊面，僅維護性警告。
- **處置**：接受風險。替換 `validator` 需重寫 61 檔 / 439 處驗證標註，成本/風險與收益不成比例；維持 ignore，追蹤上游遷移進度（見 `docs/plans/dependency-maintenance-remediation-plan-2026-06-24.md` WS-3）。

---

## 4. 環境限制紀錄

- `cargo-audit` 預設從 `github.com` git clone RustSec advisory-db，被組織 egress 政策擋（HTTP 403）。改自 `codeload.github.com`（白名單可達）下載 tarball，以 `cargo-audit audit --db <local> -n` 離線掃描。
- `api.osv.dev` 同樣被擋；`pip-audit` 改用 `pypi.org`（白名單）的 advisory API，正常運作。
- Cargo.lock 的 yanked 檢查因 crates.io index 查詢受限會噴 `couldn't check if the package is yanked` 雜訊，**不影響 advisory 比對結果**。

---

## 5. 修補檔案清單

| 檔案 | 變更 |
|---|---|
| `services/print-pdf/requirements.txt` | `pypdf` 6.11.0→6.13.3、`python-multipart` 0.0.28→0.0.31 |
| `uv.lock` | requests / python-dotenv / idna / urllib3 / pygments / pytest 等升級 |
| `package-lock.json` | `picomatch` / `yaml` 傳遞依賴升級 |

> `frontend/`（pnpm）與 `backend/Cargo.lock` 本次無檔案變更。
