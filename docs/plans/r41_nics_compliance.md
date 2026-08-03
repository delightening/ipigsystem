# R41 — NICS 防護基準合規 gap 修復實施計畫

> **立案**：2026-05-11
> **背景**：對應 `docs/security/NICS_COMPLIANCE_AUDIT_2026-05.md`。普級 ~92% 已達標，本計畫補完 4 個 PARTIAL + 3 個中級補強 + 1 個高級評估，共 8 項。
> **目標等級**：普級 100%（mandatory），中級補強到 ~90%（best effort，不追 SOC/FIPS/RTO 8h）。
> **總工時估計**：**~8–10 小時**（重新評估後，比初估縮減 ~30%，因 R41-2/5/6 已多半實作）。
> **完成標準**：每項都有 (a) 程式或文件落地、(b) 對應 acceptance test 或人工 verify、(c) `docs/PROGRESS.md` §9 紀錄。

---

## 修正後的工作量再評估（vs 立案時）

| # | 原估 | 修正後 | 修正原因 |
|---|---|---|---|
| R41-1 後端 idle session | 4h | **4h** | 仍需新欄位 + middleware + acceptance test |
| R41-2 HMAC chain 主動告警 | 3h | **1h** | `audit_chain_verify.rs` 已實作完整 verify + alert + dispatch，只缺啟用旗標 |
| R41-3 Audit 容量分區政策 | 1h | **1h** | 純文件，含 Prometheus alert rule |
| R41-4 密碼政策 NIST 偏離文件化 | 1h | **0.5h** | 純文件 |
| R41-5 SAST CI | 3h | **1.5h** | `cargo-audit` + Trivy 已就位（CI line 39 + 596），只缺 semgrep |
| R41-6 R22 IP block 串接驗證 | 2h | **1h** | `ip_blocklist::auto_block` 已實作，只需驗證 R22 alert path 是否觸發它 |
| R41-7 Security index 連結 | 0.5h | **0.5h** | 純文件 |
| R41-8 DB at-rest 評估 | 2h | **1h** | 僅評估文件，不實作 |

**合計**：~10.5h（保守）

---

## Phase 排序原則

1. **Phase A — 純文件 / 啟旗標**（無 production 變動）→ 一次 PR 全包，可平行做
2. **Phase B — CI 變動**（不影響 runtime）→ 第二 PR
3. **Phase C — 後端邏輯變動**（idle session + verify R22 wiring）→ 最後做，獨立 PR，需 acceptance test

| Phase | 包含項 | PR 數 | 預估工時 |
|---|---|---|---|
| A | R41-2 (啟旗標), R41-3, R41-4, R41-7 | 1 PR | 3h |
| B | R41-5 (semgrep) | 1 PR | 1.5h |
| C | R41-1 (idle), R41-6 (R22 verify), R41-8 (assess) | 2-3 PR | 6h |

---

## Phase A — 文件 + 啟旗標（一次到位）

### R41-2 啟用 HMAC chain 每日驗證

**現況**：`backend/src/services/audit_chain_verify.rs` 已完整實作（含 verify_chain_range + create_security_alert + SecurityNotifier::dispatch）。`SchedulerService::register_audit_chain_verify_job` 已排程每日 02:00 UTC。預設 `AUDIT_CHAIN_VERIFY_ACTIVE=false`，因 R26-6 HMAC 版本化要 ops 確認 migration 037 + 測試環境無 false positive 後才啟用。

**待辦**：
1. 確認 migration 037 已套用到 prod（`SELECT * FROM _sqlx_migrations WHERE version = 37`）
2. **僅在 staging / 隔離測試 DB** 設 `AUDIT_CHAIN_VERIFY_ACTIVE=true` 並讓 cron 跑連續 ≥7 天（覆蓋 weekend + weekday + 跨日邊界）
3. 確認 ≥7 天均無 false positive → prod docker-compose secrets 設 `AUDIT_CHAIN_VERIFY_ACTIVE=true`
4. **Tamper 測試僅可在 staging / 還原備份至獨立 DB 進行**：`UPDATE user_activity_logs SET hash = 'broken' WHERE id = ?` → 隔日 cron 應產 security_alert + email。**禁止對 production `user_activity_logs` 做任何 UPDATE / DELETE**（會污染稽核鏈、且 HMAC chain 從此斷裂無法復原）
5. Production 端的驗證僅做非破壞性檢查：cron 啟動 log + dry-run verifier endpoint + 模擬 security_alert dispatch 路徑

