# R71-2 安全評估：PI 開通信核准寄送

> 立案：2026-06-16 ｜ 對應 TODO `R71-2`、盤點報告 #9
> 狀態：**評估稿 + 實作**（off main 獨立 PR；做法 A + 新權限，使用者拍板）

## 0. 範圍與結論

| 項目 | 內容 |
|---|---|
| 端點 | `POST /pi-account-invites/:id/approve-send` |
| Handler | `handlers/protocol/pi_provision.rs::approve_send_pi_invite` |
| Service（新） | `services/protocol/pi_provision.rs::approve_send_pi_invite` |
| 寄送內容 | 「設定密碼」連結（**憑證級**） |

**結論**：原 `approve_send_pi_invite` **業務邏輯 + raw SQL 混在 handler**（違反分層）、**無 tx、無 audit、`is_admin()` 硬編碼**、寄送前 pending 檢查為無鎖讀（並發可雙寄）。寄的是設定密碼信，屬最敏感核准動作。

## 1. 現況缺口（威脅面）

| # | 缺口 | 風險 | 嚴重度 |
|---|---|---|---|
| G1 | **無稽核**：寄送開通信（憑證信）未寫 `user_activity_logs` | 寄出設定密碼信卻查無「誰核准、寄給誰」 | 🔴 高 |
| G2 | **無併發冪等守衛**：pending 檢查為無鎖讀 | 兩個並發核准都通過 → 重複寄送 | 🟠 中 |
| G3 | **分層違規**：業務邏輯 + raw SQL 在 handler | 維護性、與全站 service-driven 不齊 | 🟡 低 |
| G4 | **權限硬編碼 `is_admin()`** | 粒度與全站不齊、無法委派 | 🟡 低 |

## 2. 修補設計（做法 A：email-first，失敗 rollback）

下沉至 `ProtocolService::approve_send_pi_invite`，收歸單一 tx：

```text
actor.require_user()；handler require_permission!(aup.pi_invite.approve)
# tx 外（避免 forgot_password 取第二條 pool 連線造成死結，gemini #726）
SELECT i.email,i.status … JOIN users（active 未刪除）WHERE i.id=$1   ← 非鎖讀，早退 not-found/非 pending
token = forgot_password(pool, email)                                ← tx 外產 token
tx = begin
  ├ SELECT status FROM pi_account_invites WHERE id=$1 FOR UPDATE     ← 鎖列、權威重驗 pending（解 G2）
  ├ UPDATE … SET status='sent',approved_by,sent_at WHERE id AND status='pending'
  ├ log_activity_tx(PROTOCOL / PI_INVITE_SEND)                       ← 解 G1
  ├ send_password_reset_email(config, token)                        ← SMTP（不取 DB 連線）；失敗 ? → rollback
  └ commit（寄信成功才落地；失敗保留 pending 可重試）
```

**做法 A 取捨**（使用者拍板）：email 是外部副作用無法 rollback。A 將「標記 sent + 稽核」置於 tx 內、寄信成功才 commit；寄信失敗 → rollback 保留 pending 可重試。最壞情況僅「email 成功但 commit 失敗（罕見）→ 重試寄第二封」（無害），優於 B 的「顯示已寄但實際沒寄」。並發冪等由 `FOR UPDATE` 權威重驗序列化。

- **連線池死結防範（gemini #726）**：`forgot_password`（pool 取連線）移至 tx **開始前**；tx 內不再向 pool 取第二條連線。`send_password_reset_email` 為純 SMTP、不取 DB 連線，留在 tx 內以保「寄信失敗 rollback」。
- token 於 tx 外產生；若 tx 因寄信失敗 rollback，留**無害且會過期**的孤兒 token。
- 寄信為低頻 admin 動作，tx 短暫橫跨一次 SMTP 可接受。

## 3. 權限（做法：新增細粒度權限）

- 新增 `aup.pi_invite.approve`（migration 103，對齊 AUP 域 `aup.{entity}.{action}` 慣例；**注意**：較先前討論的 `protocol.pi_invite.approve` 改用 `aup.` 前綴以符合既有規範）。
- **無回歸**：原為 is_admin only；admin 經 `has_permission` 短路仍具備。不自動授其他角色 → 維持「僅 admin」，如需委派由 admin 於 UI 指派。

## 4. 範圍邊界

- 僅下沉 / 強化 `approve_send_pi_invite`（敏感 mutation）。`list_pi_account_invites`（admin 唯讀清單、raw SQL + is_admin）**本輪不動**，列為可選 follow-up。

## 5. 回測點

- **新 acceptance test**（`backend/tests/api_pi_invite_approve_audit.rs`）：
  - 核准 → invite `sent` + 留 `PI_INVITE_SEND` 稽核
  - 冪等：第二次核准 → 422（BusinessRule）、不重寫稽核
  - 非 admin 具 `aup.pi_invite.approve` → 200（可委派）
  - 非 admin 無權限 → 403（守衛拒絕）
- **None 守衛**：`forgot_password` 回 None（無法產 token）視為失敗（`AppError::Internal`），不標 sent。service fn 抽 `fetch_pending_pi_invite_email` / `mark_pi_invite_sent_tx` 兩 helper 以符合 ≤50 行函數規範。
- 測試環境 email 停用時 `send_password_reset_email` 回 Ok（no-op），故 happy path 可在 CI 跑綠。
- **測試指令層級**：動到 handler 層 → CI `cargo test --all-targets`。本地 `cargo check --lib --tests` + clippy 綠。

## 6. 合併順序注意

migration 版號 **103**，須在 #722（101）、#725（102）**之後**合併，維持 `sqlx::migrate!` 版序（101 → 102 → 103）。

---

*做法 A + 新權限經使用者拍板。email 外部副作用採「先寄信、失敗 rollback」，並發冪等靠 FOR UPDATE。*
