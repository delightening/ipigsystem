# iPig System — User Assurance Checklist

> **目的**：操作層的 smoke test，由 user (PI / vet / admin / staff) 走過確認系統「真的能用」。
> **不是**：cargo test / Playwright 等程式碼級驗證（CI 已涵蓋），也不是 GLP 正式 IQ/OQ。
>
> **適用時機**：
> - 重大 deploy 後（如本日 sliding session overhaul）
> - 月度 GLP 自查
> - 新環境 cutover 後
> - 懷疑系統某層悄悄壞掉時（如 R51 watcher silent dead 事件）
>
> **預估時間**：跑完全部 ~90 min；只跑 P0 critical ~30 min。
>
> **使用方式**：勾選 ☐ → ☑ 通過，☒ 失敗（記 issue/截圖到備註欄）。每節結尾的 `PASS?` 是該節整體狀態。

---

## P0 — 上線 critical（每次 deploy 必跑）

### 1. 認證 & Session（2026-05-18 sliding session overhaul 後重點）

- ☐ **登入**：開 `https://ipigsystem.asia/login` → 輸入帳密 → 應跳轉 `/dashboard` 並顯示歡迎 toast
- ☐ **錯誤帳密**：故意輸錯密碼 → 紅色 destructive toast「登入失敗」，**不會** 跳 dashboard
- ☐ **2FA**：有 2FA 的帳號登入 → 跳 2FA 頁 → 輸入 6 位數驗證碼 → 成功進系統
- ☐ **訪客模式**：使用 QA 密碼庫提供的測試帳號登入 → 進 `/demo`，能看數據但寫入會擋
- ☐ **登出**：右上選單登出 → 跳回 `/login`，後端 session 結束（admin audit page 可驗）
- ☐ **Session 持久**：登入後正常使用 1+ 小時，期間移動滑鼠/打字 → **不會** 出現「即將過期」dialog（已移除）
- ☐ **連續操作 sliding**：開兩個 tab，舊 tab 持續操作 → 新 tab 開啟時舊 tab **不會** 被踢（LRU 改為砍最不活躍）
- ☐ **過期重導**：手動清掉瀏覽器 cookie（或等到 8h idle）→ 任何 API call → 自動跳 `/login?reason=session_expired`，顯示**灰色** toast「登入時效已到期」（**不是紅色**）
- ☐ **重設密碼**：`/forgot-password` → 收 email → 點連結 → 設新密碼 → 用新密碼登入

**PASS?** ☐

---

### 2. Dashboard

- ☐ 首頁載入 < 2s 顯示卡片（活躍動物 / 待辦試驗 / 我的待簽 等）
- ☐ 各角色看到對應卡片（PI 看試驗、VET 看巡場、QAU 看品保）
- ☐ 點任何卡片進對應頁不會 404 / 500

**PASS?** ☐

---

## P1 — 主要業務流（每週走一次）

### 3. 動物管理（Animal）

- ☐ **動物清單**：`/animals` → 列表顯示，能依耳號搜尋
- ☐ **建立動物**：填表新增（耳號、來源、入欄日期、性別、體重）→ 列表出現新筆
- ☐ **編輯動物**：點動物進 detail → 編輯按鈕 → 改體重 → 儲存後列表反映
- ☐ **動物移動**（換欄/換 pen）：找個動物 → 改 pen_code（D15 → D20）→ 儲存 → 在 `/animals/vet-patrol` 頁的新欄位看到該耳號
- ☐ **可用豬隻查詢**（R47）：`/animals/available-pigs` → 過濾條件勾選 → 顯示符合的動物清單
- ☐ **巡場報告**：`/animals/vet-patrol-reports` → 列表 + 開新單 → 填寫 → 儲存 → PDF 預覽
- ☐ **動物來源** master：`/animals/sources` → 新增來源 → 用於新動物建立時下拉

**PASS?** ☐

---

### 4. 試驗計畫 / Protocol（GLP）

- ☐ **計畫列表**：`/protocols` 顯示
- ☐ **建立 AUP 計畫**：填試驗目的、用豬數、SD/PI 簽核流程 → 儲存
- ☐ **計畫詳情**：點開 protocol → tabs（基本資料 / 動物 / 觀察 / 病歷 / 採血 / 屍解 / 附件 / 簽核 / amendment）全部能切換不報錯
- ☐ **送審 (submit)**：草稿 → 送 IACUC 審 → 狀態 PENDING_REVIEW
- ☐ **審查意見回覆**：reviewer 角色登入 → 填回覆 → review_reply PDF 產生
- ☐ **審核結果**：IACUC_CHAIR → 通過/退回 → review_result PDF 產生
- ☐ **修訂單 (amendment)**：在已通過 protocol 開 amendment → 改項目 → 簽核 → 變動寫進 audit log
- ☐ **我的計畫書**：`/my-projects` → 看到自己的 protocols

**PASS?** ☐

---

### 5. ERP — 採購 → 入庫 → 庫存 → 對帳

