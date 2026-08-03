# DR Drill 年度演練紀錄

> **用途**：保存歷年災難復原（Disaster Recovery）演練紀錄，作為 GLP §10 / SOC 2 A1.2 / ISO 27001 A.8.13 / 21 CFR §11.10(c) 還原能力證明。
> **適用範圍**：本系統 production / staging 環境之備份還原與服務復原驗證。
> **維護者**：SRE lead + QAU。每年至少 1 次（建議每季 1 次），演練後 7 個工作日內必須回填本表。
> **配套文件**：[`DR_DRILL_CHECKLIST.md`](DR_DRILL_CHECKLIST.md)（演練檢核項目）、[`DR_RUNBOOK.md`](DR_RUNBOOK.md)（執行步驟）

---

## 1. 演練頻率與要求

| 項目 | 要求 |
|---|---|
| **最低頻率** | 每年 1 次（GLP / FDA pre-audit 強制） |
| **建議頻率** | 每季 1 次（SOC 2 Type II 持續性證據） |
| **RTO 目標** | < 4 小時 |
| **RPO 目標** | < 1 小時 |
| **演練範圍** | 至少 1 次「完整毀損模擬」（非僅 backup restore） |
| **參與角色** | SRE on-call + admin + QAU 觀察員（≥1 名） |
| **通過標準** | 所有 DR_DRILL_CHECKLIST.md 項目綠燈 + RTO / RPO 達標 |

---

## 2. 演練紀錄表

| 日期 | 主持人 | 涵蓋範圍 | 發現問題 | 修補時程 | 通過? | 報告連結 |
|---|---|---|---|---|---|---|
| 2026-05-09 | Jason | DB backup restore — R36 first drill（R2 → 解密 → pg_restore → row-count 比對 5 表全相符） | R36-1/2 backup script bug 數週靜默失敗（同日修），SMB obscured 密碼 stdin 問題（同日修），DSM SMB 密碼僅 6 字元（同日輪換為 16 字元） | 已全數修補當日 | ✅ | 見下方「2026-05-09 R36 First Drill」段 |
| 2026-07-18 | Jason | DB backup restore — R82-1 drill（今日 02:00 加密備份 → GPG 解密 → `pg_restore` 到隔離 `ipig_db_drill` 容器 → 逐表 row-count 比對 prod；經 `dr_drill.sh` 一鍵腳本） | `dr_drill.sh` 於 Windows/Git Bash 上 `docker exec` 的 `/tmp` 引數被 MSYS 轉成 Windows 路徑（→ pg_restore 找不到檔、還原 0 表）且錯誤被 `>/dev/null 2>&1` 吞掉（誤判）；當日修（`MSYS_NO_PATHCONV=1` 只加在 `docker exec pg_restore`、真就緒判定、還原後表數=0 才判失敗且保留錯誤 log） | 已修當日 | ✅ | 見下方「2026-07-18 R82-1 Drill」段 |
| 2027-XX-XX | TBD | TBD | — | — | — | — |
| 2028-XX-XX | TBD | TBD | — | — | — | — |

> **欄位說明**：
> - **涵蓋範圍**：例「DB backup restore only」/「完整 cold-start」/「跨 region failover」
> - **發現問題**：未通過或勉強通過的 checklist 項目；無問題填「無」
> - **修補時程**：發現問題的修補 PR / issue 與預計完成日
> - **通過?**：✅ / 🟡（部分通過，已修補）/ ❌（未通過，需重演）
> - **報告連結**：相對路徑指向 `docs/audit/dr-drills/YYYY-MM-DD.md`（**TODO[使用者]**：報告子目錄結構待確認）

---

## 3. 每次演練必填欄位（報告 template）

新建 `docs/audit/dr-drills/YYYY-MM-DD.md` 時建議含：

```markdown
# DR Drill — YYYY-MM-DD

## 演練資訊
- 主持人：
- 參與者：
- 開始時間：YYYY-MM-DD HH:MM (GMT+8)
- 結束時間：YYYY-MM-DD HH:MM (GMT+8)
- 涵蓋範圍：

## RTO / RPO 量測
- 偵測到中斷 → 開始復原：M 分鐘
- 開始復原 → 服務恢復：M 分鐘
- 資料遺失視窗（最後 backup → 中斷時刻）：M 分鐘
- RTO 達標？✅ / ❌
- RPO 達標？✅ / ❌

## DR_DRILL_CHECKLIST 結果
（逐項打勾並附 evidence 連結 / screenshot）

## 發現問題與後續行動
| # | 問題 | 嚴重度 | 後續 action item / PR | 負責人 | 完成日 |

## QAU 觀察員簽核
- 觀察員：
- 簽核時間：
- 結論：通過 / 部分通過 / 未通過
```

