# 程式碼審查報告：PR #200-300

> 建立日期：2026-06-07 ｜ 視角：current main（HEAD 76875312）｜ 產出：單一彙整報告 + 嚴重度分級（先報告、後修復另議）

## 總結

本輪以 6 路平行 sub-agent 審查 PR #200-300 範圍（約 50 個 code PR；純 dependabot / CI bump / docs-only / closed-superseded 已略過）。每個 finding 皆由 sub-agent 對照 current main 程式碼驗證、再由 orchestrator 對 Critical/High 逐筆複驗（讀實際檔案）。

**確認仍存在於 current main 的 finding**：Critical 1、High 5、Medium 3、Low 6。

最關鍵者為 **Critical-1（#262 安樂死仲裁 fail-open）**：CHAIR 仲裁 `decision` 欄位無 enum/validator，任何非精確 `"approve_appeal"` 字串（typo / 空字串 / 前端傳錯 key）一律落入 else 分支 → order 轉 `approved` → VET 可執行不可逆安樂死。GLP 終決節點 fail-open，建議優先修。

審查面向（4 維）：正確性 Bug／回歸 · 安全/權限/稽核 · 專案規範一致性 · 簡化/效能。
嚴重度：🔴Critical=可被利用漏洞/資料毀損/生產當機 · 🟠High=明確 bug/權限缺口/影響核心流程 · 🟡Medium=邊界 case/規範違反/可維護性 · 🟢Low=風格/小重複/nice-to-have。

---

## Critical

### Critical-1 [#262 · 正確性/安全] 安樂死仲裁 `chair_decide` 對非白名單 decision fail-open，預設走「執行安樂死」路徑
- **檔案**：`backend/src/services/euthanasia.rs:553`
- **問題**：`ChairDecisionRequest.decision` 型別為 `String`，`models/euthanasia.rs:144-145` 註解寫「'approve_appeal' or 'reject_appeal'」但**無 `#[validate]` / enum 約束**，handler `decide_appeal` 的 `req.validate()?` 對此欄位無效。`chair_decide` 終態判定為 `let new_status = if req.decision == DECISION_APPROVE_APPEAL { "cancelled" } else { "approved" }`（553-557）——任何非精確等於 `"approve_appeal"` 的字串（typo 如 `"reject_apeal"`、空字串、前端傳錯 key、garbage）全部落入 else → order status = `approved`。CHAIR 本意「核准暫緩、保留動物」，但只要字串拼錯反而把動物推向被執行。
- **影響**：GLP 不可逆操作（安樂死）的終決節點 fail-open。單一字串錯誤可導致研究豬被錯誤核准執行，且 audit 會記成正常「reject appeal → approved」，事後無法辨識為誤判。
- **驗證**：Confirmed in current main。`euthanasia.rs:553` else 分支 → `"approved"`；`models/euthanasia.rs:144-155` decision 無 validate；handler 僅 `req.validate()?` + CHAIR role 檢查。
- **建議修法**：`decision` 改 enum（或 `#[validate(custom)]`），並把判定改為明確三分支 match：`approve_appeal → cancelled`、`reject_appeal → approved`、**其他 → `AppError::BadRequest` 拒絕**。fail-closed：未知值絕不可預設成執行路徑。

---

## High

### High-1 [#205/#213 · 安全/不可否認性] amendment 核准/否決簽章用可偽造的 plain SHA-256（未走 #276 的 HMAC v2）
- **檔案**：`backend/src/services/amendment/workflow.rs:84`
- **問題**：`insert_decision_signature_tx`（amendment APPROVE/REJECT 終態決定簽章）以 `signature_data = SignatureService::compute_hash(&signature_input)` 計算，即 plain `SHA-256(signer_id|content_hash|timestamp|"internal")`；且 INSERT 欄位列（90-108）不含 `hmac_version` → 落 DB default = 1（legacy v1）。PR #276 的整個目的就是把 `signature_data` 從「任何拿到 content_hash+timestamp+method 者可重算偽造」的 plain SHA-256 升級為 HMAC-SHA256+secret（v2）。但 amendment 這條「法定核准簽章」路徑完全沒套用。
- **影響**：amendment 的 21 CFR §11.50 核准/否決簽章（C2 核心非否認目標）其 `signature_data` 可被有 DB 寫入權者偽造，與 password/handwriting 路徑（已 HMAC 保護）防護不一致——它所保護的 maintenance/observation 簽章反而比這條法定簽章更強。
- **驗證**：Confirmed in current main。`workflow.rs:84` `compute_hash`；INSERT（90-108）無 `hmac_version`，對比 `signature/mod.rs:364-389` 的 `sign_internal` 走 `build_signature_data_v2` 並寫 `hmac_version=2`。
- **建議修法**：amendment 決定簽改呼叫 `SignatureService::build_signature_data_v2(...)` 並於 INSERT 寫 `hmac_version=2`；或直接走 `sign_record_tx` 統一路徑。

