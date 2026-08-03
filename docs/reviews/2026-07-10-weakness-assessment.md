# 全專案弱點總體檢（2026-07-10）

> 背景：使用者詢問「這個專案的弱點在哪」。指揮官派五路並行唯讀掃描
> （後端 Rust、前端 React、安全合規、測試/CI/維運、文件債務），本檔為彙整結論
> 與後續派工計畫。追蹤輪次：`docs/TODO.md` §R82。
>
> 掃描方法：五個獨立 subagent（後端/前端/CI 維運/文件 = sonnet、安全 = opus），
> 各自附證據位置（檔案:行號）與「檢查過但沒問題的範圍」，主對話交叉彙整。

## 0. 總評

安全與工程紀律成熟度**高於一般一人專案**：SQL 全參數化（grep `format!` 拼 SQL 零命中）、
ES256 JWT + jti 黑名單、HMAC 稽核鏈、CI 含 IDOR hard gate / gitleaks / cargo-deny / Trivy /
Playwright E2E、observability 全套（Prometheus/Grafana/Loki/Alertmanager）。

真正的弱點不在「有沒有做」，而在兩個結構面：
**營運韌性（筆電 prod + 未驗證的異地備份）**與**「巨檔 × 零測試」的核心模組組合**。

## 1. 弱點清單（依風險排序）

### W1【存亡級】Prod 跑在筆電上，異地備份「無法證明存在」
- 文件自承的架構級風險：`docs/plans/r56-aws-migration.md`（R56 全 13 項 PARK）。
- 備份腳本與 R2+NAS 方案已寫好，但 `BACKUP_GPG_RECIPIENT` / `BACKUP_RCLONE_REMOTES`
  在 `.env.example:274-289` 預設空白；prod 實際 `.env` 是否已填，repo 內無法驗證。
  若未填 = 備份只在同一台筆電上，等同無 3-2-1。
- DR 演練僅一次（2026-05-09，`docs/runbooks/dr-drill-records.md:28`），下次排 2027。

### W2【高】測試防護網名不符實
- 後端 coverage gate `--fail-under 4`（4%）且只量 `--lib`（`.github/workflows/ci.yml:427-434`）；
  真正覆蓋 handler 的 358 個整合測試不在覆蓋率量測內。
- 前端 vitest 未帶 `--coverage`、無 thresholds（`ci.yml:467-469`、`frontend/vitest.config.ts:19-24`）；
  280 個頁面元件僅 8 個 `.test.tsx`。
- 核心大模組零測試：`services/scheduler.rs`（1866 行）、`services/animal/vet_patrol.rs`（1941 行）
  在 `tests/` 與 inline `#[cfg(test)]` 均查無對應測試。

### W3【高】巨檔違反自訂量化門檻，持續惡化
- 後端 27 檔 >800 行：`services/equipment.rs` 2820 行（39 fn）、`services/audit.rs` 2081 行、
  `vet_patrol.rs` 1941 行、`scheduler.rs` 1866 行、`glp_compliance.rs` 1657 行。
- 前端 106 檔 >300 行（占 14%）：`VetPatrolReportDialog.tsx` 1302 行（25 個 state/effect）、
  `EquipmentPage.tsx` 844 行。
- 與 W2 是複利關係：巨檔＋無測試＝最危險組合。

### W4【中，合規】安全深度防禦缺口（opus 審查）
1. **legacy `audit_logs` 表無 HMAC 鏈**（`services/audit.rs:324-351` 無 integrity_hash），
   寫入的是高價值 SoD 事件：模擬登入 `handlers/auth/impersonate.rs:47`、
   使用者建立/變更 `handlers/user.rs:340,401`。DB 寫入權者可竄改而不被鏈驗證偵測。
   ⚠️ 待查證：這些事件是否並行寫入 HMAC 鏈的 `user_activity_logs`。
2. **CSRF secret 由 JWT 私鑰派生**（`config.rs:250-263`）：JWT 私鑰外洩即可離線推導
   CSRF secret，破壞金鑰隔離。
3. **打卡地理圍籬信任 proxy header**（`middleware/real_ip.rs:40-47`、
   `handlers/hr/attendance.rs:232,282`）：`TRUST_PROXY_HEADERS=true` 且後端非完全內網時，
   偽造 `x-real-ip` 可繞過考勤圍籬。
