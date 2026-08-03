# 程式碼審查報告：PR #1-100

> 建立日期：2026-06-08 ｜ 視角：current main ｜ 6 路平行 sub-agent + orchestrator 對 High 逐筆複驗

## 總結

PR #1-100 為專案**最早期**的 PR：~40 個 merged code PR（其餘為 closed dependabot / 純 docs）。這批程式碼經 R10–R63 大規模重構，**多數已被取代或重寫**——審查只保留「**仍存在於 current main**」的 finding。

確認仍存在的 finding：**High 2、Medium 7、Low 5**。架構重構組（#58/#59/#62）全數 superseded/clean，無 finding。

嚴重度：🔴Critical=可利用/資料毀損 · 🟠High=明確 bug/權限缺口/核心流程 · 🟡Medium=邊界/合規/可維護 · 🟢Low=風格/小缺陷。

## 驗證裁決（2026-06-08 adversarial verify，3 路逆向驗證）

| Finding | 裁決 |
|---|---|
| #55 IACUC 審查者匿名 | ✅ **確認需修**（匿名僅前端，handler 放行 PI 直讀真名/email） |
| #56 進銷貨 COGS（月度未沖 SR + 按類別 cogs=0） | ✅ **確認需修**（報表已使用，財務正確性） |
| #63/#97 facility 零 audit | ✅ **確認需修**（service+handler 0 AuditService、無 trigger） |
| #93 equipment 校正/報廢 CRUD 無 audit | ✅ **確認需修（Low）** |
| #91 AI「read」scope 過廣 | 🟡 **真但可接受**（admin-only 簽發；analytics 全域唯讀 by-design）→ 文件化 |
| #72 體重匯入 audit 歸 System | 🟡 **真但可接受**（audit 有寫、僅 actor 誤標；accountability 小瑕疵） |
| #48 終態動物 pen_id 未守 | 🟡 **真但可接受**（容量計算排除終態→cosmetic；可加一行守衛） |
| #61 SO/DO 計畫歸屬無 actor 授權 | 🟡 **真但可接受**（倉管代開銷貨工作流；建議跟使用者確認） |
| #91 AI protocols 無 is_internal 閘門 | ❌ **誤報**（protocols 表無 is_internal 欄；只回 metadata；#611 模型不適用） |

> 確認需修：#55 / #56 / #63·#97 / #93。修復計畫見 `docs/reviews/code-review-0-200-fix-plan.md`。

---

## High

### High-1 [#55 · security] IACUC 盲審審查者匿名僅靠前端隱藏，PI 可直接從 API 讀到審查者真名/email
- **檔案**：`backend/src/services/protocol/comment.rs:86`（+ `handlers/protocol/review.rs` list_review_comments）
- **問題**：reviewer 匿名（盲審）只在前端 `useCommentsData.ts` 以 `shouldAnonymizeReviewers` 決定顯示「審查者 A/B/C」或真名。後端 `get_comments` SQL 無條件 `SELECT COALESCE(u.display_name, c.reviewer_name) as reviewer_name, u.email as reviewer_email`，handler 對任何「與計畫相關」者（**含 PI 本人**，正是被匿名保護的對象）放行，回傳前不依角色裁剪欄位。
- **影響**：PI / 計畫成員可直接呼叫 `GET /api/v1/reviews/comments?protocol_id=...`（或開 DevTools 看 response）取得每則審查意見對應的審查者真實身分，繞過 IACUC 盲審匿名 → 審查者報復風險、審查獨立性受損（合規問題）。
- **驗證**：Confirmed in current main。`comment.rs:86` SQL 無 anonymize 分支；raw reviewer_name/email 已下發到瀏覽器（前端僅顯示時不用）。
- **建議**：service/handler 層依 viewer 角色裁剪——viewer 非 IACUC_STAFF/CHAIR/REVIEWER/VET/admin 時，回傳前清空 `reviewer_name`/`reviewer_email`（或以伺服器端穩定代號取代），不要把真名下發。

