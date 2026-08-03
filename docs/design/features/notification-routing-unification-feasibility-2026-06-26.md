# 通知路由統一化 — 可行性評估與架構建議

> **日期**：2026-06-26　**狀態**：評估中（尚未動 code，待裁定方向）
> **目標（使用者原話）**：對整個通知路由做更新，**不要有寫死通知**，全部都要經過路由設定。
> **前置**：見 `docs/audit/notification-routing-vs-actual-2026-06-26.md`（現況落差稽核）。

---

## 1. 語意澄清：兩種解讀，差別極大（**最關鍵決策**）

「全部經過路由、零寫死」可落成兩種完全不同的架構：

| | (a) 純角色路由 | (b) 統一派送 + Resolver（**推薦**） |
|---|---|---|
| 模型 | `event × role_code` 靜態表，收件人＝持有該角色的所有人 | 每事件宣告「收件人來源（角色 or 關係解析器）＋管道」，走同一派送管線 |
| 關係型通知 | ❌ 無法表達「這張假單的申請人」 | ✅ 用 relational resolver 解析 |
| 隱私風險 | 高（把私人通知廣播給整個角色） | 低（resolver 精準解析當事人） |
| 是否「零寫死」 | 表面零寫死，實際**做不到**（會壞掉一半通知） | 真零寫死：handler 只發事件＋給 context，不決定收件人 |
| 業界對應 | 不存在純此模型的成熟產品 | Novu / Knock / Courier 的 actor-recipient + workflow 模型 |

**結論：必須走 (b)。** 純角色路由 (a) 會讓 8 個關係型通知退化（見 §4）。
以下評估全部以 (b) 為前提。

---

## 2. 為什麼純角色路由不可行：收件人有「兩種本質」

現行通知的收件人，本質上分兩類：

- **角色型 (role-based)**：「所有 VET」「所有 IACUC_STAFF」「所有倉管」
  - 現行 `notification_routing(event_type, role_code)` 已能表達。
  - 例：`leave_submitted` → 通知所有 ADMIN_STAFF（誰來審都行）。✅ 合理。
- **關係型 (relational / actor-recipient)**：對象由「**這個實體的關係**」決定，而非「持有某角色的所有人」
  - 「**這張**假單的申請人」「**這個**計畫的 PI/SD」「被指派審**這個**計畫的委員」「**這張**安樂死單的開單獸醫 / PI / CHAIR」
  - 靜態 `(event × role)` 表**無法**表達——因為它問的是「持有角色 X 的人」，答不出「實體 Y 的那個特定人」。

**現行 8 個死路由幾乎全是關係型**（見稽核報告）：
`leave_approved`=申請人本人、`leave_cancelled`=核准經手人、`overtime_approved`=申請人、`euthanasia_order_created`=該單 PI/VET/CHAIR、`vet_recommendation_created`=該計畫 PI/SD、`emergency_medication`=VET+該計畫 PI。

> 把這些塞進角色路由的後果：「你的假單核准了」會寄給**全體 ADMIN_STAFF**；「安樂死單」會寄給**全院 VET** 而非開單那位。→ 隱私外洩 + 雜訊爆炸。
> 這正是為何原作者當初把它們寫死——**寫死是錯的手段，但要解的問題（關係型對象）是真的**。

---

## 3. 業界做法（Novu / Knock / Courier）

成熟通知基礎設施的共識架構（查證自三家主流平台文件）：

- **Actor / Recipient 模型 + Workflow 引擎 + Subscriber 偏好**。
- **關鍵分工**：
  - **WHO（收件人）**：在「**觸發時**」解析並傳入 workflow。角色/群組型用 **Topics**（訂閱式）；關係型對象由**應用程式碼算出後傳入** subscriber。→ 收件人**不是**全部塞在靜態 config，而是「config 宣告來源 + 程式解析」。
  - **HOW（管道與偏好）**：channel routing + 每使用者 preferences 由 **config + 偏好表**控制。
  - **WHAT（內容）**：template 由 config 控制（本專案已有 `services/email/*` render）。
- **三層分離**正是本專案目前**最缺**的：現在 WHO/HOW/WHAT 混在每個 `notify_*` 函式裡，且每個函式各做各的。

**對本專案的啟示**：不需要引入 Novu/Knock（它們是 self-host 服務 / 外部 SaaS，撞本專案「strict CSP / 最小依賴 / solo prod 自管」規範，且 overkill）。**借用它們的「模型」，用最小內建實作**即可。

---

## 4. AI 時代的補充建議（使用者要求「AI 的建議」）

