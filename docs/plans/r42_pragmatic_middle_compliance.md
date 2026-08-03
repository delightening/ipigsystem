# R42 — Pragmatic 中級合規 cherry-pick 計畫（future-proofing）

> **立案**：2026-05-11
> **狀態**：**parked / 條件式啟動**。本計畫**不立即執行**。
> **前提**：ipig_system 目前是 solo 研究室系統、無對外客戶、無 SaaS 場景。下列項目對單人筆電系統 over-engineer。**僅在出現觸發條件時啟動對應子項**。
> **設計哲學**：risk-based menu，**不**追整套中級認證；從附表十中級單點挑「對 SME 真正降低客戶資料外洩風險」的項目，搭普級已完成基礎構成 pragmatic middle baseline。

---

## 觸發條件（啟動本計畫的場景）

| 場景 | 機率（未來 2 年內）| 啟動子項 |
|---|---|---|
| 系統開放給其他研究單位（多租戶）| 中 | R42-1, R42-2, R42-4 |
| ipig SaaS 化 / 商業營運 | 低 | 全部 |
| 接政府研究計畫，採購方要求 vendor security assessment | 中 | R42-3, R42-4 |
| 與企業客戶簽 B2B 合作 | 低 | R42-1, R42-3 |
| 通過 ISO 27001 Stage 1 預審需求 | 低 | R42-4, R42-5 |
| 個資外洩或被攻擊事件 | 低（但成本高）| R42-2 立即 |
| **以上皆無** | — | **本計畫繼續 parked** |

---

## 目前基線（vs pragmatic SME baseline）

對照「中小企業實作規劃」討論中那張 ✅ 表，盤點 ipig_system 已落地與差距：

| pragmatic 項目 | 目前狀態 | 已落地點 / Gap |
|---|---|---|
| MFA 強制（全員）| 🟡 **半達標** | TOTP 已建（P5-3）；admin 強制、一般使用者可選。**Gap**：未對所有使用者強制 |
| 加密備份 + offsite + 測過還原 | ✅ 完成 | R36 全部 + 2026-05-08 row-count DR drill 通過 |
| 自動補丁 + Dependabot + Trivy | ✅ 完成 | CI 含 Dependabot + cargo-audit + Trivy + semgrep（R41-5）|
| 最小權限 RBAC | ✅ 完成 | R28-4 ActorContext + `services/access.rs` |
| Audit log + 不可竄改鏈 | ✅ 完成 | HMAC chain（R26）+ R41-2 daily verifier 程式就緒 |
| Phishing 員工訓練 | ⚪ N/A | solo 系統無「員工」 |
| Incident Response runbook | 🟡 **散落** | `docs/runbooks/` 有 backup/DR/secret 等個別 runbook，**Gap**：無「事故發生 → 通報 → 控制 → 復原」一頁式總綱 |
| 全磁碟加密 | 🟡 評估完成 | R41-8 結論 BitLocker；**Gap**：實際啟用待 2026-06 |
| TLS 1.2+ + HSTS + CSP | ✅ 完成 | nginx-ssl + Cloudflare WAF + R31 CSP |

**結論**：9 個項目 5 ✅ / 3 🟡 / 1 N/A。**現況已優於多數 SME 中級水位**；只剩 3 個 Gap 是有實質意義的補強。

---

## R42 子項規劃（按優先級）

### R42-1 全員 MFA 強制（含一般使用者）

**現況**：admin 強制 TOTP；一般使用者可選但**未強制**。

**為何「未來才做」**：solo 系統只有自己一個 admin → 已強制。多人時才有意義。

**觸發條件**：第 2 位實際使用者加入系統時啟動。

**實作（觸發後）**：
- `users` 表加 `mfa_required_after TIMESTAMPTZ`（強制截止日）
- 登入時若 `now > mfa_required_after` 且未設定 TOTP → 強制導去 `/profile/security/setup-mfa`
- Admin UI 可批次設定強制
- Grace period 14 天（讓使用者有時間設）

**工時**：~6h

---

### R42-2 Incident Response 一頁式總綱

**現況**：`docs/runbooks/` 散落 7+ 個 runbook（backup-restore / secret-rotation / docker-restart / 等），**沒有「事件發生 → 立即動作」的 entry point 文件**。事故發生時需要在多個檔案間跳。

**為何「現在可以做」**：成本低（~3h），對 solo 也有用（壓力下不會忘 step）。**這個是 R42 唯一現在做也合理的項目**。

**實作**：
- 新建 `docs/runbooks/00_INCIDENT_RESPONSE.md`
- 涵蓋場景：DB 損毀 / 帳號被盜 / 勒索軟體 / 資料外洩疑似 / 服務中斷
- 每個場景 ≤ 5 步「先做什麼」+ 連結到對應 detail runbook
- 包含通報對象（自己、ipig 使用者群、保險公司若有）+ 時間 SLA
- 從事件偵測到完整 IR 流程 ≤ 30 分鐘可走完一輪

**觸發條件**：**現在**，或當其他 R42 任一啟動時。

**工時**：~3h

---

### R42-3 Vendor Security Assessment 應對包

