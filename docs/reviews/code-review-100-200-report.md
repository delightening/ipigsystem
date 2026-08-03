# 程式碼審查報告：PR #101-200

> 建立日期：2026-06-08 ｜ 視角：current main ｜ 6 路平行 sub-agent + orchestrator 對 High 逐筆複驗

## 總結

PR #101-200 主體是 **R26 Service-driven Audit 重構 epic（#153-199）**——此為**現行 live 的稽核架構**（非 superseded），加上一批安全修復 PR（#128/#137/#138/#140/#152）。其餘為 dependabot / docs / tests。

確認仍存在於 current main 的 finding：**High 4、Medium 5、Low 4**。其中最一致的主題是 **R26 遷移漏網——部分模組/路徑從未改為 service-driven audit**（vet_advice、care_record create/update、equipment legacy 報廢/恢復、storage_location 編輯/調撥），形成 GLP 稽核軌跡缺口；另有一個跨計畫 IDOR。Group E（cleanup/AI/shutdown）全數 clean。

嚴重度：🔴Critical · 🟠High · 🟡Medium · 🟢Low（calibrate honest，prod-on-laptop 單 instance 已納入並發類校準）。

## 驗證裁決（2026-06-08 adversarial verify，3 路逆向驗證）

| Finding | 裁決 |
|---|---|
| #138 dashboard get_vet_comments 跨計畫 IDOR | ✅ **確認需修**（global query 僅 animal.record.view，STUDY_DIRECTOR/CLIENT 可達） |
| #179 approve_transfer SoD | ✅ **確認需修**（require_animal_access 解析到來源計畫，轉出方可獨推全程；簽章在平行端點不 gate） |
| #179 transfer 步驟 2-5 race | ✅ **確認需修**（UPDATE 無 status WHERE / 無 version → 可重複推進，修法 trivial） |
| #174/#176 vet_advice CRUD 無 audit | ✅ **確認需修**（含 delete；醫療內容；無 trigger） |
| #182 care_record create/update 無 audit | ✅ **確認需修**（update 內含 TODO；醫療 pain/meds） |
| #167 equipment 報廢/恢復 無 audit+非 tx | ✅ **確認需修**（pool 非 tx；status_logs 非 HMAC chain） |
| #197 storage_location 編輯/調撥 無 audit | ✅ **確認需修**（create 有 audit、兩兄弟無） |
| HMAC chain created_at 排序 | 🟡 **真但可接受**（單 instance 罕見；最多誤報 warning，非資料損失） |
| #168 role update is_system | 🟡 **真但可接受**（admin-only + 強制簽章 + audit） |
| DateTextInput 不完整/無效日期 | 🟡 **真但可接受**（後端 NaiveDate 反序列化擋下→400；UX 瑕疵非資料毀損） |
| #194 DB_ROLLBACK 037 runbook | ❌ **誤報**（文件內部一致，下一行已說明 try-both） |
| #158 verifier partition_date TZ 午夜 | ❌ **誤報**（db service 為 UTC；TZ:Asia/Taipei 在 print-pdf 非 db） |

> 確認需修：#138 / #179(×2) / #174·#176 / #182 / #167 / #197（+ 0-100 的 #63·#97 facility 同屬 audit 缺口群）。修復計畫見 `docs/reviews/code-review-0-200-fix-plan.md`。

---

## High

### High-1 [#138 · security] 儀表板 `get_vet_comments` 跨計畫洩漏獸醫評論（#138 IDOR sweep 漏網的姊妹端點）
- **檔案**：`backend/src/handlers/animal/dashboard.rs:30-50`
- **問題**：`get_vet_comments` 只用 `require_permission!("animal.record.view")` 把關，底層 SQL 對 `vet_recommendations × animal_observations × animals × users` 全域 JOIN、`ORDER BY created_at DESC LIMIT`，**無 per-protocol 邊界**。PI 角色持 `animal.record.view` + `view_project`（無 view_all），呼叫此端點即可讀全院所有計畫（含其他 PI）的最新獸醫評論、耳號、欄位位置、評論內容。
- **影響**：違反異種移植研究核心的 per-PI 計畫資料隔離。同波 v2 審計（#138）已對 `report.rs` / `animal_medical_report.rs` 套 `accessible_protocol_ids` 收斂，唯獨此 dashboard 端點漏掉；route 已掛載（`routes/animal.rs` `/animals/vet-comments`）。
- **驗證**：Confirmed in current main（`dashboard.rs:23` 有權限但無 boundary；對照 `handlers/report.rs:104` / `animal_medical_report.rs:64`）。
- **建議**：比照 `report_protocol_boundary`，非 view_all 使用者取 `accessible_protocol_ids`，SQL 加 `WHERE p.protocol_id = ANY($boundary)`（空集合回空）。

