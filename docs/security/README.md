# 安全文件目錄

> **本資料夾範圍**：政策 / 規範 / 合規對照 / 設計 RFC。
> **不在這裡的**：操作手冊 → `docs/runbooks/`；架構設計 → `docs/design/`；歷史審計 → `docs/archive/code-reviews/`。

---

## 🗂️ 心智模型

| 想找什麼 | 去哪裡 |
|---|---|
| 政策 / 規範（what / why） | **本資料夾** `docs/security/` |
| 操作手冊（壞了怎麼辦） | `docs/runbooks/` |
| 架構設計（怎麼蓋的） | `docs/design/` |
| 歷史審計報告 | `docs/archive/code-reviews/` |
| 實作 code | `backend/src/middleware/`, `services/auth/`, `services/audit.rs` |

---

## 📋 文件分類

### 1. 威脅與總覽

| 文件 | 主題 |
|---|---|
| [`THREAT_MODEL.md`](THREAT_MODEL.md) | 威脅模型 — 資產清單 + threat actor + STRIDE |
| [`security.md`](security.md) | 安全綜合紀錄 + 合規對照索引（早期主文件） |
| [`SECURITY_COMPLETED.md`](SECURITY_COMPLETED.md) | 已完成安全項目歷史 |

### 2. 合規對照

| 文件 | 主題 | 下次複查 |
|---|---|---|
| [`NICS_COMPLIANCE_AUDIT_2026-05.md`](NICS_COMPLIANCE_AUDIT_2026-05.md) | NICS 行政院資通安全防護基準對照（普 100% / 中 ~85% / 高 ~70%） | 2026-11-11（半年）|
| [`SOC2_READINESS.md`](SOC2_READINESS.md) | SOC2 對齊度 | — |
| [`GLP_VALIDATION.md`](GLP_VALIDATION.md) | GLP 合規驗證 | — |
| [`ELECTRONIC_SIGNATURE_COMPLIANCE.md`](ELECTRONIC_SIGNATURE_COMPLIANCE.md) | 電子簽章法規（21 CFR Part 11 / 台灣電子簽章法） | — |

### 3. 認證 / 授權 / Session

| 文件 | 主題 |
|---|---|
| [`PASSWORD_POLICY.md`](PASSWORD_POLICY.md) | 密碼政策（NIST SP 800-63B；說明對附表十的主動偏離 + 補償控制）|
| [`CREDENTIAL_ROTATION.md`](CREDENTIAL_ROTATION.md) | 憑證 / Secret 輪替 SOP |
| [`SESSION_LOGOUT_MANAGEMENT.md`](SESSION_LOGOUT_MANAGEMENT.md) | Session 管理 / logout 流程 |

### 4. 稽核日誌 / 完整性

| 文件 | 主題 |
|---|---|
| [`HMAC_VERSIONING.md`](HMAC_VERSIONING.md) | Audit chain HMAC 版本控制（legacy / canonical）|
| [`AUDIT_REDACTION.md`](AUDIT_REDACTION.md) | 敏感資料遮罩規則 |

### 5. 資料保護

| 文件 | 主題 |
|---|---|
| [`DATA_RETENTION_POLICY.md`](DATA_RETENTION_POLICY.md) | 各類紀錄保留年限 + 稽核日誌容量分區 |
| [`csp-baseline-2026-04.md`](csp-baseline-2026-04.md) | CSP 基線 |

### 6. 偵測與回應（RFC）

| 文件 | 主題 | 狀態 |
|---|---|---|
| [`TIERED_DETECTION_RFC.md`](TIERED_DETECTION_RFC.md) | 分層安全偵測（ATR 借鏡）— R48 立案 | RFC，未實作 |

### 7. 一次性審計產物

| 文件 | 主題 |
|---|---|
| [`UPSERT_SCAN_REPORT.md`](UPSERT_SCAN_REPORT.md) | upsert SQL 掃描報告 |

### 8. 服務水準

| 文件 | 主題 |
|---|---|
| [`SLA.md`](SLA.md) | 安全相關 SLA（事件回應時間等） |

---

## 🔗 跨資料夾關聯

下方列出與本資料夾政策對應的「操作」/「設計」/「審計」文件 — **本資料夾說 what / why，這些說 how / when / who**。

### 與 `docs/runbooks/` 的對應

| 政策（本資料夾） | 對應 runbook |
|---|---|
| `HMAC_VERSIONING.md` | [`../runbooks/audit-chain-broken-runbook.md`](../runbooks/audit-chain-broken-runbook.md) |
| `csp-baseline-2026-04.md` | [`../runbooks/csp-enforce-cutover.md`](../runbooks/csp-enforce-cutover.md) |
| `CREDENTIAL_ROTATION.md` | [`../runbooks/secrets-management.md`](../runbooks/secrets-management.md) + [`../runbooks/backup-private-key-handling.md`](../runbooks/backup-private-key-handling.md) |
| `DATA_RETENTION_POLICY.md` | [`../runbooks/DR_RUNBOOK.md`](../runbooks/DR_RUNBOOK.md) + [`../runbooks/DR_DRILL_CHECKLIST.md`](../runbooks/DR_DRILL_CHECKLIST.md) + [`../runbooks/backup-setup.md`](../runbooks/backup-setup.md) |
| （啟動程序）| [`../runbooks/cold-start.md`](../runbooks/cold-start.md) |

### 與 `docs/design/` 的對應

| 政策（本資料夾） | 對應設計文件 |
|---|---|
| `HMAC_VERSIONING.md` + `ELECTRONIC_SIGNATURE_COMPLIANCE.md` | [`../design/r30-9-signature-audit-chain.md`](../design/r30-9-signature-audit-chain.md) |

### 與 `docs/archive/code-reviews/` 的對應

歷史審計（snapshot in time，非政策）：

- [`../archive/code-reviews/security_audit_v2_final.md`](../archive/code-reviews/security_audit_v2_final.md)
- [`../archive/code-reviews/walkthrough_security_audit_2026_04_14.md`](../archive/code-reviews/walkthrough_security_audit_2026_04_14.md)

### 與 code 的對應

| 概念 | 政策文件 | 主要 code 位置 |
|---|---|---|
| Audit chain | `HMAC_VERSIONING.md` + `AUDIT_REDACTION.md` | `backend/src/services/audit.rs`, `middleware/actor.rs` |
| CSP | `csp-baseline-2026-04.md` | `backend/src/middleware/csp.rs`, `handlers/csp_report.rs` |
| Session | `SESSION_LOGOUT_MANAGEMENT.md` | `backend/src/services/auth/session.rs` |
| Password | `PASSWORD_POLICY.md` | `backend/src/services/auth/password.rs` |
| Rate limit / IDOR / Honeypot | （無單一政策文件，列入 R48-1 改善）| `backend/src/middleware/` 各檔 + `routes/mod.rs::honeypot_routes` |

---

## 🔁 維護慣例

- 新增安全文件時，**先在本檔加入分類**再寫文件
- 政策變更需更新對應 runbook（雙向同步）
- 一次性審計報告（如 NICS_COMPLIANCE_AUDIT_2026-05.md）檔名帶日期，舊報告不刪除（trend tracking）
- RFC 落地後將狀態欄改為「實作中」/「已實作」，code merge 後保留文件作為歷史 context
