# 死權限碼稽核：13 個「檢查了 / 授予了，但永遠不會生效」的權限

> 2026-08-08 ｜ 起因：按鈕權限徹查系列 PR 3 / PR 4 各自撞到一個死碼，判斷是系統性問題後做全面掃描。
> 對照基準：**prod DB 的 `permissions` 表**（199 筆），不是 seed 原始碼。

---

## 0. 一句話結論

後端有 **13 個權限碼被 `require_permission!` / `has_permission` 檢查，但不存在於 `permissions` 表**。
`has_permission` 對它們永遠回 `false`，功能實際上只靠 `is_admin()` 短路才能用——
**「只有管理員做得到」是意外達成的，不是設計**。其中 `facility.manage` 有 19 個呼叫點且無任何 fallback，
等於整個設施管理模組在無人察覺的情況下變成管理員專屬。

---

## 1. 根因：授權 seed 對「不存在的碼」靜默無視

`startup/permissions.rs` 把權限授予角色的 SQL 是：

```sql
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code = $1
  AND p.code = ANY($2::text[])
ON CONFLICT DO NOTHING
```

它 **JOIN 的是 `permissions` 表**。若授予清單裡的某個碼不在該表中，
JOIN 直接不產生列 —— 沒有錯誤、沒有警告、`rows_affected` 少一筆也沒人看。

於是只要有人「在角色的授予清單裡加了一個碼，卻忘了同時把它加進權限目錄」，
這個碼就會永遠是死的，而且**啟動一切正常、CI 全綠、沒有任何徵兆**。

同樣地，handler 那端寫 `require_permission!(user, "some.new.code")` 時，
也沒有任何機制確認這個字串真的存在。兩端都是純字串，沒有交叉驗證。

> PR 1（#48）產生的 `permissions.generated.ts` 已經讓**前端**這一側有型別保護——
> PR 4 的 `PERMISSIONS.ERP_PARTNER_DELETE` 就是被 `tsc` 擋下來才發現的。
> 但**後端自己**仍然是裸字串，沒有對應的保護。

---

## 2. 完整清單

掃描方式：正規表示式抽出 `backend/src/**/*.rs` 中所有 `require_permission!(_, "…")`
與 `has_permission("…")` 的字串（146 個），與 prod `permissions` 表（199 個）取差集。

### 2-1 Group A — 不在任何角色授予清單裡（10 個）

這些碼從頭到尾沒人打算授予任何角色，補進目錄**不改變任何人的權限**（仍是管理員專屬）。

| 權限碼 | 呼叫點 | fallback | 實際效果 |
|---|---|---|---|
| `facility.manage` | `handlers/facility.rs` ×19 | 無 | **整個設施管理模組管理員專屬** |
| `system.admin` | `handlers/ai.rs` ×4 | 無 | AI/agent 管理端點管理員專屬 |
| `admin.treatment_drug.view` | `handlers/treatment_drug.rs` | 無 | 治療用藥主檔管理員專屬 |
| `admin.treatment_drug.create` | 同上 | 無 | 同上 |
| `admin.treatment_drug.edit` | 同上 | 無 | 同上 |
| `admin.treatment_drug.delete` | 同上 | 無 | 同上 |
| `erp.product.delete` | `handlers/product.rs:162` | 無 | 產品刪除管理員專屬 |
| `erp.partner.delete` | `handlers/partner.rs:156` | `is_admin` | 夥伴刪除管理員專屬 |
| `hr.attendance.manage` | `handlers/hr/attendance.rs:359` | `is_admin` | 出勤管理管理員專屬 |
| `animal.euthanasia.create` | `handlers/euthanasia.rs:41` | `has_role(ROLE_VET)` | **有 fallback，功能正常**：實際等同「VET 或管理員可開安樂死單」 |

> `animal.euthanasia.create` 是這組裡唯一功能沒壞的——因為它寫了 `|| has_role(ROLE_VET)`。
> 但那正是本專案想淘汰的 role 硬判；碼補齊後才能把 role 判斷換掉。

### 2-2 Group B — 已寫進角色授予清單，卻靜默沒生效（3 個）

| 權限碼 | 呼叫點 | 原始碼中已授予的角色 |
|---|---|---|
| `aup.review.reply` | `handlers/protocol/review.rs:325/355/390` | `PI`、`IACUC_STAFF`、`EXPERIMENT_STAFF`、`INTERN`、`STUDY_DIRECTOR` |

`startup/permissions.rs` 的 271 / 418 / 453 / 537 / 765 行都把這個碼寫進了上述五個角色的清單，
但因為它不在權限目錄裡，五筆授予**全部靜默落空**。

