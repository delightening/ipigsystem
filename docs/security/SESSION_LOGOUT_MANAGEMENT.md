# Session 與登出功能整合說明

> **參考標準**：OWASP Session Management Cheat Sheet、OWASP Testing for Logout Functionality
> **最後更新**：2026-05-18（sliding session overhaul — 修復 heartbeat handler ID bug、session_limit LRU 排序、移除前端時間倒數 warning、調整 idle 8h / absolute 24h）

本文件彙整本專案的登出／Session 機制，對照業界資安標準，並說明如何在維護資安的前提下避免使用者重複登入的困擾。

---

## 一、登出情境與業界對照總覽

| 登出情境 | 業界／資安參考 | 本專案現況 | 避免重複登入作法 |
|---------|----------------|-----------|------------------|
| **1. 使用者主動登出** | OWASP：必須 server-side 撤銷、清除 cookies | ✅ `POST /auth/logout`：JWT 黑名單、結束 sessions、撤銷 refresh token、清除 cookies | 使用者主動操作，無困擾 |
| **2. Session 逾時（無操作）** | OWASP：Idle timeout（15–30 分低風險、2–5 分高風險）、Server 端強制 | ✅ 後端 `cleanup_expired` cron（每 5 min）依 `session_timeout_minutes`（=480 min/8h）關閉 idle session；前端無倒數 dialog（依後端 401 處理） | ✅ Heartbeat（有操作時每 60s）更新 `last_activity_at`；連續使用不會被踢，僅真 idle ≥ 8h 才會 |
| **3. Refresh token 失效（401）** | OWASP：token 過期後應導向登入，不再自動續期 | ✅ `clearAuth()` 清除前端狀態、導向登入（不 call 後端 logout） | 僅在 token 已失效時登出，屬預期；避免 503 誤判為登出 |
| **4. 管理員強制登出** | OWASP：支援 admin 撤銷可疑 session | ✅ `POST /admin/audit/sessions/:id/logout` 強制結束指定 session、audit log | 被踢出者下次操作即 401，需重新登入 |
| **5. 密碼變更後** | OWASP：敏感操作後建議撤銷其他 sessions | 需確認專案實作 | 可採「其他裝置下次操作才登出」以減少打斷 |
| **6. 帳號刪除（GDPR）** | OWASP / GDPR：停用帳號時結束所有 sessions | ✅ `delete_me_account` 結束所有 sessions、撤銷 refresh tokens、清除 cookies | 一次性停用，不影響日常 UX |
| **7. 503 等暫時性錯誤** | 業界：區分暫時錯誤 vs 認證失效，避免誤登出 | ✅ 503 會重試 2 次，不當成 logout；401 才觸發 clearAuth | 伺服器短暫不可用時不會誤登出 |
| **8. 多裝置／多 tab** | OWASP：多 tab/session 管理 | ✅ 多 tab 共用 cookies；heartbeat 更新當前 session；後端 `session_timeout_minutes` 可調 | 有操作的 tab 會續期； idle 裝置逾時登出 |

---

## 二、資安與 UX 平衡原則對照

| 原則 | 業界建議 | 本專案對應 |
|------|----------|-----------|
| **Server-side 撤銷** | 登出必須在 server 端撤銷 session/token | ✅ JWT blacklist、`user_sessions` 標記、`refresh_tokens` revoked_at |
| **逾時雙軌** | Idle timeout + Absolute timeout | ✅ Idle = `session_timeout_minutes`（DB 可調，預設 480 min/8h）；Absolute = `ABSOLUTE_SESSION_TIMEOUT_MINUTES`（hardcoded 1440 min/24h，hijack 上限保護） |
| **Cookie 清除** | 登出時覆寫並清除 cookies | ✅ `build_clear_cookie` 清除 access_token、refresh_token |
| **活動續期** | 有操作時延長 session，減少頻繁登入 | ✅ useHeartbeat：滑鼠／鍵盤／點擊／滾動每 60 秒發送 heartbeat |
| **預警與續期** | 逾時前給予續期選項，避免突兀中斷 | ⚠️ 2026-05-18 取消預警 dialog — 改靠 sliding session（有操作就不會過期）+ 401 後 `/login?reason=session_expired` 顯示中性灰色 toast。Rationale：原 6h 警告其實在使用者活躍狀態下也會 fire（time-based 跟活動脫鉤），UX 比真沒警告更困惑 |
| **防誤登出** | 區分暫時性錯誤 vs 認證失效 | ✅ 503 重試、401 才 clearAuth；`isLoggingOut` 鎖避免併行登出 |