**Acceptance**：
- prod env var 已設 active=true
- staging tamper 測試產出 `audit_chain_broken` security_alert + 收到通知 email/LINE
- prod 連續 7 天 cron 跑完無 false positive log

**Files**：`.env` (or Docker secret), `docker-compose.prod.yml`

**Risk**：低；最壞情況產 false positive → 暫時 disable 旗標即可

---

### R41-3 Audit table 容量分區政策文件化

**現況**：`DATA_RETENTION_POLICY.md` §2 寫「稽核日誌保留 10 年」，但**未說明大量 row 後的歸檔/分區策略**。Prometheus 有磁碟告警（P5-7），但未對 `user_activity_logs` 表本身設容量閾值。

**待辦**：
1. `DATA_RETENTION_POLICY.md` 新增 §6：
   - 觸發點：`user_activity_logs` row count > 5M 或 size > 5GB
   - 行動：執行 `bin/audit_archive` CLI（**新建**，把 >2 年資料匯出加密 tar.gz 到備份卷 + DELETE）
   - 排程：每月手動 review（半年內預期不會觸發，5GB ≈ 數百萬筆事件）
2. Prometheus alert rule：`pg_relation_size{table='user_activity_logs'} > 5e9` → warning
3. 建立 `backend/src/bin/audit_archive.rs` skeleton（最小可跑：export + delete + 寫 audit log 紀錄歸檔事件）

**Acceptance**：
- 文件描述清楚
- alert rule 在 Prometheus 載入無語法錯誤（`promtool check rules`）
- `cargo build --bin audit_archive` 通過

**Files**：
- `docs/security/DATA_RETENTION_POLICY.md`
- `deploy/prometheus/alerts.yml`（or 對應路徑）
- `backend/src/bin/audit_archive.rs`（新檔；不需 acceptance test，bin tool 走人工 verify）

**Risk**：低

---

### R41-4 密碼政策 NIST 偏離文件化

**現況**：CLAUDE.md「⛔ 禁止事項」明文禁止密碼過期 + 歷史紀錄，但**未提供合規 audit 看得懂的依據**。附表十中/高級字面要求「定期更換」，故需顯式說明本系統依 NIST SP 800-63B 偏離。

**待辦**：建立 `docs/security/PASSWORD_POLICY.md` 涵蓋：
- 現行政策：min 10 碼、無歷史、無過期、**Argon2id**（argon2 0.5 crate 預設參數，記憶體強化）、5 次失敗 30 分鐘鎖定
- NIST SP 800-63B §5.1.1.2 引用（建議不要強制定期更換、改採風險基礎重置）
- 偏離附表十中/高級的說明：本系統採 NIST 國際慣例優於附表十條文，與業界 1Password / GitHub / AWS 對齊
- 補償控制：2FA TOTP（P5-3，admin 強制 + 一般使用者可選）、HIBP 未採用但 Argon2id 記憶體強化計算成本、5/30min 帳號鎖定、HMAC chain audit

**Acceptance**：文件存在、可 link 到 audit 報告

**Files**：`docs/security/PASSWORD_POLICY.md`（新檔）

**Risk**：零

---

### R41-7 Security index 連結 + 半年複查排程

**待辦**：
1. `docs/security/security.md`（若不存在則建）加入索引段：
   ```markdown
   ## 合規對照
   - [NICS 防護基準 2026-05](NICS_COMPLIANCE_AUDIT_2026-05.md)（下次複查：2026-11-11）
   - [密碼政策](PASSWORD_POLICY.md)
   - [資料保留政策](DATA_RETENTION_POLICY.md)
   - [HMAC 版本管理](HMAC_VERSIONING.md)
   ```