### High-2 [#241/#249 · 安全/GLP 紀錄鎖] 已簽收的維修保養紀錄仍可被 update / delete（handler 卻回報 `is_locked=true`）
- **檔案**：`backend/src/services/equipment.rs:788`
- **問題**：`sign_maintenance_reviewer` 簽章後在 record 上寫 `reviewer_signature_id`（1127-1149），`get_maintenance_signature_status` 對前端回 `is_locked: is_signed`（`handlers/signature/maintenance.rs:66`）。但 `update_maintenance_record_tx`（788）與 `delete_maintenance_record_tx` 完全沒有檢查 `reviewer_signature_id.is_some()`（`reviewer_signature_id` 守衛只出現在 1127 的「防重複簽章」，不在 update/delete）。任何具 `equipment.maintenance.manage` 權限者仍可改/刪一筆已簽收的紀錄。對照 observation/surgery/blood_test/care（#204）皆有 `ensure_not_locked` guard。
- **影響**：違反 21 CFR §11.10(e)(1)「簽章後紀錄不可竄改」。前端顯示「已鎖定」但後端不擋——使用者以為安全，實際可繞過修改/刪除已驗收維修紀錄，audit trail 失真。
- **驗證**：Confirmed in current main。`equipment.rs:788` update tx 在 `SELECT FOR UPDATE` 後直接組 UPDATE（796-838），無 signature 守衛；grep `reviewer_signature_id.is_some()` 僅命中 1127（sign 路徑）。
- **建議修法**：在 update/delete maintenance 的 tx 內（`SELECT FOR UPDATE` 後）加 `if existing.reviewer_signature_id.is_some() { return Err(AppError::Conflict("已簽收紀錄不可修改/刪除".into())) }`，與 #204 `ensure_not_locked` pattern 對齊。

### High-3 [#207 · 正確性/安全] 2FA 登入路徑未套用 #207 的「session-before-token」修正，SEC-28 併發 session 上限退化為 best-effort
- **檔案**：`backend/src/handlers/two_factor.rs:167`
- **問題**：`verify_2fa_login` 先呼叫 `complete_2fa_login` 簽發並回傳 access/refresh token（167-169），`create_session` 與 `end_excess_sessions`（SEC-28 併發 session 上限）卻放在其後的 `tokio::spawn` 火忘式背景任務（180-190）。這與 PR #207 對密碼登入路徑（`handlers/auth/login.rs:116-126`：session 先建好、`end_excess_sessions` 同步、失敗即中止登入）刻意修正的順序**完全相反**。
- **影響**：(a) 2FA 使用者（admin 為強制 2FA 對象）的併發 session 上限不被強制——token 已發出回傳，spawn 內 `end_excess_sessions` 若失敗/被 runtime drop，超量 session 不被踢，SEC-28 對 admin 形同虛設。(b) 若 `create_session` 失敗，user 仍持有可用 token 但 `user_sessions` 無對應列（孤兒 token，session 列管/稽核缺漏）。(c) #207 commit 宣稱「session 建立必須在 token 發出前」，但此承諾僅對 2 條登入路徑的 1 條成立。
- **驗證**：Confirmed in current main。`two_factor.rs:167`（issue token）vs 185-189（spawn 內 `create_session`/`end_excess_sessions`）；對照 `handlers/auth/login.rs:116-126` 正確順序。
- **建議修法**：將 `create_session` + `end_excess_sessions` 移到回傳 token 之前同步執行（失敗即 `Err` 中止、不發 token），與密碼路徑對齊；`log_success` 可維持 fire-and-forget（純遙測）。