---

## 三、技術實作摘要

> ⚠️ **重要：本系統有兩條獨立的 idle 路徑**（2026-05-21 補注）
>
> Sliding session 設計裡，「使用者多久沒活動算 idle」其實由 **兩個獨立機制** 並行判定，
> 任一條觸發都會把使用者踢回登入頁。歷次 review 多次踩到「只改一條另一條繼續踢」
> （PR #455 / #472 後仍有使用者回報，root cause 即為此），故獨立寫一節提醒。
>
> | 條件 | A. user_sessions 路徑 | B. refresh_tokens 路徑 |
> |---|---|---|
> | **看哪個欄位** | `user_sessions.last_activity_at` | `refresh_tokens.last_used_at` |
> | **參數來源** | `system_settings.session_timeout_minutes`（DB，admin UI 可調） | `.env` `AUTH_IDLE_TIMEOUT_MINUTES`（config.rs 預設值） |
> | **目前值** | 480 min（8h） | 600 min（10h），config.rs 預設（2026-05-25 自 480 上調；見 `constants.rs::SESSION_IDLE_TIMEOUT_MINUTES`） |
> | **滑動續期者** | 前端 `useHeartbeat` 每 60s POST `/auth/heartbeat`（活動偵測：mouse/keyboard/click/scroll/touchstart） | 前端 `useProactiveRefresh` 在 access token 80% TTL 處 silent refresh + 任何 401 → reactive refresh |
> | **巡檢觸發** | scheduler 每 5 min 跑 `SessionManager::cleanup_expired`，把 idle 過期者標 `ended_reason='timeout'` | 每次 `/auth/refresh` 即時：`AuthService::reject_if_idle_timeout` 看到 `last_used_at` 已超過閾值就直接 revoke 該 refresh token 並回 401 |
> | **失敗時症狀** | 後台 cron 標記後，下次 API call 帶舊 session 看到 ended → middleware 回 401 | 使用者離開電腦 > 閾值，回來第一個動作觸發 refresh → 立即被踢 |
> | **失敗時 audit / log** | `user_sessions.ended_reason='timeout'` row 留底 | `refresh_tokens.revoked_reason='idle_timeout'` row 留底 + tracing.info |
>
> **改一個就要改另一個**：任何 session idle 行為調整 PR，至少要在 description 寫清楚為什麼只動一條
> （例如「B 路徑刻意保留 30 min 給高敏感 endpoint」之類），不能 silent 漏網。
>
> **現況（2026-07-04 稽核 B-1 對齊）**：A=8h、B=10h 兩條閾值目前**不一致**——實際 idle 上限
> 取兩者較嚴者，即 **8h**（path A 的 `cleanup_expired` 每 5 min 先把 session 標 timeout）。B 的 10h
> 較寬，一般不會先觸發。若要真正放寬到 10h，需同步把 `system_settings.session_timeout_minutes` 調為 600。

### 3.1 前端

| 元件 | 職責 |
|------|------|
| `useAuthStore.logout()` | 呼叫 `POST /auth/logout`，清除 `user`、`isAuthenticated`、`accessTokenExpiresAt` |
| `useAuthStore.clearAuth()` | 僅清除前端 state，不呼叫後端（供 401 refresh 失敗時使用） |
| ~~`SessionTimeoutWarning`~~ | 2026-05-18 已移除 — time-based 倒數跟活動脫鉤，造成 UX 困惑。改靠 sliding session + 401 toast |
| `useHeartbeat` | 偵測使用者活動（mouse/keyboard/click/scroll/touchstart），每 60 秒發送 `POST /auth/heartbeat` 更新 session 活躍時間 |
| `useProactiveRefresh` | 在 access token 80% TTL 處 silent refresh，避免 reactive 401 → refresh 卡頓 |
| `api.ts` interceptor | 401 時嘗試 refresh；refresh 失敗 → `clearAuth()` + 導向 `/login?reason=session_expired`；503 時重試，不當成登出 |
| `LoginPage` | 讀 `?reason=session_expired` URL param，顯示中性灰色 toast「登入時效已到期」 |

