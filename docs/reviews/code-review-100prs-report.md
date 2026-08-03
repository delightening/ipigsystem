# Code Review 彙整報告 — 最近 100 PR（#600–#490）

> 審查日期：2026-06-04 ｜ 視角：現況程式碼 ｜ 6 路平行審查（群組 A–F）
> 計劃見 `docs/reviews/code-review-100prs-plan.md`。略過 G(dependabot)/H(docs/清理)。

## 摘要

| 嚴重度 | 數量 |
|---|---|
| 🔴 Critical | 1 |
| 🟠 High | 5 |
| 🟡 Medium | 9 |
| 🟢 Low | 11 |

整體品質高：HMAC chain、IDOR 雙層守衛、invitation 提權守衛、#575 採購過帳交易、#581 通知去重、#586 巡場按鈕前後端授權對齊等核心邏輯都紮實且多有測試。風險集中在「PI 帳號開通服務」「跨 HTTP 多步非原子」「MCP 認證 SQL bug」「ADJ 出庫儲位負庫存」幾處。

---

## 🔴 Critical（1）

### C1. MCP 認證查不存在的欄位 `user_roles.role_code`，整條 MCP 認證 runtime 崩潰
- **位置**：`backend/src/handlers/mcp.rs:323`
- **維度**：正確性 ｜ **PR**：#532（scope 守衛建於此函式回傳的 roles）
- **問題**：`SELECT role_code FROM user_roles WHERE user_id=$1`，但 `user_roles` 表（002 migration）只有 `role_id`，全 codebase 其餘 18 處皆 `JOIN roles r ON ur.role_id=r.id` 取 `r.code`。此查詢執行期必拋「column does not exist」→ `?` 傳成 `AppError::Database` → 在 `authenticate_mcp_key` 被吞為 Unauthorized。
- **影響**：所有 MCP key 認證在 roles 載入階段就崩，#532 的 scope/角色雙重守衛形同失效（tools/list、tools/call 全 401）。現有測試只測純函式 `check_tool_permission`，完全不打 DB，所以 CI 全綠掩蓋此 bug。
- **建議**：改 `SELECT r.code FROM user_roles ur JOIN roles r ON ur.role_id=r.id WHERE ur.user_id=$1`；補一條真打 DB 的 MCP auth 整合測試。**先確認 MCP 是否真有在用**。

---

## 🟠 High（5）

### H1. 補登歷史變更跨 3 個 HTTP 呼叫非原子，失敗留孤兒 DRAFT 並卡死編號
- **位置**：`frontend/src/components/protocol/HistoricalAmendmentDialog.tsx:52-81`
- **維度**：正確性 ｜ **PR**：#544
- **問題**：依序呼叫 `create_historical` → `historical-reviews` → `finalize-historical` 三個獨立 endpoint。中段或末段失敗時，已建立的 `is_historical` DRAFT amendment 殘留並佔用 `revision_number`（MAX+1）。
- **影響**：使用者看到失敗 toast，但 DB 留未生效草稿、live amendment 編號被往後推；重試再建一筆累積孤兒；該 DRAFT 又被 `ensure_live_amendment` 擋住無法走正常流程 → 卡死。
- **建議**：後端提供單一 transactional endpoint（create+reviews+finalize 一次 tx）。優先後端合併，次選前端失敗 cleanup。

### H2. PI 帳號開通直接 raw INSERT，繞過 UserService，無 USER_CREATE 稽核
- **位置**：`backend/src/services/protocol/pi_provision.rs:88-116`
- **維度**：安全/稽核 ｜ **PR**：#566
- **問題**：`provision_pi_account` raw INSERT users + user_roles(PI)，未走 `UserService::create`，因此不寫 `USER_CREATE` 稽核（只記 protocol 端 `PROTOCOL_PI_PROVISIONED`），也繞過 `validate_role_assignment`。
- **影響**：CSO 角度「誰建立此帳號」無法從 user activity log 追溯；對 GLP 合規是稽核缺口。系統憑空多一個可登入帳號卻在 user 稽核軸上隱形。
- **建議**：建帳後補一筆 `USER_CREATE` `log_activity_tx`（entity=user），或重用 UserService 內部建帳路徑。

