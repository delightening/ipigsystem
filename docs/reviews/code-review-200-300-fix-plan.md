# 修復計畫：PR #200-300 code review findings

> 建立日期：2026-06-07 ｜ 來源：`docs/reviews/code-review-200-300-report.md` ｜ 視角：current main（HEAD 76875312）
> 原則：依 CLAUDE.md「思考紀律（goal-driven + surgical）」「執行紀律（測試驗證標準 / 停機規則 / commit 粒度）」拆 PR。
> **狀態：plan-only，未動碼。每個 PR 內含 reproducing/acceptance test 先紅後綠的驗收標準。**

---

## 修復順序總覽

| 順序 | PR | 涵蓋 finding | 風險 | 測試層級 | 需使用者裁定 |
|---|---|---|---|---|---|
| 1 | **euthanasia 仲裁 fail-closed** | Critical-1 (#262) | 低（純收斂判定） | `--all-targets` | 否 |
| 2 | **GLP 簽章完整性** | High-1 (#205/#213) · High-2 (#241/#249) · Low-1 (#273) | 中（簽章 + migration） | `--all-targets` | 否 |
| 3 | **2FA session 完整性** | High-3 (#207) | 中（auth 流程） | `--all-targets` | 否 |
| 4 | **production fail-fast 生效** | High-4 (#283) · Low-6 (#283) | 高（compose / CI / 啟動語意） | `cargo check` + 手動啟動驗證 | **是（A/B 方案）** |
| 5 | **存取/併發守衛** | High-5 (#237相關) · Medium-2 (#290相關) | 中（IDOR + 併發） | `--all-targets` | 否 |
| 6 | **health liveness/readiness 分級** | Medium-3 (#238) | 高（容器健檢 / depends_on） | `cargo check` + 手動健檢 | **是（方案選擇）** |
| 7 | **小修批次（可選）** | Low-2 (#265) · Low-5 (#239) | 低 | `cargo check` | 否 |
| — | **延後（不在本批）** | Medium-1 (#298) · Low-3 (#210/#218) · Low-4 (#210) | — | — | — |

> 停機規則：每個 PR 做完適用測試綠燈 + commit 後**停**，不自動 push / 不自動開下一個 / 不自動 merge（等明確同意）。

---

## PR 1 — euthanasia 仲裁 `chair_decide` fail-closed（Critical-1 / #262）

**根因**：`ChairDecisionRequest.decision: String` 無 enum/validator，`chair_decide` 用 `if decision == "approve_appeal" { cancelled } else { approved }`，任何非精確字串 fall-through 到「核准執行安樂死」。

**修法（fail-closed，三分支顯式）**：
1. `backend/src/services/euthanasia.rs:34` 旁新增 `const DECISION_REJECT_APPEAL: &str = "reject_appeal";`。
2. `euthanasia.rs:553` 把二分支改三分支：
   ```
   let new_status = match req.decision.as_str() {
       DECISION_APPROVE_APPEAL => "cancelled",
       DECISION_REJECT_APPEAL  => "approved",
       _ => return Err(AppError::BadRequest("無效的仲裁決定".into())),
   };
   ```
   並把拒絕放在 UPDATE appeal/order **之前**（避免已寫 appeal 才發現 decision 非法）。
3. （建議）`models/euthanasia.rs:144` `decision` 加 `#[validate(custom = "validate_chair_decision")]` 或文件註解對齊；以 service match 為權威守門，validator 為前置友善錯誤。

**Surgical 邊界**：只動 euthanasia 仲裁判定與常數；不碰 pi_approve/execute（已驗證正確）。

**驗收（先紅後綠）**：
- 新增 integration test：CHAIR 對 appeal 送 `decision="garbage"`（及空字串）→ 期望 HTTP 400 / `AppError::BadRequest`，且 `euthanasia_orders.status` 維持仲裁中（**未**轉 `approved`）、appeal 未被寫入。
- 既有 `approve_appeal`/`reject_appeal` happy-path test 仍綠。
- `cargo test --all-targets` 全綠（動到 handler 流程）。

---

## PR 2 — GLP 簽章完整性（High-1 + High-2 + Low-1）

三項皆屬「簽章不可偽造 / 已簽紀錄不可竄改」同一主題，合併一個 PR、分 commit。

### Commit 2a — amendment 決定簽改 HMAC v2（High-1 / #205/#213）
**根因**：`amendment/workflow.rs:84` 用 plain `compute_hash`（v1），INSERT（90-108）無 `hmac_version` → 落 default=1。
**修法**：
- 把 `SignatureService::build_signature_data_v2`（`signature/mod.rs:211`）開放給 amendment 模組呼叫（改 `pub(crate)`，或新增薄包裝 `SignatureService::build_internal_signature_data(signer_id, content_hash, ts) -> Result<(String, i16)>`，內部 `hash_input="internal"`）。安全性來自 `AUDIT_HMAC_KEY`、非 hash_input 機密性，故 internal 簽用固定 `"internal"` marker 即可。
- `workflow.rs:84` 改為 `let (signature_data, hmac_version) = SignatureService::build_internal_signature_data(signer_id, &content_hash, timestamp.timestamp())?;`
- INSERT（90-108）欄位列補 `hmac_version`，VALUES 補對應 bind。
**驗收**：新增 test — amendment APPROVE/REJECT 後查 `electronic_signatures.hmac_version = 2`，且 `signature_data` 等於以 `AUDIT_HMAC_KEY` 重算的 HMAC（沿用既有 v2 test 模式）。

### Commit 2b — 已簽收 maintenance 紀錄鎖（High-2 / #241/#249）
**根因**：`update_maintenance_record_tx`（`equipment.rs:788`）/ `delete_maintenance_record_tx`（`equipment.rs:877`）在 `SELECT ... FOR UPDATE` 後無 `reviewer_signature_id` 守衛，但 handler 回 `is_locked: is_signed`（`handlers/signature/maintenance.rs:66`）。
**修法**：在兩個 tx fn 取得 `existing` 後（FOR UPDATE 之後、UPDATE/DELETE 之前）插入：
```
if existing.reviewer_signature_id.is_some() {
    return Err(AppError::Conflict("已簽收的維修保養紀錄不可修改/刪除".into()));
}
```
對齊 #204 observation/surgery/blood_test/care 的 `ensure_not_locked` pattern。
**驗收**：新增 test — 對已 `sign_maintenance_reviewer` 的紀錄呼叫 update / delete → 期望 `AppError::Conflict`；未簽紀錄仍可正常 update/delete。

### Commit 2c — immutability trigger 鎖 `is_valid` 方向（Low-1 / #273）
**根因**：`migrations/041_audit_signature_immutability_triggers.sql:70` 的 trigger 允許 `is_valid` 雙向變動，直接 SQL 可把作廢簽章 `false→true` 復活。
**修法**：**新增** migration（不改既有 041，沿 down.sql template），在 `check_electronic_signatures_immutable` 函式內加：
```
IF NEW.is_valid AND NOT OLD.is_valid THEN
    RAISE EXCEPTION '不可將已作廢電子簽章重新生效 (§11.70)';
END IF;
```
**驗收**：`cargo check` 綠；dev DB 啟動自動套用 migration；手動 `UPDATE electronic_signatures SET is_valid=true WHERE is_valid=false` 應被 trigger 擋下。

**整 PR 測試**：`cargo test --all-targets` 全綠（動到 service 層 mutation + handler）。

---

## PR 3 — 2FA session 完整性（High-3 / #207）

**根因**：`handlers/two_factor.rs:167-190` 先回 token 再於 `tokio::spawn` 內 `create_session`/`end_excess_sessions`，與密碼路徑（`handlers/auth/login.rs:116-126`）相反，SEC-28 併發上限對 admin 退化 best-effort、且 create_session 失敗會留孤兒 token。
**修法**：把 `create_session` + `end_excess_sessions` 移出 spawn、放到 `complete_2fa_login` 回傳 token **之前**同步執行；任一失敗即 `return Err(...)`（不發 token）。`log_success`（純遙測）維持 fire-and-forget。對照 login.rs 的既有寫法逐行對齊（含失敗中止語意）。
**Surgical 邊界**：只動 `verify_2fa_login` handler 的順序；不改 token 簽發邏輯本身。
**驗收（先紅後綠）**：
- Integration test：2FA 使用者連續登入超過 `max_sessions_per_user` → 期望最舊 session 被 `end_excess_sessions` 踢除、`user_sessions` 列數 == 上限（現況會超出）。
- create_session 失敗注入（或以既有 mock 模式）→ 不回傳可用 token。
- 既有 2FA happy-path 仍綠。`cargo test --all-targets` 全綠。

---

## PR 4 — production 啟動 fail-fast 真正生效（High-4 + Low-6 / #283）

**根因**：`is_production()`（`startup/mod.rs:36`）靠 `APP_ENV`/`RUST_ENV`，全 compose/.env/Dockerfile 從未設定 → `main.rs:94-122` 兩處 fail-fast 永不觸發。

> ⚠️ **此 PR 需使用者裁定（高風險：改 compose / 啟動語意 / 可能改 CI）**。兩方案：
>
> **方案 A（顯式、最小）**：`docker-compose.prod.yml` 的 api service 加 `environment: APP_ENV=production`。
> - 優點：改動小、語意明確、不影響 dev（dev compose 不設即維持寬鬆）。
> - 缺點：依賴「未來不會忘了設」——若新 compose 漏設又回到 inert。
>
> **方案 B（fail-safe 預設）**：反轉 `is_production()` 語意——只有明確 `APP_ENV in {development, test, ci}` 才視為非 prod，**未標記一律當 production**。
> - 優點：prod-on-laptop 單一環境下「漏設=安全（fail-fast）」，符合現實。
> - 缺點：需確認所有 dev/CI 路徑都有設 `APP_ENV`（否則 dev/CI 啟動會被 fail-fast 擋下）；改動語意風險較大、需掃 CI workflow 與本地啟動腳本。
>
> **建議**：先做 **A**（立即讓 prod 生效、零副作用），把 **B** 列為後續 hardening（需配套確認 dev/CI 皆標記）。等使用者選定再實作。

**Low-6 併入**：`startup/config_check.rs:14` 的警告摘要補上 `X-Internal-Token`（print-pdf）/ SMTP 等 prod-required 項，或於函式 doc 註明「僅涵蓋軟性警告項，硬性 secret 由 `Config::from_env` 把關」。（JWT/csrf 已硬性 fail，不需移動。）

**驗收**：
- 方案 A：`cargo check` 綠；手動以 `APP_ENV=production` + 故意缺 `AUDIT_HMAC_KEY` 啟動 → 期望 `exit(1)`（現況會繼續啟動）。
- 方案 B：另需 `cargo test` 覆蓋 `is_production()` 各 env 組合 + 確認 CI workflow / 本地啟動腳本都設了非-prod 標記。
- **不可逆操作守則**：改 compose / CI 屬需明確同意項，實作前再確認一次。

---

## PR 5 — 存取/併發守衛（High-5 + Medium-2）

兩項皆 pre-existing、與 #237/#290 主題相鄰；模組不同，分 commit。

### Commit 5a — copy observation 來源存取權（High-5 / #237相關）
**根因**：`services/animal/observation.rs:372` `copy()` 直接 `get_by_id(source_id)` 複製，未驗 source 所屬 animal/protocol 存取權（cross-protocol read IDOR）。
**修法**：在 handler `copy_animal_observation`（或 service `copy()` 入口）對 **source** 反查 `animal_id`（`access.rs::get_observation_animal_id`）後 `require_animal_access`；並校驗 source 與 target 同 animal/同 protocol（依業務語意，預設要求同 animal）。
**驗收**：test — user 對自己計畫 animal 有權，指定他人計畫 observation 的 source_id → 期望 403；同計畫 copy 仍成功。

### Commit 5b — GRN over-receipt + 併發（Medium-2 / #290相關）
**根因**：`services/document/grn.rs:136` `create_additional_grn` 在 pool（非 tx、無 FOR UPDATE）讀「已入庫量」後才開 tx；`grn.rs:257` 核准只重算 label、不擋 `received > ordered`。
**修法**：
- `create_additional_grn` 把剩餘量查詢移入 tx 並對 PO 行 `FOR UPDATE`（序列化併發入庫）。
- `update_po_receipt_status`（核准路徑）加守衛：`received ≤ ordered`，超量 → `AppError::Conflict`。
**驗收**：test — 對同一 PO 重複入庫使 received > ordered → 期望被擋；正常部分入庫累積至剛好 ordered 仍成功。

**整 PR 測試**：`cargo test --all-targets` 全綠。

---

## PR 6 — health liveness/readiness 分級（Medium-3 / #238）

**根因**：`health.rs:82` 把 `metrics_up` 併入 `all_ok` → recorder 失敗使 `/api/health` 永久 503，docker `HEALTHCHECK`（`bin/healthcheck.rs:43` 要求 200+healthy）連帶標容器 unhealthy，與 main.rs「觀測降級但業務不受影響」意圖矛盾。

> ⚠️ **此 PR 需使用者裁定（高風險：改容器健檢語意，可能影響 `depends_on: service_healthy` 連鎖）**。
> **前置事實確認**：先檢查 `docker-compose.prod.yml` 是否有 `depends_on: condition: service_healthy` 連鎖（決定 503 是否真會拖垮 web 等下游）。
>
> 方案（擇一）：
> - **方案 I（推薦）**：保留 `/api/health` 詳細分級回報（degraded 資訊有價值），但讓**容器層 healthcheck**（`bin/healthcheck.rs` / Dockerfile）只認 **DB liveness**（DB up = healthy），metrics/disk/pool 飽和不致容器 unhealthy。
> - **方案 II**：`/api/health` 拆 `/api/health/live`（DB）與 `/api/health/ready`（含 metrics/disk），Dockerfile 指向 live。
> - **方案 III（最小）**：把 `metrics_up` 移出 `all_ok`（降為純報告欄位）。
>
> 等使用者選定再實作。

**驗收**：模擬 recorder 失敗 → 容器仍 healthy、`/api/health` 仍顯示 metrics degraded；DB down → 容器 unhealthy。手動驗證 prod compose 起得來。

---

## PR 7 — 小修批次（可選，Low-2 + Low-5）

- **Low-2（#265）**：`services/audit.rs` free-text search 對 `q_text` escape `\ % _` 並加 `ESCAPE '\'`，使萬用字元被當字面。test：搜尋含 `_` 的字串只命中字面。
- **Low-5（#239）**：`constants.rs:207` advisory lock 中央註冊表補登 `services/stock/ledger.rs:270` 的 2-arg `(warehouse,product)` lock 命名空間說明（純文件 drift，無功能改動）。

**測試**：`cargo check` 綠（Low-2 動 service，建議 `--all-targets`）。

---

## 延後（不在本批，已記錄理由）

- **Medium-1（#298 signature_bridge plaintext payload）**：綁 R56 AWS migration 的 column 級加密，已是 backlog（memory: signature-bridge-encryption），不在本批重開。
- **Low-3（#210/#218 重複 user SELECT）**：效能微優化，低 QPS 可接受；若做，併入未來 permission_cache 重構（把 `tokens_valid_after` 併入 cache value）。
- **Low-4（#210 moka Arc 退化）**：程式碼註解已標 acknowledged limitation，影響微小，不修。

---

## Self-check（對齊 CLAUDE.md 思考紀律）

- [x] 每個 PR 的每一變更都 trace 回某個 finding（無 drive-by）。
- [x] 多解處（PR4 / PR6）已 surface tradeoff、標「需使用者裁定」，未 silent pick。
- [x] 每個 PR 列 reproducing/acceptance test（先紅後綠）作為 success criteria。
- [x] 配合既有 pattern（`ensure_not_locked` / `build_signature_data_v2` / login.rs session 順序 / migration down.sql template）。
- [x] 不可逆操作（改 compose / CI / migration 上 staging-prod）標明需明確同意。
