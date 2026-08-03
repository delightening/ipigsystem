# Guest Demo 模式架構

> **最後更新**：2026-07-07
> **對象**：前端維護者、想擴充 demo 可見頁的人、審視資料隔離的資安/合規人員
> **一句話**：訪客（guest）登入後看到的是一套**純前端、零真實資料**的唯讀展示；所有 API 請求被
> 單一 axios interceptor 攔下，回靜態假資料，永不觸及後端業務資料。

---

## 1. 目的

- **對外唯讀展示**：讓潛在客戶 / 稽核方在不開真帳號的前提下，瀏覽整套系統的操作面貌，
  凸顯 **GLP 合規、稽核追蹤、計畫書審查、動物照護、進銷存**等賣點。
- **零真實資料**：demo 過程中頁面呈現的所有數字/清單都是寫死的示範資料，
  **不可能**因為 guest 操作而讀到或寫入任何真實記錄。
- **零後端負擔 / 零攻擊面擴大**：guest 的請求根本不出瀏覽器（interceptor 短路），
  後端另有 guest_guard 擋寫入作為第二道防線。

---

## 2. 核心不變式（改動前必讀）

> 這些是「訪客資料隔離」的地基。破壞任何一條都可能讓 guest 漏看真實資料或讓頁面崩潰。

1. **單一攔截點**：唯一的攔截邏輯在 `frontend/src/lib/api/client.ts` 的
   **第一個 request interceptor**（註冊順序早於 CSRF interceptor）。它呼叫
   `getGuestDemoData(url, method)`（來自 `frontend/src/lib/guest-demo/routes.ts`），
   有回值就用 `config.adapter` **短路**該請求（回 200 + demo data），完全不發 HTTP。

2. **禁止新增 fetch/axios 實例**：全前端只能透過這個 `api` 實例（`client.ts` 的 default export）
   打 API。**任何新的 `fetch()` / `new axios.create()` / 直連端點都會繞過 interceptor**，
   在 guest 模式下直接打到後端 → 漏真實資料或噴 401，破壞隔離。新增資料存取一律走既有 `api`。

3. **只放行 `/auth/*`**：`PASSTHROUGH_PREFIXES = ['/auth/']`。登入/登出/refresh 需真的到後端
   （guest 登入本身走真實 `/auth`）。其餘所有路徑都被 interceptor 接管。
   注意 `/me` **已從 passthrough 移除**，改由 `exactRoutes` 回 `GUEST_USER`（避免打後端）。

4. **寫入回假成功 + toast**：非 GET（POST/PUT/PATCH/DELETE）一律回
   `{ success: true, _guest_demo: true }`，並由 client interceptor 彈出「示範模式無法儲存」
   toast（文案經 `getGuestWriteToast()` 走 i18n）。**報表查詢**雖走 POST 但語意是讀取，
   回 demo 陣列且不彈 toast（見 `postReportRoutes` 與 `getGuestWriteToast` 對 `/reports/` 的豁免）。

5. **is-guest 判定**：interceptor 以 `useAuthStore.getState().isGuest()` 判斷是否啟用攔截；
   側邊欄與路由守衛用 `useAuthIsGuest()`。guest 身分本身由真實登入回傳的 `roles: ['GUEST']` 決定。

---

## 3. 請求攔截流程

```
guest 發 API 請求
      │
      ▼
client.ts request interceptor (第一個)
  isGuest()? ──no──► 正常送後端
      │yes
      ▼
getGuestDemoData(url, method)   （routes.ts）
  1. 去除 baseURL 前綴（/api/v1 或 /api）
  2. isPassthrough(path)?  → /auth/* 回 undefined（不攔截，送後端）
  3. 去除 query string → cleanPath
  4. method === 'GET':
        cleanPath ∈ exactRoutes?     → 回該筆 demo data
        cleanPath 命中 prefixRoutes? → 回對應 demo data（依陣列順序，先到先中）
        皆未命中                      → 回 EMPTY_PAGINATED
  5. method 非 GET:
        cleanPath ∈ postReportRoutes? → 回 demo 陣列（報表查詢，讀取語意）
        否則                          → 回 { success:true, _guest_demo:true }（假成功 + toast）
      │
      ▼
回值 !== undefined → config.adapter 短路，回 200 + demo data（不發 HTTP）
```

**關鍵設計**：

- **exactRoutes 優先於 prefixRoutes**：精確路徑先比對，未命中才走前綴。前綴表 `prefixRoutes`
  是有序陣列，**順序重要**——較specific 的子資源前綴必須排在 catch-all 前綴之前
  （例：`/animals/demo-a1/` → `EMPTY_ARRAY` 必須早於 `/animals/` → 單筆 animal 物件，
  否則 array 端點會拿到 object 而 `.map()` 崩潰）。