### High-2 [#174/#176 · compliance] `VetAdviceRecordService` create/update/delete 完全無 audit log
- **檔案**：`backend/src/services/animal/vet_advice.rs:207-277`
- **問題**：create / update / delete 直接收 `pool: &PgPool`，寫入 `animal_vet_advice_records`（observation + suggested_treatment＝獸醫醫療診斷內容）後**完全不寫任何 audit**（無 `log_activity_tx`/oneshot，handler 端也無補）。#176 補了 delete 的 IDOR（`WHERE id=$1 AND animal_id=$2`）但 audit 從未補上。
- **影響**：對 GLP 醫療紀錄做新增/竄改/刪除而無稽核軌跡（21 CFR §11.10）；與同模組 observation/blood_test/surgery 的 SDD 標準明顯不一致。
- **驗證**：Confirmed in current main（`vet_advice.rs:207/230/259` 三 mutation 無 audit；handler 呼叫端也無）。
- **建議**：三 mutation 改 SDD 簽名 `(pool, actor, ...)` + `log_activity_tx`，event_type `VET_ADVICE_RECORD_CREATE/UPDATE/DELETE`，before snapshot 走 FOR UPDATE。

### High-3 [#182 · compliance] `CareRecordService` create/update 無 audit（照護給藥紀錄；update 自承 TODO）
- **檔案**：`backend/src/services/animal/care_record.rs:187-220, 231-284`
- **問題**：`create` 直接 pool INSERT 疼痛評估/術後給藥（pain_score、injection_*、post_medications）無 audit；`update` 雖補了 C1 簽章雙層守衛 tx，但 doc 自承「本函式仍未寫 audit log（R26 SDD 補齊範圍…留 TODO）」。delete 已有 SDD audit，create/update 仍缺。
- **影響**：照護給藥（醫療資料）新增與修改無稽核軌跡，GLP §11.10 缺口。
- **驗證**：Confirmed in current main（`care_record.rs:230` TODO 註解、create/update 無 `log_activity_tx`）。
- **建議**：create/update 收 actor + `log_activity_tx`，event_type `CARE_RECORD_CREATE/UPDATE`。

### High-4 [#167 · compliance/atomicity] equipment `approve_disposal` / `restore_equipment` 非交易、無 audit、TOCTOU（legacy 未遷移 _tx）
- **檔案**：`backend/src/services/equipment.rs:1481`（approve_disposal）/ `:1571`（restore_equipment）
- **問題**：兩條 legacy 核准端點三筆寫入（UPDATE disposals / INSERT status_logs / UPDATE equipment）各自直接打 `pool`、**無 transaction**；讀 existing 無 FOR UPDATE、UPDATE 無 `AND status=...` 守衛 → 並發可重入；**全程無 `log_activity_tx`**。設備報廢/復活是 GLP 受監管資產生命週期動作。#167 只補了 SoD self-approve 守衛（`:1502`），未補交易/稽核。對照 `sign_disposal_approver_tx`（_tx 正確範本：tx + FOR UPDATE + 狀態守衛 + 稽核）。
- **影響**：資產處置核准缺稽核軌跡；中途失敗/並發造成 disposal 與 equipment 狀態不一致。
- **驗證**：Confirmed in current main（`equipment.rs:1512+` 直接打 pool、無 audit；routes/hr.rs disposal approve/restore 已掛載）。
- **建議**：兩條改 `pool.begin()` + `SELECT ... FOR UPDATE` + 狀態守衛 + 同 tx `log_activity_tx`，比照 `sign_disposal_approver_tx`。

---

## Medium

### Medium-1 [#153/#158/#170 · audit integrity] HMAC chain `created_at` 排序 vs advisory-lock 寫入序在並發下可分歧 → verifier 誤報斷鏈
- **檔案**：`backend/src/services/audit.rs:1078`（writer prev_hash 子查詢）/ `:818`（verifier 重播排序）
- **問題**：`log_activity` 的 `created_at` 沿用 `NOW()`（=transaction_timestamp，於 tx BEGIN 凍結），但 chain 連結順序由 `AUDIT_LOG_CHAIN_LOCK_KEY` advisory lock 取得序決定。若先 BEGIN 的 tx 後搶到 lock，writer 以 `ORDER BY created_at DESC` 取的 prev_hash 與 verifier 以 `created_at ASC` 重播的順序會不一致；`id` 為 v4 隨機，撞值 tiebreaker 亦隨機。
- **影響**：高並發時段 audit_chain_verify cron 可能誤報 `audit_chain_broken`（critical alert）→ 告警疲勞、稀釋真實竄改偵測。**非 integrity 喪失**。校準 Medium：本部署為 prod-on-laptop 單 instance、低並發，實際觸發機率低，但架構上存在。
- **驗證**：Confirmed in current main（writer/verifier 排序鍵不一致；migration 077 INSERT 未設 created_at）。
- **建議**：以「單調遞增 chain 序」取代 created_at 求 prev_hash（如 lock 區段內用 `clock_timestamp()` 或序號），writer/verifier 同步。屬 audit 架構/合規路徑變更，**高風險、建議 surface 後再動**。