- ☐ **採購單 (PO)** 建立：`/erp` → 開 PO → 選廠商 + 品項 + 數量 + 預期到貨日 → 儲存得 PO 編號
- ☐ **採購單 approve**：主管角色 → approve → 狀態 APPROVED
- ☐ **採購入庫 (GRN)**：把 PO 接收成入庫單 → 填實際到貨數量 + 批號 + 效期 → 儲存
  - 部分入庫：PO 100 進 60 → 剩 40 留待後續入庫
  - 完全入庫：PO 100 進 100 → PO 狀態 COMPLETED
- ☐ **儲位選擇**：入庫時下拉選擇 warehouse + 儲位 → 寫進 stock_ledger
- ☐ **庫存查詢**：`/inventory` → 顯示各品項當前數量
- ☐ **庫存帳本**：`/inventory/stock-ledger` → 看到剛才入庫的異動紀錄
- ☐ **庫存盤點 (stocktake)**：開盤點 → 帳面 vs 實盤 → 差異調整
- ☐ **調撥**：A 倉庫 → B 倉庫 → stock_ledger 兩筆異動
- ☐ **銷貨 (sales)**：開銷貨單 → 選客戶 → 出庫 → 庫存扣
- ☐ **AP 應付帳款 aging**：`/reports/ap-aging` → 看到未付廠商款項分齡
- ☐ **AR 應收帳款 aging**：`/reports/ar-aging` → 看到未收客戶款項分齡

**PASS?** ☐

---

### 6. HR — 打卡 / 請假 / 加班

- ☐ **打卡**：`/hr/attendance` → 上班打卡（檢查 GPS 範圍）→ 下班打卡 → 工時計算正確
- ☐ **請假**：`/hr/leave` → 申請假別 + 日期 → 送出 → 主管 approve → 我的請假頁顯示已核
- ☐ **特休餘額**：`/hr/annual-leave` → 看到當年特休總額 / 已休 / 剩餘
- ☐ **加班**：`/hr/overtime` → 申請加班 + 事由 → 主管核 → 計入加班時數
- ☐ **行事曆同步**：`/hr/calendar-sync` → 接 Google Calendar → 請假/加班同步到 Google

**PASS?** ☐

---

### 7. 報表 / PDF

> 主要驗證 R60 PDF 模板視覺對齊進度。每模板開出後**人工目測**是否：
> - 中文渲染為標楷體（容器內 AR PL UKai TW FOSS 替代）
> - 英數字渲染為 Times Roman 風（Liberation Serif）
> - layout 對齊 reference PDF（如有）

- ☐ **巡場報告 (vet_patrol)**：產生今日巡場 PDF → 中文標楷體、欄位 layout 合理（cell 比例 R60-9 已知 in-progress）
- ☐ **AUP 計畫書**：產生計畫書 PDF → 中文標楷體、layout 對齊 reference
- ☐ **病歷總表 (medical_record)**：產生 PDF → 對齊 reference
- ☐ **審查意見回覆 (review_reply)**：產生 PDF → 對齊 reference
- ☐ **審核結果 (review_result)**：產生 PDF → 對齊 reference
- ☐ **豬隻核准 (pig_approval)**：產生 PDF
- ☐ **血液檢驗 (blood_test)**：產生 PDF
- ☐ **手術 (surgery)**：產生 PDF
- ☐ **倉儲報表 (warehouse)**：產生 PDF
- ☐ **稽核日誌 (audit_log)**：admin 從 audit page export → PDF
- ☐ **巡場報告（多筆，vet_patrol_report）**：產生 PDF
- ☐ **會計報表**：`/reports/accounting` → 月結 → PDF / Excel 匯出
- ☐ **採購明細**：`/reports/purchase-lines` → 區間 → 顯示 + 匯出
- ☐ **銷貨明細**：`/reports/sales-lines` → 區間 → 顯示 + 匯出
- ☐ **庫存帳/在手量**：`/reports/stock-ledger`、`/reports/stock-on-hand`
- ☐ **血液檢驗成本/分析**：`/reports/blood-test-cost`、`/reports/blood-test-analysis`

**PASS?** ☐（11/11 是 R60 完整通過目標）

---

### 8. 管理員 (Admin)

- ☐ **使用者管理**：`/admin/users` → 新增 / 停用 / 改 role → 異動寫 audit log
- ☐ **角色管理**：`/admin/roles` → 看到 PI / VET / IACUC_STAFF / 等 role → 權限對應
- ☐ **邀請**：`/admin/invitations` → 發邀請 email → 收件人點連結進 `/invitations/accept` 設密碼 → 進系統
- ☐ **系統設定**：`/admin/settings` → Session 逾時可調 (目前 480 min/8h) → 改值儲存 → 5 min 內 scheduler 套用
- ☐ **稽核日誌**：`/admin/audit-logs` → 篩選 / 匯出 → HMAC chain 驗證通過
- ☐ **Session 強制登出**：`/admin/audit?tab=sessions` → 選一個 session → 強制登出 → 該使用者下次操作 401
- ☐ **設備管理**：`/admin/equipment` → 新增設備 / 校正紀錄 / 維修紀錄
- ☐ **環境監控**：`/admin/environment-monitoring` → 溫度 / 濕度 / 警報
- ☐ **動物欄位修正申請**：`/admin/animal-field-corrections` → 受理修正請求 → 走簽核流程