- **未匹配 GET 回 `EMPTY_PAGINATED`**（`{ data:[], total:0, page:1, per_page:20, total_pages:0 }`）：
  這是「分頁列表形狀」的安全預設。若某頁期望的是 plain array 或 object，就必須在
  exactRoutes 顯式補正確形狀（見 §6 維護 checklist）。
- **interceptor 不解析 query param**：比對前會 `slice` 掉 `?...`，所以帶篩選條件
  （選人、日期、protocol_id）的請求都回同一份 demo data，**demo 內的過濾不會真的生效**（見 §7）。

---

## 4. 目錄結構與各檔職責

`frontend/src/lib/guest-demo/`

| 檔案 | 職責 |
|---|---|
| `routes.ts` | **核心**：URL→demo data 映射（`exactRoutes` 精確 + `prefixRoutes` 前綴 + `postReportRoutes`）、`getGuestDemoData()`、`getGuestWriteToast()`、`GUEST_USER`、`EMPTY_PAGINATED/ARRAY/OBJECT` 預設、passthrough 清單 |
| `index.ts` | barrel re-export（`export * from` 各資料檔），供 routes.ts 匯入 demo 常數 |
| `animals.ts` | 動物列表/全部/統計/依欄舍、觀察/體重/疫苗/手術/疼痛評估、動物來源、可用豬隻；棟-區-欄（buildings/zones/pens）|
| `protocols.ts` | 計畫書列表 `DEMO_PROTOCOLS` + 三筆詳情 P1/P2/P3 |
| `hr.ts` | 特休結餘摘要、請假、出勤、加班 |
| `erp.ts` | 產品、單據、夥伴、倉庫/倉庫樹/儲位、各儲位庫存 |
| `equipment.ts` | 設備列表、校正、年度計畫 |
| `qau.ts` | QAU 儀表板 |
| `admin.ts` | 使用者/角色/權限、操作日誌、QAU 稽查/不符合/SOP、訓練記錄 |
| `dashboard.ts` | 首頁 widget：低庫存告警、獸醫留言、今日出勤、行事曆事件、我的計畫、未讀通知、待審變更數 |
| `messaging.ts` | 站內信 thread 列表 + thread 詳情 |
| `glp.ts` | GLP 合規 8 頁：受控文件、變更申請、風險、管理審查、配製記錄、職能評估、研究報告、環境監測點/讀值 |
| `reports.ts` | 報表中心：庫存/帳本、進銷明細、成本、進銷月報/按夥伴/按分類、血檢成本/分析、試算表/傳票/帳齡/損益、週報醫療、副產物月報 |
| `misc.ts` | 雜項：巡場報告、血檢模板/套組/預設、HR 內部使用者/特休/逾期補休、庫存、維護、QA 排程、治療用藥、設施/物種/部門、登入/工作階段/安全告警/安全稽核、我的變更申請 |
| `fixes.ts` | 後補的缺口修補：部門成員、IP 黑名單、預約規劃、可預約動物、訊息收件人、巡場報告詳情、首頁日曆、HR 員工、未分配庫存、設備供應商彙總 |

> 資料檔的拆分無嚴格領域邊界，`fixes.ts`/`misc.ts` 是歷次補洞累積的集散地——新增資料時
> 放進最貼近的檔即可，重點是在 `routes.ts` 補上**正確形狀**的映射。

---

## 5. 可見範圍契約

guest 看到的側邊欄 ≈ **幾乎整棵導航樹**，僅扣除下列兩類：

**(A) 側邊欄隱藏子項** — `GUEST_HIDDEN_CHILD_IDS`
（`frontend/src/components/layout/sidebarNavConfig.ts`，於 `useSidebarNav.ts` 過濾）：

| 隱藏 id | 原因 |
|---|---|
| `admin.users` | 使用者管理（含 PII）|
| `admin.settings` | 系統設定（infra 細節）|
| `admin.notificationRouting` | 通知路由（infra）|
| `hr.invitations` | 邀請管理（客戶開通，寫入流程）|
| `animalManagement.fieldCorrections` | 修正審核（僅管理員，guest 無意義）|

**(B) route wrapper 全擋** — `<GuestBlock>`（`frontend/src/components/auth/GuestBlock.tsx`）：
對 guest 直接 `Navigate → /dashboard`。用在「整條 route 都不適合 demo」的新增/編輯/送審頁。
現行 `App.tsx` 以 `GuestBlock` 包住的路由：

- 產品：`/products/new`、`/products/:id/edit`
- 單據：`/documents/new`、`/documents/:id/edit`
- 計畫書：`/protocols/:id/edit`、`/protocols/import-approved`、`/protocols/:id/import-review`
- 動物：`/animals/:id/edit`（及新增/匯入類頁）

