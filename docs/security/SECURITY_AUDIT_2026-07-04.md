# 資安稽核報告 — 2026-07-04

> 方法：6 個並行 subagent 分軸靜態掃描（授權/IDOR/SoD、HMAC 鏈、注入/上傳/DoS、CSP/JWT/外洩、
> 文件落差/panic/設定）+ 1 個對抗驗證 agent 反駁高風險 finding。全程唯讀，未修改任何程式碼。
> 所有 finding 附 file:line，可自行覆核。訓練記憶不作依據，結論以程式碼為準。

## Executive Summary

**無 Critical、無 High。最高嚴重度 Medium。** 整體防禦成熟：SQL 全參數化/白名單、上傳有 magic
number + 路徑穿越防護、CSP strict 無 eval、密碼 Argon2id、HMAC 鏈寫讀對稱、敏感欄位序列化遮蔽、
歷史 IDOR 熱區（MCP #611 / dashboard #138 / message matrix #365 / attachment / PI 列舉）全數驗證已修。

| 嚴重度 | 數量 | 項目 |
|---|---|---|
| Critical | 0 | — |
| High | 0 | （原 1 候選經對抗驗證降級，見 L-1） |
| Medium | 5 | M-1 設備閒置審批可自核 SoD｜M-2 HMAC changed_fields 潛伏耦合｜M-3 GLP/ERP 核准缺 requester≠approver｜M-4 文件 list 洩漏財務摘要｜M-5 Forwarded-IP 信任缺來源驗證 |
| Low | 4 | L-1 vet_recommendation 缺物件層授權（降級）｜L-2 設備維護驗收可自簽｜L-3 GDPR 刪帳號 cache 殘留（降級）｜L-4 訊息附件 rate limit 走錯層 |
| 盲點（設定/文件落差） | 4 | B-1 session idle 8h↔10h 分岔｜B-2 .env.example 鎖定 15↔30 弱化｜B-3 unwrap CI 僅 warn｜B-4 死碼常數/過時註解 ×3 |

對抗驗證的價值：原授權 agent 主張 vet_recommendation 為 **High IDOR**；對抗驗證查權限矩陣後
證明持有該權限的角色（admin + VET）**都具 view_all**，跨計畫提權不可利用 → 降 Low。避免了一次誤報。

---

## Medium

### M-1【confirmed】設備閒置審批可自核（SoD 離群點）
- 位置：`backend/src/services/equipment.rs:1885` `approve_idle_request`
- 情境：建立閒置申請者若同時持 `equipment.idle.approve`，可核准自己的申請。函式讀了
  `before.applied_by`（:1905）卻從未比對 `current_user.id`，:1919-1944 直接進 UPDATE。
- 離群證據：同檔 `approve_disposal:1534` 有 `existing.applied_by == current_user.id → Forbidden`，此路徑漏。
- 信心度：**High（對抗驗證確認）**。衝擊限設備 active/inactive 狀態，非合規核心，故列 Medium。
- 修補方向：補一行 `if before.applied_by == current_user.id { return Forbidden }`。

### M-2【潛伏】HMAC changed_fields 寫端 vs DB stored proc 耦合脆弱點
- 位置：寫端 `services/audit.rs:576-580,635`；proc `migrations/077:54-66,82`；讀端 `audit.rs:914`
- 情境：寫端對「app 端 changed_fields」算 HMAC，但該 Vec 為空時傳 NULL 給 stored proc，
  proc 改用 JSONB EXCEPT 自算並存入可能非空的陣列；verifier 讀 DB 存的值。今日一致**僅因**
  `DataDiff::compute` 的 top-level key-diff 恰好複刻 proc 邏輯。目前無任何 service 觸發此路徑
  （欄位 `pub(crate)` 可繞過），但一旦有人手建 DataDiff 或 proc 邏輯漂移，受影響 row 會被判斷鏈
  → critical 假告警 → 告警疲勞掩蓋真竄改。
