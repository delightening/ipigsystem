# 程式碼審查報告：PR #300-400

## 總結

本輪審查涵蓋 PR #300-400 範圍。經 verifier 逐筆於 current main 驗證後，**確認仍存在**的 finding 共 7 項：High 2 項、Medium 4 項、Low 1 項（其中數筆原始 severity 經 verifier 校準下修，標題下方 `Sev-n` 採用校準後等級）。另有 3 項經 verifier 駁回（已修復 / 機制描述有誤 / by-design），列於文末供參。

---

## Critical

（無）

## High

### High-1 [#386 · security]（校準：medium–high 交界） view_project-only 使用者（PI）可列舉全院未指派庫存豬，繞過 list_animals 範圍限制
- **檔案**：`backend/src/handlers/animal/animal_core.rs:116`
- **問題**：新端點 `list_available_pigs` 只檢查 `view_all OR view_project` 任一即放行（127-133 行），完全沒有依 `view_project` 做範圍縮限。對照同檔既有的 `list_animals`：對「只有 view_project、無 view_all」的使用者會 `result.data.retain(|a| a.iacuc_no.is_some())`（58-64 行），刻意隱藏未指派計畫（Unassigned、`iacuc_no IS NULL`）的純庫存豬。`report.rs:104-106` 與 `services/report.rs:468` 也一致採用此 `restrict_to_project_animals` 模式。PI 角色（`startup/permissions.rs:236`）只有 `animal.animal.view_project`、無 `view_all`，因此外部 PI 可透過 `/animals/available?export=xlsx` 列舉並匯出全院 Unassigned + Completed 庫存豬（耳號、品種、性別、體重、欄位位置），形成 broken access control。
- **驗證**：已於目前的 main 分支中確認。list_available_pigs（services/animal/core/query.rs:347）不接收 user/actor/restrict 參數，SQL（line 384）僅以 status 過濾、無 iacuc_no/user gate。Helper get_user_iacuc_nos（query.rs:242）存在但未接入此端點。PR #386（commit 4be96503）引入後無後續 commit 修正，self-acknowledging 註解「view_project 也可看全庫存」（102-103 行）仍在。校準為 medium-高交界：揭露對象為已驗證內部 PI、內容為營運庫存 metadata（非 PII / 醫療 / 財務），但仍屬刻意設計之範圍模型被破壞。
- **建議修法**：比照 `list_animals` / report 端點，對「view_project 且非 view_all」的呼叫者套用 `iacuc_no IS NOT NULL` 範圍限制：handler 計算 `restrict = has_view_project && !has_view_all` 傳入 service，於 eligible CTE 與 excluded 查詢加上 `(NOT $restrict OR a.iacuc_no IS NOT NULL)` 條件。`view_all`（VET/admin）維持看全庫存。

### High-2 [#380 · correctness]（校準：medium） 全域 401 redirect 攔截器把「二級認證密碼輸錯」誤判為 session 過期，強制登出管理員
- **檔案**：`frontend/src/main.tsx:48`
- **問題**：PR #380 在 `mutationCache.onError`（與 `queryCache.onError:34`）新增：任何 AxiosError 且 `response.status===401` 就呼叫 `forceRedirectToLogin()`（`clearAuth()` + `window.location.href='/login'`）。此 401 判斷「先於」既有的 `if (mutation.options.onError) return` 守門，且無法區分 401 的兩種來源：(a) auth middleware 的 session 過期（正確該登出），(b) 敏感操作二級認證（step-up reauth）密碼輸錯（`backend/.../password.rs:230` 回 `Unauthorized` → HTTP 401）。`useUserManagement.ts:350` 的 `confirmPasswordMutation` 原設計是 toast「密碼錯誤，請重新輸入」讓 admin 重試，現在被全域攔截器當成 session 失效 → 整個帳號被登出。破壞 step-up reauth UX 與既有 onError 契約。
- **驗證**：Chain fully confirmed in current main（commit 3e9d639，後續 #451 未動此區）。`client.ts:230-231` 只排除 `/auth/login` 與 `/auth/refresh`、未排除 `/auth/confirm-password`，故輸錯密碼還會先觸發 token refresh + retry（再送一次錯密碼、產生第 2 筆 `reauth_failure` audit），才把 401 丟到全域 handler 登出 admin。校準為 medium 而非 high：fail-closed（強制登出、無提權 / 資料外洩 / 資料遺失），重新登入即可恢復，範圍限 admin step-up 流程。
- **建議修法**：在 `forceRedirectToLogin` 的 401 判斷加上來源辨識——(a) 檢查 `error.config?.url`，若為 step-up/reauth 端點（`/auth/confirm-password` 等帶密碼驗證的 POST）則 return 不 redirect；或 (b) 後端把「step-up 密碼驗證失敗」改回非 401（如 422/403），401 全域登出專屬給 middleware；或 (c) 把 401 分支移到既有 `if (mutation.options.onError) return` 之後，讓帶 onError 的 reauth mutation 自行處理。

