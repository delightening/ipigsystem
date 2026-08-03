# Security Event Detection Limits

> **目的**：誠實標註 iPig 各安全偵測 event 的**預期誤判率（false-positive rate）** + **已知 evasion 情境** + **維運半夜被告警吵醒時的第一步 cross-check**。
>
> **理念**：對齊 [`TIERED_DETECTION_RFC.md`](TIERED_DETECTION_RFC.md) §4.1 — ATR repo 把 regex coverage 寫成「62–70%」、把 64 條已知 evasion 公開到 README，是對單人維運（[[prod-on-laptop]]）最友善的做法。本表用同樣的精神：**不假裝 100% 準確**，讓收到 alert 的人立刻知道「下一步該查什麼」而不是「先慌一下」。
>
> **適用場景**：勤務人員（同 admin / SRE）半夜收到 `security_alerts` row 寫入通知時，照本表分鐘級決定 (a) 立即處置 vs (b) 隔天再看。

---

## 1. 事件對照表

> Tier 對應 RFC §2.1 — Tier 0 = invariant 硬規則（0% FP，誤判即 bug），Tier 1 = blacklist 比對，Tier 2 = regex / 啟發式。

| event_type | Tier | 嚴重度 | 預期 FP 率 | 第一步 cross-check |
|---|---|---|---|---|
| `REFRESH_TOKEN_REUSE` | 2 (啟發式) | warning / critical | **~60–80%**（見 §2） | session.last_ip / last_user_agent vs reused_ip / reused_ua |
| `HONEYPOT_HIT` | 1 (blacklist) | warning | **~5%**（誤踩固定路徑） | 來源 IP 是否在 user-agent allowlist（scanner / bot vs 真實 user） |
| `RATE_LIMIT_AUTH` | 0 (invariant) | warning | **0%**（純計數）| 連 IP 是否在 known good range，密碼錯誤次數連發 vs 一發 |
| `RATE_LIMIT_API` / `_WRITE` / `_UPLOAD` | 0 (invariant) | warning | **0%** | 同上，但通常代表 client 端 bug（迴圈未節流）而非攻擊 |
| `RATE_LIMIT_FORGOT_PASSWORD` | 0 (invariant) | warning | **~10%**（家人共享 IP / 連續打錯）| email 是否屬於系統存在的使用者 |
| `RATE_LIMIT_AI_KEY` | 0 (invariant) | warning | **0%** | 看 AI key 對應使用者是否短時間打了大量 cost-bearing endpoint |
| `ACCOUNT_LOCKOUT` | 0 (invariant) | warning | **~20%**（使用者忘記密碼）| 帳號是否屬於剛回工時忘密碼的真實使用者 |
| `PERMISSION_DENIED` | 0 (invariant) | info | **~70%**（多為 UI 路由錯誤導致）| 同一 user 短時間內是否打到同 endpoint 多次 |
| `USER_AUTO_SUSPENDED` | 0 (invariant) | critical | **~5%** | scheduler 邏輯（多次失敗鎖定）是否合理觸發 |

---

## 2. `REFRESH_TOKEN_REUSE` 細項

> 此事件 FP 率最高 — 三階段啟發式（R46-1/2/3）即為**降誤判**而設計，仍會有殘留誤判。

實作見 `backend/src/services/auth/session.rs::handle_refresh_token_reuse`。

### 2.1 已知 false-positive 情境

| 情境 | 為何誤判 | 啟發式覆蓋？ |
|---|---|---|
| 使用者在 mobile + desktop 多分頁同時操作 | 兩條 client 各自呼叫 refresh，慢的那條撞到已 rotate 的 token | ✅ R46-1 race window（≤ 5 秒，僅 `tracing::warn`，不告警）|
| 行動裝置切換 Wi-Fi / 4G 重連 | client 重新整理，舊 token 殘留 | ✅ R46-2 same IP + same UA → severity 降 `warning` |
| 使用者把 browser 開著去吃午餐，回來再開頁 | pre-R46-2 legacy token 缺 last_ip baseline，被重用觸發 | ✅ R46-3 stale-tab heuristic：>1h 且 baseline NULL → `warning` |
| 共享 NAT 內網（公司 office）多使用者 | 同 IP 但不同 UA / 不同 user_id | ❌ 不適用（FK = user_id，不會跨使用者交叉）|
| 使用者複製 cookie 到其他 browser 試 | same IP 但不同 UA | ⚠️ 維持 `critical`（fail-safe 設計 — 這條真的可能是攻擊也可能是使用者）|

### 2.2 真正攻擊 indicator（不要 dismiss）

- `reused_ip` 與 `last_login_ip` 在不同**國家** / **ASN**：機率高為 token 外流。
- `time_since_rotation_secs > 86400`（>1 天）且 `same_ip = false`：使用者不太可能隔天才從不同 IP 重用。
- 同一 user 短時間內**多次** `REFRESH_TOKEN_REUSE`：攻擊者持續嘗試。
- alert `context_data` 含 `severity = critical` 且 `same_ip = false, same_ua = false`：三階段啟發式全沒救濟。