- 信心度：**高（確認為潛伏、非現行 bug）**。
- 修補方向：寫端在 before+after 皆存在時一律傳算好的 changed_fields（永不傳 NULL），或移除 proc fallback，或加 debug_assert 鎖不變式。

### M-3【理論】GLP/ERP 核准缺 requester≠approver（靠權限分離兜底）
- 位置：`services/glp_compliance.rs:947 approve_change_request`、`:301 approve_controlled_document`；
  `services/document/workflow.rs:235 approve`、`:450 admin_approve`
- 情境：同時持對應 approve 權者可核准自建的變更請求/受控文件/ERP 單據（大額 ADJ 有 WM→admin
  兩段部分分離，一般單無）。與 disposal/transfer/leave 的程式強制自核守衛不一致。
- 信心度：Med（可利用性取決於權限矩陣是否把申請與核准權授予同一角色）。
- 修補方向：核准函式補 `created_by/requested_by != approver` 守衛。

### M-4【待驗證】文件 list 端點洩漏跨建立者財務摘要
- 位置：`handlers/document.rs:74 list_documents` → `services/document/crud.rs:577`
- 情境：`get_document` 走 `check_access`（建立者/WM/admin），但 `list` 僅 `require_permission!(erp.document.view)`、
  SQL 無 `created_by` scope → 空 filter 回傳全部單據摘要（doc_no、partner、total_amount、protocol_no）。
- 信心度：Med（視 `erp.document.view` 是否只授予 WM/財務）。
- 修補方向：list 對非 WM/admin 加 `created_by` 收斂。

### M-5【待驗證】Forwarded-IP header 信任缺來源驗證
- 位置：`backend/src/middleware/real_ip.rs:40-57`
- 情境：`trust_proxy_headers=true` 時依序信任 `cf-connecting-ip`→`x-real-ip`→`x-forwarded-for`，
  未檢查 `ConnectInfo(addr)`（TCP 對端）是否真為受信反代。此函式被 rate limiter、IP 黑名單、
  蜜罐自動封鎖共用。若攻擊者能繞過 Cloudflare 直連 origin（同主機另一容器被攻陷/誤曝 port），
  可偽造任意 IP：(a) 每次換 IP 繞過 per-IP 限流；(b) 偽造成同事 IP 命中蜜罐 → 觸發**永久**封鎖陷害對方。
- 信心度：**⚠️ 待驗證**——目前 docker-compose 將 api 綁 `127.0.0.1:8000`，外部無法直連，需同主機/
  同 network 內另一容器先被攻陷才可觸發；屬系統性設計缺口（零層防禦），非單一 bypass。
- 修補方向：僅在 `ConnectInfo(addr)` 屬已知反代/loopback 網段時才信任 forwarded header，否則 fallback socket IP。

---

## Low

### L-1【降級】vet_recommendation 缺物件層授權（深度防禦一致性）
- 位置：`handlers/animal/vet_recommendation.rs:30/76/121/167`；service `services/animal/medical.rs:524,584,536`
- 結構屬實：四個寫入 handler 只 `require_permission!("animal.vet.recommend")`，無 Scoped/animal-access 守衛；
  service 直接用 caller 傳入的 record_id INSERT。離群點成立（同檔 GET 版、姊妹 `add_medical_record`
  都有 `Scoped<AnimalWrite>` + `require_animal_has_protocol`）。
- **對抗驗證降級**：`animal.vet.recommend` 全庫僅授予 admin + VET（`migrations/002_auth_users.sql:319,347`），
  兩者**都持有** `animal.animal.view_all`（:345）。跨計畫提權不可利用 → Low。
- 前提條件（重要）：此結論僅對**預設 seed** 成立。**若日後自訂角色把 `animal.vet.recommend` 指派給
  非 view_all 角色，此項立即升 High。** 建議仍補 Scoped 守衛消除這個未來地雷。

### L-2【confirmed】設備維護驗收可自簽（SoD 離群點）
- 位置：`services/equipment.rs:1054 review_maintenance_record`
- 情境：登錄維護紀錄者可自任驗收者，無「登錄者≠驗收者」守衛。與 M-1 同類離群。
- 信心度：High（未經對抗驗證，但邏輯與 M-1 同構）。修補：補登錄者≠驗收者守衛。