### High-2 [#91 · security] AI data-query key 的「read」scope 跨資料域過度授權（且為 migration 預設值）
- **檔案**：`backend/src/middleware/ai_auth.rs:75`
- **問題**：`has_scope` 對持「read」scope 的 key 一律放行所有 `.read` 結尾權限（`self.scopes.contains("read") && scope.ends_with(".read")`）。migration 017 預設 scope 就是 `["read"]`。因此任何以預設值建立的 AI key 同時可讀 `animal.read` / `protocol.read` / `facility.read` / `stock.read` / `hr.read`——跨動物、計畫、人資全部資料域，無最小權限。
- **影響**：管理員若以為「read」是受限唯讀，實際發出的是**全域唯讀萬用金鑰**；單把 key 外洩即等同全院區資料讀取權（含 protocols PI 名單、HR 概況）。違反最小權限。
- **驗證**：Confirmed in current main。`ai_auth.rs:72-76` 邏輯原樣保留；`handlers/ai.rs` 依此判定 required_scope。
- **建議**：移除「read → 全 `.read`」展開捷徑，要求 key 明列具體 scope；或把 migration 預設改為 `[]`，逼管理員顯式授權。

---

## Medium

### Medium-1 [#48 · correctness/compliance] 終態動物移動防護只擋 `pen_location` 文字欄，未擋 `pen_id` FK
- **檔案**：`backend/src/services/animal/core/update.rs:107-115`（守衛）vs `:136/:159`（pen_id 寫入）
- **問題**：終態（euthanized/sudden_death）守衛只檢查 `req.pen_location`（自由文字），但同一 UPDATE 的 `pen_id = COALESCE($10, pen_id)`（line 136，bind `req.pen_id` line 159）**無終態守衛**。已犧牲/猝死動物仍可經 `pen_id` 被指派到實體欄位。
- **影響**：終態動物 `pen_id` 可被竄改成有效欄位連結，與「終態不可移動」明確守衛矛盾，GLP 房舍紀錄語意不一致（pen 容量計算排除終態，故非容量污染，但記錄錯置）。
- **驗證**：Confirmed in current main（`update.rs:136` 無終態 CASE）。
- **建議**：終態守衛同時拒絕 `req.pen_id.is_some()`；或 SQL 改 `pen_id = CASE WHEN status IN ('euthanized','sudden_death') THEN pen_id ELSE COALESCE($10, pen_id) END`。

### Medium-2 [#72 · compliance] 體重批次匯入 audit 歸給 System，丟失真實匯入者
- **檔案**：`backend/src/services/animal/import_export.rs:514`
- **問題**：`process_weight_row` 硬寫 `ActorContext::System { reason: "weight_batch_import" }`，即使 handler 已認證真實使用者並把 actor 傳入。`AnimalWeightService::create` 用 `actor.actor_user_id()` → System → `SYSTEM_USER_ID`，真實匯入者 id 被丟棄。基本資料匯入（`process_basic_row`）卻正確用真實 actor。
- **影響**：每筆匯入體重的 `created_by` 與 audit 都記成「系統」而非實際人員——GLP 體重量測紀錄喪失操作者歸屬。
- **驗證**：Confirmed in current main（`import_export.rs:514`、`weight.rs` 用 actor 推導）。
- **建議**：把 handler 傳入的真實 `actor` 傳給 `AnimalWeightService::create`，移除 System 替換（批次匯入仍是已登入使用者行為，無理由匿名化）。

