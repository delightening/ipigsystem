# 「核准」按鈕盤點 Round 2：HR 請假/加班 + 安樂死

> 立案：2026-06-16 ｜ 承接首輪盤點 `approval-buttons-inventory-2026-06-16.md` §7「排除清單」中的 **HR 請假·加班核准** 與 **安樂死核准/申訴**（使用者於 R71 收尾後指定「另開新盤點輪」）。
> 方法：與首輪同「防護九軸」標準（權限 / 交易 / 併發守衛 / 稽核 / ActorContext / 樂觀鎖·409 / 電子簽章 / 通知 / 狀態機守衛）＋ 前端（gate / 防連點 / 確認框 / cache invalidate）。**僅盤點，未更動 production 程式碼。**

## §0 摘要（TL;DR）

**與首輪 R71-1~3 的「兩極化破損」不同——本輪兩塊後端防護大致健全：**

- **安樂死（pi_approve / pi_appeal / chair_decide）後端防護完整** —— 已於 **R30-1** 強化：tx + `FOR UPDATE` + `version` 樂觀鎖(409) + in-tx audit + 電子簽章(approve/decide) + 通知 + 狀態機 fail-close。**無後端缺口。**
- **HR 請假/加班核准後端亦健全** —— tx + `SELECT … FOR UPDATE` + in-tx audit + ActorContext + 狀態機守衛皆具備。
- **缺口集中在前端**（無權限 gate / 部分無防連點 / 多數無確認框）＋ **HR 的「核准結果通知」缺漏**。
- ⚠️ **重要更正**：初步自動掃描曾將「HR 加班核准無 `WHERE status` CAS」標為 Critical race window —— **經人工驗證為誤判**：`approve_overtime` 在 `pool.begin()` tx 內先 `SELECT … FOR UPDATE` 鎖列並重驗 `status`（`services/hr/overtime.rs:472-493`），悲觀鎖已序列化並發，第二個請求必阻塞至前者 commit 後再讀到新狀態 → 失敗。UPDATE 未加 `WHERE status` 僅為冗餘，**無 race**。

## §1 範圍

| 盤點動作 | 後端 service:行 | Handler / Route |
|---|---|---|
| HR 請假核准 | `services/hr/leave.rs::approve_leave` | `handlers/hr/leave.rs` / `POST /hr/leaves/:id/approve` |
| HR 加班核准 | `services/hr/overtime.rs::approve_overtime:461` | `handlers/hr/overtime.rs` / `POST /hr/overtime/:id/approve` |
| 安樂死 PI 核准 | `services/euthanasia.rs::pi_approve:259` | `handlers/euthanasia.rs` / `POST /euthanasia/orders/:id/approve` |
| 安樂死 PI 申訴 | `services/euthanasia.rs::pi_appeal:349` | `handlers/euthanasia.rs` |
| 安樂死 Chair 決定 | `services/euthanasia.rs::chair_decide:481` | `handlers/euthanasia.rs` |

## §2 後端防護九軸總表

| 動作 | 權限 | tx | FOR UPDATE | 稽核 | ActorContext | 樂觀鎖/409 | 電子簽章 | 通知 | 狀態守衛 |
|---|---|---|---|---|---|---|---|---|---|
| HR 請假核准 | ⚠️ `is_admin()`/role 硬編碼 | ✅ | ✅ | ✅ `LEAVE_APPROVE_INTERIM/FINAL` | ✅ | ✅ WHERE status CAS→409 | ❌ | ❌ approve 無通知 | ✅ |
| HR 加班核准 | ⚠️ `is_admin()`/role 硬編碼 | ✅ | ✅（並發安全，悲觀鎖） | ✅ `OVERTIME_APPROVE_INTERIM/FINAL` | ✅ | ➖ 悲觀鎖足夠（不需 409） | ❌ | ❌ approve 無通知 | ✅ |
| 安樂死 PI 核准 | ✅ IDOR(pi=self) | ✅ | ✅ `lock_order_for_pi` | ✅ `EuthanasiaOrderApproved` | ✅ | ✅ version CAS→409 | ✅ `sign_record_tx` | ✅ | ✅ 僅 `pending_pi` |
| 安樂死 PI 申訴 | ✅ IDOR(pi=self) | ✅ | ✅ | ✅ `EuthanasiaOrderAppealed` | ✅ | ✅ version CAS→409 | ➖（申訴非簽章節點，符設計） | ✅ chair | ✅ |
| 安樂死 Chair 決定 | ✅ `ROLE_IACUC_CHAIR` | ✅ | ✅（appeal+order 雙鎖） | ✅ `EuthanasiaChairDecided` | ✅ | ✅ version CAS→409 | ✅ `sign_record_tx`(Decide) | ✅ | ✅ fail-close 白名單 |

> ➖＝該軸對此動作不適用或現有機制已足夠（非缺口）。

## §3 前端總表

| 動作 | 權限 gate | 防連點 disable | 確認框 | cache invalidate |
|---|---|---|---|---|
| HR 請假核准 | ❌ 無 | ✅ `disabled={approvePending}` | ❌ | ✅ |
| HR 加班核准 | ❌ 無 | ✅ `disabled={isApproving}` | ❌ | ✅ |
| 安樂死 PI 核准 | ❌ 無 | ⚠️ 無 disabled | ❌ | ✅ |
| 安樂死 PI 申訴 | ❌ 無 | ⚠️ 無 disabled | ⚠️ 有填寫對話但無二次確認 | ✅ |
| 安樂死 Chair 決定 | ✅ 角色檢查 | ⚠️ 無 disabled | ❌（終決動作宜補） | ✅ |

## §4 缺口 → R72 立案對照

| 缺口 | 性質 | R72 |
|---|---|---|
| 安樂死三鈕無前端權限 gate；PI 核准/申訴/Chair 無防連點；終決動作無確認框 | 前端 code-only（後端已完整） | R72-1 |
| HR 請假/加班核准鈕無前端權限 gate、無確認框 | 前端 code-only（防連點已有） | R72-2 |
| HR 請假/加班核准無「核准結果通知」給申請人（僅 submit 有通知） | 後端，UX/可追溯 | R72-3 |
| HR 核准權限 `is_admin()`/role 硬編碼，非 `require_permission!`（與全站不齊） | 後端一致性，低風險，需評估是否新增權限 | R72-4（評估） |

## §5 待產品/合規拍板（未逕自立案）

- **HR 請假/加班核准是否需電子簽章**？安樂死 / GLP record 因 21 CFR §11 非否認性需簽章，但 HR 請假/加班屬一般行政審批、非 GLP raw data，**傾向不需**。待產品/合規確認後再決定是否立案。

## §6 結論

本輪兩塊（HR 行政審批、安樂死）**不在首輪「破損」之列**：安樂死後端已達 GLP 級完整（R30），HR 後端具 tx/鎖/稽核/狀態守衛。剩餘為**前端一致性**（gate / 防連點 / 確認框）＋ **HR 核准通知**＋ 權限風格一致性，皆為**低~中風險、非緊急合規漏洞**。建議併入 R71 前端統一批次（R71-8~11）一起處理，避免前端重工。
