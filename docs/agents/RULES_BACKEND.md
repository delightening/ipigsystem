# Backend 規範（Rust / Axum）

> 何時讀本檔：任何會動到 `backend/` 下 .rs 檔或 migration SQL 的任務，動手前先讀完。
> 內容抽自 2026-07-04 之前的 CLAUDE.md（原文備份：`docs/agents/backup/CLAUDE.md.2026-07-04.bak`）。

## 1. 架構分層與依賴方向

```
Handler → Service → Repository → Model
   ↓         ↑
Middleware ──┘

Utils（純函式，任何層皆可呼叫，但 Utils 本身不依賴任何層）
```

- 依賴只能**向下**，禁止反向依賴
- `utils/` 不依賴任何業務模組，不依賴 `AppState`
- `models/` 不依賴任何其他層
- Middleware 可呼叫 Service（例如認證中間件驗證 token）

## 2. 目錄職責

| 目錄 | 職責 | 禁止事項 |
|------|------|----------|
| `handlers/` | HTTP 請求解析與回應組裝 | ❌ 業務邏輯、SQL、複雜條件判斷 |
| `services/` | 核心業務邏輯、權限檢查 | ❌ 直接建構 HTTP response、直接寫 SQL |
| `repositories/` | 封裝所有 SQL 查詢（sqlx::query） | ❌ 業務邏輯判斷 |
| `models/` | DB entity（`FromRow`）+ API request/response DTO | ❌ 業務邏輯、SQL、依賴其他層 |
| `middleware/` | 橫切關注點（認證、CSRF、限流、ETag） | ❌ 業務邏輯 |
| `utils/` | 純函式工具（日期、字串、加密） | ❌ 依賴 AppState 或業務型別 |
| `startup/` | 應用程式啟動初始化（DB、migration、seed） | ❌ runtime 呼叫 |
| `bin/` | CLI 維運工具 | 過時工具定期清理 |

基礎設施檔案：`error.rs`（統一 `AppError` enum + `IntoResponse`）、`config.rs`（環境變數集中讀取，
禁止散落 `std::env::var`）、`constants.rs`（全域常數）。

## 3. 專項規則

- 錯誤處理統一 `AppError`；handler 回傳 `Result<impl IntoResponse, AppError>`；`?` 逐層傳播。
- 禁止裸 `unwrap()`（測試除外）；`expect()` 僅限啟動初始化（main.rs）且附描述訊息。
- 測試碼禁 `unwrap_err()`，用 `expect_err("描述")`。
- 禁止 `#[allow(dead_code)]` / `#[allow(unused)]`，未使用直接刪（僅限本次任務造成的 unused）。
- SQLx 具名參數，禁止字串拼接 SQL。
- 相同 SQL SELECT ≥2 次 → 提取到 `repositories/`。同一權限檢查 ≥2 處 → `services/access.rs`。
- 魔術字串定義為 `const` 或 `enum`。
- Service 呼叫 Repository 取資料，不直接寫 SQL。
- DB 查詢禁止 `unwrap_or` 靜默降級，必須 `?` 傳播（使用者明確要求過）。

## 4. 命名慣例

Handler：`list_animals` / `get_animal` / `create_animal` / `update_animal` / `delete_animal` /
`export_{entity}_{format}` / 領域動詞 `submit_amendment`。不加 HTTP method 前綴。

Repository：`find_{entity}_by_{field}` / `list_{entities}` / `insert_` / `update_` / `delete_` /
`exists_{entity}_by_{field}`。

檔名 `snake_case.rs`；常數 `UPPER_SNAKE_CASE`。

## 5. Import 排序（rustfmt 自動化）

std → 第三方 crate（字母序）→ 空行 → `crate::` → `super::`/`self::`。
設定：`imports_granularity = "Module"` + `group_imports = "StdExternalCrate"`。

## 6. ActorContext（Service-driven audit，R28-4）

三種 actor 變體（`middleware/actor.rs`）：

| Variant | 何時使用 | `actor_user_id` |
|---|---|---|
| `User(CurrentUser)` | HTTP request 帶 JWT，所有需登入的 mutation | `Some(user.id)` |
| `System { reason }` | scheduler / bin tool / migration / 系統自動觸發 | `Some(SYSTEM_USER_ID)` |
| `Anonymous` | 尚未登入但需 audit | `None`（FK NULL） |

