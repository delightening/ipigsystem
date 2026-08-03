# 後端依賴「維護性問題」處置計畫（2026-06-24）

> **性質**：規劃文件，**不含任何程式碼 / 依賴變更**。等使用者逐項裁定後才實作。
> **觸發**：使用者要求「有使用的套件就換成有良好維護的依賴，看看能否避免套件維護問題」。
> **調查方法**：`cargo-audit`（離線 RustSec DB）實測 + `Cargo.lock` 反向依賴解析 + `index.crates.io` 版本查詢 + 原始碼用法 grep。
> **關聯**：`backend/deny.toml`、`docs/security/DEPENDENCY_CVE_SCAN_2026-06-24.md`、PR #788。

---

## 0. TL;DR（先看這段）

1. **使用者的前提需要修正**：那 5 個「unmaintained」advisory 對應的 crate（`bincode`/`fxhash`/`kuchiki`/`proc-macro-error`）**早就不在依賴樹裡了**——它們是已被移除的 `printpdf` 0.9 的傳遞依賴。`lettre` 的也已隨升級修復。**deny.toml 裡有 5 條是殭屍 ignore**。
2. **目前真正「活著」的維護性問題只有 1 個**：`proc-macro-error2`，由 **`validator`**（不是 deny.toml 註解寫的 utoipa）的 derive macro 引入。**且無升級路徑可擺脫**（validator 0.20 已是最新，所有 0.19+ 都用它，更舊版用更老的 proc-macro-error）。
3. **🔴 報告更正**：`rsa`（RUSTSEC-2023-0071）先前被我判定「程式碼路徑不會執行」是**錯的**——RS256 實際用於 Google Calendar service-account JWT 簽章。需改為「可達但 Marvin 威脅模型下實務不可利用」。
4. **建議結論**：**不要為了消除維護性警告而替換 `validator`**（用太重、本身有維護、只是 build-time macro）。真正值得做的是 (a) 清掉 5 條殭屍 ignore、(b) 修正 2 處錯誤註解、(c) 評估把 `jsonwebtoken` 換 `aws-lc-rs` 後端順手移除 `rsa`。

---

## 1. deny.toml 8 條 ignore 的真實狀態（實測校正）

> 以 `cargo-audit`（**不讀** deny.toml，純 RustSec 比對）+ `Cargo.lock` 反查為準。

| RUSTSEC ID | crate | deny.toml 標註來源 | **實際狀態** | 真實來源 |
|---|---|---|---|---|
| RUSTSEC-2023-0071 | `rsa` | sqlx-mysql ❌ | 🔴 **LIVE**（漏洞） | `jsonwebtoken`（RS256，見 §3） |
| RUSTSEC-2026-0173 | `proc-macro-error2` | utoipa ❌ | 🟡 **LIVE**（unmaintained 警告） | `validator_derive 0.20` |
| RUSTSEC-2026-0097 | `rand` | rand 0.8 | ⚪ **LIVE**（unsound 警告） | 多處傳遞（0.8.5 + 0.9.2 並存） |
| RUSTSEC-2024-0370 | `proc-macro-error` | utoipa | 💀 **STALE**（crate 已不存在） | — |
| RUSTSEC-2025-0141 | `bincode` | printpdf 0.9 | 💀 **STALE**（printpdf 已移除） | — |
| RUSTSEC-2025-0057 | `fxhash` | printpdf 0.9 | 💀 **STALE**（printpdf 已移除） | — |
| RUSTSEC-2023-0019 | `kuchiki` | printpdf 0.9 | 💀 **STALE**（printpdf 已移除） | — |
| RUSTSEC-2026-0141 | `lettre` | lettre 0.11.21 | 💀 **STALE**（現用 0.11.22 已修） | — |

> **驗證依據**：`cargo-audit` 全量輸出只報 `rsa` / `proc-macro-error2` / `rand`（兩版）；`grep '^name = "<crate>"' Cargo.lock` 對 printpdf/bincode/fxhash/kuchiki/proc-macro-error 皆回 0 筆；lettre 為 0.11.22。

---

## 2. 真實依賴鏈

```text
直接依賴 (Cargo.toml)         傳遞引入                 維護性/安全 advisory
─────────────────────────────────────────────────────────────────────
validator = "0.20"  ──► validator_derive 0.20 ──► proc-macro-error2 2.0.1   RUSTSEC-2026-0173 (unmaintained)
jsonwebtoken = "10" ──► rsa 0.9.10                                          RUSTSEC-2023-0071 (Marvin)
(多處) ─────────────► rand 0.8.5 / 0.9.2                                    RUSTSEC-2026-0097 (unsound)

utoipa = "5" ───────► (proc-macro2 only，不含 proc-macro-error*)            ✅ 乾淨
printpdf（已移除）──► bincode / fxhash / kuchiki                            💀 已不存在
```

---

## 3. 🔴 rsa 風險重新評估（報告更正）