### Medium-2 [#197 · compliance] `storage_location` 庫存編輯與調撥兩路徑無 audit（#197 只修了 create）
- **檔案**：`backend/src/services/storage_location.rs:320`（update_inventory_item）/ `:570`（transfer_inventory）
- **問題**：#197 把 `create_inventory_item` 改 tx + FOR UPDATE + `log_activity_tx`，但兄弟路徑 `update_inventory_item`（可把 on_hand_qty 直接覆寫任意非負值）與 `transfer_inventory` 皆不收 actor、不寫 audit。儲位庫存＝財務紀錄。
- **影響**：庫存被人工改寫/調撥無「誰何時改了多少」軌跡（GLP/財務可追溯缺口）。負庫存風險已由 tx 內 `WHERE on_hand_qty >= $1` 擋住，純稽核缺口。
- **驗證**：Confirmed in current main（`storage_location.rs:320/570` 無 actor/audit）。
- **建議**：兩函式比照 `create_inventory_item` 收 actor、tx 內 FOR UPDATE 取 before、同 tx 寫 `STORAGE_INVENTORY_UPDATE/TRANSFER`。

### Medium-3 [#179 · concurrency] transfer 步驟 2-5 狀態檢查在 tx 外、無 row lock
- **檔案**：`backend/src/services/animal/transfer.rs:220/284/343/390`
- **問題**：vet_evaluate / assign_plan / approve / complete 的 `before.status != Expected` 檢查皆透過 `get_transfer(pool, ...)`（plain pool SELECT，無 FOR UPDATE）在開 tx 之前讀，tx 內不重讀/重鎖。兩並發請求可各自通過檢查、各自 UPDATE → 狀態機重複推進 / vet_evaluations 重複插入。步驟 1 `initiate_transfer` 已正確 tx 內 FOR UPDATE（#179），2-5 未比照。
- **影響**：狀態機並發下可被重複推進；GLP 流程完整性風險。需兩同步請求且 transfer 罕用 → Medium。
- **驗證**：Confirmed in current main。
- **建議**：步驟 2-5 before 讀取移入 tx + `FOR UPDATE`。

### Medium-4 [#179 · authz] `approve_transfer` 無轉入 PI 角色區辨、無防自我核准（SoD 在狀態機層未落實）
- **檔案**：`backend/src/handlers/animal/transfer.rs:131`
- **問題**：步驟 4「PI 同意」只檢 `animal.record.create` + `require_animal_access`，與步驟 1 initiate 同權限，無轉入/轉出 PI 角色區辨、無防 `initiated_by == approver`。與 signature-signing-authority 模型（transfer 需 VET + 轉出/入 PI）在「狀態推進 handler 層」不一致（簽章層或有檢查）。
- **影響**：非 PI 角色可推進核准；SoD 在狀態機層未落實。
- **驗證**：Confirmed in current main（approve 用 `animal.record.create`）。
- **建議**：approve 增轉入 PI 角色檢查（或 service 層 `match actor` 角色）+ 防自我核准。

