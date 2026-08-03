# 🚦 CI/CD 入門：給 ipig_system 維運者的版本

> 這份文件**不是 DevOps 教科書**，是寫給你（solo 維運異種器官移植研究系統的獸醫）。所有範例都對應你 prod-on-laptop 上真的在跑的東西。

---

## 0. 一頁速查

| 縮寫 | 全稱 | 一句話 |
|---|---|---|
| **CI** | Continuous Integration | 你每次 push 程式時，**自動跑檢查**（編譯、測試、安全掃描…） |
| **CD** | Continuous Delivery / Deployment | CI 通過後，**自動把程式送上線** |
| **Pipeline** | — | CI + CD 串成的流水線 |
| **Job** | — | Pipeline 裡的一個獨立檢查步驟 |
| **Workflow** | — | GitHub Actions 用的詞，一個 yml 檔 = 一個 workflow，可含多個 job |

**你 ipig_system 現況**：
- CI = `.github/workflows/ci.yml` — 18 個 jobs（編譯 / 測試 / 安全 / 守門 / E2E）
- CD = `services/auto_deploy/` 的 R51 watcher daemon — 偵測 origin/main 更新自動拉 + `docker compose up -d --build`

---

## 1. 為什麼需要 CI/CD（先講痛）

### 沒 CI/CD 的世界

想像你動物舍每次採血都要：
1. 自己回想清潔流程有沒有跳步驟
2. 自己核對採血量
3. 自己確認標籤沒貼錯
4. 自己抄寫進系統

**人為錯誤一定會發生**。一個忘了就傷豬隻 / 出論文錯誤。

軟體沒 CI/CD 也一樣：
1. 改完 code 自己跑 test？常常忘記
2. 自己跑 lint？看心情
3. 自己掃安全漏洞？幾乎沒人手動做
4. 改完忘了 build → push 到 main → 別人 / prod 壞掉

### 有 CI/CD 的世界

把上面那些檢查都**寫成腳本**，每次有人 push 就**自動跑一輪**。失敗就擋住，不讓 merge / 不讓上線。

**核心價值**：把「人類記憶力 / 紀律」換成「自動化保險」。

---

## 2. CI vs CD 的差別

```text
你寫程式 → git push → ┌──────────────────────┐ → ┌──────────────────────┐
                     │   CI (檢查階段)         │    │  CD (部署階段)         │
                     │                      │    │                      │
                     │  - 編譯              │    │  - Build artifact     │
                     │  - 測試              │    │  - 上 staging         │
                     │  - 安全掃描          │    │  - 健康檢查           │
                     │  - 各種守門          │    │  - 上 production      │
                     └──────────────────────┘    └──────────────────────┘
                              ↓                          ↓
                          綠勾 / 紅叉                自動或手動觸發
```

| | CI | CD |
|---|---|---|
| **時機** | 每次 push / PR | CI 通過後 |
| **目的** | 抓壞掉 | 送上線 |
| **失敗代價** | 擋住合併 | 線上壞掉，可能需 rollback |
| **誰負責** | 開發 / reviewer | 維運 / SRE |
| **你的設定** | GitHub Actions (`.github/workflows/`) | R51 auto_deploy watcher（本機 daemon） |

### CD 的兩派風格

| 派別 | 行為 | 適合 |
|---|---|---|
| **Continuous Delivery** | 自動到 staging，**人按按鈕**才上 prod | 多人團隊、合規嚴 |
| **Continuous Deployment** | 全自動到 prod，**不問人** | solo / 高信任 CI / 可快速 rollback |

你是 **Continuous Deployment**：merge to main → R51 看到 → 1-2 分鐘內 prod 自動更新。沒按鈕、沒 staging gate。

**為什麼這樣 OK**：
- Solo 系統，沒有「另一個人按按鈕」這選項
- 18 個 CI jobs 替代了人工 gate
- rollback = 1 行 `git revert` + R51 自動重 deploy

---

## 3. CI 裡面通常放什麼

照「從快到慢、從低層到高層」的順序排：

