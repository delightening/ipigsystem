# iPig 系統 — 密碼政策 (Password Policy)

> **版本**：1.0
> **生效日期**：2026-05-11
> **核可依據**：NIST SP 800-63B (2017, rev. 4 草案)、業界共識（GitHub / AWS / 1Password / Microsoft）
> **本文目的**：為合規稽核（NICS 附表十 / NIST 800-63B）與外部審查者明確說明本系統之密碼政策、所採用之偏離以及對應之補償控制 (compensating controls)。

---

## 1. 現行政策摘要

| 項目 | 設定 | 程式碼位置 |
|---|---|---|
| 雜湊演算法 | **Argon2id**（預設參數，記憶體強化） | `backend/Cargo.toml` argon2 0.5；`services/auth/password.rs::hash_password` |
| 最短長度 | **10 字元** | `constants.rs::PASSWORD_MIN_LENGTH = 10`；`services/auth/password.rs::validate_password_strength` |
| 最長長度 | 128 字元 | `models/user.rs` validator |
| 字元組合限制 | **強制大寫 + 小寫 + 數字**；特殊字元不強制 | `services/auth/password.rs::validate_password_strength`（SEC-10）|
| 弱密碼黑名單 | 30 組常見弱密碼（password / 123456 / qwerty 等）拒絕 | `password.rs::COMMON_WEAK_PASSWORDS` |
| 定期更換 | **不強制**（NIST 建議廢除）| CLAUDE.md「⛔ 禁止事項」#1 |
| 歷史紀錄 / 重用禁止 | **不檢查** | CLAUDE.md「⛔ 禁止事項」#2 |
| 失敗鎖定 | **5 次 / 30 分鐘** | `constants.rs::ACCOUNT_LOCKOUT_MAX_ATTEMPTS = 5`、`ACCOUNT_LOCKOUT_DURATION_MINUTES = 30` |
| 雙因子認證 | **TOTP 強制可選 + 強烈建議**（admin 強制） | P5-3 完成；`services/auth/totp.rs` |
| 預設臨時密碼 | 首次登入強制更換 | `models/user.rs::must_change_password` |
| 鑑別資訊回顯 | 禁止（前端 `type=password`，後端 `#[serde(skip_serializing)]`） | `models/user.rs:44-56` |

---

## 2. 與 NICS 附表十「身分驗證管理」之對照

附表十中/高級「定期更換」、「密碼歷史」字面要求，本系統依 **NIST SP 800-63B** 與業界共識**主動偏離**，採取下列補償控制：

| 附表十條文 | 本系統做法 | 補償控制 |
|---|---|---|
| 「密碼應定期更換」 | **不強制** | (a) 5 次失敗鎖定；(b) TOTP 2FA；(c) HMAC chain audit；(d) Argon2id 高計算成本 |
| 「禁止重複使用前 N 次密碼」 | **不檢查** | 同上；NIST 認定強制歷史造成可預測 pattern (e.g. `Pwd1` → `Pwd2`) |
| 「至少含大寫/小寫/數字/特殊字元」 | **強制大寫 + 小寫 + 數字**（特殊字元不強制）+ min 10 碼 | 採部分組合 + 長度 + 弱密碼黑名單 + Argon2id + 2FA + 鎖定的綜合策略；未完全採用 NIST「廢除組合」是與附表十中/高級妥協的中間路線（NIST 建議廢除，但弱密碼黑名單仍保留必要性）|

### 偏離依據

**NIST SP 800-63B §5.1.1.2 Memorized Secret Verifiers**：

> "Verifiers SHOULD NOT impose other composition rules (e.g., requiring mixtures of different character types or prohibiting consecutively repeated characters) for memorized secrets."
>
> "Verifiers SHOULD NOT require memorized secrets to be changed arbitrarily (e.g., periodically). However, verifiers SHALL force a change if there is evidence of compromise of the authenticator."

**業界對齊**：GitHub、AWS Console、1Password、Microsoft Azure AD、Google Workspace 均已停止強制定期更換（2019 後逐家移除）。

---

## 3. 帳號異常事件處理（分級回應）

依事件性質採取**分級回應**——對「明確 compromise 證據」事件必須強制更換密碼（NIST §5.1.1.2 「force change on evidence of compromise」），對「疑似攻擊或來源異常」事件採鎖定 / 封鎖以阻斷攻擊路徑：

| 事件 | 偵測點 | 動作 | 是否強制改密碼 |
|---|---|---|:-:|
| HIBP 比對為已洩漏密碼 | （未實作；列為 future enhancement） | `must_change_password=true` + 強制重登 | ✅ |
| 同帳號異地 IP 短時間多次成功 | R22 安全告警 | 鎖定帳號 + `must_change_password=true` + email 通知 | ✅ |
| 管理員確認帳號遭盜用 | 後台 Admin UI | `must_change_password=true` | ✅ |
| Brute force（多次失敗，**未成功登入**）| `services/auth/login.rs` 5 次失敗 → 30 分鐘鎖定 | 帳號鎖定，自動解鎖 | ❌（密碼未洩漏，僅暫鎖）|
| IDOR probe / 攻擊性流量 | `services/ip_blocklist.rs::auto_block` | 自動封鎖來源 IP | ❌（被攻擊端未必對應帳號 compromise）|

**註**：CLAUDE.md「⛔ 禁止事項」#1 禁止**例行性 / 時間驅動的**密碼更換（NIST 廢除項）；上表的強制改密碼為**事件驅動 / compromise evidence-driven**，符合 NIST 規範。

---

## 4. 合規 audit 對照表

| 控制要求（NICS 普級 → 高級） | 本政策 PASS / NOTES |
|---|---|
| 唯一帳號 | ✅ Email unique constraint |
| 密碼最短長度 | ✅ ≥ 10（高於附表十普級 8 碼基準）|
| 密碼複雜度 | ✅ 強制大寫 + 小寫 + 數字混合 + 弱密碼黑名單（30 組）|
| 密碼雜湊不可逆 | ✅ Argon2id |
| 鑑別資訊不明顯回顯 | ✅ password 欄不可序列化 |
| 失敗鎖定 | ✅ 5 / 30min |
| 多因子認證 | ✅ TOTP（admin 強制、一般使用者可選）|
| 預設密碼首次登入更換 | ✅ `must_change_password` 旗標 |
| 定期更換 | 🟡 **不採用**；依 NIST 建議；補償控制：2FA + 鎖定 + audit |
| 密碼歷史紀錄 | 🟡 **不採用**；依 NIST 建議；補償控制同上 |

---

## 5. 異動記錄

| 日期 | 版本 | 異動 |
|---|---|---|
| 2026-05-11 | 1.0 | 初版（R41-4 NICS 合規補強）|

---

## 6. 參考

- NIST SP 800-63B Digital Identity Guidelines (2017 / draft rev. 4)：https://pages.nist.gov/800-63-3/sp800-63b.html
- CLAUDE.md「⛔ 禁止事項」 §1, §2
- 行政院《資通安全責任等級分級辦法》附表十「身分驗證管理」
- `docs/security/NICS_COMPLIANCE_AUDIT_2026-05.md` §4 識別與鑑別
