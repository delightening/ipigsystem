# R75-P4 / R66-D2 結構性授權 — 實作計畫（Hybrid 分階段）

> 立案：2026-06-19。對應 TODO 項：R75-P4（型別/資料層根治）+ R66-D2（CI 掃描防護網）。
> 方向已由使用者裁定為 **D. Hybrid 分階段**。本檔為實作計畫，逐 Phase 完成必停回報。

## 根因

全系統 object-level 授權皆為 handler/service body 內「要記得呼叫」的 `access::require_*()`。
漏呼叫**不會編譯失敗**，只會變稽核發現。R75 跨輪累積漏掉 7+ handler 即此缺口反覆證明。
現狀：`services/access.rs` ~35 個 require 函式、**492 個呼叫點**散落 667 個 handler。

R66-D2 與 R75-P4 是同一根因的**互補兩層**：
- R66-D2 = 外部防護網（CI 靜態掃描「有沒有呼叫授權」）
- R75-P4 = 內部根治（讓「漏呼叫」變編譯錯誤）

## 既有資產盤點（2026-06-19）

- **`scripts/ci_handler_security_scan.sh` 已存在但失效**：
  1. **未接進 CI**（`.github/workflows/` 零引用）→ 從未生效。
  2. **抓不到已證明漏洞類別**：只靠 `_current_user`（底線=未使用）信號；R66-A1/R75-2 那批
     （有 `require_permission!` 卻漏 `access::require_*`）參數正常使用 `current_user`，完全漏掉。
     Pattern 2 為空殼（`WARN_COUNT=0` 無作用）。
- **CI `guards` job**（`ci.yml:142`，本 PR 接入授權掃描後由 5-in-1 → 6-in-1）做 pattern 檢查（SQL injection、audit pattern 等）
  → 強化後的授權掃描自然接這裡當第 6 guard。

---

## Phase 1：CI handler 授權掃描（關閉 R66-D2）— 修正範圍（2026-06-19 使用者裁定方向 1）

### 關鍵發現（為何修正範圍）

對現況跑「handler 必含 `access::require_*`」的廣掃描 → **262/361（73%）被旗標**；
放寬 pattern（納入 service 慣例）+ 排除內部 by-design 模組後**殘留仍 100 個**，且大多仍是
service-delegated 偽陽性（hr 假單按 user scope、messaging 按 thread scope、R75-11
`resolve_review_comment` 守衛在 service 層）。**根因**：object-level 授權合法分散在
handler / service / 角色三層，文字掃描**跟不進 service**，連 R75 已修 handler 都誤旗標。
→ 純文字掃描**無法成為乾淨硬 gate**；可靠根治交給 Phase 2 型別化。

### 修正後做法（雙軌）

1. **硬 gate（低誤報）**：既有 `scripts/ci_handler_security_scan.sh`（窄 `_current_user` + Path/body
   偵測，抓「宣告了身分卻忽略」的 IDOR 類）接進 CI `guards` job。對現況跑 **EXIT=0（0 誤報）已驗** →
   可當阻擋 gate，立即關閉 R66-D2 的「忘用 current_user」一面。
2. **Advisory（非阻擋）**：`scripts/ci_handler_authz_scan.py`（廣掃描，放寬 pattern + 排除內部模組）
   **永遠 exit 0**，產 ~100 筆 triage worklist，供 Phase 2 型別化取材與人工複查，不阻擋 CI。
3. **CI gate 終局**：俟 Phase 2 `Scoped<T>` 落地，gate 收斂為「protocol/animal family handler
   必用 `Scoped<T>`」——這是乾淨、低誤報的可機械檢查條件。

**為何不用 `syn`**：掃描是 guardrail 非正確性證明；文字啟發式足夠，且免新 dev 依賴。

**Verify**：窄掃描現況 EXIT=0 已驗；advisory exit 0 已驗。
**工作量**：S。**停點**：接 `ci.yml`（CI 設定變更=不可逆操作）前 surface diff 等使用者明確同意。

## Phase 2：protocol / animal 兩族 typed scope wrapper（編譯期強制）

**目標**：兩族新 handler「拿不到未授權的資源值」= 漏檢查直接編譯不過。

**做法（縮小版 `Owned<T>`）**：
- `Scoped<T>` 建構子：`Scoped::<ProtocolId>::authorize(pool, user, id).await?`，唯一建構路徑跑
  `require_protocol_related_access`。
- read/write 能力分離（對齊 `require_animal_access` vs `require_animal_read_access`）→ marker type
  `Scoped<AnimalId, Read>` / `Scoped<AnimalId, Write>`。
- **漸進式**：只改 protocol/animal handler 簽章；其餘不動。逐批跑 `cargo test --all-targets`。

⚠️ **不確定**：遷移 churn 估中等但未逐一盤點。**先抽 3 handler 做 pilot 驗 ergonomics，pilot 後重估再續**，不一次全改。

**工作量**：M–L（pilot 後重估）。**停點**：pilot 完成必停，由使用者確認 pattern 可複製。

## Phase 3：R75-P3 ownership 不變式 property test（跨切面安全網）

**目標**：proptest 編碼「user X 對非自己資源 R 的任何請求必 403/404、永不 200 帶 R 內容」，明列未覆蓋 resource type。
**工作量**：M。**停點**：完成 → 報告覆蓋率缺口。

---

## 停機規則

- 每 Phase 完成必停（commit 後不自動 push、不自動進下一 Phase）。
- Phase 1 強化後掃描若冒出**新真漏洞** → 停下 surface，不自行 silent 修。
- 新增依賴 / 改 CI 設定（`ci.yml`）依 CLAUDE.md 屬不可逆操作 → push 前明確同意。