### High-4 [#283 · 正確性/安全] R30-23/24 production 啟動 fail-fast 在實際 prod 從未觸發（`APP_ENV`/`RUST_ENV` 從未設定）
- **檔案**：`backend/src/startup/mod.rs:36`
- **問題**：`is_production()` 依賴 `APP_ENV` 或 `RUST_ENV == "production"`，未設定時回 `false`。全 codebase 搜尋（`docker-compose*.yml` / `.env*` / `secrets/` / `Dockerfile*`）**皆未設定 `APP_ENV` 或 `RUST_ENV`**。`main.rs:94-122` 的兩處 fail-fast 都守在 `&& is_production()` 之下。
- **影響**：#283 號稱的「production startup hardening」（config 警告 fail-fast + DB self-test fail-fast）在這台 prod-on-laptop **完全 inert**——config 缺 `AUDIT_HMAC_KEY`/地理圍籬、DB self-test 偵測到 system_user 缺失 / permissions 表空 / schema drift 時，只會 `tracing::error!` 然後繼續啟動，不 `exit(1)`。GLP §1.4「啟動前驗證 schema/role/permission」的防線形同虛設。
- **驗證**：Confirmed in current main。`startup/mod.rs:36-41`；`main.rs:94-122` fail-fast 守在 `is_production()`；grep `APP_ENV|RUST_ENV` 於所有 compose/.env/Dockerfile = 0 命中。
- **建議修法**：(a) `docker-compose.prod.yml` 的 api service 加 `environment: APP_ENV=production`；或 (b) 反轉預設語意——`is_production()` 在「未明確標記 dev/staging/CI」時視為 production（fail-safe 預設），較符合 prod-on-laptop 單一環境現實。

### High-5 [#237 相關 · 安全] `copy_animal_observation` 未驗證 **來源** observation 的計畫存取權（cross-protocol read IDOR）
- **檔案**：`backend/src/services/animal/observation.rs:372`
- **問題**：`copy_animal_observation` handler 對「目標 `animal_id`」呼叫 `require_animal_access`，但 service `copy()` 直接 `get_by_id(source_id)` 複製 content/treatments/remark 等欄位到新紀錄，**從未驗證 `source_id` 所屬 animal/protocol 的存取權**。具 `animal.record.copy` 且對自己計畫某 animal 有權的 user，可指定他人計畫 observation 的 `source_id`，把跨計畫敏感觀察內容複製進自己可讀的新紀錄。
- **影響**：與 #237 修補的 create IDOR 同類，但 **source 維度未涵蓋**；違反 C2 動物層級資料隔離（跨計畫資料外洩）。
- **驗證**：Confirmed in current main。`observation.rs:372` `Self::get_by_id(pool, source_id)` 無 access 檢查；`access.rs` 有 `get_observation_animal_id` 可用於反查。**備註**：此缺陷為 pre-existing，不在 #237 等 4 個 PR 的 diff 內，列此因屬「#237 IDOR 覆蓋盤點的 sibling endpoint missed」範疇。
- **建議修法**：service `copy()` 開頭（或 handler）對 source 反查 `animal_id` 後 `require_animal_access`；並限制 source 與 target 同 animal/同 protocol。

---

## Medium

### Medium-1 [#298 · 安全/明文殘留] 手機簽章 bridge submit 把含明文密碼的 payload 以 plaintext JSONB at-rest 存於 `signature_bridge_sessions`
- **檔案**：`backend/src/services/signature_bridge.rs` submit + `migrations/047`
- **問題**：公開端點 `submit_bridge_public` 接收 payload（含 `MutationSignaturePayload.password` 明文）直接寫入 `signature_bridge_sessions.payload` JSONB，migration 047 註解自承「暫存 plaintext JSON，後續加 column 級加密」。雖 TTL 5min + 已從 IDXF export 排除，DB 快照/WAL/backup 在窗口內仍含明文密碼。
- **影響**：違反 no-plaintext-credentials 原則。**已知 backlog**（memory: signature-bridge-encryption 綁 R56 AWS migration），列此僅確認仍存在，不重複開單。
- **建議修法**：短期可改 submit 端不收 password 明文（傳已驗證一次性 token），或加 column 級加密。

