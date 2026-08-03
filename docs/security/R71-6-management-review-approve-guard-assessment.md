# R71-6 安全評估：GLP 管理審查結案守衛（軟性 SoD）

> 立案：2026-06-16 ｜ 對應 TODO `R71-6`、盤點報告 `docs/audit/approval-buttons-inventory-2026-06-16.md` §F / §7
> 狀態：**評估稿 + 實作**（off main 獨立 PR；做法 A — 軟性 SoD，使用者拍板）

## 0. 範圍與結論

| 項目 | 內容 |
|---|---|
| 端點 | `PUT /admin/management-reviews/:id`（泛型更新） |
| Service | `services/glp_compliance.rs::update_management_review` |
| 狀態流程 | `planned → in_progress → completed → closed` |
| 既有權限 | `glp.management_review.view` / `.manage`（無 `.approve`） |

**結論**：`update_management_review` 的 `status = COALESCE($4, status)` **無發布狀態守衛**，任何持 `glp.management_review.manage` 編輯權者可經泛型 PUT 直接把審查設為 `completed`/`closed`（＝正式結案），繞過任何簽核把關 → **SoD 漏洞**。對比同檔 `change_request` / `study_report` 皆有 `RELEASE_STATUSES` 守衛。

## 1. 為何不直接照抄 change_request

`change_request` / `study_report` 的守衛是「硬擋發布狀態 + 導向專屬核准端點」（`approve_change_request` 等）。但**管理審查無專屬核准/簽署端點**（程式碼自承為 follow-up，`glp_compliance.rs:1218-1220`），狀態目前**只能**靠泛型 PUT 設定。純硬擋 `completed`/`closed` 會使其**完全無法設定**，破壞現有結案流程。

## 2. 修補設計（做法 A：軟性 SoD）

不另開端點。在 `update_management_review`（已於上方 `SELECT ... FOR UPDATE` 鎖列、無 TOCTOU）內加結案保護門檻——**目前已結案 OR 正轉入結案** 皆須具 approve 權限：

```rust
const RELEASE_STATUSES: [&str; 2] = ["completed", "closed"];
let currently_released = RELEASE_STATUSES.contains(&before.status.as_str());
let transitioning_to_released = req.status.as_deref()
    .map(|s| RELEASE_STATUSES.contains(&s) && s != before.status.as_str())
    .unwrap_or(false);
if currently_released || transitioning_to_released {
    let current_user = actor.require_user()?;
    if !current_user.has_permission("glp.management_review.approve") {
        return Err(AppError::Forbidden(...));   // 須具 approve 權限
    }
}
```

> `currently_released` 分支關鍵：防 manage-only 在審查**已結案後**經「不帶 status 的更新」竄改 title/decisions，或將其**降級**回 in_progress 再改（gemini 審查指出的繞過路徑）。

- 新權限 `glp.management_review.approve`（migration 102，比照 `change.request.approve` 命名）。
- **無回歸**：migration 將 approve 授予所有現有持 `.manage` 的角色；admin 經 `has_permission` 短路具備。
- SoD 價值：`approve` 與 `.manage` 分離後可獨立管控 — 新的 manage-only 角色不會自動獲得結案能力。
- 一般編輯（planned/in_progress、填議程決議）不受影響。

## 3. 範圍邊界

- **不含**正式「管理審查電子簽章簽署流程」（深層 follow-up，`glp_compliance.rs:1218-1220`）。本 PR 僅補「誰能結案」的權限門檻。
- 既有 `update_management_review` 已 `tx + FOR UPDATE + log_activity_tx`，本 PR 不動其交易/稽核結構，僅加守衛。

## 4. 回測點

- **新 acceptance test**（`backend/tests/api_management_review_approve_guard.rs`，service-level）：
  - manage-only 設 `completed` → `Forbidden`
  - manage-only 設 `in_progress`（非終態、未結案）→ Ok
  - 具 `approve` 權者設 `completed` → Ok
  - 已結案後 manage-only 改 title（status=None）→ `Forbidden`（防竄改）
  - 已結案後 manage-only 降級 `in_progress` → `Forbidden`（防降級繞過）
- **測試指令層級**：未動 handler 簽名（守衛在 service 層），但屬合規敏感 → CI `cargo test --all-targets`（需 Postgres）。
- 本地 `cargo check --lib --tests` + `cargo clippy --all-targets -- -D warnings -A deprecated` 綠。

## 5. 合併順序注意

migration 版號 **102**，須在 **#722（R71-1, migration 101）之後合併**，以維持 `sqlx::migrate!` 版序（101 → 102）。

---

*做法 A 經使用者拍板：用最小改動（一權限 + 一 migration）堵住「任何編輯者可自行結案」核心 SoD 洞，不破壞流程、不動前端；完整簽署流程留 follow-up。*