## Medium

### Medium-1 [#363 · correctness] Entry-photo mutation handlers 繞過 COMPLETED（GLP-locked）報告不可變保護且不寫 audit
- **檔案**：`backend/src/handlers/animal/vet_patrol.rs:466`
- **問題**：PR #363 引入 entry-level photo handlers（`upload_vet_patrol_entry_photo`、`update_vet_patrol_entry_photo_caption`、`delete_vet_patrol_entry_photo`），三者只 gate 於 `animal.vet.recommend` 權限、純對 `entry_id`/`photo_id` 操作。upload 路徑呼叫的 `ensure_entry_exists`（`services/.../vet_patrol.rs:281`）只檢查 `r.deleted_at IS NULL`、**不檢查父報告 status**；`delete_entry_photo`（1679）與 `update_entry_photo_caption`（1659）完全不 join 報告。對照報告 `update()`（657-662）對 `status='completed'` 明確拒絕（migration 063：「完成後 status=completed，任何人都不能再改 GLP 不可變醫療紀錄」）。淨效果：vet 仍可對已定稿/鎖定的巡場報告新增、改 caption 或**刪除**照片證據，繞過 GLP lock；且四個 handler 皆不寫 audit log，鎖定醫療紀錄被異動卻無 trail。
- **驗證**：Confirmed in current main（HEAD ee6f4c0d）。五個 photo 函式（1451/1518/1612/1659/1679）皆無 `AuditService::log_activity_tx` 呼叫，而 service 其餘 lifecycle mutation（568/838/929/1022/1105/1287/1344）每筆都 audit。Severity medium：需已驗證的特權 vet 角色、文字報告本身仍鎖定，但「未 audit 的不可逆刪除 GLP 附掛證據」屬真實完整性/合規缺口。
- **建議修法**：在 `ensure_entry_exists` 及 delete/update entry-photo service fn 中 JOIN `vet_patrol_reports`，`status='completed'` 時拒絕（並比照 `update()` 的 status match）。另對 non-draft 報告的 entry-photo add/delete 寫 audit log（如 `VET_PATROL_ENTRY_PHOTO_DELETED`），讓已送出/鎖定紀錄的異動可追溯。

### Medium-2 [#365 · security] 群組 thread 繞過 access matrix：禁止配對（vet↔PI）可透過第三方建群同桌通訊
- **檔案**：`backend/src/services/messaging/access.rs:107`
- **問題**：Access matrix（R40-1，明確禁止 vet↔PI、PI↔PI）只在建立 thread 時以 `ensure_can_message_all` 驗 sender → 每個 recipient 的配對，**從不驗 recipient↔recipient**。因此一個 Staff（可同時寫 VET 與 PI）可建立 group thread 把 VET_X 與 PI_Y 一起拉進來：Staff→VET 與 Staff→PI 各自 allowed 而通過檢查，結果 VET 與 PI 成為同 thread participant。`send_message`（message.rs:96）只檢查 `is_participant`、不重跑 matrix，VET_X 與 PI_Y 即可在該 thread 內互通並讀取彼此內容——直接違反「vet↔PI 禁止」這條刻意設計的安全控制。另外後加入既有 group 的 participant 因 `last_read_at=NULL`，`get_thread`（thread.rs:288，無 joined_at 過濾）會回傳加入前的全部歷史訊息，放大資訊外洩面。
- **驗證**：Confirmed in current main。唯一的 matrix enforcement（thread.rs:100 的 `ensure_can_message_all`）只驗 sender→each recipient（access.rs:147-154），從不驗 recipient↔recipient。Group thread 明確支援多 recipient（thread.rs:89,92），Staffs 對 Vet 與 PI 皆 allowed（access.rs:96-97）。history-leak 放大亦真實（message.rs:72-78 無 joined_at filter）。Severity medium：繞過刻意設計的隔離控制，但需 insider Staffs 帳號當橋接，未升級為 admin / 資料破壞。後續無 PR 修正（access.rs git log 僅 #365 引入 + #523 recipient-endpoint 改動）。
- **建議修法**：建立 group 時除 sender→recipients 外，對「所有 participant 兩兩配對」（含 recipient↔recipient）跑 `messaging_pair_allowed`，任一禁止即拒建；或在 `send_message` 時對「目前活躍 participant 全集」重新驗證 matrix。若維持 MVP 行為，至少在 `docs/plans/messaging.md` 與 access.rs 明載「群組成員間不再強制 matrix」為已知限制並評估可建群角色。另建議 `get_thread`/`list_for_thread` 以 `participant.joined_at` 過濾。