> 兩者互補：(A) 讓側邊欄不出現該入口；(B) 讓即使有人直接打 URL 也會被導回 dashboard。
> 兩者都**不需要**在 `routes.ts` 補資料（因為頁面根本不會渲染 / API 不會被打）。

---

## 6. ★ 加新頁時的維護 checklist

> 每次讓一個**新頁面對 guest 可見**（沒有被 `GUEST_HIDDEN_CHILD_IDS` 或 `GuestBlock` 擋掉），
> 就必須做完以下項目，否則 guest 進該頁會看到空白，或更糟——**直接 crash 白屏**。

1. **補該頁「初始載入端點」的 demo 資料**：找出頁面 mount 時會打的所有 API 路徑，
   在 `routes.ts` 的 `exactRoutes`（或必要時 `prefixRoutes`）逐一補上。
2. **★ 形狀要對：陣列 vs 物件 vs 分頁**。這是最常見的 crash 來源：
   - 頁面對回值做 `.map()/.filter()/.some()/for...of` → 端點必須回**陣列**（或 `{ data: [...] }`，
     視前端如何取值），**不可**用預設的 `EMPTY_PAGINATED`（那是物件，`.map` 會炸）。
   - 頁面把回值當 detail 物件用其欄位 → 必須回**物件**，不可回陣列。
   - 端點是分頁列表 → 回 `EMPTY_PAGINATED` 形狀的物件（`{ data, total, page, per_page, total_pages }`）。
   > `routes.ts` 內大量註解正是在標記「此端點回 plain array / 回 { data: [...] } / 回物件」——
   > 沿用同樣的精確度，別讓物件頁吃到陣列、或陣列頁吃到物件。
3. **跨端點 id 對齊**：若頁面先打列表、點一列再打詳情/子資源，列表項的 `id` 必須與詳情端點的
   demo key 對得上（例：`DEMO_PROTOCOLS` 的 `demo-p1` ↔ `/protocols/demo-p1` ↔
   `/protocols/demo-p1/animal-stats`）。id 對不齊 → deep-link 落到 catch-all `EMPTY_PAGINATED`，
   物件頁又拿到分頁物件而崩潰。
4. **子資源前綴排序**：若新增的是 `/x/:id/sub` 類子資源，確認其 exact 條目或
   specific 前綴排在 `/x/` catch-all 之前（見 §3）。
5. **寫入友善提示（選配）**：若該頁有明顯的儲存/送出動作，可在 `getGuestWriteToast()` 的
   resource 對應加一條，讓 toast 文案更貼切（非必要，預設文案也可用）。

---

## 7. 已知限制

- **不吃 query param**：interceptor 比對前會去除 `?...`，所以任何靠 query 篩選的頁
  （選人下拉、日期區間、`protocol_id` 過濾、分頁 page）在 demo 中**回同一份資料、過濾不生效**。
  若某頁的核心體驗依賴過濾，需自行在頁面層以 client-side filter 對 demo 資料處理
  （部分頁已如此，如 MyAmendmentsPage 打 `/amendments` 後客戶端過濾）。
- **照片/附件留空**：巡場照片、附件等一律回空陣列（`/vet-patrol-reports/*/photos` → `EMPTY_ARRAY`），
  避免破圖；demo 中不呈現真實影像。
- **統計/儀表板為靜態近似**：dashboard 數字（在場動物數、待審數、活躍工作階段）是寫死的示範值，
  不反映任何即時狀態。
- **後端仍是第二道防線**：即使前端隔離被繞過，後端 guest_guard 仍擋寫入；但**讀取隔離完全倚賴前端
  interceptor**，故 §2 的「禁止新增 fetch/axios 實例」是硬紅線。

---

## 8. 相關檔案

| 用途 | 路徑 |
|---|---|
| 攔截點（interceptor） | `frontend/src/lib/api/client.ts` |
| 映射表 + 進入點 | `frontend/src/lib/guest-demo/routes.ts` |
| demo 資料檔 | `frontend/src/lib/guest-demo/{animals,protocols,hr,erp,equipment,qau,admin,dashboard,messaging,glp,reports,misc,fixes}.ts` |
| 側邊欄隱藏清單 | `frontend/src/components/layout/sidebarNavConfig.ts`（`GUEST_HIDDEN_CHILD_IDS`）|
| 側邊欄過濾邏輯 | `frontend/src/components/layout/useSidebarNav.ts` |
| route 全擋 wrapper | `frontend/src/components/auth/GuestBlock.tsx`（用於 `App.tsx` 各 new/edit/import 路由）|
| is-guest 判定 | `frontend/src/stores/auth`（`isGuest()` / `useAuthIsGuest()`）|