2. TODO.md 加排程提醒：在 R41 chapter 加「下次複查：2026-11-11」注記

**Acceptance**：grep 能搜到 `NICS_COMPLIANCE_AUDIT_2026-05.md` 連結 ≥ 1 處

**Files**：`docs/security/security.md`, `docs/TODO.md`

---

## Phase B — SAST CI 補強

### R41-5 加入 semgrep 程式碼級 SAST

**現況**：`.github/workflows/ci.yml` 已有：
- L39 `cargo audit`（Rust dep 弱掃）✅
- L596 Trivy 容器掃描（image CVE）✅

**Gap**：缺**程式碼級 SAST**（會掃 SQL 拼接、XSS sink、unsafe deserialize 等模式）

**待辦**：
1. CI 新增 `semgrep` job（使用 `returntocorp/semgrep-action` 或 `semgrep ci`）
2. ruleset 採用 `p/rust` + `p/typescript` + `p/owasp-top-ten` 基準
3. 第一次跑允許 PR comment（不 fail）；觀察 1 週後依基線 finding 數決定是否 fail build
4. `.semgrepignore` 視首跑結果調整

**Acceptance**：
- 新 PR 觸發時 semgrep job 跑完並 post comment 或 SARIF 上傳
- 至少跑一次完整 main branch baseline 並記錄 finding 數到 `docs/security/security.md`

**Files**：`.github/workflows/ci.yml`, `.semgrepignore`（新檔）, `docs/security/security.md`

**Risk**：低（純 CI 增量）；可能踩到大量舊 finding，故先 non-blocking

---

## Phase C — 後端邏輯 + 評估

### R41-1 後端閒置 session 強制 revoke

**現況**：
- JWT 6h expiry + Refresh token 30d（`constants.rs:11` `REFRESH_TOKEN_EXPIRY_DAYS = 30`）
- 前端 `SessionTimeoutWarning` 元件預警（P1-32）
- **後端 refresh endpoint 不檢查「最後活動時間」**，所以 user 30 天沒動仍能 refresh 取得新 JWT

> **2026-05-18 更新**：上述 "JWT 6h" 與 "SessionTimeoutWarning 預警" 為 R41 立案時
> 現況快照，2026-05-18 sliding session overhaul（PR #455）後已不再如此 —
> JWT TTL = 15 min (env 預設)、SessionTimeoutWarning 元件已移除、idle 強制登出
> 改由 `cleanup_expired` 5min cron 執行（idle 8h、absolute 24h）。R41-1 後端
> refresh idle 檢查另由 R41 章節後續方案落地。本段保留 audit trail 不直接覆寫。

**設計選擇**（surface tradeoff）：

| 方案 | 實作 | 缺點 |
|---|---|---|
| **A. DB `refresh_tokens.last_used_at`** | 每次 refresh 更新；refresh endpoint 檢查 `now - last_used_at < idle_window` | 不會記 access token 活動（只記 refresh），window 偏寬鬆 |
| **B. DB `refresh_tokens.last_activity_at` + middleware throttled update** | 每個帶 JWT 的 request 都更新（但 ≤1 次/5 分鐘 throttle 降 DB 寫入） | 每個 request 多 1 條 DB write 路徑（即使 throttled） |
| **C. Redis sliding window** | 性能最佳 | **本專案沒 Redis**，引入新依賴 over-spec |

**建議**：**方案 A**。

理由：附表十「閒置鎖定」的合規語意是「使用者長期不互動則需重新登入」。Refresh token 滾動 = 主動 session 的明確指標（前端有 axios interceptor 在 token 快過期時自動 refresh，意味著 user 有在用 app）。Refresh 失敗 → 前端走 login flow，符合條文精神。Cost 低、不引入 Redis、不污染每個 request 路徑。

