# Backup 完整設定 Runbook（R36）

> **目的**：把 prod DB backup 從「僅本機 docker volume」升級為「本機 + Cloudflare R2 + DS918 SMB」三點異地複本，符合 3-2-1 規則。
>
> **適用對象**：第一次設定 / 從筆電遷移到 NAS 後的重新設定。
>
> **預估時間**：1-2 小時（含申請 Cloudflare 帳號等）。

---

## 架構

```
prod Postgres (DB)
        │
        ▼
docker volume db_backups            ← 本機，每天 02:00 cron
        │
        ▼ pg_dump → gzip → GPG encrypt
        │
        ├──▶ Cloudflare R2          ← 雲端異地（防火災 / 設備被偷）
        └──▶ \\DS918\home\ipigsystem_backup  ← 本地 NAS（防 prod 機損毀）
```

# 必做步驟（依序）

## Step 1：產 dedicated GPG keypair（10 min）

**重要**：用一把**只給 backup 用**的 key，不要用個人 PGP key（私鑰外洩風險不同）。

### 1.1 產 key

在你**個人工作機**（不是 prod 機）跑：

```bash
gpg --full-generate-key
```

選項：
- Type: `(1) RSA and RSA`
- Key size: **4096**
- Expiration: `0`（不過期，backup key 換 key 太麻煩）
- Real name: `ipig backup`
- Email: `backup@ipig.local`（隨便取，只是 identifier）
- Passphrase: **設一個強密碼**（這個密碼是還原時要打的，務必另外記）

產完查看 key ID：
```bash
gpg --list-keys backup@ipig.local
# 看 pub  rsa4096/<KEY_ID> 那行
```

### 1.2 匯出公鑰 → 給 prod 用

```bash
gpg --armor --export backup@ipig.local > backup_gpg_pubkey.asc
```

複製 `backup_gpg_pubkey.asc` 到 prod 機的 `secrets/backup_gpg_pubkey.asc`。

### 1.3 匯出私鑰 → 離線存兩份（**最關鍵**）

```bash
gpg --armor --export-secret-key backup@ipig.local > backup_gpg_privkey.asc
```

私鑰必須**離線**存兩份，**不可放雲端**：

