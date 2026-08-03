# R71-3 安全評估：設備閒置申請核准（equipment idle request approval）

> 立案：2026-06-16 ｜ 對應 TODO `R71-3`、盤點報告 `docs/audit/approval-buttons-inventory-2026-06-16.md` #10
> 狀態：**評估稿 + 實作**（off main 獨立 PR）

## 0. 範圍與結論

| 項目 | 內容 |
|---|---|
| 端點 | `POST /equipment-idle-requests/:id/approve` |
| Handler | `handlers/equipment.rs::approve_idle_request` |
| Service | `services/equipment.rs::approve_idle_request` |
| 權限 | `equipment.idle.approve`（既有；admin 經 `has_permission` 短路具備） |

**結論**：核准會連動改設備狀態（Active↔Inactive）＋寫狀態 log，但原本 **SELECT→UPDATE idle_request→UPDATE equipment→INSERT status_log 各自對 pool 散打**（無交易、無鎖、無稽核、未用 ActorContext）。為同檔離群者。修法＝比照同檔已完整的 `review_maintenance_record`（tx + FOR UPDATE + `log_activity_tx` + `require_user()`）對齊。**無新權限、無 migration**。

## 1. 現況缺口（威脅面）

| # | 缺口 | 風險 | 嚴重度 |
|---|---|---|---|
| G1 | **非原子**：idle_request UPDATE / equipment UPDATE / status_log INSERT 為 3 次獨立 pool 呼叫 | 中途失敗→「申請已核准但設備狀態未改」或「狀態 log 缺失」，資料漂移 | 🔴 高 |
| G2 | **無併發守衛**：初始 SELECT 無 `FOR UPDATE` | 兩個並發核准都通過 pending 檢查→重複套用 | 🟠 中 |
| G3 | **無稽核**：未寫 `user_activity_logs`/HMAC chain | 設備狀態被改卻查無「誰核准、改前→改後」 | 🔴 高 |
| G4 | **未用 ActorContext**：service 收 `&CurrentUser` 裸值 | 與全站 service-driven audit 不齊；無法走 Anonymous 拒絕/system 歸因 | 🟡 低 |

## 2. 修補設計

`approve_idle_request` 收歸**單一 tx**（悲觀鎖，對齊本輪鎖策略）：

```
actor.require_user() + has_permission("equipment.idle.approve")
tx = pool.begin()
  ├ SELECT … FROM equipment_idle_requests ir … WHERE ir.id=$1 FOR UPDATE OF ir   ← 鎖申請列、取 before、重驗 pending（解 G2）
  ├ UPDATE equipment_idle_requests SET status=… WHERE id=$1 AND status='pending'
  ├ if approved:
  │    SELECT * FROM equipment WHERE id=$1 FOR UPDATE                            ← 鎖設備列
  │    validate_status_transition + INSERT equipment_status_logs + UPDATE equipment  ← 同 tx（解 G1）
  ├ SELECT … (after 快照)
  └ log_activity_tx(EQUIPMENT / IDLE_REQUEST_APPROVE|REJECT, diff before→after)  ← 解 G3
tx.commit()
通知申請人（post-commit 側效應；失敗僅 warn，不回滾已核准）
```

- 參考樣板：`services/equipment.rs::review_maintenance_record`（tx + FOR UPDATE + `log_activity_tx` + `require_user()`）。
- `IdleRequestWithDetails` 補 `impl AuditRedact`（無敏感欄位）供 before/after diff。
- handler 改傳 `ActorContext::User`（解 G4）。

## 3. 不需動的部分

- **權限**：`equipment.idle.approve` 已存在，admin 短路具備 → **無回歸、無 migration**。
- **前端**：`EquipmentPage.tsx` 的 `approveIdleMutation` 已 invalidate `['equipment']`/`['equipment-all']`，核准後 cache 與 DB 一致 → 無需改。

## 4. 回測點

- **新 acceptance test**（`backend/tests/api_equipment_idle_audit.rs`）：核准閒置申請後斷言 (1) idle_request status=approved (2) equipment status=inactive (3) `user_activity_logs` 有 `IDLE_REQUEST_APPROVE` entry。
- **測試指令層級**：動到 handler 層 → CI `cargo test --all-targets`（需 Postgres）。
- 本地 `cargo check --lib --tests` + `cargo clippy --all-targets -- -D warnings -A deprecated` 綠。

## 5. 待裁子決策

無。純 pattern 對齊，無權限模型/schema 變更。

---

*與 R71-1 同模式（tx + FOR UPDATE + in-tx audit），但更單純：無新權限、無 migration、前端無須改。*