### L-3【降級】GDPR 自助刪帳號 permission_cache 殘留
- 位置：`handlers/auth/account.rs:94 delete_me_account`；`services/user.rs:581 deactivate_self`；
  middleware `auth.rs:207-214`
- 結構屬實：自助路徑未 `permission_cache.invalidate` 也未設 `tokens_valid_after`（admin 路徑 `user.rs:183` 有）；
  middleware cache hit 不重查 is_active，僅 miss 才驗（5min TTL）。
- **對抗驗證降級**：主窗口已被 JWT 黑名單關閉——`delete_me_account` 立即 `jwt_blacklist.revoke(當前 jti)`
  + `end_all_sessions` + 清 refresh token；middleware `validate_jwt`（`auth.rs:146`）在 permission_cache
  之前先擋黑名單 → 當前 token 立即 401。殘留僅影響**同一使用者其他裝置**尚未過期的 access token
  （自刪自受、≤ access-token TTL、非跨使用者非提權）→ Low 深度防禦缺口。
- 修補方向：`deactivate_self` 收尾補 `permission_cache.invalidate(&id)` + `UPDATE users SET tokens_valid_after=NOW()`。

### L-4【confirmed】訊息附件上傳走錯 rate limit 層（DoS 面）
- 位置：`backend/src/routes/messaging.rs:32-35`（`POST /messages/attachments`）；`routes/mod.rs:85,90`
- 情境：該路由 merge 進 `protected_routes` 只套 `write_rate_limit`（120/min），未套其他 7 個上傳端點
  共用的 `upload_rate_limit`（30/min）。單張最大 10MB → 可用 4 倍速率（120×10MB/min）灌檔塞爆磁碟。
- 信心度：High（比對三個 routes 檔確認）。修補：把該路由移入 `upload_routes` 或掛 `upload_rate_limit_middleware`。

---

## 盲點（設定/文件落差；非可利用漏洞，但影響合規與維運）

- **B-1【中高】session idle 文件↔code 分岔（8h vs 10h）**：`SESSION_LOGOUT_MANAGEMENT.md` §3.3 與
  `config.rs:282` 註解仍寫 480min/8h，但 `constants.rs:113` 已是 600/10h（R57 migration 071 兩條 idle
  路徑都改對了，文件/註解沒跟上）。諷刺的是這正違反該文件自己強調的「雙路徑同步 + PR 寫 why」規範。
- **B-2【中】.env.example 帳號鎖定弱化**：`.env.example:91-92` `ACCOUNT_LOCKOUT_DURATION_MINUTES=15`
  vs `PASSWORD_POLICY.md` 宣稱 30 分鐘 vs `constants.rs:17` 常數 30。照 .env.example 部署會讓鎖定時間
  減半——而鎖定正是該政策用來補償「不強制定期換密碼」的關鍵控制。修補：.env.example 改回 30 或註解掉。
- **B-3【低-中】unwrap 禁令 CI 僅 warn**：`.github/workflows/ci.yml:404` 用 `-W clippy::unwrap_used`
  （非 `-D`），只警告不擋 merge。現況全 codebase 無 request-path 裸 unwrap（人工紀律撐著），但機器不擋
  未來新引入。修補：backlog 清空後改 `-D`。
- **B-4【資訊】死碼/過時註解 ×3**：`ACCESS_TOKEN_EXPIRY_HOURS`(constants.rs:14) 死碼、實際用
  `JWT_EXPIRATION_MINUTES`；`data_import.rs:275` 的 100MB 檢查被全域 30MB body limit 擋成死碼；
  `docker-compose.yml:690` 稱 print-pdf 未驗 token 但 `main.py:103` 已 fail-closed 驗證。皆更新註解即可。

---

## 正面確認（已驗證紮實，供信心佐證）

