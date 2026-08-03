# iPig 災難復原手冊 (DR Runbook)

> **RPO 目標**：< 1 小時（最多損失 1 小時資料）
> **RTO 目標**：< 4 小時（4 小時內恢復服務）

---

## 1. 緊急聯絡

| 角色 | 負責人 | 聯絡方式 |
|------|--------|---------|
| 系統管理員 | _填入_ | _填入_ |
| 資料庫管理員 | _填入_ | _填入_ |
| 主管 | _填入_ | _填入_ |

---

## 2. 故障分級

| 等級 | 定義 | 回應時間 | 範例 |
|------|------|---------|------|
| P0 | 服務完全中斷 | 立即 | DB 崩潰、主機當機 |
| P1 | 核心功能異常 | 30 分鐘內 | 登入失敗、打卡無法使用 |
| P2 | 非核心功能異常 | 2 小時內 | 報表產出錯誤、通知未送達 |
| P3 | 輕微問題 | 下個工作日 | UI 顯示異常、翻譯錯誤 |

---

## 3. 復原程序

### 3.1 情境一：資料庫毀損

**症狀**：`/api/health` 回傳 503、API 日誌大量 DB 連線錯誤

```bash
# Step 1: 確認 DB 容器狀態
docker compose ps db
docker compose logs db --tail 50

# Step 2: 嘗試重啟
docker compose restart db
sleep 10
curl http://localhost:8080/api/health

# Step 3: 如重啟無效，從備份還原
docker compose down

# 找到最新備份檔（實際檔名格式 ipig_YYYYMMDD_HHMMSS.sql.gz.gpg，一律 GPG 加密）
docker compose run --rm db-backup ls -lt /backups/ | head -5

# 還原（以實際檔名替換）— 備份為 pg_dump -Fc（custom format），必須用 pg_restore，
# 不可用 psql 管道（會因非純文字 SQL 而失敗）。GPG 私鑰須先從 USB import。
docker compose up -d db
sleep 10
gpg --decrypt /path/to/ipig_YYYYMMDD_HHMMSS.sql.gz.gpg \
  | gunzip \
  | docker compose exec -T db pg_restore -U postgres -d ipig_db \
      --clean --if-exists --no-owner --no-acl

# Step 4: 重啟所有服務
docker compose up -d
```

**驗證**：
- [ ] `curl /api/health` 回傳 200
- [ ] 登入功能正常
- [ ] 最近的資料存在

---

### 3.2 情境二：API 服務崩潰

**症狀**：前端顯示 502 Bad Gateway、Nginx 正常但 API 無回應

```bash
# Step 1: 查看 API 日誌
docker compose logs api --tail 100

# Step 2: 重啟 API
docker compose restart api

# Step 3: 如持續崩潰，回滾至上個版本
git log --oneline -5
git checkout <previous-commit>
docker compose build api
docker compose up -d api
```

---

### 3.3 情境三：主機完全毀損（全新部署）

```bash
# Step 1: 在新主機安裝 Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Step 2: 取得程式碼
git clone <repository-url> ipig_system
cd ipig_system

# Step 3: 還原 .env 設定
cp .env.example .env
# 填入正式環境設定（JWT_SECRET 必須與舊環境一致！）

# Step 4: 啟動基礎服務
docker compose up -d db
sleep 15

# Step 5: 從異地備份還原
rsync -az user@nas:/backups/ipig/ ./backups/
gunzip -c ./backups/latest.sql.gz | \
  docker compose exec -T db psql -U postgres ipig_db

# Step 6: 還原上傳檔案
rsync -az user@nas:/backups/ipig/uploads/ ./uploads/

# Step 7: 啟動所有服務
docker compose up -d

# Step 8: 更新 DNS / Cloudflare Tunnel
```

**驗證清單**：
- [ ] `/api/health` 回傳 200 + healthy
- [ ] 管理員帳號可登入
- [ ] 稽核紀錄完整
- [ ] 上傳檔案可存取
- [ ] 打卡功能正常（IP + GPS）

---

## 4. 備份驗證程序

建議每季度執行一次完整的備份還原演練。

### 演練步驟（自動化腳本）

一鍵演練腳本：[`../../scripts/backup/dr_drill.sh`](../../scripts/backup/dr_drill.sh)。
它會取最新 GPG 加密備份 → 驗 SHA256 → 解密 → 起「隔離的」`ipig_db_drill` 容器 →
`pg_restore` 還原 → 與 prod `ipig-db` 逐表 row-count 比對 → 自動清除。全程唯讀 prod。

```bash
# 前提：插 USB、import 私鑰
gpg --import <USB碟>/ipig_backup_private.asc

# 執行演練（不給參數 = 自動取最新備份；解密時 pinentry 要 Bitwarden passphrase）
./scripts/backup/dr_drill.sh

# 演練後移除私鑰恢復 USB-only
gpg --delete-secret-keys 84F051E0AD2AA40F
```

> ⚠️ 備份為 `pg_dump -Fc`（custom format），必須用 `pg_restore` 還原，不可用 `psql`
> 管道（舊版本手冊的 `gunzip | psql` 會失敗）。腳本已用正確路徑。

### 演練記錄表

| 日期 | 執行人 | 備份日期 | 還原耗時 | 資料完整 | 備註 |
|------|--------|---------|---------|---------|------|
| _YYYY-MM-DD_ | _姓名_ | _YYYY-MM-DD_ | _X 分鐘_ | ✅/❌ | |

**完整檢查表**：詳見 [DR_DRILL_CHECKLIST.md](DR_DRILL_CHECKLIST.md)，含步驟清單與紀錄範本。

---

## 5. 事後檢討範本

每次 P0/P1 事件後，填寫以下範本：

```
事件標題：
發生時間：
發現時間：
解決時間：
影響範圍：
根本原因：
時間線：
  - HH:MM 發現問題
  - HH:MM 開始處理
  - HH:MM 服務恢復
改善措施：
  1.
  2.
```
