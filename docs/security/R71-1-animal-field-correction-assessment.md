# R71-1 安全評估：動物欄位修正核准（animal field correction review）

> 立案：2026-06-16 ｜ 對應 TODO `R71-1`、盤點報告 `docs/audit/approval-buttons-inventory-2026-06-16.md` §G/#13
> 狀態：**評估稿，待拍板後實作**（本輪起手 PR）

## 0. 範圍與結論

| 項目 | 內容 |
|---|---|
| 端點 | `POST /animals/animal-field-corrections/:id/review` |
| Handler | `handlers/animal/field_correction.rs::review_animal_field_correction` |
| Service | `services/animal/field_correction.rs::review` / `apply_correction` |
| 可改欄位 | `CORRECTABLE_FIELDS = ["ear_tag", "birth_date", "gender", "breed"]`（動物身分級欄位） |
| 前端 | `pages/admin/AnimalFieldCorrectionsPage.tsx` |

**結論**：核准會直接覆寫動物身分欄位，卻**無稽核、非原子、無併發守衛、權限粗放、前端顯示陳舊**。屬本輪合規風險最高項，須一次補齊後端三軸（audit / tx / lock）＋權限收斂＋前端 cache。

## 1. 現況缺口（威脅面）

| # | 缺口 | 證據 | 風險 | 嚴重度 |
|---|---|---|---|---|
| G1 | **無稽核軌跡** | `review` approve 分支只 `apply_correction` + UPDATE status，未寫 `user_activity_logs`/HMAC chain；連已 SELECT 出的 `old_value` 都被 `_old_value` 丟棄 | 身分欄位被改卻查無「誰改、改前→改後」，GLP/合規致命 | 🔴 高 |
| G2 | **非原子（無交易）** | `apply_correction`（UPDATE animals）與 UPDATE request status 為兩次獨立 pool 呼叫（`:169` / `:172`） | 中途失敗→「動物已改、申請仍 pending」或反之，狀態漂移 | 🔴 高 |
| G3 | **無併發守衛** | 初始 SELECT `status='pending'` 為 pool 純讀、無 `FOR UPDATE`；animal row 未鎖 | 兩個並發 approve 都通過 pending 檢查→重複套用（冪等漏洞） | 🟠 中 |
| G4 | **權限粗放硬編碼** | handler 用 `is_admin()`（`:64`），非 `require_permission!`；與 create 用 `require_permission!(…, "animal.animal.edit")` 不一致 | 無法委派非 admin 審核者；粒度與全站不齊 | 🟠 中 |
| G5 | **未用 ActorContext** | service 收 `reviewed_by: Uuid` 裸值，非 `&ActorContext` | 無法走 R28-4 的 Anonymous 拒絕／system 歸因；與全站 service-driven audit 不齊 | 🟡 低 |
| G6 | **前端 cache 陳舊** | approve/reject 的 `onSuccess` 只 invalidate `['animals-animal-field-corrections-pending']`（`AnimalFieldCorrectionsPage.tsx:87/103`），未刷新動物本體 | DB 耳號已改、動物列表/詳情仍顯示舊值，須手動重整 | 🟠 中（UX/資料信任） |

## 2. 權限模型

- **現況**：`is_admin()` 全有全無；requester 與 reviewer **無職責分離（SoD）守衛**——理論上同一人可送出再自核（目前 create 走 `animal.animal.edit`、review 走 admin，實務上多半隔開，但無程式強制）。
- **目標**：handler 改 `require_permission!`，service 改收 `&ActorContext` 並 `require_user()`（拒 Anonymous）。

> ⚠️ **子決策 D1（權限 key）**：要 (a) **新增 `animal.field_correction.review`** 並以 migration seed + 授予 admin/審核者角色（較正確、可委派，但動 RBAC seed＋migration），還是 (b) 暫時沿用 `is_admin()` 僅補三軸（最小變更，權限粒度留待後續）？建議 (a)。
> ⚠️ **子決策 D2（SoD）**：是否加「reviewer ≠ requester」強制守衛？建議加（兩人原則），成本低。

