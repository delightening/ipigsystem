# R30-9 Design: Electronic Signatures Audit Chain + Invalidate Flow

> **Status**: APPROVED (2026-05-02) — 待實作
> **Owner**: Jason
> **PR 切分**: PR-C chain hash v3 → PR-D invalidate flow
> **依賴**: HMAC chain 既有實作（PR #213 / R26 / R30-7）

---

## 1. 動機

`electronic_signatures` 表目前**完全沒進 HMAC audit chain**：
- 新增簽章（`SignatureService::sign_record_tx`）只寫 row，HMAC chain 不知道有這筆
- 撤銷簽章流程缺失，已用過的簽章無法 invalidate（compromise 時無 emergency 機制）

實際後果：
- 攻擊者直接 `INSERT INTO electronic_signatures` 偽造簽章，HMAC chain verifier 不會察覺
- signer 離職 / key compromise 時，無法在系統內留稽核紀錄標記「此簽章已不可信」

對應 21 CFR §11.10(e)：
> Use of secure, computer-generated, time-stamped audit trails to independently record... the actions of operators who create, modify, or delete electronic records.

簽章本身就是 electronic record，必須有獨立 audit trail。

---

## 2. 兩個 sub-task

| ID | 範圍 |
|---|---|
| **R30-9a** | 簽章 INSERT/INVALIDATE 同 tx 寫 audit chain row + chain hash 計算含 sig fingerprint |
| **R30-9b** | electronic_signatures 加 invalidate 流程（schema + service + handler + UI） |

兩者獨立 PR，依序實作（9a 先，9b 依賴 9a 的 audit log 路徑）。

---

## 3. R30-9a — Audit Chain v3（含 sig fingerprint）

### 3.1 Hash schema 改動

⚠️ **Gemini PR #304 review (high) 修正**：原本 design doc 寫「v2 input 含 entity」是**錯的**。實際 `HmacInput` (`backend/src/services/audit.rs:78-86`) 只有 7 欄，**不含 entity_type / entity_id**。這本身就是 v2 的安全 gap — 攻擊者若有 DB 寫權限可改 entity_id 不破壞 chain hash。

**現行 v2 chain hash input**（`canonical_bytes` length-prefix）：
```
prev_hash | event_category | event_type | actor_user_id | before_data | after_data | impersonated_by | [changed_fields...]
```

**v3 chain hash input**（修正 v2 的 entity gap + 加 extra_input 給 SIGNATURE_*）：
```
prev_hash | event_category | event_type | actor_user_id | before_data | after_data | impersonated_by | [changed_fields...] | entity_type | entity_id | extra_input
```

新增 3 個 hash input 欄位：
- `entity_type` / `entity_id`：**v3 一律含**（修補 v2 entity gap，提升所有事件的完整性）
- `extra_input`：v3 only，給特定事件加額外綁定

`extra_input` 用法（type `TEXT NULLABLE`）：
- 一般 v3 event：空字串，但 hash 公式仍會拼進去（length-prefix 0）
- SIGNATURE_CREATE：`extra_input = sig_id || ':' || sig_content_hash`
- SIGNATURE_INVALIDATE：`extra_input = sig_id || ':' || invalidation_reason_hash`

### 3.2 Forward-compat 設計（關鍵）

⚠️ **不可逆 migration**。一旦 v3 row 寫入，verifier 必須同時支援 v1 / v2 / v3 三種公式（v1 legacy 已存在於 `legacy_concat_message`）。