### Medium-3 [#91/#611 · security] AI 查詢回傳全院 protocols，無 is_internal / 可見範圍閘門（與 #611 MCP 修補不對齊）
- **檔案**：`backend/src/repositories/ai.rs`（query_protocols）
- **問題**：AI `protocols` 域查詢 `WHERE ($1 IS NULL OR status=$1)`，無 `is_internal` 過濾、無 `pi_user_id` 範圍限制，回傳所有計畫的 iacuc_no/title/pi_name。這正是 MCP read 路徑在 #611 被修掉的同類問題，但 AI(#91) 路徑從未補上。
- **影響**：持 AI key（依 High-2 預設 read 即含 protocol.read）者可列舉全部計畫基本資料含內部標記計畫。資訊外洩（非改寫，回摘要欄位，故 Medium）。
- **驗證**：代碼層面 query_protocols 確無 is_internal 條件；對照 #611 對 MCP 已加閘門。
- **裁決（與驗證表一致）**：歸『誤報 / 真但可接受』，**不納入修復批次**。理由：(a) protocols 表本身無 is_internal 欄，#611 的 is_internal 閘門模型不適用於此路徑（與表格 #91 列「誤報」一致）；(b) 殘留的「AI key 全域唯讀」範圍屬 by-design，依 High-2 裁決以文件化處理。此處僅保留代碼現況描述，單一結論以本裁決為準。
- **建議（若日後決定收斂）**：於 DESIGN/docs 明載「AI key=全域唯讀」並要求簽發走額外審核；非本批次工作項。

### Medium-4 [#56 · correctness/money] 按類別進銷貨報表 COGS 恒為 0、毛利等於銷貨額
- **檔案**：`backend/src/services/report.rs:654-659`
- **問題**：`purchase_sales_by_category` 的 `cogs_amount` 硬編 `0::NUMERIC`，`gross_profit` 直接等於 `sales_amount`（未扣任何成本）；且 DO/SR/RTN 全以正值相加（退貨被加進銷貨而非沖減）。
- **影響**：管理層看「按品類毛利」會得到嚴重高估的毛利 + 退貨灌大銷貨，做出錯誤品類決策。
- **驗證**：Confirmed in current main（`report.rs:654-659`）。
- **建議**：cogs 實查 stock_ledger 加權平均或 journal 5200 按類歸集；gross_profit = sales(扣退貨) − cogs；SR/RTN 改負向。

### Medium-5 [#56 · correctness/money] 月度進銷貨 COGS 只加借方，未沖減銷貨退貨的 5200 貸方
- **檔案**：`backend/src/services/report.rs:556-564`
- **問題**：`cogs_monthly` 用 `SUM(jel.debit_amount)` 計 5200。SR 銷貨退貨對 5200 寫貸方（`accounting.rs::post_sr`），但此查詢只計借方 → 有退貨月份 COGS 高估、gross_profit 低估。
- **驗證**：Confirmed in current main（`report.rs:556-564` vs `accounting.rs` post_sr 貸 5200）。
- **建議**：cogs 改 `SUM(debit_amount) − SUM(credit_amount)`（5200 淨額）。

### Medium-6 [#63/#97 · compliance] 設施（facility/building/zone/pen/department/species）模組所有 mutation 零 audit log
- **檔案**：`backend/src/services/facility.rs`（整檔）+ `handlers/facility.rs`
- **問題**：25+ 個 create/update/delete mutation 完全無 `AuditService::log_activity*`（service 與 handler 兩層皆無）。RBAC（`facility.manage`）正常，但結構性變更（改容量、停用棟舍、刪欄位）不進 GLP 防竄改 audit chain。其他模組已於 R26 遷移 Service-driven audit，facility 從未遷移。
- **影響**：GLP 環境下房舍結構異動無法回溯誰在何時改了什麼。
- **驗證**：Confirmed in current main（`facility.rs` 無 AuditService import）。
- **建議**：facility mutation 比照 animal/equipment 接 Service-driven audit。