**舊（錯誤）結論**：「系統只用 ES256，RSA 程式碼路徑不會執行 → 不可利用」。

**事實**：
- 使用者登入 JWT：`Validation::new(Algorithm::ES256)`（`middleware/auth.rs:141`）✅ ES256。
- `Algorithm::SHA1`（`two_factor.rs`）：是 **TOTP** 雜湊演算法（totp-rs），與 rsa 無關。
- **`Algorithm::RS256`（`services/google_calendar.rs:558`）**：用 `EncodingKey::from_rsa_pem` + `jsonwebtoken::encode` 簽 Google service-account JWT 換取 access token → **確實走 `rsa` crate 的 RSA 私鑰簽章**。

**正確風險評估（RUSTSEC-2023-0071 Marvin Attack）**：
- Marvin 是對 RSA **私鑰運算**的時序側通道，利用前提：攻擊者能**反覆**對**可控輸入**觸發私鑰運算並**量測細粒度時序**。
- 此處的運算是：用**系統自有**的 Google service-account 私鑰，簽**系統自產**、固定結構的 claims（iss/scope/aud/exp/iat），**伺服器端對外呼叫** Google token endpoint。
- 攻擊者**無法**提交選擇密文做解密、**無法**取得逐次運算的時序 oracle → **Marvin 威脅模型的前提不成立**。
- 殘餘風險：若 service-account 私鑰外洩，攻擊者可冒充該服務帳號——但那是金鑰保管問題，與 Marvin 無關。

**結論**：嚴重度維持「實務風險低、可接受」，但**理由必須從「路徑不可達」改為「路徑可達但不符 Marvin 利用前提」**。`docs/security/DEPENDENCY_CVE_SCAN_2026-06-24.md` §3.1 需據此更正（見 WS-6）。

---

## 4. 處置計畫（workstreams）

> 每項標示風險、成本、是否建議做。**全部尚未執行。**

### WS-1 — 清除 5 條殭屍 ignore（✅ 建議優先做）
- **動作**：從 `backend/deny.toml [advisories].ignore` 移除 RUSTSEC-2024-0370 / 2025-0141 / 2025-0057 / 2023-0019 / 2026-0141 五行。
- **理由**：對應 crate 已不在依賴樹；殭屍 ignore 會掩蓋「未來這些 crate 又被引入」的真實警訊，違反 §10 清理規則（清自己造成的 / 過時項目）。
- **風險**：極低、可逆。**驗證**：移除後 `cargo deny check advisories` 仍綠（因為這些 crate 本就不存在，不會觸發）。
- **成本**：~5 分鐘。

### WS-2 — 修正 deny.toml 2 處錯誤註解（✅ 建議，與 WS-1 同批）
- **動作**：
  - RUSTSEC-2023-0071 註解 `sqlx-mysql` → 改 `jsonwebtoken（RS256，Google Calendar service-account 簽章）`。
  - RUSTSEC-2026-0173 註解 `utoipa` → 改 `validator_derive`。
- **風險**：純註解，零功能影響。

### WS-3 — proc-macro-error2 / validator（⛔ 不建議替換，建議維持 ignore + 追蹤上游）
- **現況**：`validator` 0.20（最新）→ `validator_derive` → `proc-macro-error2`。**無版本可擺脫**（已查 crates.io：0.19+ 全用 proc-macro-error2，0.16–0.18 用更老的 proc-macro-error）。
- **關鍵判斷**：
  - `proc-macro-error2` 是 **build-time proc-macro 依賴**，**不進產出 binary**、**零執行期攻擊面**。advisory 僅 "unmaintained"，**非漏洞**。
  - `validator` 本身**有在維護**，問題只在它的傳遞 build 依賴。
  - 專案對 validator 的使用**極深**：**61 個檔案、439 處** `#[derive(Validate)]` / `#[validate(...)]`，遍及 auth / handlers / services。
- **替換選項與評估**：
  | 選項 | 成本 | 風險 | 結論 |
  |---|---|---|---|
  | A. 升級 validator | — | — | ❌ 無更新版本 |
  | B. 改用其他驗證 crate（如 `garde`、`nutype`） | 高（61 檔重寫 + 各自也可能有 proc-macro 傳遞依賴） | 高（動到 auth 驗證邏輯） | ❌ 不划算 |
  | C. 自寫驗證（`utils/validation.rs`） | 極高（439 處） | 極高 | ❌ 與「外科手術式變更」原則相悖 |
  | D. 維持 ignore + 追蹤 validator 上游 issue | 極低 | 無 | ✅ **建議** |
- **建議**：**D**。為 build-time、零執行期風險的 unmaintained 警告做 61 檔重構，是典型 over-engineering。保留 ignore，於 validator repo 追蹤「migrate off proc-macro-error2」進度，待上游自然解決。