| 階段 | 名稱 | 在幹嘛 | 失敗代表 |
|---|---|---|---|
| 1 | **Compile / Build** | 程式碼能不能編譯 | syntax 錯 / 缺檔 / 編譯期型別錯 |
| 2 | **Type check** | 型別對不對 | 變數錯誤、函式簽章不符 |
| 3 | **Lint** | 風格 / 反 pattern | 命名不一致、用了禁忌寫法 |
| 4 | **Unit test** | 函式邏輯對 | 計算錯、邊界條件壞 |
| 5 | **Integration test** | 服務之間對話 | API + DB 結果不一致 |
| 6 | **E2E test** | 真實使用者瀏覽器 | 按鈕點下去沒反應、登入流程斷 |
| 7 | **Dependency security** | 第三方套件 CVE | 用到的 lib 有已知漏洞 |
| 8 | **Static Application Security Testing (SAST)** | 程式碼層級漏洞 | SQL injection / XSS / 不安全的加密 |
| 9 | **Secret scanning** | git 裡有沒有密碼 | 不小心把 .env 提交 |
| 10 | **Container scanning** | Docker image 有沒有 OS 層漏洞 | base image / apt 套件 CVE |
| 11 | **Custom guards** | 專案特有禁忌 | 違反 CLAUDE.md / 內部規範 |

**設計原則**：愈靠上愈快、愈不能跳；愈下愈慢、可以暫時 skip 但累積風險。

---

## 4. ipig_system 18 個 CI jobs 逐個介紹

來自 `.github/workflows/ci.yml`。**綠勾 = 通過**，**紅叉 = 失敗 PR 不能 merge**。

### 編譯 / 測試 / 型別（4 個）

| Job | 在幹嘛 | 觸發紅燈時通常是什麼 |
|---|---|---|
| `Backend: cargo check` | Rust 編譯檢查（不產 binary） | use 錯誤 / type mismatch / lifetime 錯 |
| `Backend: cargo test` | Rust 整套測試（需 Postgres） | 某個 fn 改了行為、test fixture 不對齊 |
| `Backend: clippy` | Rust lint（風格 + 反 pattern） | 用了 `.unwrap()` 在非測試碼 / 變數命名違規 |
| `Frontend: tsc check` | TypeScript 型別 + vitest 測試 | 型別錯 / Zustand store 用法錯 / hook 邏輯壞 |

> **⚠️ R57-8**：`Frontend: tsc check` 名字 misleading — 其實同時跑 tsc + vitest。失敗時要看 log 才知道是哪邊紅。

### 覆蓋率（1 個）