### Medium-7 [#93 · correctness] 設備報廢核准 / 恢復 / 閒置核准的多筆寫入非交易性
- **檔案**：`backend/src/services/equipment.rs:1512` / `1600` / `1811`（approve_disposal / restore_equipment / approve_idle_request）
- **問題**：三者各用 2-3 條獨立 `sqlx::query`（更新申請狀態 + 寫 status_log + 更新 equipment 狀態）但**未包進 transaction**。維修路徑（`*_tx` 系列）已正確用 tx，這三條 legacy 核准路徑沒有。
- **影響**：第二/三條 query 失敗會留下「申請已核准但設備狀態未變」或「log 已寫但設備未更新」的不一致。
- **驗證**：Confirmed in current main（三條皆直接打 pool 非 tx；對比 `review_maintenance_record` 用 `pool.begin()`）。
- **建議**：三條核准路徑改 `pool.begin()` + `tx.commit()` 包覆，比照維修路徑。

---

## Low（摘要）

- **Low-1 [#91 · security]** AI key 以裸 SHA-256 儲存（無 HMAC/secret）；高熵 key 使暴力不可行，僅縱深防禦缺一層。建議改 HMAC-SHA256(server_secret, key)。（`ai_auth.rs:193`）
- **Low-2 [#61 · authz]** SO/DO 可歸屬到任一已核准計畫，僅驗計畫狀態（Approved）未驗 actor 對該計畫有權（`document/crud.rs:160`）。若場域政策為「倉管可代任意活躍計畫開銷貨」則屬預期——建議與使用者確認。
- **Low-3 [#95/#94 · correctness]** `DateTextInput`：不完整日期會把殘缺 ISO 寫進 `data-iso`（後端 NaiveDate 擋下回 400，不污染 DB）；湊滿 8 碼不驗日期有效性（`99999999`→`9999-99-99`）。建議完整且有效才輸出 + 即時提示。
- **Low-4 [#49 · correctness]** `leave_cancelled` 通知路由表（migration + routing UI 清單）從未被 `notify_leave_cancelled` 讀取 → dead config / 誤導 admin（設了收不到）。功能本身（通知原核准經手人）正常。
- **Low-5 [#93 · compliance]** 設備校正/報廢/CRUD 多數無 audit chain（屬 R26 未竟遷移範圍，非 #93 個別缺陷）。

---

## 已 superseded / clean（備查）

- **#1（GLP/電子簽章基礎）**：原 printpdf PdfService + 最初 signature handler 已被 R32（print-pdf/WeasyPrint）+ signature per-entity 重寫取代，原碼不存。
- **#58/#59/#62（架構重構）**：routes 模組化已改 ServiceBuilder + `.layer()`，無 route group 失去 middleware（反而 additive 加 guest_guard/ip_blocklist）；#62 實為 docs-only；#58 抽取的 pure functions 邏輯正確、測試仍在。**無 finding**。
- **#54（移除 activity_logger middleware）**：由 R26 Service-driven audit（`log_activity_tx` 遍布 services）+ `log_security_event` 取代，audit 覆蓋未降反升；data_import 動態 SQL 經 `is_export_table` 白名單把關。
- **#83 WAF 移除**：ModSecurity overlay 原為 DetectionOnly，app 層用參數化 SQL + DOMPurify + Argon2，無 code 層防護遺失。
- **#85 歡迎信**：已改傳 password-reset token，無明文密碼/列舉。
- **#52/#53/#47/#71/#75/#76/#80/#81/#57/#73**：純前端重構或欄位/i18n，後端授權獨立把關，無殘留問題。
- **#56 報表授權 / 金額型別**：三支 purchase-sales handler 已補 `require_permission!("erp.report.view")`；會計全用 `rust_decimal::Decimal`（R62 ledger）。**已修**（COGS 算法問題見 Medium-4/5）。
- **#61/#92/#84/#74/#77/#60/#70**：計畫狀態驗證已補、batch/expiry 重寫、product UPDATE SQL 等價抽取，無殘留正確性問題。

> 本報告僅列 verifier 確認於 current main 仍存在的 finding。早期 PR 多數已被後續重構覆蓋。