```rust
// services/audit.rs HmacInput 加 v3 欄位
pub(crate) struct HmacInput<'a> {
    // 既有 v2 欄位
    pub event_category: &'a str,
    pub event_type: &'a str,
    pub actor_user_id: Uuid,
    pub before_data: &'a Option<serde_json::Value>,
    pub after_data: &'a Option<serde_json::Value>,
    pub impersonated_by: Option<Uuid>,
    pub changed_fields: &'a [String],
    // R30-9a v3 新增（v2 row 給 None / "")
    pub entity_type: Option<&'a str>,
    pub entity_id: Option<&'a str>,
    pub extra_input: Option<&'a str>,
}

impl HmacInput<'_> {
    /// v3 編碼：在 v2 後接續 length-prefix entity_type / entity_id / extra_input
    pub fn canonical_bytes_v3(&self, prev_hash: Option<&str>) -> Vec<u8> {
        let mut buf = self.canonical_bytes(prev_hash);  // 重用 v2 編碼
        write_field(&mut buf, self.entity_type.unwrap_or("").as_bytes());
        write_field(&mut buf, self.entity_id.unwrap_or("").as_bytes());
        write_field(&mut buf, self.extra_input.unwrap_or("").as_bytes());
        buf
    }
}

// compute_hmac_for_fields_versioned 加 v3 分支
match version {
    HMAC_VERSION_LEGACY => mac.update(input.legacy_concat_message(prev_hash).as_bytes()),
    HMAC_VERSION_CANONICAL => mac.update(&input.canonical_bytes(prev_hash)),
    HMAC_VERSION_V3 => mac.update(&input.canonical_bytes_v3(prev_hash)),  // 新
}
```

`hash_version` 欄位（已存在於 `user_activity_logs`，目前值為 1 / 2）：
```sql
-- 既有：ALTER TABLE user_activity_logs ADD COLUMN hmac_version SMALLINT NOT NULL DEFAULT 2;
-- 本 PR 新加常數
const HMAC_VERSION_V3: i16 = 3;
```

新 row 預設仍為 v2；只有特定事件強制寫 v3：
```rust
// services/audit.rs::log_activity_tx
let version = match entry.event_type {
    // R30-9a：簽章事件強制 v3 — entity 進 hash + extra_input 綁 sig fingerprint
    "SIGNATURE_CREATE" | "SIGNATURE_INVALIDATE" => HMAC_VERSION_V3,
    _ => HMAC_VERSION_CANONICAL,  // v2 保留現狀
};
```

**為什麼不全 row 升 v3？** 把所有 row 都升 v3 = 所有舊 v2 row 的 hash 公式都變了 = chain 必須全表 rewrite。我們選漸進升：v3 只給 SIGNATURE_* 事件用，其他事件未來可分批升（每升一個 event_type 都是不可逆 migration）。

### 3.3 Migration 050

```sql
-- migrations/050_audit_chain_v3_with_sig.sql
ALTER TABLE user_activity_logs
    ADD COLUMN IF NOT EXISTS hash_version SMALLINT NOT NULL DEFAULT 2,
    ADD COLUMN IF NOT EXISTS extra_input TEXT NULL;

-- 既有 row 全部設 v2（與目前實作一致）
UPDATE user_activity_logs SET hash_version = 2 WHERE hash_version IS NULL;

COMMENT ON COLUMN user_activity_logs.hash_version IS
'R30-9a: HMAC chain hash 公式版本。v2 = 不含 extra_input（既有），v3 = 含 extra_input（SIGNATURE_* 等）';
COMMENT ON COLUMN user_activity_logs.extra_input IS
'R30-9a: 額外進 chain hash 的 input；v3 only。SIGNATURE_CREATE: sig_id:content_hash';
```

對應 down `migrations/down/050_audit_chain_v3_with_sig.sql` 標 **IRREVERSIBLE**：
```sql
-- WARNING: IRREVERSIBLE — once v3 rows exist, dropping these columns breaks
-- chain verification for v3 rows. To roll back, must:
-- 1. Stop writes (downtime)
-- 2. Re-compute and rewrite all v3 rows as v2 (lossy: drops sig fingerprint binding)
-- 3. Then drop columns
-- This is only safe if NO v3 rows exist yet (i.e. immediate rollback after migration up).
SELECT COUNT(*) FROM user_activity_logs WHERE hash_version = 3;
-- ^^^ if this returns > 0, do NOT proceed.

-- ALTER TABLE user_activity_logs DROP COLUMN hash_version;
-- ALTER TABLE user_activity_logs DROP COLUMN extra_input;
```