`reply_review_comment` 有 owner fallback（計畫擁有者 / co-editor 可回覆），
所以功能沒有完全壞掉；但「PI 以外的五種角色應該能回覆審查意見」這個明確寫下的意圖，
**從來沒有生效過**。

⚠️ **這一組與 Group A 性質不同**：補進目錄會讓那五個角色**真的拿到**這個權限，
是實質的授權擴張（雖然那本來就是原作者的意圖）。

#### 2-2-1 補記：防呆測試當場又抓到兩個

上面 11 個是**人工掃描**的結果，而人工掃描只看了「被 `require_permission!` /
`has_permission` 檢查的碼」，沒看「授予清單裡的碼」。§3-2 的防呆測試寫完第一次執行，
立刻多抓到兩個：

| 權限碼 | 呼叫點 | 原始碼中已授予的角色 |
|---|---|---|
| `aup.attachment.upload` | **無** | 同上五個角色 |
| `aup.attachment.delete` | **無** | 同上五個角色 |

與 `aup.review.reply` 顯然是同一批意圖、同一次漏補。差別是**目前沒有任何 handler
檢查它們**（附件上傳/刪除走其他授權路徑），所以補進目錄不改變任何行為。

這件事本身就是本報告 §3-2 的最佳論據：**人工掃描會漏，機器不會**。
死碼總數因此從 11 修正為 **13**。

---

## 3. 修法（**已於本 PR 全數實施**，使用者 2026-08-08 裁定）

### 3-1 補碼（分兩批，因為風險不同）

- **Group A**：補進權限目錄即可。不改變任何人的實際權限（沒有角色被授予，仍只有管理員通得過），
  但讓前端可以誠實上閘（`<Can permission={PERMISSIONS.FACILITY_MANAGE}>` → 只有管理員看得到按鈕），
  也讓後續要把權限授予某些角色時有東西可授。
- **Group B**：使用者裁定「補齊，讓五個角色真的拿到」。`aup.review.reply` 因此成為實質授權擴張；
  `aup.attachment.*` 因無人檢查而無行為變化。

### 3-2 補防呆（否則一定復發）

根因是「兩端都是裸字串、沒有交叉驗證」。建議加一個整合測試：

```
掃描 backend/src 中所有 require_permission! / has_permission 的字串
∪ startup/permissions.rs 所有角色授予清單中的字串
⊆ permissions 表的 code 集合
```

差集非空就紅。這個測試會在**第一次打錯字時**就擋下來，而不是等到某個功能
悄悄變成管理員專屬、幾個月後才被人發現。

已實作於 `backend/tests/permission_codes_exist.rs`（兩條測試：檢查端、授予端）。
並做過變異驗證——把 `facility.manage` 從目錄移掉，測試如預期紅燈且列出全部 19 個呼叫點，
確認它不是空轉的斷言。

`backend/tests/permission_constants_sync.rs`（PR 1 加的）目前只驗
`permissions.generated.ts` 與 DB 一致，管不到後端自己的裸字串——正是這 13 個漏網的原因。

### 3-3 授予 SQL 改為可觀測（**未實施，backlog**）

`INSERT ... SELECT ... JOIN permissions` 靜默漏授是根因的另一半。
最小改法：授予後比對 `rows_affected` 與清單長度，不符就 `tracing::warn!` 列出差集。
（不建議直接 fail startup——prod 啟動失敗的代價比一行警告大。）

---

## 4. 對按鈕權限徹查系列的影響

- **PR 3**：`animal.euthanasia.create` 已改用 `animal.euthanasia.recommend`（VET 實際持有的碼）。
- **PR 4**：`PartnerTable` 的刪除鈕刻意未上閘。本 PR 合併後 `erp.partner.delete` 就存在了，
  屆時把該處改成 `<Can permission={PERMISSIONS.ERP_PARTNER_DELETE}>`（＝只有管理員看得到，與後端一致）。
- **PR 5（AUP）**：`aup.review.reply` 屬 Group B，需先裁定；`VetReviewForm` 的
  `has_role(ROLE_VET)` 也要等新碼才能換掉。
- 設施管理（`facility.manage`）不在原稽核的 P0–P2 清單裡，因為它路由層本來就擋住了
  ——但擋住的方式是「所有人都被擋，只有管理員例外」，不是設計意圖。

---

## 5. 附帶發現：後端仍有 11 處 role 硬判

`handlers/` 下的 `has_role(` 呼叫點：

```
document.rs:74            euthanasia.rs:42/157/177
protocol/crud.rs:40/222/223/239/621/660
protocol/review.rs:251
```

原稽核 §7 只點名了 `VetReviewForm`（`crud.rs:621`）。實際上是 11 處。
這些要換成 permission code，前提是對應的碼存在且授予正確——與本報告的補碼工作綁在一起。