### H3. PI relink 會關聯到任意 email 相符的既有帳號（含內部 staff/admin）
- **位置**：`backend/src/services/protocol/pi_provision.rs:76-101`
- **維度**：正確性/權限 ｜ **PR**：#566
- **問題**：以 `LOWER(email)` 比對既有帳號時只排除軟刪除，未檢查是否為內部員工/高權角色。若外部 PI 的 `basic.pi.email` 恰等於某內部 admin email（或被刻意填入），relink 會把 `protocols.pi_user_id` 指向該內部帳號，approve 後對該信箱寄「設定密碼」連結。
- **影響**：可被用於對既有帳號觸發密碼重設信（社交工程），或把計畫 PI 誤掛到內部高權帳號。
- **建議**：relink 既有帳號時若 `is_internal=true` 或具非 PI 高權角色 → 拒絕或要求 admin 確認；audit diff 明確記錄 relink 目標帳號。

### H4. 「忘記密碼」token 重設流程完全無 audit log
- **位置**：`backend/src/services/auth/password.rs:392-430`
- **維度**：安全/稽核 ｜ **PR**：#532
- **問題**：`change_own_password` / `reset_user_password` 都寫 SECURITY audit，但 `reset_password_with_token` 改了密碼、撤了 refresh token、設了 `tokens_valid_after`，卻沒寫任何 audit row。
- **影響**：攻擊者取得重設 token（信箱被盜）接管帳號時，HMAC chain 與 user_activity_logs 無任何痕跡，事後鑑識看不到「密碼曾被 token 重設」。
- **建議**：補一筆 SECURITY event（`PASSWORD_TOKEN_RESET`）；無登入 actor 走 `log_security_event_tx`（Anonymous），與 §Anonymous 表格「尚未登入但需 audit」一致。

### H5. ADJ 出庫調整的儲位庫存可被扣成負數
- **位置**：`backend/src/services/stock/ledger.rs:162-192`
- **維度**：正確性 ｜ **PR**：#575（同模組）
- **問題**：`process_adjustment` 不論增減都呼叫 `upsert_storage_location_inventory(…, line.qty, …)` 傳**原始帶號 qty**。ADJ 出庫時 `line.qty<0`，`ON CONFLICT … on_hand_qty + EXCLUDED.on_hand_qty` 等於加負值，且該 upsert 分支**無** `on_hand_qty>=qty` 下限檢查。
- **影響**：warehouse 級有 `check_stock_available` 守總量，但**單一儲位** `storage_location_inventory` 可被扣成負數，造成儲位庫存漂移。
- **建議**：ADJ 出庫（qty<0）改走 `decrement_storage_location_inventory`（取 `-line.qty`），正向走 upsert。

---

## 🟡 Medium（9）

### M1. `generate_amendment_no` 無鎖 MAX+1，並發補登/live 變更撞號回 500
- `backend/src/services/amendment/crud.rs:43-68` ｜ 正確性 ｜ PR #544/#525
- tx 外無 `FOR UPDATE`/advisory lock 取 `MAX(revision_number)+1`，並發第二筆撞 `UNIQUE(protocol_id, amendment_no)`，23505 未映射 → 500。建議 tx 內 `pg_advisory_xact_lock(protocol_id)` 或捕捉 23505 映射 `Conflict`。

### M2. `update_protocol` 缺 IDOR 關聯檢查，持 `aup.protocol.edit` 者可編輯任何補登中計劃
- `backend/src/handlers/protocol/crud.rs:198-216` ｜ 安全/權限 ｜ PR #544
- 與同檔 `change_protocol_status` 走 `require_protocol_related_access` 的模式不一致。**屬授權設計選擇，需確認是否刻意全域編輯語意**。

### M3. import_review 全量取代 DELETE 未限定補登來源，假設前提脆弱
- `backend/src/services/protocol/import_review.rs:52-59` ｜ 正確性 ｜ PR #534/#544
- 對 import_pending 計劃 `DELETE FROM review_comments WHERE protocol_id=$1` 全刪重建，「import_pending 僅有補登資料」假設無 DB 層保障。建議 DELETE 加條件或 schema 加 `is_import_backfill` 標記。

### M4. finalize 後無法再開通 PI 帳號（潛在死路）
- `backend/src/handlers/protocol/pi_provision.rs:33` + `access.rs:499` ｜ 正確性 ｜ PR #566
- 端點以 `can_manage_import_pending` 把關，對 `import_pending=false` 一律回 false。補登中漏開通 → finalize → PI 永遠無法被開通。**需使用者裁定是否刻意限制**。

### M5. PI 開通 approve 寄信回傳 email（弱列舉）
- `backend/src/handlers/protocol/pi_provision.rs:123-129` ｜ 安全 ｜ PR #566
- admin only 故風險受限，但與一般 forgot_password 防列舉設計不一致。建議僅回 `{ok:true}`。