### 2.3 維運第一步

```sql
-- 查 alert 完整 context（DataGrip / psql）
SELECT context_data FROM security_alerts WHERE id = '<alert-id>';

-- 看該使用者最近的 session activity
SELECT id, last_ip, last_user_agent, rotated_at, revoked_at, revoked_reason
FROM refresh_tokens
WHERE user_id = '<user-id>'
ORDER BY created_at DESC
LIMIT 10;
```

判斷 `last_ip` 跟 `reused_ip` 是否同一 ISP / 國家。差太多 → 強制 logout + 通知使用者改密碼。同 ISP → 大概率是合法 client bug，可暫時 dismiss 但記下 user_id 看頻率。

---

## 3. `HONEYPOT_HIT` 細項

實作見 `backend/src/handlers/honeypot.rs` + `routes/mod.rs::honeypot_routes`。

蜜罐路徑（`/wp-admin`, `/.env`, `/admin.php` 等）是**真實使用者絕對不會打到**的 URL。FP 率極低，但仍有：

- **掃描器測試自己的 cookie domain**：commercial security scanner（如 Cloudflare bot）有時會打蜜罐路徑做存活測試。
- **舊 bookmark / link rot**：理論上不會撞到蜜罐路徑（這些路徑 iPig 從未 serve 過）。

維運第一步：看 user-agent，是 `Googlebot` / `Cloudflare-Healthcheck` / 已知 bot → dismiss；是 Chrome / curl + 無 referrer → 真正掃描，IP 加 ban list。

---

## 4. `RATE_LIMIT_*` 細項

純計數型 invariant，FP 率原則為 0（達到閾值 = 真的達到），但**閾值本身**可能設得太緊：

| 端點族 | 目前閾值 | 觸發代表 |
|---|---|---|
| `auth` | 30 req / min / IP | 同 IP 1 秒打 1 次密碼 — 通常是暴力破解 |
| `api` (general) | 600 req / min | 前端 bug（迴圈無節流）為大宗 |
| `write` | 60 / min | 大量匯入 / 大量寫入 — 確認是否有 batch upload 場景 |
| `upload` | 10 / min | 短時間上傳 10 個檔，正常使用者很少撞到 |
| `forgot_password` | 5 / min | 連續輸錯 email 5 次，~10% 是真實使用者忘了 |
| `ai_key` | 依 key 上限 | 該 key 對應使用者打了大量 cost endpoint |

維運第一步：先看 `RATE_LIMIT_API` 是否同一 IP 連續觸發 — 一次性可暫不理；連 5 分鐘以上 → 該 IP 加 ban list。

---

## 5. `ACCOUNT_LOCKOUT` 細項

實作：5 次密碼錯誤 → 鎖定 N 分鐘（見 `services/auth/session.rs`）。

FP 率 ~20% — 使用者長假回來忘密碼、輸入法切換沒注意大小寫。

維運第一步：看 lockout 對應 user.email 是否屬於系統使用者 + 該 user 過去 30 天活躍狀況。活躍使用者忘密碼 → 主動聯絡 / unlock。Email 不存在 → 帳號枚舉攻擊，紀錄 IP 但不擴大處置（lockout 本身已抑制）。

---

## 6. 維運回應 SOP（半夜版）

收到 critical alert 時的決策樹：

1. **先看 alert 的 event_type** → 對應本表 §1
2. **打開 `security_alerts.context_data`** — JSONB 內含 user / IP / UA / time delta
3. **同事件 24h 內幾次？**
   - 1 次 → 多半 FP，明早再看（除非是 `USER_AUTO_SUSPENDED` 或 `REFRESH_TOKEN_REUSE` + 不同國家 IP）
   - 5+ 次 → 攻擊在進行，立即 ban IP / force logout 該 user
4. **GLP 影響？** 若涉及 audit / signature 完整性 → 升級 `[[byproduct-samples-financial]]` 等同金錢級別的處置門檻

---

## 7. 連結

- [`TIERED_DETECTION_RFC.md`](TIERED_DETECTION_RFC.md) — 偵測方法論母文件（ATR 借鏡 / 五 tier 架構）
- [`THREAT_MODEL.md`](THREAT_MODEL.md) — 威脅模型（資產 + actor + 風險矩陣）
- `backend/src/services/auth/session.rs` — REFRESH_TOKEN_REUSE 三階段啟發式實作
- `backend/src/handlers/honeypot.rs` — 蜜罐路徑實作
- `backend/src/constants.rs` § Security events — 所有 `SEC_EVENT_*` 常數

---

## 8. 更新原則

- **修改 FP 率估計時**：在 PR 描述放 30 天觀察期樣本（`security_alerts` 表 row 數 / dismissed 數 / 確認攻擊數）
- **新增 event_type 時**：必須同時在本表 §1 加 row，否則禁止 merge — 對齊 CLAUDE.md § 「ActorContext::Anonymous 適用情境」新增事件 checklist
- **此文件不放實際攻擊指紋** — IP 黑名單 / known scanner UA 等屬營運機密，放 `secrets/` 或 admin 私有筆記