### 3.2 後端

| 元件 | 職責 |
|------|------|
| `handlers::auth::logout` | JWT blacklist、`LoginTracker::log_logout`、`SessionManager::end_all_sessions`、`AuthService::logout`、清除 cookies |
| `handlers::auth::heartbeat` | 2026-05-18 修：呼叫 `update_activity_by_user(user_id)`（原本錯誤呼叫 `update_activity(session_id)` 並傳 user_id，SQL `WHERE id = $1` 永遠 0 rows → sliding session 失效） |
| `SessionManager::end_all_sessions` | 將該使用者所有 active sessions 標記為結束 |
| `SessionManager::force_logout` | 強制結束指定 session（管理員） |
| `SessionManager::cleanup_expired` | 依 `session_timeout_minutes` 將 idle 逾時 sessions 標記為 timeout。2026-05-18 起由 scheduler 每 5 min 呼叫（原本未連線，形同虛設）|
| `SessionManager::end_excess_sessions` | 砍掉超出 `MAX_SESSIONS_PER_USER` 的 session。2026-05-18 起按 `last_activity_at DESC NULLS LAST` 排序（LRU），不再砍最舊（避免砍到正在用的舊 tab） |
| `SessionManager::update_activity_by_user` | 依 user_id 找最新 active session，更新 last_activity_at + IP |
| `SchedulerService::register_session_cleanup_job` | 每 5 min cron，從 system_settings 讀 timeout 後呼叫 cleanup_expired |
| `AuthService::logout` | 將該使用者所有 `refresh_tokens` 設為 `revoked_at` |

### 3.3 設定參數（2026-05-18 重新審視後）

| 參數 | 位置 | 值 | 說明 |
|------|------|-----|------|
| `session_timeout_minutes` | `system_settings`（DB，admin UI 可調） | **480 (8h)** | Idle timeout：last_activity_at 超過此值 → cleanup_expired 標 ended_reason='timeout'。Heartbeat 有活動就 reset |
| `AUTH_IDLE_TIMEOUT_MINUTES` | `.env` / `constants::SESSION_IDLE_TIMEOUT_MINUTES`（env-driven，預設 480） | **480 (8h)** | R41-1 NICS 閒置鎖定：refresh_tokens.last_used_at 超過此值 → `reject_if_idle_timeout` 撤銷該 token 並回 401。**與 session_timeout_minutes 是兩條獨立路徑**，兩者皆 8h 才能避免「離開電腦 >30 min 第一次 refresh 就被踢」(2026-05-21 修)。R41-1 落地時預設為 30 min（NICS 普級保守值），2026-05-22 對齊 sliding 設計改為 480；嚴格 idle 需求環境可在 .env 顯式調低 |
| `ABSOLUTE_SESSION_TIMEOUT_MINUTES` | `session_manager.rs`（hardcoded） | **1440 (24h)** | Absolute timeout：started_at 起算超過此值即使有活動也踢出。hijack 上限保護 |
| `MAX_SESSIONS_PER_USER` | `constants.rs` | **10** | 同使用者並行 session 上限；超出時按 `last_activity_at DESC NULLS LAST` 砍最不活躍的 |
| `ACCESS_TOKEN_EXPIRY_HOURS` | `constants.rs` | 24 | JWT 簽發壽命；`useProactiveRefresh` 在 80% TTL (19.2h) silent refresh |
| `REFRESH_TOKEN_EXPIRY_DAYS` | `constants.rs` | 30 | Refresh token 絕對壽命；30 天無回來才需重新打密碼 |
| `SESSION_CLEANUP_CRON` | `scheduler.rs` | `0 */5 * * * *` | 每 5 min 跑 cleanup_expired |