4. **AI API key scope 過粗**（`middleware/ai_auth.rs:73-78`）：單把 read key 可跨全模組讀取。

### W5【中】效能與維護債
- 通知 job N+1：`services/notification/alert.rs:158-179`、`:245` 對每個 recipient 各發
  2 次 query，人數成長線性退化。
- 逐筆 INSERT 反模式：`services/animal/blood_test.rs:253-274`（迴圈內單筆 INSERT）。
- 非測試碼 204 處 `unwrap()/expect()`，熱點：`audit.rs`（15）、`middleware/real_ip.rs`（14）、
  `utils/crypto.rs`（10）。
- `guest-demo` 影子後端 4,494 行（`frontend/src/lib/guest-demo/`），與真實 API 平行維護必漂移
  （已有架構文件 `GUEST_DEMO_ARCHITECTURE.md`，漂移風險仍在）。

### W6【低】死重與文件滯後
- `backend/migrations_squashed/`（8 檔）全庫無引用。
- README 宣稱 123 migrations，實際 127；狀態列停在 R79（現已 R81+）。

## 2. 檢查過沒問題的範圍（五路彙整）

- SQL injection 面：sqlx 全參數化、動態搜尋有 ILIKE ESCAPE 跳脫。
- 認證/Cookie/CORS/CSP/secrets fail-fast：均紮實（詳見安全路回報）。
- 前端型別紀律：`any` 僅 14 處、`@ts-ignore` 0、API 層集中（0 處繞過 fetch）、
  Zustand store 範疇清晰。
- 錯誤處理：單一 `AppError` enum，無多套並存。
- migrations 001–127 編號連續、命名一致。
- CI 安全掃描面完整；dependabot 四生態全開；observability 全套且備份腳本有 metric。

## 3. 後續派工計畫（對應 TODO.md §R82）

| # | 弱點 | 任務 | 模型 | 紅線 |
|---|---|---|---|---|
| R82-1 | W1 | prod 筆電實機備份還原演練 + `.env` 備份設定查證，記錄入 dr-drill-records | sonnet（限本機 session） | 無（唯讀 prod DB） |
| R82-2 | W2 | `scheduler.rs` 補整合測試 ≥10（不動本體） | sonnet | 無 |
| R82-3 | W2 | `vet_patrol.rs` 補整合測試 ≥10（含 #928 PDF 回歸、audit 路徑） | sonnet | 無 |
| R82-4 | W2 | CI coverage 改 ratchet（含整合測試量測 + 前端 thresholds） | sonnet | **動 CI，需核准** |
| R82-5 | W4-1 | audit_logs HMAC 缺口查證 + SoD 事件遷鏈方案（先方案後動手） | **opus** | 方案回使用者裁決 |
| R82-6 | W4-2 | CSRF_SECRET 改獨立必填 fail-fast（比照 AUDIT_HMAC_KEY） | **opus** | merge 前需 prod `.env` 補值 |
| R82-7 | W3 | 前端巨檔試點：拆 `VetPatrolReportDialog.tsx` → ≤300 行/檔 | sonnet | 無 |
| R82-8 | W3 | 後端巨檔試點：拆 `services/equipment.rs` 為子模組（純搬移） | sonnet | 無 |
| R82-9 | W5 | `alert.rs` N+1 批次化（紅→改→綠） | sonnet | 無 |
| R82-10 | W6 | migrations_squashed 清理 + README 數字/狀態同步 | haiku | 刪檔前回報 |

**建議順序**：R82-1（本機，最高回報）→ R82-2+3 並行 → R82-5 查證 → R82-9、10 隨手清
→ R82-4（等核准）→ R82-6 → R82-7+8 試點成功後批次展開其餘巨檔。

## 4. 不確定處（需 prod 實機確認）

- prod `.env` 的 `BACKUP_GPG_RECIPIENT` / `BACKUP_RCLONE_REMOTES` 是否已填。
- nginx 是否清洗入站 `x-real-ip` / `cf-connecting-ip`（決定 W4-3 可利用性）。
- 模擬登入「開始」是否有並行 HMAC 鏈上紀錄（決定 W4-1 嚴重度）。
- W5 的 N+1 未實測 prod 資料量下的延遲，僅靜態證據。