### WS-4 — rsa / jsonwebtoken（🔬 建議做技術驗證 spike，再決定）
- **目標**：移除 `rsa` crate（順帶從根本消除 Marvin 警告，而非靠 ignore 壓）。
- **選項**：
  | 選項 | 做法 | 成本 | 風險 |
  |---|---|---|---|
  | A. jsonwebtoken 換 `aws-lc-rs` 後端 | `jsonwebtoken` 改用預設 features（aws-lc-rs）取代 `rust_crypto`；aws-lc-rs 提供**常數時間** RSA，移除 `rsa` crate **並修掉**時序問題 | 中（需確認 build/CI/Docker 有 cmake + C toolchain；驗證 ES256 + RS256 皆正常） | 中（動到認證核心加密後端） |
  | B. 維持現狀 + 接受風險 | 不動，保留 ignore | 0 | 低（實務不可利用） |
- **🔬 spike 實測結果（2026-06-24，已執行並還原）**：在拋棄分支對 `jsonwebtoken` 改 `features = ["aws_lc_rs", "use_pem"]` 實測——
  | 驗證項 | 結果 |
  |---|---|
  | aws-lc-rs 本機編譯 | ✅ 成功（cmake 3.28 在場，5m03s） |
  | rsa 是否進 binary | ✅ **否**（`cargo tree -e normal -i rsa` 預設/`--all-features` 皆空；無 rsa 編譯產物）；RS256 改走常數時間 aws-lc-rs |
  | rsa 是否離開 Cargo.lock | ❌ **否**（jsonwebtoken 選用依賴，`grep '^name = "rsa"' Cargo.lock` 仍 1 筆） |
  | **能否拿掉 ignore** | ❌ **否**。CI `security-audit` job 跑 lockfile-based `cargo audit`（`ci.yml:54`），實測仍 flag RUSTSEC-2023-0071 |
  | Docker build | ⚠️ **高機率失敗**：`backend/Dockerfile:17` builder 只裝 `pkg-config`+`libssl-dev`，無 cmake/build-essential，aws-lc-sys 編不過 → 需一併改 3 個 Dockerfile |
- **結論（使用者裁定 2026-06-24）**：**採 B，放棄 A**。切換僅得「binary 不含 rsa」之防禦縱深，但**無法消除 advisory/ignore**（rsa 賴在 lock、cargo-audit lockfile 模式必報），又需動 Dockerfile、加重 build 與新增 native 依賴；原 rsa 風險已低（§3 不符 Marvin 前提），CP 值不足。維持 `rust_crypto` + accepted-risk ignore。

### WS-5 — rand（⚪ 無動作，維持 ignore）
- RUSTSEC-2026-0097 為 **unsound 警告**，僅在啟用 rand 的 `log` + `thread_rng` 組合時觸發；本專案未啟用。**升級無解**（0.8.5 與 0.9.2 皆被標記）。**維持 ignore**，註解已正確。

### WS-6 — 更正已交付的掃描報告（✅ 建議，文件修正）
- **動作**：更新 `docs/security/DEPENDENCY_CVE_SCAN_2026-06-24.md` §3.1，把 rsa 的「路徑不會執行」改為 §3 的正確評估（路徑可達 / 不符 Marvin 前提）；並在 PR #788 補一則更正說明。
- **理由**：已 push 的報告含我引入的事實錯誤，誠實原則要求更正。

---

## 5. 建議優先序與「不做什麼」

**建議做（低風險、高 hygiene 價值）**：
1. WS-1 清殭屍 ignore + WS-2 修註解（同一 commit）✅ 已完成（PR #788）
2. WS-6 更正報告 ✅ 已完成（PR #788）
3. ~~WS-4 spike（aws-lc-rs）~~ ✅ 已實測 → **放棄**（見 WS-4 spike 結果：無法消 ignore + Docker build 風險）

**建議不做**：
- ❌ 替換 `validator`（WS-3 選項 B/C）——成本/風險與「消除 build-time 警告」收益嚴重不成比例。

**本質澄清**：使用者原始訴求「換掉有維護問題的套件」，調查後發現**我們直接使用的套件（validator、utoipa、jsonwebtoken）本身都有維護**；維護性 advisory 全來自**傳遞的 build-time 依賴**，無法靠「換直接依賴」乾淨解決（除 rsa 可經換加密後端移除）。因此計畫重心從「替換」轉為「**清理過時策略 + 一個可選的後端遷移 spike**」。

---

## 6. 驗證標準（實作階段適用）

| Workstream | 驗證命令 / 標準 |
|---|---|
| WS-1 / WS-2 | `cargo deny check advisories`（backend）綠燈；`cargo deny check` 全項綠 |
| WS-4 (若採 A) | `cargo build` 綠；`cargo test --lib`（auth 相關）綠；手動驗 Google Calendar token 簽章；`cargo-audit` 不再報 rsa |
| WS-6 | 文件審閱，無功能影響 |

> 依 CLAUDE.md 測試標準：WS-1/2/6 屬 docs/設定，`cargo check`/`cargo deny` 綠即可；WS-4 動到加密後端，需 `cargo test` 相關項全綠（auth 屬 service 層，必要時整合測試）。