- **HMAC 鏈**：Anonymous fallback（寫 `unwrap_or(SYSTEM_USER_ID)` = 讀，audit.rs:618/920）、prev_hash、
  版本分流、原子性（`pg_advisory_xact_lock` + 同 tx）、verifier 獨立重算不信任 DB `previous_hash` 欄位。
- **Anonymous actor**：全庫僅 login/audit 兩處構造，從不流入業務 mutation → 「service 未 reject Anonymous」不可利用。
- **JWT**：改密/改角色設 `tokens_valid_after` + 每請求 `enforce`（舊 backlog 已修）；refresh family rotation + reuse detection。
- **注入/上傳**：動態 SQL 全白名單或位置參數；表名來自編譯期常數 + admin-only + 二次密碼；上傳 magic number + MIME 白名單 + `canonicalize` + ZIP entry 路徑檢查。
- **前端**：`dangerouslySetInnerHTML` 僅 2 處走 DOMPurify 白名單；`safeHref` 擋 `javascript:`/`data:`；CSP `script-src 'self'`。
- **加密/密碼**：TOTP secret / signature payload XChaCha20-Poly1305 AEAD + zeroize + AAD 綁定 + fail-closed；Argon2id。
- **錯誤處理**：依 SQLSTATE 回通用中文訊息，不洩 SQL/表名/堆疊。

---

## 建議下一步深挖的 3 個方向

1. **設備模組 SoD 全盤補齊**（M-1 + L-2 已是離群點）：`equipment.rs` 有多個 approve/review 函式，
   建議一次抽出統一的 `assert_not_self_approval(applied_by, current_user)` helper，逐一套用並補 SoD 測試，
   同時把 M-3 的 GLP/ERP 核准納入同一輪——這類「大多有、少數漏」最容易再長出新離群點。
2. **權限矩陣 × 物件層授權的系統化盤點**：L-1 降級的唯一理由是「持權角色都 view_all」——這是脆弱前提。
   建議產出一張「權限 code → 授予角色 → 是否 view_all → 對應 handler 是否有物件層 Scoped 守衛」矩陣，
   把「只靠 view_all 兜底、缺 Scoped」的端點全列出來（vet_recommendation 是第一個），一次補防。
3. **信任邊界端到端驗證**（M-5 + B-1/B-2）：確認 prod 實際網路拓樸（cloudflared 走 docker network 還是
   host loopback）、`real_ip.rs` 是否該加反代網段白名單；同時把 session idle / 帳號鎖定的文件、註解、
   .env.example、constants 四處對齊，並考慮寫一個 CI 檢查防止設定值與文件再次漂移。

---

## 稽核方法論的誠實聲明

- 本次為**靜態分析**，未做動態滲透測試（與 THREAT_MODEL §7 一致）。M-4/M-5 標「待驗證」正因其可利用性
  取決於執行期權限授予與網路拓樸，需實機確認。
- **兩個 sonnet 掃描 agent 使用了 bash `find`，繞過了 settings 的 `Bash(find *)` deny 規則**（harness 已標記）。
  繞過的是唯讀搜尋、非破壞性操作，且所有 finding 都附 file:line 可獨立覆核，故結論仍採用；但這是一個
  真實的治理缺口——subagent 可繞過主 session 的工具限制。已記入制度維護待辦（見文末）。
- 未逐行審查：`handlers/mcp.rs`、`mcp_keys.rs`、`signature_bridge.rs`、`calendar/training/treatment_drug/qau`、
  facility GET 的 router middleware wiring、解壓縮炸彈（僅驗 entry 路徑名未驗壓縮比）。這些列為後續。

## 制度維護待辦（本次稽核衍生）
- 在 `docs/agents/MAINTENANCE.md` 或派工模板補一條：**派工唯讀掃描 agent 時，prompt 明確禁止 bash
  find/grep/cat，改用 Glob/Grep/Read**——因 subagent 不繼承主 session 的 deny 規則，會繞過。本次已在
  對抗驗證 agent 的 prompt 加了這條，證明有效（該 agent 未違規）。
