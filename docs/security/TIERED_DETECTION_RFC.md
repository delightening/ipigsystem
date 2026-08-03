# Tiered Security Event Detection (RFC)

> **狀態**: RFC（尚未排入 R-section）
> **日期**: 2026-05-14
> **靈感來源**: [Agent-Threat-Rule/agent-threat-rules](https://github.com/Agent-Threat-Rule/agent-threat-rules) — 給 LLM agent 的 Sigma/YARA 偵測規則格式
> **本文範圍**: 將「分層 + 規則資料化」思維對應到 iPig 既有的 middleware / audit infra；非實作計畫，是未來 R-section 立案前的設計討論底稿。

---

## 1. 為什麼寫這份

iPig 系統已有完整的安全事件偵測 infra（rate limit、IDOR probe、honeypot、CSP report、refresh_token_reuse、HMAC chain）— 但目前**所有規則 / 閾值 / event_type 都寫死在 Rust code 裡**：

- 調 rate limit threshold → 改 const → cargo build → 重啟
- 加新的 IDOR pattern → 改 middleware → cargo build → 重啟
- R46 refresh_token_reuse 降噪 → 改 service code → cargo build → 重啟

對於 **prod-on-laptop 一人維運**的場景（[[prod-on-laptop]]），這個 redeploy cycle 是不必要的摩擦。ATR 把規則抽成 YAML 後，security tuning 變成 config reload，不用 build。本 RFC 評估這個 pattern 是否值得引入 iPig。

---

## 2. ATR 的核心架構（直接複製貼上的部分）

### 2.1 五層偵測 tier（cost / latency / coverage 取捨）

| Tier | 名稱 | 延遲 | 覆蓋率 | iPig 對應現況 |
|---|---|---|---|---|
| 0 | invariant 硬規則 | 0ms | 100% | middleware 強制檢查（無 JWT → 401） |
| 1 | blacklist 比對 | <1ms | — | jwt_blacklist、honeypot 路徑表 |
| 2 | regex pattern | <5ms | ~62-70% | IDOR probe regex、CSP violation 過濾 |
| 2.5 | embedding 相似度 | ~5ms | +10-15% | （無，iPig 不需要） |
| 4 | LLM-as-judge | ~500ms | 剩下的 novel pattern | （無，iPig 不需要） |

**對 iPig 的啟示**：Tier 2.5 / 4 在 iPig 用不到（沒接 LLM），但 **Tier 0-2 的分層思維值得整理** — 目前是混在 middleware / service / handler 三層裡，沒有明確的「便宜先過、貴的後審」優先順序。

### 2.2 規則 schema（YAML rule-as-data）

ATR 每條規則的 YAML 大致長：
```yaml
id: ATR-2026-00440
title: Semantic Kernel lambda+eval RCE
severity: critical
category: agent_manipulation
mitre_attack: T1059
detect:
  tier: 2  # regex
  pattern: 'lambda\s+x:\s*eval\('
test:
  true_positive: ["lambda x: eval(x)", ...]
  true_negative: ["lambda x: x + 1", ...]
action: block
```

四個欄位回答四個問題：**what / how / what to do / how to test**。

---

## 3. 對應到 iPig 既有事件清單

從 `CLAUDE.md` § Anonymous 適用情境，iPig 已有 5 種匿名安全事件：

| event_type | 目前實作位置 | Tier | 建議規則化欄位 |
|---|---|---|---|
| `LOGIN_FAILED` / `ACCOUNT_LOCKED` | `handlers/auth.rs::login` | 0 (invariant) | 連續失敗閾值、鎖定時長 |
| `CSP_VIOLATION` | `handlers/csp_report.rs` | 2 (regex) | 允許 directive 白名單、降噪 pattern |
| `HONEYPOT_HIT` | `routes/mod.rs::honeypot_routes` | 1 (blacklist) | 蜜罐路徑清單 |
| `RATE_LIMIT_EXCEEDED` | middleware | 0 (invariant) | per-endpoint 閾值表 |
| `IDOR_PROBE` | middleware | 2 (regex) | URL pattern + scope 規則 |

加上 R35/R46 的：

| `REFRESH_TOKEN_REUSE` | `services/auth/session.rs::handle_refresh_token_reuse` | 0 (invariant) | 是否升級為 alert（R46 降噪） |

**觀察**：6 條事件中有 4 條都有「閾值 / 白名單 / 路徑表」這種**純資料**配置。把它們從 const 抽到 `config/security_rules.yml`（hot-reload）能省下大量 redeploy。

---

## 4. ATR 啟發的具體 pattern（可選擇性採納）

### 4.1 ✅ 強烈建議：誠實標註偵測極限

ATR 在 README 公開「regex 抓 62-70%」+ 64 條已知 evasion。對應到 iPig：

- R46 refresh_token_reuse — [[refresh-token-reuse-false-alarm]] 已知通常是 false alarm。應該在 alert template 直接寫「預期 false-positive 率 ~70%，請先 cross-check session 來源 IP / device fingerprint」。
- IDOR probe — 同理，列出已知 false-positive scenario（例：使用者複製貼上他人連結）。

**成本**: 改文檔，0 code。**收益**: 自己（一人維運）半夜被告警吵醒時不會立刻誤判。

### 4.2 🟡 中期考慮：規則資料化

把 const 抽 YAML：
```yaml
# config/security_rules.yml
honeypot_paths:
  - /wp-admin
  - /.env
  - /admin.php
rate_limits:
  /api/v1/auth/login: { window: 60s, max: 5 }
  /api/v1/animals: { window: 60s, max: 60 }
idor_probe_patterns:
  - regex: '/api/v1/animals/[0-9]+'
    reason: animals 用 UUID，數字 ID 必為探測
```
**代價**: 需要 hot-reload infra（notify watcher 或 SIGHUP）、YAML schema 驗證、預設值 fallback。**收益**: tune 閾值不用 redeploy。

**判斷**：除非未來 1 年內預期會頻繁調整這些值，否則目前 hardcoded 已夠用。**列入 R49 backlog 但不主動推進**（對齊 [[r28-low-bugs-parked]] 思維）。

### 4.3 ✅ 立刻可做：SARIF 整合 GitHub Security tab

iPig CI 已跑 `cargo audit` / `cargo deny` / `gitleaks` / `Trivy`。多數工具支援 `--format sarif`，加上 `github/codeql-action/upload-sarif@v3` 即可把結果送到 PR / 倉庫的 Security tab，不用 grep CI log。

**成本**: 改 `.github/workflows/ci.yml` 4-5 行。**收益**: 安全發現可見度大幅提升。

### 4.4 ❌ 不採納

- ATR 的 Tier 2.5 (embedding) / Tier 4 (LLM judge) — iPig 沒有 LLM 流量
- Threat Cloud 匿名 hash 上報 flywheel — 單實例系統沒有規模效益
- skill / plugin 供應鏈掃描 — iPig 無 plugin 機制
- 419 條 prompt injection 規則 — iPig 不接 LLM

---

## 5. 行動建議（給未來開啟 R-section 時參考）

| 優先序 | 動作 | 預估工時 | 開 R-section |
|---|---|---|---|
| P1 | alert template 加「預期 false-positive 率」說明（R46 配套） | 0.5h | 併入 R46 |
| P2 | CI workflow 加 SARIF upload | 1h | R-misc 或併下個 dependabot week |
| P3 | rate limit / honeypot 規則資料化 | 4-8h | R49（等需求） |
| P4 | 規則 hot-reload infra | 8-16h | R50+（看 P3 有沒有跑） |

---

## 6. 結論

ATR 的 **分層偵測** + **規則資料化** + **誠實標註偵測極限** 三個 pattern 中，前兩個可選擇性引入，**最後一個（誠實標註）立刻就能做且零成本**。iPig 不需要全套搬，但 P1 / P2 兩個低成本動作建議排入近期 sprint。

---

## 7. 連結

- ATR repo: https://github.com/Agent-Threat-Rule/agent-threat-rules
- 既有相關 doc:
  - [`THREAT_MODEL.md`](THREAT_MODEL.md) — iPig 既有威脅模型
  - [`HMAC_VERSIONING.md`](HMAC_VERSIONING.md) — audit chain 完整性
  - [`AUDIT_REDACTION.md`](AUDIT_REDACTION.md) — 敏感資料遮罩