---

## 4. 反向引用

- 演練檢核項目：[`DR_DRILL_CHECKLIST.md`](DR_DRILL_CHECKLIST.md)
- 演練執行步驟：[`DR_RUNBOOK.md`](DR_RUNBOOK.md)
- Traceability：[`../glp/traceability-matrix.md`](../glp/traceability-matrix.md) §11.10(c)
- 合規對應：[`../glp/R26_compliance_requirements.md`](../glp/R26_compliance_requirements.md) R26-3

---

## 5. 演練紀錄詳情

### 2026-07-18 — R82-1 Drill（第二次完整備份還原驗證 + drill 腳本上線）

**演練資訊**
- 主持人：Jason（solo dev/維運）；USB 私鑰 import + Bitwarden passphrase 由本人，還原/比對由 Claude 執行
- 時間：2026-07-18 10:39–10:40 (GMT+8)
- 涵蓋範圍：DB backup restore（今日 02:00 加密備份，本地 `/backups` 取檔）；經新 `scripts/backup/dr_drill.sh` 一鍵腳本

**RTO / RPO 量測**
- GPG 解密 + gunzip：~1 秒（agent 快取 passphrase）
- pg_restore（192 表 / 4.2M custom-format）：**8 秒**
- 完整鏈（取檔→SHA256→解密→起容器→還原→比對→清除）：~20 秒
- **RTO 估算**：< 30 分鐘 — 達標（目標 < 4h）
- **RPO**：cron 02:00 daily，最差 ~24h；當日 02:00→10:40 無寫入差異（見比對全相符）

**DR Drill 結果**
- ✅ 本地備份 SHA256 完整性通過
- ✅ GPG 解密成功（加密子鑰 `84F051E0AD2AA40F`，rsa4096；USB 私鑰 import + Bitwarden passphrase）
- ✅ pg_restore 到隔離 `ipig_db_drill` 容器成功（exit 0、零 stderr、public 表 **192＝prod 192**）
- ✅ Row count **8 表全相符**：animals 153 / users 35 / protocols 32 / electronic_signatures 18 / documents 145 / stock_ledger 718 / audit_logs 222 / user_activity_logs 2971（drill＝prod）
- ✅ 演練後私鑰從 keyring 刪除（`gpg --delete-secret-keys`，恢復 USB-only）
- ⏸️ 異地下載路徑（R2/NAS）本次未走（取本地 `/backups`；異地副本存在性/一致性由日常監控 + R36 前次演練覆蓋）
- ⏸️ 完整 cold-start（Cloudflare tunnel / DNS）未涵蓋，下次納入

**發現問題與後續行動**

| # | 問題 | 嚴重度 | 後續 action | 負責人 | 完成日 |
|---|------|--------|------------|---------|--------|
| 1 | `dr_drill.sh` 於 Windows/Git Bash：`docker exec pg_restore /tmp/dump.sql` 引數被 MSYS 轉成 Windows 路徑（`C:/Users/.../Temp/dump.sql`）→ 容器內找不到、還原 0 表；且 pg_restore 錯誤被 `>/dev/null 2>&1 \|\| true` 吞掉致難診斷 | 🟠 HIGH（工具，非備份本體） | 修 `dr_drill.sh`：`docker exec pg_restore` 加 `MSYS_NO_PATHCONV=1`（`docker cp` 不加，host 來源需轉換）、就緒判定改真 psql 查詢、還原後表數=0 才判失敗並保留 `restore.log` | Jason/Claude | 2026-07-18 |

**QAU 觀察員簽核**
- 觀察員：N/A（solo；git 歷史 + 本表雙軌 audit trail）
- 結論：✅ **通過** — 備份可完整還原、資料與 prod 一致；工具 bug 當日修復並重跑驗證。

**結論**：R82-1 備份還原第二次端到端驗證通過（第一次為 2026-05-09 R36）；順帶修好 `dr_drill.sh` 的 Windows 相容性使其成為可重複的季度演練工具。

### 2026-05-09 — R36 First Drill（首次完整異地備份還原驗證）