**現況**：無；採購方要 vendor security questionnaire 時得臨時拼湊。

**為何「未來才做」**：目前無對外客戶。

**觸發條件**：第一個採購方要求 vendor security assessment 時啟動（48h 內可完成）。

**實作（觸發後）**：
- 新建 `docs/security/VENDOR_SECURITY_ASSESSMENT.md`
- 預填答案包含：
  - 系統架構圖（複用既有）
  - 資料加密說明（複用 NICS audit）
  - Backup/DR 摘要（複用 R36）
  - Incident response 摘要（複用 R42-2）
  - SOC 2 readiness（已有 `SOC2_READINESS.md`）
  - 個資處理流程（複用 21 CFR Part 11 文件）
  - 開放問答模板：50 題常見供應商評估問題（SIG Lite 範本）

**工時**：首次 ~8h；後續複用每客戶 ~2h

---

### R42-4 Risk Register 簡化文件

**現況**：NICS audit 報告含 risk 對照但無**獨立 risk register**。

**為何「未來才做」**：solo 系統的 risk 都在 audit 文件中可追溯；獨立 register 是 ISO 27001 要求，目前無此需求。

**觸發條件**：通過 ISO 27001 / SOC 2 預審；或保險公司要求。

**實作（觸發後）**：
- `docs/security/RISK_REGISTER.md`
- 每項風險：description / likelihood / impact / current controls / residual risk / owner
- 從 NICS audit 報告 + threat model 抽取 ~15-20 條
- 季度 review 機制

**工時**：~10h

---

### R42-5 對外個資處理 SOP（GDPR / 個資法 對應）

**現況**：`PRIVACY_POLICY.md` 已有（P2-39），但無內部處理流程（資料主體權利請求、刪除請求、跨境傳輸等）。

**為何「未來才做」**：目前無對外個資處理場景；研究動物資料非「個資」。

**觸發條件**：開放系統給研究合作對象（含其同仁的人事資料時）；或 SaaS 化。

**實作（觸發後）**：
- 個資清冊（哪些表存哪些個資）
- DSAR 處理 SOP（資料主體請求權）
- 跨境傳輸評估（若使用境外服務商）
- 刪除/匿名化技術方案
- 個資外洩通報程序（72h 通報 NCC）

**工時**：~12h

---

### R42-6 BitLocker 啟用實作（接 R41-8 評估）

**現況**：R41-8 評估完成、結論採方案 A，**實作排程 2026-06 與下次 DR drill 同時段**。

**為何「現在不做」**：需停機 + 加密時間 1-4 小時；要與 DR drill 同步避開風險。

**觸發條件**：2026-06 月內排定的 DR drill 時段（自動觸發）。

**實作**：見 [`docs/assessments/DB_AT_REST_ENCRYPTION_2026-05.md`](../assessments/DB_AT_REST_ENCRYPTION_2026-05.md) §4 步驟。

**工時**：~1h 啟動 + 1-4h 背景加密

---

## 不會做的項目（與 SME baseline 討論對應）

對應討論中「⏸ 跳過」欄：

| 項目 | 理由 |
|---|---|
| SOC 24x7 外包 | Cloudflare WAF + Prometheus alert 已涵蓋 solo 場景；月費 5-50 萬不成比例 |
| FIPS 140-2 HSM | Argon2id + AES-GCM 已是業界共識；採購 HSM 對 solo over-spec |
| RTO 8h 熱備援 | DS925+ 未來計畫中（記憶 `nas-setup`），但與 R42 獨立 |
| ISO 27001 / SOC 2 認證 | 認證費用 30 萬+，續審 + 顧問費；單人系統 ROI 為負 |
| 紅藍隊演練 | 一次 15-50 萬；對 commodity threat 邊際效益低 |
| 紙本 ISMS 政策手冊 | 文件齊備但 control 退化是反向激勵；現有 markdown docs 已超過 |

---

## 觸發監控 / 何時 review

- **不主動推進**：R42 整體 parked。
- **每半年隨 NICS audit review**（2026-11-11 / 2027-05-11）：check 觸發條件是否出現；若是則拿出對應子項立即啟動
- **R42-2 IR 總綱**：唯一例外，可在現在做（成本低、效益實在）
- **R42-6 BitLocker**：已排程 2026-06 自動觸發

---

## 與 R41 之關係

- R41 達成「**普級 100% + 中級 cherry-pick 走到 ~92%**」
- R42 是「**剩下的 8% 中級在什麼條件下追**」的決策框架
- R42 不是 R41 的延伸實作，而是**觸發監控 + 應對 playbook**

---

## 建議：唯一現在做的項目

**R42-2 IR 一頁式總綱**（~3h）。理由：
- 對 solo 也有實質價值（壓力下不會忘步驟）
- 成本極低
- 是其他 R42 子項的依賴前置（vendor assessment / 個資外洩通報都會引用它）
- 與 R41-7 security index 對齊，補完 runbook 入口

是否現在啟動 R42-2？或 R42 整體繼續 parked？

---
*本計畫由 2026-05-11 中小企業中級合規討論延伸而來。除 R42-2 外，**不主動推進**。下次 review：2026-11-11。*