## 3. 交易邊界（fix 設計）

目標：`review` 收歸**單一 tx**，悲觀鎖（依本輪決策 3）：

```
tx = pool.begin()
  ├ SELECT … FROM animal_field_correction_requests WHERE id=$1 AND status='pending' FOR UPDATE   ← 鎖申請列、重驗 pending（解 G3）
  ├ (可選) SELECT … FROM animals WHERE id=$animal_id FOR UPDATE                                   ← 鎖動物列
  ├ approve: apply_correction(&mut tx, …)            ← 改用 &mut tx（解 G2）
  │          UPDATE … SET status='approved', reviewed_by, reviewed_at
  │          log_activity_tx(&mut tx, actor, { category:"ANIMAL", type:"FIELD_CORRECTION_APPROVE",
  │                                            entity: animal, data_diff: old_value→new_value })   ← 解 G1
  ├ reject : UPDATE … SET status='rejected', reason||=…   + log_activity_tx(… "…_REJECT")
  └ tx.commit()
```

- 參考既有樣板：`services/animal/transfer.rs::initiate_transfer`（tx + FOR UPDATE + `log_activity_tx`）、`services/glp_compliance.rs::create_management_review`（`log_activity_tx` + `DataDiff`）。
- `apply_correction` 簽名由 `pool: &PgPool` 改 `executor: &mut Transaction`（或泛型 executor），維持四欄位分支不變。
- `DataDiff`：用 G1 目前被丟棄的 `old_value` 與 `new_value` 組 before/after（單欄位 diff）。

## 4. 前端 cache 修補（解 G6）

`AnimalFieldCorrectionsPage.tsx` 的 approve/reject `onSuccess` 追加（list item 已含 `animal_id`）：

```ts
queryClient.invalidateQueries({ queryKey: ['animals-animal-field-corrections-pending'] }) // 既有
queryClient.invalidateQueries({ queryKey: ['animals'] })          // 列表（前綴）
queryClient.invalidateQueries({ queryKey: ['animal', r.animal_id] }) // 詳情
```

對齊既有 `pages/animals/hooks/useAnimalDetailMutations.ts:43-44` 同樣 pattern。

## 5. 回測點（verifiable goal）

- **既有 unit tests**：`field_correction.rs` `#[cfg(test)]`（`validate_new_value` 各分支，`:289+`）→ 重構後須仍綠。
- **新 acceptance test（先紅）**：核准一筆 pending 申請後，斷言 (1) `animals` 對應欄位已改；(2) `user_activity_logs` 有對應 `FIELD_CORRECTION_APPROVE` entry（含 before/after）；(3) 申請 status='approved' 與欄位變更**同一 tx**（可用「中途模擬失敗→兩者皆未變」驗原子性）。
- **測試指令層級**：本 PR **動到 handler（權限）層** → 依 CLAUDE.md 須 `cargo test --all-targets` 全綠（含整合測試，需本地 Postgres）。
- **Clippy**：`cargo clippy --all-targets -- -D warnings -A deprecated`。

## 6. 待你裁的子決策彙整

| # | 決策 | 建議 | 影響 |
|---|---|---|---|
| D1 | 權限 key：新增 `animal.field_correction.review`(+seed migration) vs 暫留 `is_admin()` | 新增 | 動 RBAC seed + migration（dev 自動跑 OK） |
| D2 | 加「reviewer ≠ requester」SoD 守衛？ | 加 | service 內一行檢查 |
| D3 | `ear_tag` 改值是否補唯一性檢查（同群可能撞號）？ | **本輪不做、mention** | 屬資料完整性，超出 R71-1 字面範圍，列 follow-up |

---

*本評估為實作前置，未動程式碼、未 commit。待 D1–D3 拍板後進入「acceptance test（紅）→ 實作（綠）→ commit → 停」。*