### Medium-5 [#194 · docs/correctness] `DB_ROLLBACK.md` migration 037 backfill runbook 與 verifier 行為矛盾，照做會誤報斷鏈
- **檔案**：`docs/db/DB_ROLLBACK.md:107-121`
- **問題**：runbook 要 ops `UPDATE user_activity_logs SET hmac_version=1 WHERE hmac_version IS NULL ...` 並稱「未 backfill 也等效（verifier 預設 v=1）」。但 migration 037 + verifier 明確採 **try-both**（NULL row 先試 v2、不符再 v1）——因 037 上線前 `log_activity_tx` 已寫 v2 編碼但 column 不存在，那批 row 實為 v2 但 hmac_version=NULL。
- **影響**：照 runbook 把 v2-but-NULL backfill 成 v=1 → verifier 走 explicit-version 用 v1 重算 → 不匹配 → 每日 cron 誤報斷鏈（合規告警污染）。
- **裁決（與驗證表一致）**：經逆向驗證**駁回 → ❌ 誤報，不納入修復批次**。理由：runbook 緊接的下一行已說明 verifier 採 try-both（NULL row 先試 v2、不符再 v1），文件內部一致；照 runbook backfill 的 v2-but-NULL row 仍會被 try-both 正確驗證、不會誤報斷鏈。單一結論以本裁決為準。
- **備註（代碼現況）**：`migrations/037` + `audit.rs:281-285` try-both 邏輯與 `DB_ROLLBACK.md:107-121` 並不矛盾；初判的「矛盾」係誤讀 runbook 上下文所致。如仍要強化文件清晰度，可於 runbook 補一句明示「v2-but-NULL 維持 NULL 即可」——屬選用文件潤飾，非缺陷修復。

---

## Low（摘要）

- **Low-1 [#138 · IDOR]** `get_animal_data_boundary`（`handlers/animal/transfer.rs:21`）缺 `require_animal_access`（#138 sweep 漏網）。僅回單一時間戳，低敏。建議補 access 檢查。
- **Low-2 [#140 · 偵測]** brute-force 僅以 email 為 key（`login_tracker.rs:198`），無 per-IP / password-spray 偵測 → 帳號列舉/噴密碼盲點。建議補 per-IP 失敗聚合。
- **Low-3 [#168 · authz]** `RoleService::update`（`role.rs:323`）未擋 is_system 角色權限改寫（delete 有擋）。緩解充分（閘門 dev.role.edit + ROLE_PERMISSION_CHANGE 稽核 + 可選簽章）→ 設計選擇，視產品政策決定是否補守衛。
- **Low-4 [#158/#170 · audit]** verifier `partition_date` filter 與 `created_at::date` 在 DB session TZ 非 UTC 時午夜邊界可能漏掃 row → 誤報。建議 after_connect `SET TIME ZONE 'UTC'`（⚠️ 不確定本機 PG timezone GUC，需實測）。

---

## 已驗證 solid / clean（備查）

- **R26 _tx 稽核架構**（已遷移路徑）品質高且一致：in-tx audit、FOR UPDATE、狀態守衛、SoD 齊備。確認的 audit 缺口都集中在「**未隨 R26 遷移為 _tx 的 legacy 路徑**」（vet_advice、care_record create/update、equipment disposal/restore、storage_location update/transfer）。
- **#155 protocol submit**：IACUC race 完整修復（row FOR UPDATE + advisory xact lock 同 tx）。
- **#183 medical bundle CRIT-02**：sacrifice/sudden_death 動物狀態+紀錄+audit 同 tx、animal FOR UPDATE。
- **#186 blood_test / #172 observation / #178 surgery / #181 vaccination / #184 animal_core**：SDD tx + before-snapshot FOR UPDATE + C1 簽章雙層守衛，audit 完整。
- **#160 HR leave / #161 overtime**：approve FOR UPDATE 序列化 + balance deduct 同 tx，無雙花。
- **#162/#168 user/role/2fa**：validate_role_assignment 防非 admin 指派 admin 角色、無 self-escalation。
- **#164/#190/#166/#191/#188 product/sku/partner/warehouse _tx**：cross-service mutation + audit 單一 tx；舊版非 _tx `log_activity` 已由 #188 移除。
- **#185 document/GRN**：approve 單 tx（stock + accounting SAVEPOINT + GRN 自動產 + over-receipt 守衛 + 主稽核）。
- **#128/#137 security hardening 仍成立**：JWT ES256 + aud/iss pinning、帳號狀態即時撤銷、rate-limit/honeypot/body-limit、health 資訊洩漏移除、自我提權防護皆未回歸。
- **#152 SMTP**：file-based secret + alertmanager yaml_escape；後端發信用 lettre 型別化 + sanitize_display_name，CRLF 結構性不可行。
- **Group E（#171 AI / #177 shutdown / #173/#192 dead_code / #193 DoD / #143 / #150 / #198 / #194 / #195）**：全數 clean（AI key 雙閘 authz、scheduler shutdown 無資料遺失、dead_code 無誤刪、templates 移出 VCS 不影響 runtime、audit redaction CI guard 完整、migration 033-037 rollback 正確、整合測試非 hollow）。

> 本報告僅列 verifier 確認於 current main 仍存在的 finding。R26 為現行 live 稽核架構，已遷移路徑品質高；缺口集中在未遷移的 legacy 路徑。