### Medium-3 [#378 · correctness] 巡場報告 awaiting_follow_up 鎖定可被多動物欄位繞過，篡改 GLP 動物關聯
- **檔案**：`backend/src/services/animal/vet_patrol.rs:639`
- **問題**：R39+++ 引入多動物 junction（`vet_patrol_entry_animals`）後，`update()` 在 awaiting_follow_up 階段的「只能改 follow_up」鎖定檢查（639-655）只比對 deprecated 單一欄位 `new_e.animal_id != old_e.animal_id`，未比對多動物清單 `animal_ids`。但寫入路徑（756-818）對每個 entry 一律以 `resolved_animal_ids()` 全量 replace junction，且 `resolved_animal_ids()` 在 `animal_ids` 非空時優先採用它，並把 `animal_ids.first()` 寫回鎖定的 `animal_id` 欄位（769）。因此追蹤者可送 `animal_id=<舊值>`（騙過檢查）同時 `animal_ids=[不同動物集]`，結果 junction 被替換、`animal_id` 主欄位也被改。`before_entries` 快照（`VetPatrolEntrySnapshot`，58-67）只含單一 `animal_id`，結構上無法用現有快照檢出此差異。
- **驗證**：Confirmed in current main。鎖定檢查（643-647）只比對 observation/suggestion/animal_id/category、從不比對 `animal_ids`；`resolved_animal_ids()`（204-218）在 `animal_ids` 非空時優先採用，寫入路徑全量 DELETE+INSERT junction（805-818）並把 `.first()` 寫回 `animal_id`（757→769）。audit 快照（58-67）與 `fetch_entry_snapshots`（98-107）只捕捉單一 `animal_id`，junction 變更對 DataDiff audit（828-849）不可見，篡改部分不可追溯。最近 commit（#529）未處理。Severity medium：攻擊者須為被指派的受信任 follow_up_user（或 admin），其餘動作仍有 audit。
- **建議修法**：awaiting_follow_up 鎖定檢查改用 `entry.resolved_animal_ids()` 與 DB 現有 junction 的 `animal_ids`（需新增查詢或擴充快照）做集合比對，任何差異即 `return Forbidden`；或更簡單：awaiting_follow_up 階段完全跳過 junction 的 DELETE/INSERT（805-818），只允許更新 follow_up 欄位，不重寫 animal 關聯與 primary `animal_id`。

### Medium-4 [#395 · security]（校準：low） unusual_login 30 分鐘 dedup 不分 severity，info-level admin 告警會壓掉後續真實 warning
- **檔案**：`backend/src/services/login_tracker.rs:295`
- **問題**：`create_login_alert` 入口的 30 分鐘 dedup 查詢只看「該 user 是否已有 open 的 unusual_login alert」、完全不分 severity。本 PR 同時引入 D 規則：admin 在「僅 unusual_time」時告警降為 `severity='info'`。組合後產生盲區：admin 半夜正常登入先寫一筆 info alert；30 分鐘內同帳號又從新裝置+新地理位置登入（典型帳號被盜訊號，本應寫 `warning`），dedup 偵測到既存 open info alert 直接 `return Ok(())`，真正高風險的 warning 被靜默丟棄且不升級既有 info。對照 brute_force 的 dedup（212）是單一 severity('critical')，去重不會降級風險。
- **驗證**：Verified in current main。dedup 查詢（295-306）無 severity 欄位，`recent_alert_count>0` 即 `return Ok(())`（312）丟棄新 alert 且不升級舊的。D 規則（337-339）對 admin-only-unusual_time 寫 info；`check_new_device`（463-476）對 admin 仍開啟裝置偵測，故後續 new-device+new-location admin 登入確實算 `warning`（339），被 severity-blind dedup 靜默丟棄。校準為 **low** 而非 medium：降級的是次要偵測/告警層（非 access-control bypass，登入照常成功）、admin-only、需 <30min 的人為時間窗，且既存 info alert 仍 `status='open'` 顯示於 dashboard（可見性降級/誤標，非完全靜默）。#395（37de4165）為此檔最近 commit、無後續修正。
- **建議修法**：dedup 加 severity 維度或升級語意：(a) 先算本次 severity，dedup 只壓制「同 severity 或更高已存在」——本次 warning 但既存只有 info 時放行寫入（或把既存 info 升級為 warning）；或 (b) dedup 條件加 `AND severity = $2`，使 info 與 warning 各自獨立去重。