**PASS?** ☐

---

### 9. QA / GLP（QAU 角色）

- ☐ **QAU dashboard**：`/admin/qau-dashboard` → 看待辦稽核 / 偏差
- ☐ **SOP 控制**：`/admin/qa-sop` → 新增 / 修訂 SOP → version 遞增
- ☐ **稽核 (inspection)**：`/admin/qa-inspection` → 開稽核單 → 簽核
- ☐ **偏差 / 不符合 (NC)**：`/admin/qa-non-conformance` → 開 NC → CAPA → 結案
- ☐ **訓練紀錄**：`/admin/training-records` → 員工訓練 + 評估
- ☐ **變更控制**：`/admin/change-control` → CC 單 → 簽核
- ☐ **文件控制**：`/admin/document-control` → 文件版本管理
- ☐ **配製紀錄**：`/admin/formulation-records` → 試驗配方
- ☐ **管理審查**：`/admin/management-review` → 高階審查
- ☐ **風險登錄**：`/admin/risk-register` → 風險評估表
- ☐ **試驗最終報告**：`/admin/study-final-report` → 最終報告流程

**PASS?** ☐

---

## P2 — 通知 / 整合（每月走一次）

### 10. Email 通知

- ☐ **SMTP 設定**：`/admin/settings` Email 區 → 改 smtp_host / port / 帳密 → 5 min 內套用
- ☐ **試驗送審通知**：使用者送 IACUC → 執行秘書收 email
- ☐ **加班逾期提醒**：scheduler 跑時應發 email 給主管
- ☐ **設備校正逾期**：到期設備 → email 提醒設備管理員

### 11. 站內信 (Messaging)

- ☐ `/messaging` → 新訊息 → 收件人收到
- ☐ 30 天前已軟刪訊息 → scheduler hard delete + unlink 附件

### 12. Calendar 同步

- ☐ Google Calendar OAuth 連接 → 雙向同步
- ☐ 衝突解決：iPig 事件 vs Google 事件衝突時，依 user 設定 (`keep_ipig` / `accept_google` / `dismiss`) 處理

**PASS?** ☐

---

## P3 — Monitoring & Ops（每月 + 事件時走）

### 13. 監控 dashboard

> URL 依環境而異（本機 / staging / prod / 遠端 QA）。下方 `<MONITORING_HOST>` 請替換為實際主機名稱或從環境設定取得。

- ☐ **Grafana** (`http://<MONITORING_HOST>:3001`)：可登入 → 看 backend 請求數 / latency p95
- ☐ **Prometheus** (`http://<MONITORING_HOST>:9090`)：query `ipig_api_request_duration_seconds` 有數據
- ☐ **Loki** (`http://<MONITORING_HOST>:3100`)：能查最近 1 小時 backend log

### 14. 警報

- ☐ **Alertmanager**：故意打爆 rate limit → 警報 fire → 收到通知（email / line）
- ☐ **未解警報 sweep**：scheduler 每日跑，未處理警報升級

### 15. 自動部署 (R51 watcher)

- ☐ **5 min tick log**：`%LOCALAPPDATA%\ipig-auto-deploy.log` 每 5 min 有新 entry（無新 commit 時 `tick — no new commits`，有則 deploy 訊息）
- ☐ **真實 deploy 驗證**：merge 一個 PR → 5 min 內 `ipig-api` container 自動 restart → 新 image 上線
- ☐ **失敗不卡死**：故意造一個會 build fail 的 commit → watcher log 應記 `Deploy 失敗`，下輪不會無窮重試

### 16. Backup & DR

- ☐ **DB backup**：`ipig-db-backup` container 每日跑 → 檔案落地
- ☐ **異地備份**：（如已設）OneDrive / S3 同步
- ☐ **Cold start drill**：每季從備份還原一次 — row count 對得起來

**PASS?** ☐

---

## Sign-off

| 角色 | 簽名 | 日期 | 整體結論 |
|---|---|---|---|
| PI | | | ☐ 通過 ☐ 有 issue（記下方）|
| VET | | | ☐ 通過 ☐ 有 issue |
| QAU | | | ☐ 通過 ☐ 有 issue |
| Admin/IT | | | ☐ 通過 ☐ 有 issue |

**未解 issue**（連到 GitHub Issue / TODO.md item）：

| # | 描述 | 嚴重度 | 對應 issue |
|---|---|---|---|
| | | | |

---

## 維護

- 系統新增功能 → 加進這份 checklist 對應節
- 系統移除功能（如 SessionTimeoutWarning）→ 標 deprecated 或刪行（保留 audit trail：日期 + commit ref）
- 上一次完整跑過：______（日期 + 跑的人）