### Medium-2 [#290 相關 · 正確性] 採購入庫（GRN）over-receipt + 併發視窗（#290 按鈕放大觸發面）
- **檔案**：`backend/src/services/document/grn.rs:136`（`create_additional_grn`）/ `:257`（`update_po_receipt_status`）
- **問題**：「已入庫量」SELECT 在 `pool`（非 tx、無 `FOR UPDATE`）讀取後才開 tx 建 GRN——兩次同時點「採購入庫」可各自算出相同剩餘量、各建一張涵蓋全剩餘的 GRN。且核准時只重算 `receipt_status` label，**不阻擋 over-receipt**（received > ordered 仍標 complete，draft GRN qty 可手動改大）。#290 新增的「採購入庫」按鈕使此路徑更易觸發。
- **影響**：庫存可被重複入庫 / 超量入庫，影響存量正確性（GLP/ERP 資料一致性）。缺陷本體 pre-existing，#290 為暴露面。
- **驗證**：Confirmed in current main。`grn.rs:136-254` 讀剩餘量於 pool；`grn.rs:257` 核准不檢查 received ≤ ordered。
- **建議修法**：核准 GRN 時加 `received ≤ ordered` 守衛；`create_additional_grn` 對 PO 行 `FOR UPDATE`。

### Medium-3 [#238 · 正確性] metrics recorder 啟動失敗會讓整個 stack 報 unhealthy，與「業務不受影響」設計意圖矛盾
- **檔案**：`backend/src/handlers/health.rs:82`
- **問題**：#238 把 `metrics_up` 併入 `all_ok`，`install_recorder()` 失敗 → `/api/health` 永久回 503 "degraded"。Docker `HEALTHCHECK` 跑 `/app/healthcheck`（要求 response 含 "200" 與 "healthy"，`healthcheck.rs:43`），503 → 連續 retry 失敗 → 容器標 unhealthy。但 `main.rs` 註解明說「不 fail-fast 是為了讓核心服務仍可運作；觀測降級但業務不受影響」——health 回 503 後，依賴 `depends_on: condition: service_healthy` 的下游容器會起不來，等於 metrics 子系統壞掉拖垮整個 stack。disk（相對路徑 `./uploads` 不存在）與 pool 飽和亦會翻 503。
- **影響**：意圖與實作自相矛盾；觀測層故障可放大為整站不可用（**取決於 prod compose 是否有 `depends_on: service_healthy` 連鎖**）。
- **驗證**：Confirmed in current main。`health.rs:77-82,103-107`；`bin/healthcheck.rs:43`；`Dockerfile:88-89`。
- **建議修法**：liveness（DB up = 200）vs readiness（含 metrics/disk）分級，或 docker healthcheck 只認 DB。

---

## Low