| Job | 在幹嘛 |
|---|---|
| `📊 Backend: coverage (tarpaulin)` | 用 [tarpaulin](https://github.com/xd009642/tarpaulin) 算 Rust 測試覆蓋哪些行 |

**為什麼有用**：寫了 test 但沒測到的 code 一目了然。**為什麼也不萬能**：100% 覆蓋率 ≠ 100% 正確，只是「所有行至少被執行過一次」。

### 安全掃描（5 個）

| Job | 在幹嘛 | 抓什麼 |
|---|---|---|
| `🔒 Security: cargo audit` | RustSec 漏洞資料庫 | 依賴的 Rust crate 有 CVE |
| `🔒 Security: pnpm audit` | npm 漏洞資料庫 | 依賴的 npm package 有 CVE |
| `🛡️ Security: cargo deny` | Cargo 依賴政策檢查 | 授權違規 / yanked / duplicate dep |
| `🔬 Security: semgrep SAST` | 程式碼模式掃描 | SQL injection、XSS、OWASP top 10 |
| `🐳 Security: Trivy container scan` | Docker image OS 套件掃描 | base image / apt package CVE |

### 秘密 / 入口（2 個）

| Job | 在幹嘛 |
|---|---|
| `🔑 Security: secret scanning (gitleaks)` | 掃 git history 裡有沒有 API key / password / token 不小心提交 |
| `🛡️ Frontend: docker-entrypoint.sh` | shellcheck 前端 docker 啟動腳本 |

### 自訂守門 Guards（5 個）

這些是 ipig_system **獨有的規則**，寫在 `.github/workflows/ci.yml` 的 shell script 裡：

| Job | 在守什麼 |
|---|---|
| `🛑 Guard: SQL injection` | 抓 backend handler 裡用字串拼接 SQL（必須用 sqlx 具名參數）|
| `🚫 Guard: unsafe code` | Rust `unsafe {}` 區塊禁止使用（FFI 例外） |
| `🔄 Guard: migration down.sql` | 確保每個 migration up 都有對應 down 可回滾 |
| `🔐 Guard: audit redaction` | 確保 PII / 敏感欄位寫入 audit 前有 redact |
| `🔐 Guard: SDD audit pattern` | 確保 Service-driven audit 模式統一（R26-4 強制） |

**為什麼這些獨立成 job**：CLAUDE.md 規範 / 合規要求 / 過去事故的硬規則 — 用 CI 強制執行才不會忘。

### E2E（1 個）

| Job | 在幹嘛 |
|---|---|
| `🧪 E2E: Playwright` | Playwright 真的開瀏覽器、登入、點按鈕、看頁面 |

跑得慢（~10-20 分鐘）但抓到的 bug 是「真實使用者體驗」級別。

---

## 5. 怎麼讀 CI 失敗

### 流程

```text
GitHub PR 頁面 → Checks 標籤 → 找紅叉 job → 點 "Details"
                                          → 看 raw log
                                          → 找 "FAIL" / "error:" / "##[error]"
```

### 常見失敗模式 + 解法

| 紅燈 job | 典型原因 | 修法 |
|---|---|---|
| `Backend: cargo check` | 改 lib 公開 type 但沒跑 `--tests` | 本地 `rtk cargo check --all-targets` 再 push |
| `Backend: clippy` | 留 `.unwrap()` 在非測試碼 | 改 `?` 傳播 / `expect("...")` |
| `Frontend: tsc check` | tsc 型別錯 OR vitest 紅 | 看 log 區分；本地 `rtk vitest run --reporter=dot` 看 exit code |
| `🔒 Security: cargo audit` | 依賴的 crate 出新 CVE | 升級依賴 OR `cargo update` OR ignore CVE（要 justify） |
| `🔄 Guard: migration down.sql` | 加了 migration 但沒寫 down | 補 `migrations/down/NNN_xxx.sql` |
| `🧪 E2E: Playwright` | UI 改了但 selector 沒更新 / timing race | 看 trace 影片（CI artifact 有） |

### ⚠️ rtk wrapper 的陷阱

> 來源：你 memory `rtk-vitest-exit-code-strict`

`rtk vitest run` 顯示 `PASS (351) FAIL (0)` 但 process **exit code 1** → CI 會紅！

```bash
rtk vitest run; echo "EXIT: $?"
# EXIT: 1 ← 就算 PASS 351 也代表 CI 會紅
```

**規則**：rtk summary 是 token 節省，**exit code 才是 single source of truth**。

---

## 6. 怎麼加新 CI job（簡版 cookbook）

### Step 1：決定要不要加

新 CI job = **永久執行成本** + **block PR 的風險**。問自己：

- [ ] 這個檢查能抓的問題**過去發生過 / 有可能發生**嗎？
- [ ] 抓到後**有明確修法**嗎？（vs 一直 noisy warning）
- [ ] 跑起來**夠快**嗎？（< 5 分鐘最好）
- [ ] **失敗時** developer 看得懂為什麼嗎？

任何一個答不上來 → 先別加。

### Step 2：寫 job

在 `.github/workflows/ci.yml` 新增 job：

```yaml
my-new-check:
  name: "🧐 Custom: my new check"
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: "確認沒人改了某禁忌"
      run: |
        if grep -rE 'forbidden_pattern' src/; then
          echo "::error::Found forbidden pattern"
          exit 1
        fi
```

關鍵：
- `name:` 起好懂的名字（會出現在 GitHub PR Checks 頁面）
- 失敗用 `exit 1`
- 用 `::error::` annotation 讓錯誤訊息在 PR 直接看到

### Step 3：本地先測

```bash
# 模擬該 job 的指令本地跑一次
bash -c '<貼 yml 裡的 run: 內容>'
echo "EXIT: $?"
```

確認本地過、本地該紅有紅，再 push。

### Step 4：先加成 **non-blocking** observation 期

第一次加新 job 建議加 `continue-on-error: true`，觀察 1-2 週看誤判率，再升級成必過。

---

## 7. CD 在你系統上怎麼跑

### R51 auto-deploy watcher

來源：`services/auto_deploy/` + R51 落地（PROGRESS.md 2026-05-15）

### 流程

```text
你 merge PR to main
    ↓
GitHub 把新 commit push 到 origin/main
    ↓
本機 R51 watcher（一個跑在筆電上的 daemon）每 N 秒 fetch
    ↓
偵測到新 commit
    ↓
git pull
    ↓
docker compose up -d --build
    ↓
1-2 分鐘後 prod 已是新版
```

### 怎麼確認 R51 健在

```powershell
# Windows
Get-Process | Where-Object { $_.ProcessName -like "*auto_deploy*" }

# 或看 log
docker compose logs auto_deploy
```

### 如果 R51 壞了

手動拉 + build：

```powershell
cd "C:\System Coding\ipig_system"
git pull origin main
docker compose up -d --build
```

### Cloudflare Tunnel 在哪一層

`Cloudflare → Tunnel → 筆電 docker compose nginx → 各 service`

CD 不管 Cloudflare — Cloudflare 只是「網路入口」，跟「程式更新」是兩件事。

---

## 8. 為什麼你目前 CI 設計合理

對 solo + 異種器官移植研究系統，18 個 CI jobs 看起來奢侈，但每個都有理由：

| 類別 | 為什麼 ipig_system 要這層 |
|---|---|
| 編譯 / 測試 / 型別 | 基本款，沒這層 = 沒 CI |
| 5 個安全掃描 | NICS 合規 + 動物實驗資料敏感性，安全債不能累積 |
| 5 個 Custom Guards | CLAUDE.md 規範用 CI 強制 — 不靠人類記憶 |
| E2E | 沒 QA 同事 = E2E 是唯一「真實使用者」視角 |
| Coverage | 看哪邊測試薄弱 |

**對比**：一般 SaaS 創業公司可能只有 4-6 個 CI jobs（編譯 / test / lint / 1-2 個安全掃描）。你比那種強很多 — 因為**沒人替你把關**，全靠機器人。

---

## 9. 還可以加什麼（gap）

| 候選 | 為什麼還沒有 | 該加嗎 |
|---|---|---|
| Lighthouse / 效能 | 醫療系統不關鍵 | ❌ 不必 |
| Visual regression | UI 變動不多 | ❌ 不必 |
| Mutation testing | 規模收益小 | ❌ 不必 |
| Smoke test on staging | 你沒 staging | ⚠️ 未來 NAS / AWS 後再加 |
| Migration rollback test | 有 `🔄 Guard: migration down.sql` 但只查存在不查能跑 | 🟡 R57 等等 |
| Performance benchmark | benchmark skill 存在但沒接 | 🟡 待真有效能 regression 再加 |
| Pre-commit hooks（本地） | 沒設 | 🟡 之前討論過，現在靠 CI 也 OK |

---

## 10. 名詞速查

| 名詞 | 一句話 |
|---|---|
| **Workflow** | GitHub Actions 的 yml 檔，一個 = 一條流水線 |
| **Job** | Workflow 裡的一個獨立步驟（會在獨立 VM 跑） |
| **Step** | Job 裡的一個小命令 |
| **Runner** | 跑 job 的機器（GitHub 託管 / self-hosted） |
| **Artifact** | Job 產出的檔案（test report、build 結果） |
| **Cache** | 跨 run 重用的檔案（node_modules、cargo target） |
| **Matrix** | 同一 job 用不同變數跑多次（如：跑 Node 18 + 20 + 22） |
| **OIDC** | GitHub Actions 用短期 token 取代長期密鑰登入 AWS / GCP（R56 會用到） |
| **Self-hosted runner** | 你自己機器當 CI 跑 job 的能力（ipig_system 沒用） |
| **Required check** | PR 必須通過才能 merge 的 check（branch protection 設） |
| **CodeRabbit** | 第三方 bot 自動 review PR（會在 PR 留 inline comments） |
| **Gemini Code Assist** | 同上，Google 的 |

---

## 11. 下一步學什麼

照「最常用到」排序：

1. **`docker compose` 指令** — 你天天用，但很多選項沒摸（`--scale`、`--profile`、`logs --since`）
2. **GitHub Actions yml syntax** — 想加新 CI job 必須會
3. **Rust + sqlx migration up/down** — schema 改動高風險
4. **Prometheus query (PromQL)** — 看 Grafana dashboard 時看不懂查詢條件
5. **CSP / CSRF / SameSite cookies** — 你 sliding session 都做了但底層概念可以再深化

每個都可以開獨立 `learn/` 文件（看 `learn/README.md` 候選清單）。

---

*本文件 2026-05-16 建立，作為 PR #428 sliding session cutover 期間的學習延伸。對應 CodeRabbit / Gemini 等 bot 出現後對 CI/CD 機制好奇而寫。*