## Low

### Low-1 [#399 · correctness] Lock 過期門檻（20 分）小於 task 執行上限（30 分），留下並行 deploy 視窗
- **檔案**：`scripts/auto-deploy-watcher.ps1:34`
- **問題**：watcher 用 lock file 防止兩個 deploy 同時跑（避免 docker build 衝突，註解明寫此意圖）。判定 lock 過期門檻為 20 分鐘（line 34 `$lockAge.TotalMinutes -lt 20`），但 `install-auto-deploy.ps1` 的 `ExecutionTimeLimit` 設為 30 分鐘（`New-TimeSpan -Minutes 30`）。若一次 deploy 合法跑 20~30 分鐘，下一輪 watcher 會認定 lock 已過期、強制 `Remove-Item` 並繼續，於是在前一個 deploy 仍跑 `docker compose build/up` 時啟動第二個 deploy——正是 lock 想防止的並行衝突。兩個門檻方向相反（過期門檻應 >= 執行上限）。
- **驗證**：Both facts confirmed in current main（`auto-deploy-watcher.ps1:34` 20 分、`install-auto-deploy.ps1:72` `ExecutionTimeLimit` 30 分）。lock 純時間判定、無 PID/liveness 檢查。NUANCE 使 severity 維持 low：第二個 watcher 不會自動啟動並行 build——`deploy-prod.ps1:63` 在 build 前先 `git pull --ff-only`，第一個 deploy pull 後 local HEAD == origin/main，第二個 watcher 命中 SHA-equality guard（line 69）即退出（line 75），不部署。並行 `docker build` 只在「deploy 跑 20-30 分 **且** 同窗期 origin/main 有全新 commit 落地」雙重條件下發生；solo-dev 單筆電 manual-merge prod 上罕見，最壞結果為交錯/失敗的 deploy 而非資料遺失。
- **建議修法**：把 lock 過期門檻提高到 >= `ExecutionTimeLimit`（如 35 分），或把 `ExecutionTimeLimit` 降到 < 20 分，確保「task 還可能在跑」期間 lock 不被判過期清掉。最穩健是兩常數共用同一來源值。

---

## 已不適用 / 已修復（verifier 駁回）

- **#357** create 端排除軟刪 user 的 email 檢查與 accept 端不一致造成死巷邀請 — 機制描述有誤：soft-delete 會匿名化 email（`'deleted_'||id||'@deleted.local'`），原 email 釋出、不會撞 UNIQUE，無死巷；描述的 soft-delete 場景不成立（false positive）。
- **#380** `forceRedirectToLogin` 只排除 `/login`，其餘公開路由 401 會被誤導向登入頁 — code drift 屬實但無實際可觸發路徑：所有公開頁（invite/reset-password/sign）皆不經 queryCache 觸發 401，至多 spurious redirect（latent defensive-coding gap，非可利用問題）。
- **#399** prod 自動部署無 commit 簽章 / provenance 驗證 — 描述正確但 by-design：watcher 未引入新信任邊界（只是自動化既有 manual `pull+build`），solo prod-on-laptop 下 GitHub 帳號即簽署信任根，finding 自承為 by-design 僅建議風險登記、非缺陷。

---

備註：本報告僅列出 verifier 確認**於 current main 仍存在**的 finding；上方「已不適用」區的項目已被 verifier 駁回（已修復 / 機制描述有誤 / by-design），列出僅供讀者知悉曾納入考量。