### 3.4 Verifier 改動

`services/audit_chain_verify.rs`：
```rust
fn verify_chain_rows(rows: &[ChainRow]) -> Result<()> {
    let mut prev = "GENESIS".to_string();
    for row in rows {
        let expected = compute_chain_hash(row, &prev);  // 內部依 hash_version 分流
        if row.hash != expected {
            return Err(AppError::ChainBroken(...));
        }
        prev = row.hash.clone();
    }
    Ok(())
}
```

測試覆蓋必須包含：
- 純 v2 chain（既有 row 全部，~ 2000 筆 prod）
- 純 v3 chain（mock SIGNATURE_CREATE）
- 混合 chain（v2 → v3 → v2 → v3 順序）— 確認 verifier 不卡

### 3.5 SIGNATURE_CREATE 寫入點

`services/signature.rs::sign_record_tx`：
```rust
pub async fn sign_record_tx(...) -> Result<Uuid> {
    let sig_id = /* INSERT INTO electronic_signatures ... */;

    // R30-9a：簽章建立寫進 HMAC chain
    let extra = format!("{}:{}", sig_id, content_hash);
    AuditService::log_activity_tx(
        tx,
        actor,
        ActivityLogEntry {
            event_category: "SECURITY",
            event_type: "SIGNATURE_CREATE",
            entity: Some(AuditEntity::new("electronic_signature", sig_id, &display)),
            data_diff: Some(DataDiff::create_only(&new_sig)),  // sig 完整 snapshot
            request_context: None,
        },
        Some(extra),  // 新參數：v3 extra_input
    ).await?;

    Ok(sig_id)
}
```

`AuditService::log_activity_tx` API 加新 optional 參數 `extra_input: Option<String>`，內部依此決定 hash_version。

### 3.6 統一雜湊輔助函式（規格鎖定，避免 verifier 失敗）

⚠️ **content_hash 與 reason_hash 必須使用同一個雜湊輔助函式**。否則 verifier 在驗 chain 時對 sig fingerprint 會算出不同值。

統一規格：
```rust
// services/signature/mod.rs (既有)
pub fn compute_hash(input: &str) -> String {
    // SHA256(input.as_bytes()) → lowercase hex (64 chars)
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    format!("{:x}", hasher.finalize())  // lowercase, no separators
}
```

**強制規定**（實作時不可違反）：
- 兩處都呼叫 `SignatureService::compute_hash(...)`，**禁止**手寫 SHA256 / 用 `sha256_hex` / 自訂 helper
- Input 編碼一律 UTF-8，**不**做 NFC/NFKC normalization、**不**做 trim、**不**做 case fold
- 輸出一律 lowercase hex（`{:x}`），**不**接受 uppercase / base64 / 截斷

對應寫法：
```rust
// SIGNATURE_CREATE
let extra = format!("{}:{}", sig_id, SignatureService::compute_hash(&content));

// SIGNATURE_INVALIDATE
let extra = format!("{}:{}", sig_id, SignatureService::compute_hash(reason));
```

`reason` 與 `content` 都直接傳原始字串，由 `compute_hash` 統一處理。

---

## 4. R30-9b — Invalidate Flow（只記 audit，不動 record）

### 4.1 決策

依使用者裁定：
- ✅ invalidate 純為「signer key compromise / signer 離職後撤回」這類稀有/緊急事件留稽核痕跡
- ✅ **不**自動 revert 已使用該簽章的 amendment / protocol record
- ❌ 已 APPROVED 的 amendment 如果有問題，走「再開新 amendment 改」流程，不在系統內 revoke

### 4.2 Schema 改動

```sql
-- migrations/051_signature_invalidate.sql
ALTER TABLE electronic_signatures
    ADD COLUMN invalidated_at TIMESTAMPTZ NULL,
    ADD COLUMN invalidated_by UUID NULL REFERENCES users(id),
    ADD COLUMN invalidation_reason TEXT NULL;

-- query 索引：找「使用已 invalidate 簽章的 record」用
CREATE INDEX idx_electronic_signatures_invalidated
    ON electronic_signatures (invalidated_at)
    WHERE invalidated_at IS NOT NULL;

COMMENT ON COLUMN electronic_signatures.invalidated_at IS
'R30-9b: 簽章被 admin 撤銷的時點。NULL = 仍有效。撤銷後此 sig 不再算「已簽核」，但已使用此 sig 的 record 不自動 revert（人工流程處理）';
```