- **Low-1 [#273 · 安全]** `migrations/041_audit_signature_immutability_triggers.sql:70` — `electronic_signatures` immutability trigger 允許 `is_valid`/`invalidated_*` 4 欄變動但未鎖 `is_valid` 方向，直接 SQL 將作廢簽章 `is_valid=false→true`「復活」可通過 trigger。應用層無此路徑（`signature/mod.rs:563` 只設 false），屬 defense-in-depth 缺口（威脅模型同 HMAC residual risk，需直接 DB 存取）。建議 trigger 加 `IF NEW.is_valid AND NOT OLD.is_valid THEN RAISE EXCEPTION`。
- **Low-2 [#265 · 正確性]** `services/audit.rs`（free-text search）— ILIKE `'%'||$9||'%'` 未 escape `%`/`_`（無 SQL injection 風險，已參數綁定），無法搜尋字面 `_`/`%`、全 `%` 輸入放大掃描。建議對 `q_text` escape 並加 `ESCAPE '\'`（100 字上限已抑制 DoS）。
- **Low-3 [#210/#218 · 簡化/效能]** `middleware/auth.rs:170,227` + `repositories/user.rs:32,44` — 每請求對同一 users PK 列發兩個分離單欄 SELECT（`tokens_valid_after` 每請求未快取 + miss 時 `is_active/expires_at`），可合併為單一 SELECT。auth.rs:168 doc comment 已自承此 gap。建議把 `(is_active, expires_at, tokens_valid_after)` 一起放進 permission_cache，cache hit 時真正零 DB。
- **Low-4 [#210 · 正確性]** `middleware/auth.rs:263`（`map_cache_loader_error`）— moka `try_get_with` 多並發等待者持有 `Arc<AppError>` 時 `Arc::try_unwrap` 失敗 → `Database(sqlx::Error)`（不可 Clone）退化為通用 `Internal`。極窄 race、不影響授權判斷，程式碼註解（R28-M4）已明載為 acknowledged limitation。列此僅為完整性。
- **Low-5 [#239 · 規範一致性]** `constants.rs:207` — #239 立下「新增 advisory lock 必更新中央註冊表」規則，但後續 `services/stock/ledger.rs:270` 的 2-arg `(warehouse,product)` lock 未登記。屬流程/文件 drift——ledger 用 2-arg `(int4,int4)` overload 為獨立命名空間，與 1-arg hashtext 鎖物理上不衝突，無實際 mutual-blocking。建議補登以維持「所有鎖集中可查」承諾。
- **Low-6 [#283 · 安全]** `startup/config_check.rs:14` — config fail-fast 摘要只驗 5 類（地理圍籬/admin 密碼/`AUDIT_HMAC_KEY`/`SEED_DEV_USERS`/`TEST_USER_PASSWORD`），不含 JWT 金鑰、CSRF secret、print-pdf `X-Internal-Token`、SMTP，給人「config 都驗過」錯覺。實際緩解：JWT 私/公鑰已在 `config.rs:229-238` 用 `.context()?` 硬性 fail（缺失即啟動失敗），csrf_secret 由 JWT 衍生，故真正高危 secret 不會靜默放行。建議補進警告摘要或於函式 doc 註明「僅涵蓋軟性警告項」。

---

## 已不適用 / 已修復 / by-design（verifier 駁回，僅備查）

- **CSP base-uri / report cap（#284/#285/#287）**：當時 Report-Only header 確無 base-uri、無 payload cap、INSERT 靜默吞錯，但**皆已於後續修掉**——base-uri 'self' + form-action 'self'（#410）、report cap 16KB（R33-3）、loud-log（R31-11）。current main 為單一 enforce header，無殘留。
- **#266 `/version` endpoint info leak**：掛在 `admin::routes()` 經 `auth_middleware_stack` 保護且 handler 另檢 `is_admin()`，git_sha/build_time 不對匿名外洩。Clean。
- **#268 金額 f64 rounding**：權威金額路徑在後端為 `rust_decimal::Decimal`（`document/crud.rs:569`、`workflow.rs:114`），前端 totalAmount 僅 UI 顯示且已改整數分。不成立。
- **#269/#272 protocol lost update**：`version` 欄位實存（`007_aup_protocol.sql:24`），後端 `FOR UPDATE` + `version=version+1` + `WHERE (...IS NULL OR version=$6)` + 0 row → Conflict，前端送 version 對齊，audit 呼叫端全對齊。Clean。
- **#251 disposal RBAC**：RBAC + FOR UPDATE + status guard + 重簽防護 + 職權分離 + `log_activity_tx` 全 tx 原子，handler 內無裸 SQL。Clean。
- **#270 IDXF coverage**：coverage 測試（掃 CREATE TABLE vs EXPORT_TABLE_ORDER + EXCLUDED）仍守住，後續新表皆已維護，無漏表。Clean。
- **#276 verify 不重算 signature_data**：verify 只比對 content_hash + 檢查 hmac_version/key 可用性，不重算 signature_data（hash_input 不可還原）。屬已知設計取捨，v2 防偽靠寫入端無 key 無法產生合法值。文件化即可。
- **#278 retention summary audit**：hard-delete 走 pool、summary audit 整輪結束才寫一筆；原始 soft-delete 已各自有 audit，summary 僅統計用途，GLP 可辯護。cron 已被 R63-C3 leader lock 涵蓋，無多 instance 併發刪除。
- **#239 hashtext 1-arg 三鎖共命名空間**：audit_log_chain / protocol_iacuc_number_gen / per-email 理論上 i32 hashtext 可碰撞，但皆 `xact_lock`（tx 結束釋放），最壞短暫序列化、無資料損毀；單實例低併發機率與影響俱微。

---

## 後續建議（修復節奏）

1. **優先修 Critical-1（#262 安樂死 fail-open）**——不可逆 GLP 操作，fail-closed 修法簡單（enum + 三分支 match）。
2. **High-1~4 為一組 GLP 簽章/紀錄鎖一致性 + session 完整性缺口**，建議併入一個「signature/session hardening」PR。
3. **High-5 / Medium-2 為 pre-existing IDOR / 併發缺口**，可進 backlog 排程。
4. 本報告僅列出 verifier 確認**於 current main 仍存在**的 finding；修復前請等使用者明確 go-ahead（沿用 #300-400 / #400-500 review 的「report-only、等 go fix」節奏）。

> 略過清單（無需 code review）：dependabot/CI bump #225-233 #242-247 #250 #252-256 #258 #299；docs-only / closed-superseded #202 #203 #214 #216 #219 #223 #224 #235 #248 #257 #259 #260 #261 #264 #279 #280 #281 #289 #291 #294 #295。
