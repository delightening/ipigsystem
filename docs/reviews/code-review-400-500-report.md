# Code Review — PR #400–#500（獨立安全 + 正確性審查）

> 自動化獨立 review：82 支已 merged PR，每支一 reviewer + 對每個 finding 做 adversarial verify（過濾假陽性）。
> 範圍 2026-05-14 ~ 05-26。產出 2026-06-06。**只列已驗證為真實的 finding。**

## 摘要

- 審查 PR：82 支
- raw findings：25；**經 adversarial verify 確認：16**（9 個判定假陽性已濾除）
- 分級：**High 3 / Medium 4 / Low 9**

## High（3）

### High-1　[#445 · correctness] 前端 requester 欄位與 backend schema 不符：external requester 的新增/編輯一律失敗

- **檔案**：`frontend/src/lib/api/byproductSample.ts`（byproductSample.ts:18-19 (ByproductSample.requester_text), 26-31 (CreateByproductSampleRequest.requester_text), 35-41 (UpdateByproductSampleRequest.requester_text); ByproductSampleDialog.tsx mutationFn requester_text 分支）
- **問題**：本 PR (#445, commit 5097cee1) 的前端是針對舊 schema 寫的，使用 requester_text 單欄。但 PR #452 (R53-14, commit b9db5dcb) 已先行 merge，migration 067_byproduct_requester_split.sql DROP 掉 requester_text 欄位，改成 requester_org_name + requester_contact_name 兩層，且 backend CreateByproductSampleHttpRequest / ByproductSample model 都不再有 requester_text。handler 未設定 serde deny_unknown_fields，因此前端送出的 requester_text 會被 backend 靜默丟棄 → 對 external requester 而言 requester_org_name / requester_contact_name / requester_user_id 全為 None → service 的 validate_requester() 直接回 AppError::Validation。結論：在 prod 上，凡選『外部（自由文字）』需求方的新增/編輯一律失敗，且錯誤訊息提到的是 org/contact 欄位（前端根本沒這欄），使用者無從修正。這是 review 漏掉的 backend/frontend 契約回歸，現仍存在。
- **建議修法**：更新 byproductSample.ts 的三個 TS interface 與 ByproductSampleDialog.tsx 表單：移除 requester_text，改為 requester_org_name + requester_contact_name 兩欄（external 模式兩欄都必填，對齊 backend validate_requester），並補上 special_equipment_used / work_started_at / work_ended_at billing 欄位。ByproductSamplesPanel.tsx 顯示處的 s.requester_text 也要改讀新欄位。建議同時在 backend handler 加 #[serde(deny_unknown_fields)] 讓此類契約漂移在測試/開發階段即 400 暴露，而非靜默丟棄。
- **驗證（adversarial）**：現行 main 仍存在契約回歸：frontend byproductSample.ts:29-30/38-39 與 ByproductSampleDialog.tsx:120 只送 requester_text，但 backend CreateByproductSampleHttpRequest (handlers/animal/byproduct_sample.rs:42-53) 無 deny_unknown_fields 且只認 requester_org_name/contact_name，外部需求方時 validate_requester (services/animal/byproduct_sample.rs:412-422) 因 user_id/org/contact 全 None 必回 AppError::Validation，外部新增/編輯一律失敗。

### High-2　[#447 · security] 週報端點缺少 per-animal/protocol 存取控制，project-scoped 角色可讀取全院所有豬隻病歷（broken access control / IDOR）

- **檔案**：`backend/src/handlers/animal_medical_report.rs`（33-46 (PR #447 原始：weekly_medical_report；現行檔同樣未加 access check)）
- **問題**：handler 只做 require_permission!(current_user, "animal.record.view")，service weekly_report(&state.db, &filter) 完全不依使用者所屬計畫做資料邊界過濾。但 animal.record.view 同時被 STUDY_DIRECTOR(PI) 與 CLIENT(委託人) 持有，而這兩個角色只有 animal.animal.view_project（計畫範圍），並非 view_all（見 startup/permissions.rs:518-556）。對照既有正確模式 handlers/animal/observation.rs:30-40 list_animal_observations 必須呼叫 access::require_animal_access(...)（view_all 直接放行，否則檢查是否為該動物所屬計畫成員）。週報端點繞過此檢查：任一 PI/委託人只要送出空 filter（{}），即可取回全院每一隻豬、跨所有計畫的 observation/surgery/blood_test timeline（含他人機密的手術、血檢、麻醉、體重資料）。filter 是使用者自選、非權限邊界，無法防止越權。這是跨計畫的水平越權（IDOR / 機敏資料外洩）。
- **建議修法**：在 service 端依 actor 收斂資料邊界：若使用者不具 has_protocol_view_all，必須將查詢限制在其相關計畫之 animals（沿用 access.rs 既有 protocol-membership 邏輯，例如把 accessible protocol_ids 注入 SQL 的 pr.id 過濾，或對每筆結果做 require_animal_access 等價檢查）。最小修法：在 handler 取得使用者可存取的 protocol 集合並強制 AND 進 filter（即使呼叫端 filter 為空，也只回該使用者計畫範圍內的資料）。view_all 角色維持全量。
- **驗證（adversarial）**：現行 handlers/animal_medical_report.rs:30-38 的 weekly_medical_report 僅做 require_permission!(animal.record.view)，service weekly_report(pool, filter)（services/animal_medical_report.rs:64-214）連 current_user 都未接收，SQL 僅依使用者自選 ear_tags/protocol_ids/dates 過濾，送空 body {} 時所有 WHERE 為 NULL→true 回傳全院跨計畫病歷；而 STUDY_DIRECTOR/CLIENT 僅持 animal.animal.view_project 非 view_all（permissions.rs:525,551），缺少 observation.rs:30-40 既有的 access::require_animal_access 邊界檢查，構成可觸發的跨計畫水平越權（read-only 資料外洩，故 High 非 Critical）。

### High-3　[#452 · correctness] 前端建立/編輯外部需求方 byproduct sample 全壞：仍送已移除的 requester_text，缺 org+contact 必觸 400

- **檔案**：`frontend/src/components/animal/ByproductSampleDialog.tsx`（107-120 (create payload), 102-110 (update payload)）
- **問題**：PR #452 把 backend DTO 的 requester_text 改成必須成對的 requester_org_name + requester_contact_name（external 路徑 validate_requester 要求兩欄都非空否則回 400），並 DROP 了 DB 欄位。但前端 dialog 仍只送 requester_text（serde 會直接忽略未知欄位），完全沒送 org/contact。結果：使用者在 UI 選『外部需求方』新增或編輯採樣紀錄時，backend 收到既無 requester_user_id 也無 org/contact → validate_requester 回 400『須提供 in-system FK 或同時填入機構+聯絡人』。external requester 的建立與編輯在 prod 完全無法使用。PR 把 frontend 列為 R53-14b defer，但這是會立即破壞既有功能的 breaking contract change，git log 確認 dialog 自 #445 後未再更動、R53-14b 至今未 ship，故 main 上仍是壞的。
- **建議修法**：在 R53-14b 落地前，前端 dialog 至少需把 external 路徑改送 requester_org_name + requester_contact_name（或暫時 backend 保留 requester_text 相容欄位做過渡）。理想做法：dialog 加機構/聯絡人兩個欄位、API type（byproductSample.ts:12/30/39）同步改欄位、移除 requesterText 單欄。
- **驗證（adversarial）**：現行 main 已驗證：dialog 在 external 模式只送已被 DROP 的 requester_text（ByproductSampleDialog.tsx:107-108,120；型別 byproductSample.ts:30,39 也無 org/contact），serde 直接忽略；HTTP DTO（handlers/animal/byproduct_sample.rs:42-53）只認 requester_org_name/requester_contact_name，service create 必呼 validate_requester(None,None,None)（services/animal/byproduct_sample.rs:166-170,407-424）回 400，等同單元測試 validate_requester_rejects_all_empty(:555)。R53-14b 未 ship（dialog 自 #445 後無相關改動），故外部需求方新增在 prod 必壞。

## Medium（4）

### Medium-1　[#410 · security] CSP 缺 base-uri 指令，削弱本 PR 新導入的 nonce + strict-dynamic 防護

- **檔案**：`frontend/security-headers.conf`（27）
- **問題**：本 PR 將 script-src 切換為 'self' 'nonce-$cspNonce' 'strict-dynamic' 'wasm-unsafe-eval'，整個防護核心是「只信任帶 nonce 的 script 以及它們動態載入的子 script」。但 CSP 字串中沒有 base-uri 指令（object-src 也沒有），而 CSP 規格中 base-uri 不會 fallback 到 default-src。對 nonce-based CSP 而言，注入 <base href="https://attacker"> 是教科書級的繞過手法：攻擊者若能注入一個 <base> 標籤，就能改寫頁面上以相對路徑載入之 script（含 strict-dynamic 動態建立的 script）的解析 origin，把信任鏈導向外部主機。換言之，本 PR 花大力氣移除 unsafe-eval / 第三方 CDN 並改用 nonce+strict-dynamic，卻因缺 base-uri 而留下一個可抵銷該強化的缺口。此缺口在舊 enforce header 也不存在（pre-existing），但正是本次 cutover 讓它變得 security-relevant。
- **建議修法**：在 add_header Content-Security-Policy 字串中加入 base-uri 'self'（或更嚴格的 'none'，若無動態 <base> 需求）。同時建議補上 object-src 'none' 明確封鎖外掛物件（雖 default-src 'self' 已涵蓋，明列較清楚）。
- **驗證（adversarial）**：現行 main 上 frontend/security-headers.conf:27 的單一 enforce CSP 確實只有 default-src 'self' 而無 base-uri（也無 object-src），且 CSP3 規格中 base-uri 不 fallback 到 default-src，故對本 PR 新導入的 nonce+strict-dynamic 信任模型，注入 <base> 改寫相對路徑 script 解析 origin 是公認的繞過缺口；惟需先存在 HTML 注入 sink 才能武器化，屬 defense-in-depth 強化缺口而非可獨立觸發漏洞，Medium 評級合理。

### Medium-2　[#443 · correctness] update 的 COALESCE 無法清空/切換 requester 欄位，導致 in-system↔external 互換時殘留舊值

- **檔案**：`backend/src/services/animal/byproduct_sample.rs`（~245-270 (UPDATE ... requester_user_id = COALESCE($4, requester_user_id), requester_text = COALESCE($5, requester_text)) 與 validate 區段 new_user_id = req.requester_user_id.or(before.requester_user_id)）
- **問題**：requester 設計為「二選一」：in-system researcher 用 requester_user_id，external 用 requester_text。但 update 對所有欄位都用 COALESCE，而 DTO 欄位皆為 Option<Uuid>/Option<String>，None 一律解讀成『不變更』。因此 caller 無法把已設定的欄位清成 NULL。實際後果：某筆原本 requester_user_id=Some(X)、requester_text=NULL 的紀錄，若要改為 external 需求方而送 requester_text="Dr.Y"，UPDATE 後該 row 會『同時』保有舊的 requester_user_id=X 與新的 requester_text=Y，舊的 in-system 關聯永遠清不掉。validate_requester 也因為 .or(before...) 一律拿得到舊值而判定通過，無法偵測這個殘留。結果是稽核紀錄中需求方歸屬變得語意模糊（兩個都有值），且違反『二選一』的原始設計意圖。此 COALESCE 模式在目前 main 上的同函式仍存在（requester_user_id / requester_org_name / requester_contact_name 三欄皆 COALESCE）。
- **建議修法**：區分『不變更 (欄位缺省)』與『顯式清空 (送 null)』：可改用 Option<Option<T>> + #[serde(default, deserialize_with=...)] 的雙層 Option，或在 service 對 requester 群組做『若 caller 任一 requester 欄位有送值，則整組以 caller 提供值覆寫(含清空另一欄)』的明確處理，而非逐欄 COALESCE。至少在切換 requester 類型時，把另一型別欄位顯式 SET NULL 並重跑 validate_requester。
- **驗證（adversarial）**：現行碼 byproduct_sample.rs:322-324 三個 requester 欄全用 COALESCE($n, col)，None 一律解讀為不變更，故由 in-system 切 external（送 org+contact、requester_user_id 留 None）無法清掉舊 requester_user_id；migration 067:48-54 的 CHECK 只是 OR（非 XOR），雙值殘留為合法 row，validate_merged_invariants:294 的 .or(before) 又拿到舊值而放行，月結報表:509-512 再優先顯示殘留的 requester_user_id，造成稽核歸屬錯誤——問題真實且可觸發，但屬不常見的「切換需求方」編輯路徑且可回復，維持 Medium。

### Medium-3　[#445 · correctness] 列表顯示讀取已不存在的 requester_text，external requester 顯示為 (系統內 user) undefined

- **檔案**：`frontend/src/components/animal/ByproductSamplesPanel.tsx`（ByproductSamplesPanel.tsx 需求方顯示行：requester_text ?? `(系統內 user) ${requester_user_id}`）
- **問題**：顯示邏輯 s.requester_text ?? `(系統內 user) ${s.requester_user_id}`。因 backend JSON 已不再含 requester_text key，s.requester_text 永遠是 undefined，對所有 external requester 紀錄都會落入 fallback 分支，渲染成『需求方：(系統內 user) undefined』（external 紀錄的 requester_user_id 也是 null）。即使既有 prod 已有 external 資料也會顯示錯亂。屬同一契約漂移的讀取端回歸。
- **建議修法**：改為讀新欄位：internal 用 requester_user_id（理想是顯示 display_name，需 backend 提供），external 顯示 `${requester_org_name} / ${requester_contact_name}`。對齊 backend list_monthly_report 的 requester_display 組法。
- **驗證（adversarial）**：現行碼確證：migration 067 DROP 了 requester_text 並改成 requester_org_name+requester_contact_name，backend entity byproduct_sample.rs:33-44 序列化的 JSON 已無 requester_text key，但 ByproductSamplesPanel.tsx:146 仍讀 s.requester_text ?? `(系統內 user) ${s.requester_user_id}`，故所有 row 永遠落入 fallback；external requester 的 requester_user_id 為 null（不是 undefined，描述小誤），渲染成「需求方：(系統內 user) null」，且新的 org/contact 欄位完全不顯示。屬顯示層回歸，Medium 合理。

### Medium-4　[#447 · security] 大量機敏病歷讀取端點缺少 audit 紀錄

- **檔案**：`backend/src/handlers/animal_medical_report.rs`（29-34 (PR #447)）
- **問題**：weekly_medical_report 一次回傳跨計畫、最多 5000 筆的豬隻醫療 timeline（手術/血檢/觀察/麻醉細節），屬高敏感的 bulk read，但 handler 未呼叫 AuditService。對照 handlers/data_export.rs:71-128，本專案對 bulk data export 一律寫 AuditService::log_activity_oneshot(event_type="DATA_EXPORT")。此端點同性質（大量機敏資料外流面）卻無任何 audit trail，事後無法追查誰在何時撈走哪些豬的病歷，與專案 audit-first 政策不一致。
- **建議修法**：在 handler 成功回傳前呼叫 AuditService 記一筆 read/export 類事件（event_type 如 "ANIMAL_MEDICAL_REPORT_QUERY"），帶入 actor、filter 內容（耳號/計畫/日期區間）與回傳筆數。
- **驗證（adversarial）**：現行碼 animal_medical_report.rs:30-88 三個端點（JSON/xlsx/pdf）皆無任何 AuditService 呼叫，service weekly_report 回傳最多 5000 筆跨計畫機敏 timeline（truncate 在 services/animal_medical_report.rs:211），route 已註冊（routes/report.rs:56-65）且僅 require_permission!("animal.record.view") 守衛、無 read 端 audit middleware；對照 handlers/animal/pdf_export.rs:63-77 連單一豬隻醫療匯出都寫 EXPORT_MEDICAL，本 bulk 匯出無 audit trail 屬真實且一致性破口。

## Low（9）

### Low-1　[#402 · correctness] watcher 以 $LASTEXITCODE 判斷 deploy 成敗，但 deploy-prod.ps1 成功路徑為 fall-through（無 exit 0），可被殘留的非 0 exit code 污染 → 誤報「Deploy 失敗」

- **檔案**：`scripts/auto-deploy-watcher.ps1`（92-103）
- **問題**：PR #402 把 watcher 改成 `& $DeployScript *>&1 | Tee-Object ...` 後以 `$deployExit = $LASTEXITCODE`（line 93）判斷成敗。問題在於 deploy-prod.ps1 的『成功』路徑並沒有顯式 `exit 0`——它一路 fall-through 到檔尾（deploy-prod.ps1 line 141 只剩 Write-Host）。當子 script 以 fall-through 結束時，`$LASTEXITCODE` 不是被 script 設為 0，而是保留『腳本內最後一個 native command』的 exit code。健康檢查迴圈（deploy-prod.ps1 line 110-123）中，若 `ipig-api` 容器在超時前一直不存在 / 名稱不符，`docker inspect ... 2>$null`（line 112）會以非 0 結束；30 次重試全部失敗後，迴圈走 timeout WARN 分支（line 124-127，本身也無 exit），script fall-through 時 `$LASTEXITCODE` 會殘留 docker inspect 的非 0 值。此時 api+web 其實已成功 build+up（line 88/98 都通過了），但 watcher 會因殘留 exit code 記下『Deploy 失敗（exit N）』的假警報，誤導值班者手動介入。即使健康路徑通常殘留 0，依賴『最後一個 native command 剛好 exit 0』來代表整支 deploy 成功，是脆弱且非顯式的契約。
- **建議修法**：在 deploy-prod.ps1 成功路徑結尾（line 141 之後）明確加 `exit 0`，並在健康檢查超時 WARN 分支（line 124-127）後也明確 `exit 0`（既然已決定視為非致命）。如此 watcher 端 `$LASTEXITCODE` 才是 deploy 腳本刻意設定的回傳碼，而非殘留的 native command exit。watcher 端可額外保險：把 `$deployExit` 來源從 fall-through 改為要求 deploy 腳本一律以顯式 exit code 結束。
- **驗證（adversarial）**：現行 deploy-prod.ps1 成功/超時路徑確為 fall-through 無 exit 0（line 124-141 僅 Write-Host），健康檢查超時時迴圈最後一次 docker inspect（line 112，容器不存在/名稱不符時 exit 1，已實測確認）的非 0 值會殘留至 EOF（Write-Host 為 cmdlet 不重置 $LASTEXITCODE），watcher line 93 捕捉後在 line 101-102 誤記「Deploy 失敗」，但 build(88)/up(98) 實際已通過 — 真實假警報。

### Low-2　[#404 · correctness] 全域 EAP=Continue 後，git status --porcelain 缺 $LASTEXITCODE 檢查，弱化 dirty-tree 安全守門（且註解宣稱「每個 native command 都已檢查」不實）

- **檔案**：`scripts/deploy-prod.ps1`（48 (註解 22-27)）
- **問題**：本 PR 把 $ErrorActionPreference 從 "Stop" 改為全域 "Continue"，並在註解（L22-27）明確宣稱「本 script 對每個 native command 都已手動檢查 $LASTEXITCODE，不依賴 EAP=Stop」。但 L48 的 `$dirty = git status --porcelain` 之後並沒有 $LASTEXITCODE 檢查——這是唯一例外，註解與實際不符。在舊版 "Stop" 模式下，git status 若 hard fail（例如 index 損毀、.git 被 lock、git 因警告回傳非 0）會直接拋出中斷；改為 "Continue" 後，這類失敗會讓 $dirty 變成空值，腳本誤判工作目錄為 clean，越過「避免覆寫本地修改」的 pre-flight 守門，繼續往下 git pull / build。雖然後續 `git pull --ff-only` 對已 commit 歷史有保護，但對追蹤檔案的未 commit 修改仍有被覆寫或被打包進 image 的風險。屬部署路徑的安全守門退化，且 PR 自己的註解作出了不正確的全稱保證。
- **建議修法**：在 L48 後比照其他 native command 補上檢查：
```powershell
$dirty = git status --porcelain
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ABORT] git status 失敗（exit $LASTEXITCODE）" -ForegroundColor Red
    exit 1
}
```
如此註解 L22-27 的「每個 native command 都已檢查」才成立。
- **驗證（adversarial）**：現行 scripts/deploy-prod.ps1:48 的 `git status --porcelain` 確實在 EAP=Continue（L28）下無 $LASTEXITCODE 檢查（L49 僅 `if ($dirty)`），與 L26-27 註解「對每個 native command 都已手動檢查」的全稱保證不符；git status hard-fail 且空 stdout 時 dirty-tree 守門會被略過。屬真實但極低嚴重度的 correctness 缺口——precondition 受限（L37-41 已先檢查 git rev-parse，corrupt/locked .git 多半在此即 abort），且後續 L63 `git pull --ff-only` 對追蹤檔案修改仍提供保護，非可利用的安全漏洞，Low 評級合適。

### Low-3　[#410 · correctness] csp-smoke.mjs 在 SIMULATE_CUTOVER 模式下 nonce 抽取會 silent fallback 成無效字串，產生誤導性結果

- **檔案**：`scripts/csp-smoke.mjs`（44-49）
- **問題**：buildCutoverCsp 只從現行回應的 Content-Security-Policy-Report-Only header 抽 nonce（const ro = originalHeaders['content-security-policy-report-only']）。但本 PR cutover 後，prod 已不再送出 Report-Only header（已合併為單一 enforce header）。因此一旦對 cutover 後的 prod 跑 SIMULATE_CUTOVER=1，nonceMatch 為 null，nonce 會 fallback 成字面值 'simulated-cutover-nonce'，與 HTML 中 nginx sub_filter 實際注入的 $request_id nonce 不符 → 所有 nonce 簽署的 inline script 全被 refuse → 產生大量假違規（false positive），讓人誤判 cutover 有問題。反過來，若這支腳本被當成 gate 卻在無 RO header 環境下執行，fallback 也讓「模擬 enforce」失去意義。屬測試工具的靜默降級。
- **建議修法**：當 SIMULATE_CUTOVER=1 但抓不到 nonce 時，應從現行 enforce header（content-security-policy）抽 nonce 作為 fallback，或在 nonce 抽取失敗時直接 console.error 並 exit 非 0，而非靜默套用一個保證失敗的字面 nonce。
- **驗證（adversarial）**：現行 scripts/csp-smoke.mjs:40-42 仍只從 content-security-policy-report-only 抽 nonce，而本 PR 的 frontend/security-headers.conf:27 cutover 後已移除 RO header（僅剩單一 enforce），故對 cutover 後 prod 跑 SIMULATE_CUTOVER 時 nonceMatch 必為 null、fallback 成 'simulated-cutover-nonce'，與 nginx.conf:30 sub_filter 注入 HTML 的 $request_id nonce 不符 → nonce 簽署的 inline script 全被 refuse → 假違規，無上游守衛攔截；但僅為手動 smoke 工具（未進 CI / package.json gate），且 SIMULATE 模式於 cutover 後本已邏輯過時，blast radius 極小，維持 Low。

### Low-4　[#419 · correctness] .trivyignore libpng 抑制理由與 Dockerfile 實際 apk upgrade 矛盾，可能誤導未來 review

- **檔案**：`.trivyignore`（4-10）
- **問題**：此 PR 為純基礎映像/套件升級（nginx-brotli 1.29.5→1.31.0 + apk upgrade），無任何應用層程式碼（無 Rust handler/service/repository、無 SQL、無 React），因此不存在 IDOR / 權限繞過 / 注入等存取控制風險。唯一具體矛盾在 audit 文件本身：.trivyignore 第 4 行仍宣稱忽略 CVE-2026-25646 的理由是『升級 libpng 需 apk upgrade，會導致 Brotli 模組 ABI 不相容、nginx 無法啟動』（版本 1.6.54-r0 → 1.6.55-r0），但同 PR 的 frontend/Dockerfile 第 59 與 66 行『實際就在 apk upgrade libpng』且註明版本為 1.6.55-r0 → 1.6.56-r0。兩處對「libpng 是否升級 / 目前版本」的陳述彼此衝突：若 Dockerfile 真的已升級 libpng，則 trivyignore 的『不能升級會壞 ABI』理由已過時、CVE-2026-25646 是否仍需忽略需重新評估；反之若 apk 因 ABI 風險實際被略過，則 Dockerfile 註解的版本宣稱不實。無論哪種，未來 reviewer 依此 audit 文件判斷『libpng 是否已修補』都會被誤導。此為文件/audit 正確性問題，無 runtime 行為 bug（apk upgrade libpng 在 build 時照常執行）。
- **建議修法**：以實際 build 後 Trivy 重掃結果為準對齊兩份文件：若 libpng 已成功升至 1.6.56-r0 且 nginx 仍能啟動，則更新 .trivyignore 第 4-10 行的理由（移除『會壞 ABI 故不升級』論述）並評估能否直接移除 CVE-2026-25646 條目；若實測 ABI 確實不相容導致 apk 略過 libpng，則修正 Dockerfile 第 59 行的版本宣稱。兩者擇一使陳述一致。
- **驗證（adversarial）**：現行碼確有矛盾：.trivyignore:6 的抑制理由仍宣稱「升級 libpng 需 apk upgrade 會破壞 Brotli ABI、nginx 無法啟動」且版本標 1.6.54→1.6.55-r0，但同 repo frontend/Dockerfile:66 實際 `apk upgrade ... libpng`、:59 註明 libpng 1.6.55-r0→1.6.56-r0（且 :54 澄清 ABI 顧慮僅針對全系統 apk upgrade，非單套件），因此 trivyignore CVE-2026-25646 的理由已過時、會誤導未來 reviewer 判斷 libpng 是否已修補；惟此為純 audit/文件正確性問題、無 runtime 行為 bug 或可利用路徑，維持 Low 適切。

### Low-5　[#441 · security] verify_internal_token fail-open：prod 端 secret 為空/不可讀時靜默停用全部 PDF 端點驗證

- **檔案**：`services/print-pdf/main.py`（64-110 (_load_internal_token + verify_internal_token)）
- **問題**：_load_internal_token() 在 PDF_SERVICE_TOKEN env 與 PDF_SERVICE_TOKEN_FILE 皆解析為空字串（含檔案讀取 OSError、或 secret 檔內容為空白/零長度）時回傳 ""，導致 INTERNAL_TOKEN 為空。verify_internal_token() 開頭 `if not INTERNAL_TOKEN: return` → 對全部 12 個 render 端點（/api/render + 11 個 /render-*）直接放行，不再驗 token。這些端點渲染高敏資料（醫療紀錄、動物資料、audit log 匯出、手術/血檢報告）。雖然有 log.warning 提示「validation DISABLED」，但屬 fail-open：一旦 prod 的 Docker secret 掛載失敗或 secret 檔被意外清空，print-pdf 會在 backend network 內無聲地以匿名可存取模式運行，正是本 PR 想堵的攻擊面（遭入侵容器直打 PDF 端點）。對齊本專案 CLAUDE.md「fail-safe-on」與 audit_hmac fail-safe 慣例，安全敏感路徑應 fail-closed。
- **建議修法**：以環境旗標區分 dev/prod 的空 token 語意：例如讀 ENV/APP_ENV，當判定為 production 且 INTERNAL_TOKEN 為空時，在啟動階段 raise / sys.exit(1)（fail-closed，拒絕在無 token 下啟動），僅在明確 dev/test 環境才允許 no-op pass-through。或最低限度：當 PDF_SERVICE_TOKEN_FILE 已設定但讀取失敗/為空時提升為啟動失敗，而非降級為匿名放行。
- **驗證（adversarial）**：現行 main.py:104 `if not INTERNAL_TOKEN: return` 確實 fail-open：_load_internal_token (main.py:69-84) 在 secret 檔讀取 OSError/空值時回 ""，使全部 render 端點放行，違反專案 fail-safe-on 慣例；但僅在 secret 掛載失敗等複合故障下才觸發（prod secrets/pdf_service_token.txt 現有有效 token 且已 mount，驗證實際為 ENABLED），屬防禦性 hardening 而非當前可利用漏洞，Low 評級正確。

### Low-6　[#443 · correctness] delete 的 audit DataDiff 把 soft-delete 記成一般欄位變更，before/after changed_fields 只含 deleted_at/updated_at

- **檔案**：`backend/src/services/animal/byproduct_sample.rs`（delete (~205-230) data_diff: Some(DataDiff::compute(Some(&before), Some(&after)))）
- **問題**：delete 走 soft delete，after 是僅 deleted_at/updated_at 改變的同一筆 row。DataDiff::compute(Some, Some) 走 UPDATE 語意，changed_fields 只會列出 ["deleted_at","updated_at"]，而非把它當成刪除事件記錄完整 before 快照。雖然 event_type=BYPRODUCT_SAMPLE_DELETE 已表達意圖，但與 create 用 create_only、語意上 delete 應對齊 delete_only(before) 以保留完整刪前快照不一致；稽核回溯時 diff 內容資訊量偏低。
- **建議修法**：delete 改用 DataDiff::delete_only(&before)（before=完整快照, after=None, changed_fields=["*"]），與 create 的 create_only 對稱，保留刪除前完整內容於稽核。
- **驗證（adversarial）**：現行碼 byproduct_sample.rs:395 delete 確實傳 DataDiff::compute(Some(&before), Some(&after))，after 為僅 deleted_at/updated_at 改動的同列，依 audit_diff.rs:102 diff_object_keys 走 UPDATE 語意，changed_fields 變 ["deleted_at","updated_at"] 而非 delete_only(before) 的 ["*"]；before 完整快照仍有保留故無資料遺失，純屬與 create_only 不一致、稽核 changed_fields 查詢資訊量略低，Low 合理。

### Low-7　[#445 · correctness] AnimalDetailPage 寫死 euthanasiaId={null}，新增採樣按鈕在所有動物頁永遠不可用

- **檔案**：`frontend/src/pages/animals/AnimalDetailPage.tsx`（AnimalDetailPage.tsx <ByproductSamplesPanel euthanasiaId={null} />）
- **問題**：euthanasiaId 硬編為 null，handleAdd 永遠走『此動物尚無安樂死單』分支、Add 按鈕實質失效。雖然 PR 描述/PROGRESS.md 自承這是 Follow-up（view-only 模式），但結果是此 PR 交付的『CRUD UI』實際只有 R/U/D（透過既有列才能編輯/刪除），Create 入口完全無法使用。屬已知降級而非隱藏 bug，列為 Low 供追蹤。
- **建議修法**：依 Follow-up 規劃，從 iacucEvents / euthanasia query 抓最近一筆 euthanasia order id 傳入；在補上之前可考慮隱藏 Add 按鈕（而非顯示後點了才報錯），降低使用者困惑。
- **驗證（adversarial）**：現行碼 SacrificeTab.tsx:110 仍硬寫 euthanasiaId={null}，使 ByproductSamplesPanel.tsx:77 的 handleAdd 永遠走「此動物尚無安樂死單」toast 早退、line 173 create dialog 因 Boolean(euthanasiaId) 永不渲染，因此對有 write 權限者「新增採樣紀錄」按鈕（line 121）永遠失效；屬已知 view-only Follow-up 降級（檔內註解 + PROGRESS r53 佐證），無資料/安全影響，Low 適當。

### Low-8　[#447 · correctness] 現行版本排序方向反向 + truncate 會丟掉最新事件（PR #447 後續 R53-10b 引入的回歸）

- **檔案**：`backend/src/services/animal_medical_report.rs`（210-211 (現行 main；PR #447 原始為 SQL 內 ORDER BY event_date DESC, created_at DESC LIMIT 5000，正確)）
- **問題**：PR #447 原始 SQL 用 ORDER BY event_date DESC ... LIMIT 5000，保留最新 5000 筆。現行 main 改為多表分查後在 Rust 端 rows.sort_by(event_date ASC, created_at ASC) 然後 rows.truncate(5000)。升冪排序 + truncate 會保留最舊 5000 筆並丟棄最新事件，且回傳順序變成舊→新，與「週報應看最近事件」語意相反。資料量超過 5000 時，使用者拿到的是最舊資料而非最近一週/最近事件。（此回歸非 PR #447 引入，但目前 production 仍存在。）
- **建議修法**：改為降冪排序：rows.sort_by(|a,b| b.event_date.cmp(&a.event_date).then(b.created_at.cmp(&a.created_at))) 再 truncate(5000)，回到 PR #447 原本 DESC + 保留最新的語意。
- **驗證（adversarial）**：現行 main `animal_medical_report.rs:210-211` 確為升冪排序 `sort_by(event_date ASC, created_at ASC)` 後 `truncate(5000)`，與 R53-8 spec / PR #447 原始 `ORDER BY event_date DESC ... LIMIT 5000` 相反；handler 與 frontend 皆未再重排，故 (a) 回傳順序變舊→新，(b) 一旦三表合併 >5000 筆（empty filter 可觸發）會丟掉最新事件而非最舊。問題真實存在，惟 truncate 丟資料需單次查詢逾 5000 筆（單獸醫小規模場景觸發機率偏低、且為靜默丟失），Low 評級合理。

### Low-9　[#450 · security] stale-tab 降級條件 baseline_missing 範圍超出註解宣稱的「pre-R46-2 legacy」，涵蓋所有「從未正常 rotation 即被撤銷」的 token

- **檔案**：`backend/src/services/auth/session.rs`（229 (classify_reuse_severity 呼叫，傳入 token.last_ip.is_none() && token.last_user_agent.is_none()); 配合 82-83、254-266）
- **問題**：註解 (constants.rs:120-124 與本檔 222) 宣稱 baseline 為 NULL 代表「pre-R46-2 legacy data 或從未經過 rotation」屬於可安全降級的歷史資料。但實際上 last_ip / last_user_agent 在整個 codebase 中『只』在 normal rotation 路徑 (line 82-83) 被寫入。所有其他撤銷路徑——family revoke (254-266)、idle timeout (153-156)、password change——都不寫 last_ip/last_user_agent。因此任何『登入後尚未做過任何一次 rotation 就被撤銷』的 token，其 last_ip/last_user_agent 仍為 NULL。這類 token 是現行系統持續產生的（非歷史 legacy）：例如使用者登入拿到 refresh token，因同 family 另一 token 被偵測 reuse 而整 family revoke，該 fresh token 永遠沒機會 rotation。若攻擊者竊得這種 never-rotated token，在被撤銷超過 1 小時 (REFRESH_TOKEN_REUSE_STALE_THRESHOLD_SECS=3600) 後重用，severity 會被降為 warning，而非反映真實外洩風險的 critical。family revoke 與 alert 仍會觸發，故影響限於『告警優先級被低估、SOC 可能漏看』，非完全 fail-open；但降級觸發面比註解宣稱的『legacy 過渡期資料』寬得多，且會長期存在而非隨 legacy 資料淘汰而消失。
- **建議修法**：若意圖僅針對 pre-R46-2 歷史資料，應改用更精準的 legacy 判定（例如 token.created_at < R46-2 部署時間，或新增明確的 schema 標記欄位），而非用 baseline_missing 當代理。若意圖確實涵蓋所有 never-rotated token，請更新 constants.rs 與本檔的註解，明確說明此降級對『現行持續產生的 never-rotated revoked token』也生效，並評估是否額外加條件（例如僅在 client_ip == 該 token 所屬 family 任一存活 token 的 last_ip 時才降級）以縮小被竊 token 跨裝置重用被誤降的窗口。
- **驗證（adversarial）**：代碼聲明屬實 —— last_ip / last_user_agent 僅在 session.rs:82-83（正常輪換路徑）中寫入，因此任何從未進行過輪換的 token（如 family-revoke 254-266、idle 153-156、password-change 542-564 皆會保持 NULL）在第 229 行會觸發 baseline_missing=true，並在撤銷超過 3600 秒後重用時降級為 warning；但其影響僅限於警報的嚴重度標籤（該 token 在第 56 行仍會被拒絕為 Invalid，且整個 token 家族仍會被撤銷，並寫入警報 —— 並非故障開放），權威的 constants.rs:122 註解也已說明「從未經過 rotation」的情況，因此其範圍並非未公開。對於所提及的單人獸醫系統且無 SOC 的場景，此「警報優先級被低估」的影響微乎其微 —— 評級為 Low 而非 Medium 是合理的。