已知 Anonymous 場景：登入失敗（`handlers/auth/login.rs`，`LOGIN_FAILED`/`ACCOUNT_LOCKED`）、
CSP report（`handlers/csp_report.rs`）、honeypot（`routes/honeypot.rs`）、rate limit / WAF probe（middleware 層）。

規範：
1. **HMAC chain 寫入端**：Anonymous 寫 `user_activity_logs` 時，HMAC 計算用 `SYSTEM_USER_ID`
   （不可 NULL），FK 欄位仍寫 NULL。與 `services/audit.rs::verify_chain_rows` fallback 一致。
   詳見 `docs/security/HMAC_VERSIONING.md` §4。
2. **Service 層拒絕 Anonymous mutation**：除明確匿名場景外，service mutation 應 `match actor`
   顯式拒絕 Anonymous（return `AppError::Forbidden`），參考 `services/user.rs::UserService::create` 模式
   （注意：`create_user` 這個名字在 handlers 層，別參考錯層）。
3. **新增 Anonymous 事件**：(a) 更新本表 (b) 確認 service 拒絕邏輯 (c) 進 HMAC chain 則 verifier 對齊。

## 7. 測試驗證標準（依改動層級）

| 改動範圍 | 最低驗證 |
|---|---|
| 純 infra / models / services（不改 handler） | `rtk cargo test --lib` 綠 |
| 動到 handlers / middleware / routes | `rtk cargo test --all-targets` 全綠（整合測試需先 `docker compose -f docker-compose.test.yml up -d postgres`） |
| 只動 docs / migration SQL | `rtk cargo check` 綠 |
| 刪/改 lib 公開 type 或 field | 必跑 `rtk cargo check --tests`，不可只 `--lib`（教訓：--lib 看不到測試碼的破壞） |

### 7.1 測試碼撰寫規則（自造紅燈的三個來源）

CI 紅燈裡佔比最高的是「自己寫的測試把自己弄紅」。三個已發生過的來源與對策：

1. **fixture 用了不存在的列舉 / 角色代碼**（實例：seed 了不存在的 `SYSTEM_ADMIN` role code、
   `overtime_type` 塞非法值 → 連兩次紅 CI 才找到根因）。對策：測試中每一個當 enum / role code /
   status / FK 用的字串，動筆前先用 Grep 工具在 `migrations/`、`constants.rs`、`models/` 查到
   真值照抄，並在回報中引用來源檔:行號，不憑印象拼。
2. **碰共享狀態的測試沒隔離**：動到環境變數、DB singleton、檔案系統的測試一律加 `#[serial]`，
   否則平行執行互撞，症狀是間歇性紅燈（重跑會過，最難查）。
3. **只在 CI 才第一次跑**：push 前至少跑過 §7 表對應層級。整合測試**禁用 prod DB**——
   一律 `TEST_DATABASE_URL=<獨立丟棄 DB> rtk cargo test`；沒有獨立 DB 就只跑 `--lib`，
   並在回報中明寫「整合測試留給 CI 驗」，不要假裝已驗。

## 8. Clippy 門檻

```
rtk cargo clippy --all-targets -- -D warnings -A deprecated
```

`-A deprecated` 是 R26 遷移期的過渡容忍（舊版 `AuditService::log_activity`）。
**待辦**：確認 R26-4（舊 log_activity 移除）是否已完成——用 Grep 工具搜 `backend/src`、
pattern `#\[deprecated`，若命中檔案中已無 `log_activity` 相關者，改回嚴格 `-D warnings` 並更新本節
（改本節屬事實性修正，可自行改，見 MAINTENANCE.md §1）。新 PR 一律不得引入新 warning。

## 9. Migration 注意事項

- **選號**：先查 origin/main 與 prod DB 的 `_sqlx_migrations` max，再 +1；並確認其他未合分支沒占用同號
  （2026-07-01 撞號事故教訓）。
- dev DB 自動跑 migration（app 啟動 `sqlx::migrate!`）不需問；**staging / prod DB 跑 migration 必經使用者同意**。
- 本機編譯陷阱：`.env` 會讓 `sqlx query!` 巨集的 dotenvy 解析失敗 → 暫移 .env + `SQLX_OFFLINE=1` 用 `.sqlx` 快取。