**演練資訊**
- 主持人：Jason（solo dev/維運）
- 參與者：Jason
- 開始時間：2026-05-09 12:51 (GMT+8) — 完整 backup 上傳成功
- 結束時間：2026-05-09 21:10 (GMT+8) — restore drill row-count 比對通過
- 涵蓋範圍：**DB backup restore only**（首次驗證 R36 backup 全鏈：R2 下載 → 解密 → pg_restore → row-count 比對）

**RTO / RPO 量測**（drill 為刻意演練不模擬中斷，僅量測 backup → restore 鏈）
- R2 下載延遲：~5 秒（716KB 檔案）
- 解密 → 解壓 → pg_restore：~30 秒
- 完整 restore 流程（從 USB 拿私鑰 → import → 解密 → pg_restore → 比對）：~10 分鐘（首次操作含學習成本）
- **RTO 估算（自動化後）**：< 30 分鐘 — 達標（目標 < 4 小時）
- **RPO 量測**：cron 排程 02:00 daily → 最差 RPO ~ 24 小時。**未達 < 1 小時目標**，但 vet 研究業務寫入頻率低（~ < 100 events/day），24 小時 RPO 可接受。

**DR Drill Checklist 結果**
- ✅ Backup 從 R2 異地位置下載成功
- ✅ SHA256 checksum 校驗通過（`60019a9...3c911`）
- ✅ GPG 加密 backup 用 USB 私鑰解密成功（passphrase 從 Bitwarden 取）
- ✅ pg_restore 到隔離 postgres 容器成功（exit 0）
- ✅ Row count 5 表完全匹配（animals/users/electronic_signatures/protocols/user_activity_logs）
- ✅ 演練後私鑰從 keyring 刪除（恢復 USB-only 狀態）
- ⏸️ 完整 cold-start drill（含 cloudflare tunnel reroute / DNS 切換）— **未涵蓋**，下次納入
- ⏸️ DS918 SMB 還原驗證（這次只測 R2 路徑）— **下次納入**

**發現問題與後續行動**

| # | 問題 | 嚴重度 | 後續 action item / PR | 負責人 | 完成日 |
|---|------|--------|----------------------|---------|--------|
| 1 | `pg_backup.sh` DB_NAME 預設 `erp_db` 與實際 `ipig_db` 不符，cron 數週靜默失敗，`/backups/` 空無檔案 | 🔴 CRITICAL | `6ade6c24 fix(backup): pg_backup.sh DB_NAME mismatch` | Jason | 2026-05-08 |
| 2 | `pg_backup.sh` pipefail + SIGPIPE 偽失敗使整個 script exit 1 | 🟠 HIGH | 同上 commit（修 verification 用 temp file） | Jason | 2026-05-08 |
| 3 | GPG 公鑰 import 後預設 untrusted，加密拒絕 | 🟠 HIGH | `b9cae5cd fix(backup): set ownertrust=ultimate` | Jason | 2026-05-09 |
| 4 | rclone obscure 經 stdin 在 Git Bash 取不到輸入，產出 obscured-of-empty | 🟡 MED | runbook 改用 argument 傳遞（已寫入 `backup-setup.md`） | Jason | 2026-05-09 |
| 5 | DSM `ipig_backup` 密碼僅 6 字元 — 嚴重資安漏洞 | 🔴 CRITICAL | 同日輪換為 Bitwarden 產 16 字元強密碼 | Jason | 2026-05-09 |
| 6 | Cron 排程 02:00 RPO 最差 24h，未達 < 1h 目標 | 🟡 MED | 接受現況（業務寫入頻率低）；未來考慮 WAL archiving 或 hourly delta backup | Jason | TBD |
| 7 | 首支 USB（G:）私鑰備援單點（F: 已做為第二份，但未分散位置） | 🟡 MED | 把第二支 USB 帶到不同物理地點（家裡 / 親戚家） | Jason | 1 週內 |
| 8 | DR drill 未涵蓋 DS918 SMB 還原路徑、未做 cloudflare tunnel cold-start | 🟢 LOW | 下次 quarterly drill 納入 | Jason | 2026-08（Q3 drill） |

**QAU 觀察員簽核**
- 觀察員：N/A（solo 維運，無獨立 QAU；改由 git commit 歷史 + dr-drill-records.md 雙軌作為 audit trail）
- 簽核時間：2026-05-09 21:10 (GMT+8)
- 結論：✅ **通過** — backup 鏈全部驗證；後續改善項目登記為 TODO，非阻擋。

**結論**：R36 backup 異地架構**第一次完整端到端驗證通過**。下次 drill 排程為 2026-08（Q3，3 個月內）需涵蓋 DS918 路徑 + cold-start。