- **AI 不參與「誰該收」的判定**。收件人解析必須 deterministic + 可稽核（HMAC audit chain 精神、合規路徑）。把收件人交給 LLM 判斷＝引入不可稽核的隱私決策，**不可**。
- **AI 適合的位置**（皆屬 enhancement，非本次核心，可日後接）：
  1. **批次 digest 智慧聚合**：低庫存/效期 daily 通知可由 LLM 生成自然語言摘要（目前是樣板拼字串）。
  2. **通知優先級 / 去重**：異常紀錄、緊急給藥的輕重排序。
  3. **文案在地化**：已有 template，可選 LLM 潤飾。
- **本次核心是 config-driven dispatch，不是 AI-driven routing。** AI 留作後續可選層，不納入本次重構範圍，以免混淆成功標準。

---

## 5. 目標架構：NotificationDispatcher 統一層

```
事件發生（handler / service / scheduler）
  │  只做：dispatch(event_type, EventContext { 實體 IDs, actor_id, 內容欄位 })
  ▼
NotificationDispatcher::dispatch(event_type, ctx)
  │
  ├─ 1. 載入 event_type 的所有 active routing rules
  │
  ├─ 2. 對每條 rule 解析收件人 recipients：
  │       target_kind = 'role'      → get_users_by_role(target_value)
  │       target_kind = 'resolver'  → RESOLVERS[target_value](ctx)   // 關係型
  │
  ├─ 3. 去重 + 排除 actor 本人（視事件而定）
  │
  ├─ 4. 對每個 recipient 套用 rule.channel（in_app / email / both）
  │       並疊加個人偏好 notification_settings（若保留此層）
  │
  └─ 5. 實際送出：
         in_app → create_notification(_tx)
         email  → dispatch_staff_email（時間窗 + 請假 + outbox，已存在）
```

### Schema 擴充（核心改動）
`notification_routing` 目前只有 `role_code`（只能角色）。擴充為可表達兩種來源：

```sql
ALTER TABLE notification_routing
  ADD COLUMN target_kind  TEXT NOT NULL DEFAULT 'role',   -- 'role' | 'resolver'
  ADD COLUMN target_value TEXT;                            -- role code 或 resolver key
-- 回填：target_value = role_code, target_kind = 'role'
-- role_code 保留一段過渡期後移除，或轉為 generated column
```

### Resolver Registry（程式端，宣告式）
關係查詢無法純資料庫表達，故 resolver 邏輯在程式，但**「用哪個 resolver」仍在 routing 表宣告**：

```rust
// resolver key（config 可選）→ 解析函式（程式實作）
"entity_applicant"   => 解析該實體申請人        // leave/overtime approved
"entity_approvers"   => 解析曾核准經手人         // leave_cancelled
"protocol_pi_sd"     => 該計畫 PI + SD           // vet_recommendation
"protocol_pi"        => 該計畫 PI                // emergency_medication 的 PI 部分
"euthanasia_parties" => 該單 PI / VET / CHAIR    // euthanasia_*
"assigned_reviewers" => 被指派審查委員           // review assignment
```

> **「零寫死」的真正達成**：每個事件、每個收件人來源、每個管道都在 routing 表宣告；
> handler 只負責「發出事件 + 提供 context」，**不再用 SQL 決定收件人**。
> Resolver 是「宣告式的關係解析器」，不是「寫死的收件人」——這是業界 (b) 模型的精髓。

---

## 6. 逐事件遷移盤點

| 事件 | 收件人本質 | 目標來源 | 現況 | 工作量 |
|---|---|---|---|---|
| protocol_submitted / vet_review / under_review / resubmitted / approved / rejected | 角色 | role（現有） | 已走路由，僅需統一 channel | S |
| review_comment_created / all_reviews_completed / all_comments_resolved | 角色 | role | 已走路由 | S |
| amendment_submitted / approved / rejected | 角色 | role | 已走路由 | S |
| amendment_decision_recorded | 角色 | role | 死路由（映射缺）→ 補映射 | S |
| review assignment（委員指派） | **關係** | resolver `assigned_reviewers` | 半路由（email 開關）→ 收件人轉 resolver | M |
| protocol_status_change（通知 PI） | **關係** | resolver `protocol_pi` | 寫死 PI → 轉 resolver | M |
| emergency_medication | 角色 + **關係** | role(VET) + resolver `protocol_pi` | 死路由 → 混合來源 | M |
| animal_abnormal_record | 角色 | role(VET) | 已走路由，channel `both` 失效 → 修 channel | S |
| vet_recommendation_created | **關係** | resolver `protocol_pi_sd` | 死路由 + COEDITOR 殘留 bug | M |
| animal_sudden_death | 角色 | role(VET) | **完全不發** → 接上 dispatch | M |
| euthanasia_order_created（及核准/暫緩/超時） | **關係** | resolver `euthanasia_parties` | 死路由（全硬寫）→ 轉 resolver | L |
| document_submitted / po_pending_receipt | 角色 | role | 已走路由 | S |
| low_stock_alert / expiry_alert | 角色 | role | 站內走路由；**email 走排程器寫死** → 收斂 | L |
| leave_submitted / overtime_submitted | 角色 | role | 已走路由 | S |
| leave_approved / overtime_approved | **關係** | resolver `entity_applicant` | 死路由 → 轉 resolver | M |
| leave_cancelled | **關係** | resolver `entity_approvers` | 死路由 → 轉 resolver | M |
| equipment_overdue / unrepairable / maintenance_review / disposal | 角色 | role | **實作最正確**（參考範本）；補進 UI | S(UI) |

