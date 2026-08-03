# App 層 AEAD At-Rest 加密（R66-B2 / R66-C6）

> **目的**：定義 app 層欄位級 at-rest 加密的演算法、信封格式、金鑰管理、輪替與遷移流程。
> 範圍：B2 = TOTP secret（`users.totp_secret_encrypted`）；C6 = 簽章 bridge payload
> （`signature_bridge_sessions.payload`，**尚未實作**，見 §6）。
>
> **決策日期** 2026-06-23（演算法 / 金鑰來源 / zeroize 經使用者裁定）。

## 1. 演算法：XChaCha20-Poly1305

| 決策 | 選擇 | 理由 |
|---|---|---|
| AEAD | **XChaCha20-Poly1305** | 192-bit（24-byte）nonce → 每列用隨機 nonce、永不重複，無 nonce 管理負擔（at-rest 逐列加密最佳）。純 Rust（與既有 sha2/hmac/argon2 同 RustCrypto stack）、constant-time。WireGuard/age/libsodium 採用 |
| 否決 | AES-256-GCM | 96-bit nonce 非 misuse-resistant，隨機 nonce 有加密次數上限 |
| 替代（若合規硬性要求 AES） | AES-256-GCM-SIV | 未採用；如未來稽核要求 NIST/AES 再評估 |

> 合規：21 CFR Part 11 要求「加密」但不指定演算法 → XChaCha 合規上無虞。

## 2. 信封格式

儲存字串：

```text
"<key_version>:<base64_standard(nonce(24) ‖ ciphertext+tag)>"
```

- `key_version`：目前 `1`（`ENCRYPTION_KEY_VERSION`）。支援未來輪替（§4）。
- `nonce`：24 bytes 隨機（每次加密重新產生）。
- `ciphertext+tag`：XChaCha20-Poly1305 輸出（含 16-byte Poly1305 tag）。

**AAD（associated data）綁定上下文**，解密時須帶相同值，防 ciphertext 跨列/跨實體移植：

| 場景 | AAD |
|---|---|
| B2 TOTP secret | `user_id` bytes |
| C6 payload（規劃） | `session_id ‖ user_id` bytes |

實作：`backend/src/utils/crypto.rs`（`EncryptionKey::{encrypt, decrypt}` + `is_encrypted_envelope`）。

## 3. 金鑰管理

| 項目 | 設計 |
|---|---|
| 來源 | `ENCRYPTION_KEY`（或 `ENCRYPTION_KEY_FILE`）→ `Config.encryption_key`，鏡像 `AUDIT_HMAC_KEY` 的 `read_secret` 機制；R56/AWS 後改 Secrets Manager（掛載為 file，零程式改動） |
| 強度 | 32 bytes（base64 standard，44 字元），`openssl rand -base64 32` |
| 隔離 | **與 JWT EC 私鑰、AUDIT_HMAC_KEY 皆不同**（blast-radius）。**否決**「從 JWT 金鑰派生」——換 JWT 金鑰會讓既有密文解不開、2FA 全鎖死 |
| 記憶體 | `EncryptionKey` 內 `Zeroizing<[u8;32]>`（drop 時清零）；`Debug` 遮蔽防金鑰寫進 log；解密輸出為 `Zeroizing<Vec<u8>>` |
| 缺金鑰行為 | **fail-closed**：加密路徑（如 2FA 啟用）回 `Internal` 拒絕；legacy 明文 row **讀取不受影響**（passthrough，見 §5） |

## 4. 金鑰輪替（版本化，鏡像 HMAC chain）

信封帶 `key_version` 前綴（同 `HMAC_VERSIONING.md` 的 `hmac_version` 思路）。**初期單金鑰**（v1）；未來輪替時：

1. `Config` 由「單金鑰」擴為「version → key」對應（current write key + 舊 read keys）。
2. 寫路徑用新版本；讀路徑依信封 `key_version` 選對應金鑰。
3. backfill binary 以新金鑰重加密既有 row（解舊 → 加新）。
4. 全表遷至新版本後，移除舊金鑰。

> 目前 `decrypt` 僅接受 `key_version == ENCRYPTION_KEY_VERSION`；多金鑰支援為 later（YAGNI）。

## 5. 遷移：legacy 明文 → 加密

`totp_secret_encrypted` 欄位名雖含「encrypted」但歷史上存明文 base32。過渡：

| 階段 | 行為 |
|---|---|
| 讀路徑相容 | `decrypt_totp_secret` 以 `is_encrypted_envelope`（看 `:` 前綴）判斷：信封 → 解密；無前綴 → **legacy 明文 passthrough** |
| Backfill | `cargo run --bin backfill_totp_encryption`（idempotent、`--dry-run`）：把所有 legacy 明文 row 加密為信封；已是信封者略過 |
| 收尾（backfill 完成後） | 可移除 `decrypt_totp_secret` 的 legacy passthrough 分支（改 hard error） |

> 區分依據：TOTP base32 不含 `:`，信封格式 `<digits>:<base64>` 必含 `:` → 可靠區分。

## 6. C6（已實作）— 簽章 bridge payload

`signature_bridge_sessions.payload`（含明文密碼 + 手寫 SVG + stroke_data）：

- **migration 104**：`payload` JSONB → **TEXT**（儲存 §2 信封字串；信封非合法 JSON）。既有
  in-flight row 經 `payload::text` 轉為明文 JSON（legacy），consume 端 `is_encrypted_envelope`
  判別後相容讀取。payload 短效（consume 後清 NULL，≤1hr grace 後 GC）→ 無需 backfill binary。
- **submit** 時加密、**consume** 時解密，沿用同一 `utils/crypto.rs`（§1–4）。
- **AAD = `session_id ‖ user_id`**（32 bytes）：綁定 payload 到該 session 與 owner；submit 由
  `SELECT ... FOR UPDATE` 取得 `user_id`，consume 由 owner 參數取得，兩端一致。
- 缺金鑰 → submit fail-closed 拒絕（不存明文）。

## 7. 維護記錄

| Date | Change | By |
|---|---|---|
| 2026-06-23 | C6 實作 — 簽章 bridge payload AEAD 加密（migration 104 JSONB→TEXT；AAD=session‖user；共用 utils/crypto.rs） | Claude |
| 2026-06-23 | Initial — B2 TOTP secret AEAD 加密（XChaCha20-Poly1305 + 專用 ENCRYPTION_KEY + zeroize）；C6 規劃 | Claude |