### M6. `delete_attachment` 缺物件層級存取檢查（與讀取端不一致）
- `backend/src/handlers/upload.rs:545-567` ｜ 安全/權限 ｜ PR #530
- list/download 走 `check_attachment_permission` 雙層守衛，delete 只檢查 `uploaded_by==id || is_admin`。非直接越權，屬 SoD/一致性瑕疵。建議補一致檢查或加註設計意圖。

### M7. `derive_v3_routing` 對 SIGNATURE after_data 明文 shape 有隱性耦合
- `backend/src/services/audit.rs:1014-1039` ｜ 安全/HMAC ｜ PR #511
- 自動推導 binding 依賴 after_data 抽 content_hash，與 AuditRedact 規則隱性耦合。建議確保所有 SIGNATURE_* 走 `log_signature_event_tx`（顯式 binding），自動分支降級為 fail-loud。

### M8. `tokens_valid_after` 同秒邊界競態 + 每請求多一次 PK 查詢
- `backend/src/services/auth/password.rs:147-151` + `middleware/auth.rs:171` ｜ 安全/效能 ｜ PR #532
- 秒級截斷比較留最長 ~1 秒撤銷縫隙；每個認證請求多打一次 users PK 查詢未進 cache。建議改毫秒比較（或 tva=NOW()+1s）、併入 permission_cache。

### M9. 通知/動物 Excel 與 attachments 的同類殘留
- `backend/src/services/notification/alert.rs:218-225`（效期預警 Decimal 尾零，#589 漏修同檔）＋ `backend/src/services/animal/excel_export.rs:83-86`（「備註」欄缺 formula-injection 防護，#590）＋ `backend/src/handlers/upload.rs`（handler 直接寫 SQL、attachments SELECT 重複 ≥2 次，#569/#547）＋ `frontend/.../VetReviewSection.tsx:103`（評比表格用 array index 當 key，刪列輸入錯位，#543）。

---

## 🟢 Low（11，摘要）

- **A**：`core.rs:755` list() `unwrap_or_default()` 吞 SQL 錯誤（既有，違 no-unwrap-or-on-db）；`ResearchBasicFields.tsx` render 中 `getState().hasRole`（非 selector）；`import_approved` 單函式 ~195 行超門檻；vet_review `signed_at` 永遠 null。
- **B**：`ProtocolInfoCards.tsx:62` 「待填」硬編（PI/import 子模組普遍硬編中文，依 match-existing-style 不單點改）；`crud.rs:240` PI 顯示名 SQL 在 handler 內聯。
- **C**：`mcp.rs:309` MCP 認證未檢 `expires_at`；`signature_bridge.rs:261` GC 無鎖 DELETE 窄競態。
- **E**：`DashboardPage.tsx:55` 未隨 #499 遷移 selector；`auth.ts:353` selector 雙呼叫 pattern 隱晦；`nginx.conf:87` 註解仍提已移除的 Word COM daemon；`messaging.rs:172` handler 直接寫 SQL。
- **F**：`VetPatrolReportDialog.tsx:1248` 硬編 `hover:bg-green-700`；`list_available_pigs` 對 view_project-only 未做 iacuc scoping（疑似刻意，建議加註）；`076_gin_index` 非 CONCURRENTLY（既有 pattern，知會即可）。

---

## 各群組「明確 PASS」（已驗證無問題）

- #581 通知去重、#523 access-matrix 收件人、#584 LowStockAlert FromRow、#578 限流 burst、#600 QuickActions widget、#499 selector 遷移、sliding session 雙路徑門檻一致（群組 E）。
- #586 巡場按鈕前後端授權對齊、#529 auto-acknowledge 冪等+保留 audit、#527 Jinja macro `<br>` 跳脫安全（群組 F）。
- 補登狀態機守衛、assignable-users 端點授權 + 回歸測試（群組 A/B）。
- HMAC chain 三版本編碼 + Anonymous→SYSTEM_USER_ID fallback 三處一致、attachment IDOR 雙層守衛、invitation 提權雙重守衛、#575 採購過帳 advisory lock + SAVEPOINT 交易（群組 C/D）。

---

## 建議處理順序

1. **先確認再修**：C1（MCP 是否在用）、M2/M4（授權語意是否刻意）。
2. **優先修**：C1、H2、H3、H4、H5（安全/稽核/資料一致性，改動小）。
3. **次之**：H1（需後端新端點，較大）、M1、M6、M8。
4. **進 backlog**：M3/M5/M7/M9 + 全部 Low（多為既有債與一致性 nit）。