**設計選擇 rationale**（2026-05-18 PO + dev 共同審視）：

- **8h idle**（不是 30 min 或 6h）：使用者為內部員工（vet/QA/admin），不是公開服務。動物試驗系統一天工作流動性高，30 min idle 會頻繁打斷；8h ≈ 一天工作時間，符合「下班才需重新登入」的直覺
- **24h absolute**（不是 8h 或無上限）：sliding session 允許「連續操作不被登出」是 UX 需求，但完全無上限會讓被偷 token 永久有效。24h 上限 = 加班到午夜也不打斷，但跨日一定要重新驗證
- **無前端倒數警告**：原 6h dialog 跟活動脫鉤（time-based），活躍使用者也會看到「即將過期」很困惑。改靠 sliding 保活 + 401 後 LoginPage 顯示中性灰色 toast「登入時效已到期」

---

## 四、未來可優化項目

| 項目 | 建議 | 目的 |
|------|------|------|
| **密碼變更後** | 若尚未實作：撤銷其他 refresh token，或採「其他裝置下次操作才登出」 | 兼顧安全與 UX |
| **MAX_SESSIONS_PER_USER 可調** | 目前 hardcoded 10，未來可考慮放進 `system_settings` 讓 admin 調整 | 不同部門 / 工作模式需求不同 |
| **GLP / NICS 合規確認** | 8h idle 是否符合 GLP §11 / NICS 防護基準對 session timeout 的要求，需 compliance team 簽核 | 避免內外稽查發現 |

## 五、變更歷史

| 日期 | 變更 | Why |
|------|------|-----|
| **2026-07-04** | §3.3 設定表校正：B（refresh_tokens）路徑目前值 480→600 min（10h），補「A=8h／B=10h 不一致、實際取較嚴 8h」現況註記 | 2026-07-04 資安稽核 B-1：`constants.rs::SESSION_IDLE_TIMEOUT_MINUTES` 2026-05-25 已改 600/10h，但本文件與 config.rs 註解仍寫 480/8h → 文件↔code 漂移（諷刺地違反本文件自身「改一條要同步」規範）|
| **2026-05-21** | `.env` 新增 `AUTH_IDLE_TIMEOUT_MINUTES=480` 對齊 session_timeout_minutes；§3.3 設定表補上此參數 | 使用者回報「沒到 8h 又被登出」；root cause = R41-1 idle 檢查路徑（refresh_tokens.last_used_at）2026-05-18 sliding session overhaul 沒涵蓋，仍維持 30 min 預設；使用者離開 >30 min 後第一次 refresh 即被 revoke |
| **2026-05-18** | Sliding session overhaul: 修 heartbeat handler ID bug、session_limit 改 LRU 排序、移除 SessionTimeoutWarning、idle 6h→8h、absolute 8h→24h、scheduler 5min cron 連線 | 使用者回報「<6h 被登出」；深入調查找出 4 個 root cause（heartbeat 完全壞、session_limit 砍最舊不砍最不活躍、前端時間倒數跟活動脫鉤、cleanup_expired 從未被呼叫）|
| 2026-05-16 | PR #428 sliding session 五部曲：proactive refresh + BroadcastChannel + retry + visibility | 消除 reactive 401 → refresh 的 200ms 卡頓；但 heartbeat handler bug 未發現 → sliding 仍實質失效 |
| 2026-03-06 | 初版整合說明 | 對齊 OWASP standards |

---

## 六、相關文件

- [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
- [OWASP Testing for Logout Functionality](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/06-Session_Management_Testing/06-Testing_for_Logout_Functionality.html)
- [CREDENTIAL_ROTATION.md](./CREDENTIAL_ROTATION.md) — 憑證輪換
- [spec/07_SECURITY_AUDIT.md](../spec/07_SECURITY_AUDIT.md) — 安全稽核規格