1. **USB 隨身碟 #1** — 鎖在公司保險箱 / 抽屜
2. **USB 隨身碟 #2** — 帶回家 / 給可信任的家人保管
3. （加碼）**Paper key**：用 [`paperkey`](https://www.jabberwocky.com/software/paperkey/) 工具把私鑰轉成 ASCII，列印實體紙本，鎖保險箱

**測試還原**：把私鑰 import 到另一台機器試試解密一個檔案，確保救回時用得到。

### 1.4 從個人工作機**刪掉**私鑰

```bash
gpg --delete-secret-keys backup@ipig.local
gpg --delete-keys backup@ipig.local  # 公鑰也刪，避免留軌跡
shred -u backup_gpg_privkey.asc       # 安全刪除檔案
```

從此私鑰**只在 USB / paper key 上**，prod 機跟你個人機都不存。

---

## Step 2：申請 Cloudflare R2（15 min）

### 2.1 註冊 Cloudflare 帳號

[https://dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up) — 信箱 + 密碼 + 雙重認證（**啟用 TOTP，不要用 SMS**）。

### 2.2 開通 R2

- Dashboard → 左側 R2 Object Storage → "Get Started"
- 加付款方式（R2 對 < 10GB 完全免費，但需要綁卡驗證）
- 建 Bucket：
  - Name: `ipig-backups-prod`
  - Location: `Asia-Pacific (APAC)` — 比較近
  - Default Storage Class: `Standard`

### 2.3 建 API Token（**最小權限**）

- R2 → "Manage R2 API Tokens" → Create Token
- Permission: **Object Read & Write**（不要給 Admin Read & Write）
- Specify bucket: `ipig-backups-prod`（**不要 All buckets**）
- TTL: 不過期（backup 是 daemon，過期會壞）
- 拿到後**立刻記**：
  - `Access Key ID`
  - `Secret Access Key`
  - `S3 API endpoint` 形如 `https://<account_id>.r2.cloudflarestorage.com`
- **這個 secret 只顯示一次**，搞丟要 revoke 重發

### 2.4 設 Lifecycle 規則（30 天自動刪）

- Bucket → Settings → Object Lifecycle Rules → Add rule
- Name: `delete-after-30d`
- Action: `Delete objects after 30 days`
- Prefix: 留空（適用全 bucket）

> 醫療研究習慣 90 天，看你需求調。R2 < 10GB 免費所以放久也 OK。

---

## Step 3：DS918 SMB share 設定（10 min）

### 3.1 建 backup 專用 user

不要用 admin 帳號。在 DSM：
- Control Panel → User & Group → Create
- Name: `ipig_backup`
- Password: 設強密碼，等下要記
- Groups: 不加 administrators，只加 users
- Storage quota: 適度（例 50GB）

### 3.2 建 shared folder

- Control Panel → Shared Folder → Create
- Name: `ipigsystem_backup`
- Location: 選 SSD volume（不要 HDD，IO 快很多）
- 勾選「Encrypt this shared folder」（DSM 內加密，雙保險）
- Permissions: `ipig_backup` 用戶 = **Read/Write**，其他用戶 = No access

### 3.3 確認 SMB service 開啟

- Control Panel → File Services → SMB
- ✅ Enable SMB service
- Protocol: minimum **SMB 2**（SMB 1 不安全），maximum SMB 3
- Workgroup: `WORKGROUP`（預設）

### 3.4 取得 DS918 IP

DSM → Control Panel → Network → Network Interface — 看 LAN IP（通常 `192.168.1.x` 或 `10.x.x.x`）。**用 IP 不要用 hostname**，因為容器內無法解析 NetBIOS。

例：`192.168.1.50`

---

## Step 4：填 prod 機的 secrets / .env（5 min）

在 prod 機的 ipig_system 專案根目錄。

### 4.1 GPG 公鑰

```bash
# 從 USB 複製 backup_gpg_pubkey.asc 到：
secrets/backup_gpg_pubkey.asc
```

### 4.2 rclone config

建 `secrets/rclone.conf`，內容：

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = <Step 2.3 拿到的 Access Key ID>
secret_access_key = <Step 2.3 拿到的 Secret Access Key>
endpoint = <Step 2.3 拿到的 endpoint URL>
acl = private
no_check_bucket = true

[ds918]
type = smb
host = <Step 3.4 拿到的 IP，例 192.168.1.50>
user = ipig_backup
pass = <用 rclone obscure 加密過的密碼，見下方>
domain = WORKGROUP
```

#### 取得 obscured SMB password

rclone 不存明文密碼，要先 obscure 一次：

```bash
docker run --rm rclone/rclone obscure '<原始 SMB 密碼>'
# 輸出一串字元，把它貼到 rclone.conf 的 pass=
```

### 4.3 .env 加密設定

```bash
# .env (部分)
BACKUP_REQUIRE_ENCRYPTION=true
BACKUP_GPG_RECIPIENT=backup@ipig.local
BACKUP_RCLONE_REMOTES=r2:ipig-backups-prod,ds918:ipigsystem_backup
```

`BACKUP_GPG_RECIPIENT` 要跟 Step 1.1 設的 email 完全一致。

---

## Step 5：重啟 + 驗證（5 min）

```bash
docker compose up -d db-backup
docker logs ipig-db-backup --tail 20
```

期望看到：
```
📋 iPIG DB Backup Container
   排程: 0 2 * * *
   保留: 30 天
   異地: r2:ipig-backups-prod,ds918:ipigsystem_backup
   加密: true（recipient: backup@ipig.local）

🔑 GPG 公鑰已 import（從 /run/secrets/backup_gpg_pubkey）
✅ GPG 加密已設定，收件者: backup@ipig.local
📤 異地備份目標 (rclone): r2:ipig-backups-prod,ds918:ipigsystem_backup
✅ Cron 排程已設定，啟動 crond...
```

### 手動觸發一次

```bash
docker exec ipig-db-backup /usr/local/bin/pg_backup.sh
```

成功的話會看到：
```
[ts] Starting backup of ipig_db...
Verifying backup integrity...
Encrypting backup with GPG for recipient: backup@ipig.local
Checksum: <hash>
[ts] Backup complete: /backups/ipig_<ts>.sql.gz.gpg (~700K)
  Retention: 30 days, cleaned up 0 old backups
  → 上傳到 r2:ipig-backups-prod/2026/05/...
  → 上傳到 ds918:ipigsystem_backup/2026/05/...
  ✅ 異地上傳完成
```

### 三個位置都驗證

```bash
# 本機
docker exec ipig-db-backup ls -la /backups/

# Cloudflare R2（從 Cloudflare dashboard 看 bucket）
# 或：
docker exec ipig-db-backup rclone ls r2:ipig-backups-prod/

# DS918 SMB
docker exec ipig-db-backup rclone ls ds918:ipigsystem_backup/
# 或在 Windows 上開檔案總管：\\<DS918 IP>\ipigsystem_backup\
```

---

## Step 6：Restore Drill（**首次設定後 1 週內必做**）

未驗證的 backup 不算 backup。下載最新檔 → 解密 → 還原到 test DB。

### 6.1 下載最新加密 backup

```bash
docker exec ipig-db-backup rclone copy r2:ipig-backups-prod/2026/05/ /tmp/restore_test/ --include "*.gpg"
```

### 6.2 解密（需要 USB 上的私鑰）

在你個人工作機（暫時 import 私鑰）：

```bash
gpg --import backup_gpg_privkey.asc  # 從 USB
gpg --decrypt ipig_xxx.sql.gz.gpg > ipig_xxx.sql.gz
gpg --delete-secret-keys backup@ipig.local  # 用完立刻刪
```

### 6.3 還原到 test DB

```bash
# 啟一個獨立 postgres 容器
docker run --name ipig-restore-test -e POSTGRES_PASSWORD=test -p 5433:5432 -d postgres:16-alpine

# 還原
gunzip -c ipig_xxx.sql.gz | docker exec -i ipig-restore-test pg_restore -U postgres -d postgres --create

# 抽查
docker exec ipig-restore-test psql -U postgres -d ipig_db -c "SELECT count(*) FROM animals;"
```

跟 prod row count 比對 — 一致即還原 OK。產出紀錄到 `docs/runbooks/dr-drill-records.md`。

---

# 故障排除

## entrypoint 報 `ERROR: GPG keyring 找不到 'xxx'`

`secrets/backup_gpg_pubkey.asc` 的 key 跟 `BACKUP_GPG_RECIPIENT` 不一致。
- 確認 email 完全相同
- 確認 .asc 檔內容是公鑰（`-----BEGIN PGP PUBLIC KEY BLOCK-----` 開頭）

## entrypoint 報 `ERROR: rclone remote 'xxx' 未在 secrets/rclone.conf 設定`

`BACKUP_RCLONE_REMOTES` 的 remote name 跟 `rclone.conf` `[xxx]` section 不一致。

## rclone 上傳 SMB 失敗 `dial tcp: lookup DS918`

容器無法解析 hostname，**用 IP**（在 rclone.conf 把 `host =` 改成 IP）。

## rclone 上傳 R2 失敗 `403 Forbidden`

API token 權限不夠。重新產 token，確認：
- Permission: Object Read & Write
- Bucket: 指定到正確的 bucket（不要 All buckets）

## Backup 容器一直重啟

```bash
docker logs ipig-db-backup
```
看 entrypoint 退出原因。最常見是 secret 檔不存在 — `secrets/` 內必須有：
- `backup_gpg_pubkey.asc`（可空，但 BACKUP_REQUIRE_ENCRYPTION=true 時要有內容）
- `rclone.conf`（可空，但 BACKUP_RCLONE_REMOTES 非空時要有設定）

---

# 後續維護

## 每月

- [ ] 看 Grafana → backup_last_success_timestamp_seconds 持續更新中
- [ ] 抽 R2 / DS918 各一個檔案驗證可下載

## 每季

- [ ] 跑一次 restore drill（Step 6）
- [ ] 紀錄到 `docs/runbooks/dr-drill-records.md`

## 每年

- [ ] 確認私鑰 USB 還能讀（USB 也會壞）
- [ ] R2 帳單檢查（< 10GB 應該全免費）
- [ ] DS918 backup user 密碼換新

---

# 相關檔案

- `scripts/backup/pg_backup.sh` — 主備份腳本
- `scripts/backup/entrypoint.sh` — 容器啟動邏輯
- `scripts/backup/Dockerfile.backup` — 容器 image 定義
- `docker-compose.yml` 的 `db-backup` service section
- `monitoring/prometheus/alert_rules.yml` 的 `ipig_backup_alerts` group
- `docs/TODO.md` R36 — Backup & DR 緊急修復追蹤