對應 down 安全：DROP COLUMN（NULL 欄、無 data loss 風險，但 invalidate 紀錄會丟失）。

### 4.3 Service

```rust
// services/signature.rs

impl SignatureService {
    /// R30-9b：撤銷簽章。寫 audit + UPDATE invalidated_*，不動 record（依設計）。
    pub async fn invalidate(
        pool: &PgPool,
        actor: &ActorContext,
        sig_id: Uuid,
        reason: &str,
    ) -> Result<()> {
        let user = actor.require_user()?;

        if reason.trim().is_empty() {
            return Err(AppError::BadRequest("invalidation_reason 必填".into()));
        }
        if reason.len() > 1000 {
            return Err(AppError::BadRequest("invalidation_reason 不可超過 1000 字".into()));
        }

        let mut tx = pool.begin().await?;

        // SELECT FOR UPDATE 防併發
        let before = sqlx::query_as::<_, ElectronicSignature>(
            "SELECT * FROM electronic_signatures WHERE id = $1 FOR UPDATE",
        )
        .bind(sig_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("簽章不存在".into()))?;

        if before.invalidated_at.is_some() {
            return Err(AppError::Conflict("簽章已被撤銷，不可重複".into()));
        }

        let after = sqlx::query_as::<_, ElectronicSignature>(
            r#"
            UPDATE electronic_signatures
            SET invalidated_at = NOW(),
                invalidated_by = $2,
                invalidation_reason = $3
            WHERE id = $1 AND invalidated_at IS NULL
            RETURNING *
            "#,
        )
        .bind(sig_id)
        .bind(user.id)
        .bind(reason)
        .fetch_one(&mut *tx)
        .await?;

        // R30-9a：寫 SIGNATURE_INVALIDATE chain row（v3 含 sig fingerprint）
        // R30-9 §3.6：用 SignatureService::compute_hash 與 SIGNATURE_CREATE 對齊
        let extra = format!("{}:{}", sig_id, SignatureService::compute_hash(reason));
        AuditService::log_activity_tx(
            &mut tx,
            actor,
            ActivityLogEntry {
                event_category: "SECURITY",
                event_type: "SIGNATURE_INVALIDATE",
                entity: Some(AuditEntity::new("electronic_signature", sig_id, ...)),
                data_diff: Some(DataDiff::compute(Some(&before), Some(&after))),
                request_context: None,
            },
            Some(extra),
        ).await?;

        tx.commit().await?;
        Ok(())
    }
}
```

### 4.4 Handler + Permission

新 perm `signature.invalidate`（admin only，種子 migration 一同加入）。

```rust
// handlers/signature.rs

pub async fn invalidate_signature(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Path(sig_id): Path<Uuid>,
    Json(req): Json<InvalidateSignatureRequest>,
) -> Result<Json<serde_json::Value>> {
    require_permission!(current_user, "signature.invalidate");
    req.validate()?;

    let actor = ActorContext::User(current_user.clone());
    SignatureService::invalidate(&state.db, &actor, sig_id, &req.reason).await?;

    Ok(Json(serde_json::json!({ "status": "invalidated" })))
}
```

Route: `POST /signatures/:id/invalidate { reason: String }`

### 4.5 UI

僅 admin 後台可見：
- `pages/admin/AuditLogsPage.tsx` 顯示簽章 row 時：
  - 加 badge：`已撤銷`（若 `invalidated_at != null`）
  - 加按鈕：`撤銷簽章`（若 `invalidated_at == null` 且使用者有 perm）
- 點按鈕 → 開 dialog 要求填 `reason`（textarea，required）→ 確認後 call invalidate API
- 撤銷後 toast「簽章已撤銷，相關記錄不自動變更，請人工處理」