工作量：S≈小、M≈中、L≈大。

---

## 7. 分期計畫（建議分期並存，非 big bang）

| Phase | 內容 | 驗收標準 | 風險 |
|---|---|---|---|
| **P0** | schema 擴充（target_kind/value，回填）+ Dispatcher 骨架 + Resolver registry。**不改現有行為**，新舊並存 | migration 綠 + `cargo test --lib` 綠 + 既有通知行為不變 | 低 |
| **P1** | 已走路由的角色型事件接上 Dispatcher + **統一 channel 處理**（讓 `email`/`both` 真的生效） | 設一條 email 路由 → 觸發 → outbox 有列 | 中（開始真的寄 email） |
| **P2** | 死路由的關係型事件改用 resolver（euthanasia / leave / vet_rec / emergency / sudden_death） | 每事件整合測試：對象正確、非廣播 | 中 |
| **P3** | 低庫存/效期 email 收斂進 Dispatcher，移除 scheduler 寫死角色路徑 | 收件人＝routing 決定，站內/email 一致 | 高（動排程器） |
| **P4** | 前端：補設備事件、resolver 型路由的顯示、移除「設了沒用」的誤導選項 | 路由頁 UI 與實際行為對齊 | 低 |

每個 Phase 跨 PR 邊界必停（依 CLAUDE.md 執行紀律）。動 handler/middleware 的 Phase 需 `cargo test --all-targets` 全綠。

---

## 8. 風險與反對意見（主動 push back）

1. **過度設計風險**：solo prod、規模數千動物。完整 framework 是否值得？
   - 折衷：**不引入外部框架**（Novu/Knock 撞 CSP/依賴/self-host 規範），用最小內建 Dispatcher + Resolver registry。約 1 個新 module + 1 個 migration，不加外部依賴。
2. **隱私風險（最重要）**：關係型誤設成角色＝私人通知廣播。Resolver 模型正是防這個；遷移時每事件須人工確認對象本質。
3. **email 啟用範圍**：email 有時間窗 + 請假 + outbox 成本與真實寄信副作用。**不該預設全開**——需確認哪些事件真的要 email。
4. **個人偏好 vs routing channel 雙層混亂**：現行 `notification_settings`（個人 email 開關）與 routing channel 並存且邏輯打架（低庫存最明顯）。本次須**明確定義兩者關係**（建議：routing channel = 該事件「是否提供 email 能力」；notification_settings = 個人「要不要收」；兩者 AND）。
5. **audit 一致性**：所有 dispatch 須維持現有 `dispatch_staff_email` 的 audit/outbox 行為，不可繞過 chokepoint。

---

## 9. 待裁定的關鍵決策（動 code 前需你回答）

1. **方向確認**：採 (b) 統一 Dispatcher + Resolver（推薦）；確認不是要 (a) 純角色（會退化）。
2. **遷移節奏**：分期並存遷移（推薦，P0→P4 逐步）vs 一次全改（big bang，風險高）。
3. **email 啟用範圍**：(i) 先只打通架構、channel 維持現狀不亂寄；(ii) 同時把該寄 email 的重要事件（核准/駁回/緊急）真的開起來。
4. **個人偏好層**：保留 `notification_settings` 個人開關（與 routing channel 疊加 AND）vs 統一由 routing 全權管理、移除個人開關。

---

## 附錄：來源
- Novu 文件（subscribers / workflows / how-novu-works）、Knock 文件（notification infrastructure / channels）、Courier 比較（routing 概念）。
- 系統設計通則（role-based vs relational recipient targeting、subscriber preferences、event-driven workflow）。
</content>
</invoke>
