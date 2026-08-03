# iPig 豬博士動物科技系統 — 資料保留政策 (Data Retention Policy)

> **版本**：1.0
> **生效日期**：2026-02-25
> **合規基準**：GLP (Good Laboratory Practice), FDA 21 CFR Part 11, 台灣勞基法

## 1. 政策目標
本政策旨在定義 iPig 系統內各類電子紀錄與相關資料的法定及營運保留年限，確保資料在生命週期內之完整性、可追溯性，並在達到保留年限後安全銷毀，以符合實驗動物管理與法律合規要求。

## 2. 資料分類與保留年限

| 資料類型 | 包含內容 | 保留年限 (建議) | 法規依據 / 備註 |
| :--- | :--- | :---: | :--- |
| **AUP 計畫書紀錄** | 計畫書初稿、審查歷程、核准版本、變更申請 (Amendments)。 | **計畫結案後 5 年** | GLP / 21 CFR Part 11 |
| **實驗動物醫療紀錄** | 臨床觀察、手術、血檢、體重、疫苗、疼痛評估。 | **動物處置後 5 年** | GLP / 實驗動物管理準則 |
| **安樂死與轉讓紀錄** | 申請單、核准權限、執行紀錄、電子簽章。 | **永久** | 關鍵生命週期事件，建議永久保存 |
| **稽核日誌 (Audit Trail)** | 全系統登入紀錄、資料異動紀錄、HMAC 驗證鏈。 | **10 年** | 21 CFR Part 11 / 防弊稽核需求 |
| **ERP 進銷存資料** | 產品資料、庫存異動、單據、採購/銷貨明細。 | **7 年** | 商業會計法 / 稅務法規 |
| **HR 人事考勤資料** | 出勤紀錄、加班/請假申請、GPS 定位紀錄。 | **5 年** | 台灣勞基法第 30 條 |
| **系統技術資料** | 帳號資訊 (不含密碼雜湊)、權限矩陣、GeoIP 稽核。 | **帳號停用後 3 年** | 安全性與追蹤需求 |
| **備份資料** | 加密之資料庫快照與上傳檔案備份。 | **與原始資料同步** | 遵循上述各類資料之最長期限 |

## 3. 保留期計算方式
- **研究相關資料**：自實驗計畫正式結案（Study Closure）或動物處置（Sacrifice/Euthanasia）完成日起算。
- **考勤法律資料**：自紀錄產生日起算。
- **會計憑證資料**：自年度決算程序辦理起算。

## 4. 資料銷毀規範
達到保留年限之資料，應採取以下處置：
1. **電子紀錄**：從運作中之資料庫 (Active DB) 移除，並在異地備份中徹底清除或進行偽匿名化 (De-identification) 處理。
2. **實體備份**：若有磁帶或光碟儲存，應進行物理性銷毀至無法復原程度。
3. **紀錄保留**：銷毀操作應留存稽核紀錄，並由系統管理員與合規長簽署認證。

## 5. 特殊保留 (Legal Hold)
若資料涉及進行中之法律訴訟、專利糾紛或監管機構調查，其保留期限應自動延長，直至該程序正式結束為止。

## 6. 稽核日誌容量分區政策 (R41-3, 2026-05-11)

對應 NICS 附表十「事件日誌與可歸責性 / 稽核儲存容量」要求，`user_activity_logs` 表雖保留 10 年，但需明確的容量上限與歸檔程序，避免單表無限增長導致查詢效能退化。

### 6.1 觸發閾值

由 Prometheus alert 監控 `user_activity_logs` 表，**任一條件**觸發即啟動歸檔流程：

| 條件 | Prometheus alert | severity |
|---|---|---|
| Row count > 5,000,000 | `AuditLogTableRowsWarning` | warning |
| Table size > 5 GB | `AuditLogTableSizeWarning` | warning |
| Table size > 10 GB | `AuditLogTableSizeCritical` | critical |

對應 alert rule 定義於 `monitoring/prometheus/alert_rules.yml`（R41-3）。

### 6.2 歸檔工具

CLI：`backend/src/bin/audit_archive.rs`（R41-3 skeleton）。

```bash
# 預覽
cargo run --bin audit_archive -- --before "2024-05-11" --dry-run

# 實際歸檔（會寫加密 tar.gz + DELETE）
cargo run --bin audit_archive -- --before "2024-05-11" --output /backups/audit_archive
```

### 6.3 歸檔輸出

- **格式**：加密 tar.gz（gpg/age；金鑰由 ops 持有，與 DB backup 加密金鑰分離）
- **儲存位置**：NAS backup 卷之獨立目錄 `/backups/audit_archive/<YYYY-MM-DD>/`
- **保留**：與原始紀錄一致 — 至最初紀錄產生後 10 年止
- **歸檔事件本身**：寫入新一筆 `user_activity_logs`，event_type = `AUDIT_ARCHIVE_EXECUTED`，含執行 actor / 範圍 / row count（避免 chain 斷鏈）

### 6.4 HMAC chain 完整性

歸檔流程**不重算 hash**，只 DELETE 已歸檔的舊紀錄。HMAC chain 為單向 hash 鏈：新紀錄的 `prev_hash` 在寫入當時就鎖定，DELETE 舊紀錄不影響新紀錄的鏈接驗證。歸檔後若需驗證歷史紀錄完整性，由還原歸檔 tar.gz 至獨立 read-only DB 跑 `services::audit_chain_verify::verify_chain_range`。

### 6.5 排程審查

ops 每月 review 表大小（`pg_relation_size('user_activity_logs')`），即使未觸發 alert 也應觀察成長趨勢。預估正常營運下單表約需 1–2 年才會達到 5GB 閾值。

---
*文件草擬於 2026-02-25；§6 新增於 2026-05-11（R41-3）*