無新增獨立頁面，融入既有 audit log page 即可（rare action）。

### 4.6 通知（optional，不阻擋本 PR）

invalidate 是 security 事件，理論上應通知：
- signer 本人（你的簽章被撤銷了）
- IACUC chair（系統有簽章被撤銷）

依設計可走 R30-3 outbox：
```rust
// 在 invalidate tx 內 enqueue
OutboxService::enqueue_tx(
    &mut tx, actor, "email",
    json!({ "to": signer_email, "template": "signature_invalidated", ... }),
    ("electronic_signature", sig_id),
).await?;
```

但 R30-3 outbox 必須先 merge；若先做 R30-9b 而 outbox 還沒好，可暫時用 best-effort `tracing::warn!` post-tx，後續切換。

---

## 5. PR 切分

| PR | 內容 | 預估 | 風險 |
|---|---|---|---|
| **PR-C R30-9a** | migration 050 + audit_chain_verify v2/v3 雙公式 + sign_record_tx 寫 SIGNATURE_CREATE | ~250 行 + migration | **高 — chain 不可逆，staging 必試** |
| **PR-D R30-9b** | migration 051 + invalidate service/handler + perm seed + UI button + dialog | ~400 行 + migration + UI | 中 |

順序：PR-C → PR-D（D 依賴 C 的 SIGNATURE_INVALIDATE 寫 chain 路徑）。

---

## 6. Migration / Rollout 計畫

### PR-C 步驟
1. migration 050 + down（含 IRREVERSIBLE 警告）
2. `services/audit.rs` API 加 `extra_input` 參數
3. `services/audit_chain_verify.rs` 加 v3 分支
4. `services/signature.rs::sign_record_tx` 加 SIGNATURE_CREATE chain 寫入
5. Tests:
   - v2 only chain（既有測試應全綠）
   - v3 only chain（新建）
   - v2/v3 混合 chain（新建）
   - 改 SIGNATURE_CREATE row 的 sig fingerprint → verifier 報錯（新建）
6. **Staging 必跑**：
   - 先在 staging 跑 migration 050
   - 觸發一個簽章流程 → 確認新 row 是 v3 + extra_input 寫入
   - 跑 verifier 對全 chain → 確認 v2/v3 混合無誤
   - 觀察 1 週無 verifier 異常後推 prod

### PR-D 步驟
1. migration 051 + down
2. perm `signature.invalidate` seed
3. service / handler / route
4. UI dialog + button in AuditLogsPage
5. Tests:
   - invalidate 成功 → SIGNATURE_INVALIDATE row 寫入
   - 重複 invalidate → 409
   - 無 perm → 403
6. Staging 1 週確認 admin 流程順

---

## 7. 風險 / 開放問題

| 風險 | 緩解 |
|---|---|
| migration 050 寫入 v3 row 後 down 失敗 | down 前 assert v3 row count = 0；prod migration 視同不可逆 |
| verifier 改錯破壞既有 v2 chain 驗證 | 完整單元測試覆蓋（純 v2 / 純 v3 / 混合）+ staging dry-run |
| invalidate 後 record 仍顯示「已簽核」UI 誤導 | UI 可在 record detail 旁顯示「此簽章已撤銷」警告 — 留 R30-9b 後續 follow-up，本 PR 不阻擋 |
| 簽章 fingerprint 含 sig_id 會在不同 sig 被 reuse 嗎 | sig_id 是 UUID，不會 reuse；fingerprint 唯一 |
| HMAC key rotation 衝突 | 沿用既有 `HMAC_VERSIONING.md` v2 規範，本 PR 不改 key |

---

## 8. 不在 scope

- 不做 record 自動 revert（依使用者裁定）
- 不做簽章 rotation（key 換新）
- 不做跨機構簽章互信（單一機構）
- 不做 invalidate 的審核流程（直接 admin 即時撤銷）
- chain hash v3 之後若要再進化（v4 含更多 entity 摘要等），另案處理