**閒置 window**：30 分鐘（與普級「閒置鎖定」業界慣例對齊；現有 SessionTimeoutWarning 60s 預警可保留）。

**待辦**：
1. Migration: `ALTER TABLE refresh_tokens ADD COLUMN last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
2. `services/auth/refresh.rs`（找對應檔名）:
   - 檢查 `NOW() - last_used_at > INTERVAL '30 minutes'` → return `AppError::Unauthorized("idle_timeout")`
   - 否則 UPDATE `last_used_at = NOW()` 並發新 JWT
3. 整合測試：
   - test 1: refresh in 1 minute → 200
   - test 2: mock clock advance 31 min → refresh 401
4. 前端 `SessionTimeoutWarning` 對應 401 idle_timeout 顯示明確訊息（i18n key 新增）

**Acceptance**：
- `cargo test --all-targets` 含 2 個新整合測試綠
- 手動：開瀏覽器 → 30 分鐘無互動 → 強制登出（或刷新時被踢）

**Files**：
- `migrations/0XX_refresh_token_last_used_at.sql`
- `backend/src/services/auth/refresh.rs`
- `backend/src/tests/auth_idle_test.rs`（新檔）
- `frontend/src/lib/i18n/*.json`
- 配合 i18n 規範（zh-TW + en 同步）

**Risk**：中（auth flow 改動）。Mitigation：可設定 `AUTH_IDLE_TIMEOUT_MINUTES` env var 預設 30，緊急可調 1440 暫時 bypass。

---

### R41-6 R22 自動 IP block 串接驗證

**現況**：
- `services/ip_blocklist.rs::auto_block` 已實作（grep 確認）
- R22 alert flow（`alert_threshold.rs` + `SecurityNotifier`）已實作
- **未驗證的問題**：當 R22 觸發 brute force / IDOR critical alert 時，是否同時呼叫 `auto_block`？還是 auto_block 只在別處被觸發？

**待辦**（investigation-first，非預先寫死實作）：
1. 讀 `services/alert_threshold.rs` 與 `middleware/rate_limiter.rs` 找 `auto_block` 呼叫點
2. 若已串接：寫一個整合測試證實「同 IP 連續 N 次失敗登入 → ip_blocklist 表新增該 IP」
3. 若未串接：在 `check_brute_force` critical 分支新增 `IpBlocklistService::auto_block(ip, reason, 1h)`
4. 寫 `docs/security/security.md` §IP Block flow 段落，文件化「攻擊→偵測→告警→自動封鎖」鏈

**Acceptance**：
- 整合測試：同 IP 5 次 login 失敗（已超 brute force 閾值）→ DB query `ip_blocklist` 表該 IP 存在且 `expires_at > NOW()`
- 文件更新

**Files**：（依 investigation 結果）`services/alert_threshold.rs`、新測試檔、`docs/security/security.md`

**Risk**：低（純疊加，現有 `auto_block` 已驗證可用）

---

### R41-8 DB at-rest encryption 評估文件

**待辦**：產出 `docs/assessments/DB_AT_REST_ENCRYPTION_2026-05.md` 涵蓋：

| 選項 | 優點 | 缺點 | 建議 |
|---|---|---|---|
| OS BitLocker（host C: 磁碟） | 整顆磁碟加密；零應用層改動 | 開機需密碼/TPM；筆電本來就鎖 | **推薦** |
| Postgres TDE（pgcrypto column-level） | 細粒度 | 需動 schema + app code；ipig 已加密 TOTP secret | 不推薦（過度工程） |
| NAS 加密卷（DS923+ shared folder） | 異地備份已加密 ✅ | 不影響運行中 prod DB | 已實作（R36） |
| Postgres TDE（Cybertec/EDB 商業） | 標準合規 | 商業授權成本 | 不推薦（單人系統） |

**結論預期**：建議啟用 BitLocker（Windows Pro 本來就有），其他不追。

**Acceptance**：文件落地 + 結論寫進 NICS audit 報告 §10「不建議追的項目」updated

**Files**：`docs/assessments/DB_AT_REST_ENCRYPTION_2026-05.md`, `docs/security/NICS_COMPLIANCE_AUDIT_2026-05.md`

**Risk**：零（純評估）

---

## 排程與 commit 粒度（對齊「執行紀律」§ Commit 粒度）

### PR #R41-A：Phase A 文件 + 啟旗標
- commit 1: R41-3 + R41-4 + R41-7（純文件）
- commit 2: R41-3 `audit_archive` bin skeleton + Prometheus alert
- commit 3: R41-2 啟用 `AUDIT_CHAIN_VERIFY_ACTIVE` + secret 更新（**需手動驗證 staging ≥7 天才合併**）
- 測試：`cargo check`（純文件 commit）+ `cargo build --bin audit_archive`
- 停機點：merge 後停 ✋

### PR #R41-B：Phase B SAST
- commit 1: 新增 semgrep CI job（non-blocking）
- commit 2: 跑首次 baseline + `.semgrepignore` + `docs/security/security.md` 記基線數
- 測試：CI 跑通即可（不需 cargo test）
- 停機點：merge 後停 ✋

### PR #R41-C1：R41-1 後端 idle session（風險最高，獨立 PR）
- commit 1: migration + repo 層
- commit 2: refresh service + 2 integration tests
- commit 3: 前端 i18n + error 訊息
- 測試：`cargo test --all-targets`（touches handlers）
- 停機點：merge 後 + prod smoke test 後停 ✋

### PR #R41-C2：R41-6 R22 串接 verify
- commit 1: investigation 結果寫入 docs
- commit 2:（如需）alert_threshold 加 auto_block 呼叫
- commit 3: 整合測試
- 測試：`cargo test --all-targets`
- 停機點：merge 後停 ✋

### PR #R41-C3（可選）：R41-8 評估文件
- 單一 commit，純文件
- 可併入 PR #R41-A 第二輪追加，或獨立輕量 PR

---

## 風險與緩解

| 風險 | 機率 | 緩解 |
|---|---|---|
| R41-2 啟用後 false positive 騷擾 | 中 | staging 跑 ≥7 天觀察才上 prod；隨時可 disable 旗標 |
| R41-1 idle 30 分鐘太嚴格擾民 | 中 | 用 env var 控制門檻，初期設 60 分鐘觀察 |
| R41-5 semgrep 一次出幾百筆 finding | 高 | 預先設 non-blocking，先建 baseline 再分輪降 |
| R41-6 investigation 發現未串接需大改 | 低 | `auto_block` 已存在，串接成本低 |

---

## 不在本計畫範圍（明確排除）

- **SOC 24x7 監控**：Cloudflare WAF + Prometheus alert 已 cover 普級語意
- **FIPS 140-2 加密模組**：標準 Argon2id + AES-GCM 已是業界共識；採購 HSM 對單人系統 over-spec
- **RTO 8h 熱備援**：NAS DS925+ 計畫後再評估（記憶 `nas-setup`）
- **委外開發安全條款**：N/A，solo 開發
- **紅藍隊演練 / SOC API 對接**：高級才要求，N/A
- **R22-15 Grafana security dashboard**：已 parked 在 R22，本計畫不收回

---

## 完成定義 (DoD)

- [ ] 8 個 R41 子項全部 `[x]`
- [ ] 4 個 PARTIAL（R41-1/2/3/4）對應 audit 報告章節改標 ✅ PASS
- [ ] `NICS_COMPLIANCE_AUDIT_2026-05.md` 普級總分 = 100%（與抬頭「mandatory」一致）
- [ ] `docs/PROGRESS.md` §9 紀錄完成
- [ ] 下次複查日期（2026-11-11）寫入 `security.md`

---
*本計畫由 Claude Code 於 2026-05-11 立案；R41 各項完成時逐項在 TODO.md 標 [x] 並更新此檔狀態欄。*
