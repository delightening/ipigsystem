# iPig System — 伺服器遷移 SOP

> 本機 (筆電 prod) → 自建 Ubuntu Server 24.04 LTS + Cloudflare Tunnel
>
> **2026-07-24 決策變更**：目標從「搬去 NAS 跑」（DS925+ / DS923+，見已棄用的
> `../DEPLOYMENT_NAS_DS923.md`）改成「另外買一台獨立 Linux 伺服器」，NAS
> （DS918 + DS923+）純粹當備份鏈，不跑運算。理由與硬體規格討論見
> `project_local_server_migration` 記憶條目。

## 總覽

```text
本機 (Windows)                    新伺服器 (Ubuntu Server 24.04)   Cloudflare
┌──────────────┐   scp/rsync ┌──────────────────┐   Tunnel   ┌─────────────┐
│ PostgreSQL   │ ──────────> │ PostgreSQL       │            │             │
│ uploads/     │ ──────────> │ uploads/         │            │ app.domain  │
│ configs/     │ ──────────> │ configs/         │            │     ↓       │
│ secrets/     │ ──(手動)──> │ secrets/         │            │  Tunnel     │
└──────────────┘             │ cloudflared ─────│───────────>│     ↓       │
                             │ web (nginx) ←────│────────────│  web:8080   │
                             │ api ← print-pdf   │            │             │
                             └──────────────────┘            └─────────────┘
                                      │
                                      │ rclone (不變)
                                      ▼
                             DS918（主備份，SMB）
                                      │ DSM 排程同步（NAS 對 NAS，跟本 SOP 無關）
                                      ▼
                             DS923+（備份的備份）
```

硬體規格：全新 Tower 企業伺服器（Dell PowerEdge T150 / HPE ProLiant
MicroServer Gen11 同級）、iDRAC/iLO 遠端管理、原廠到府保固、32GB ECC、
2 顆 SSD 硬體 RAID1（開機碟即資料碟，不用另外規劃資料分割區）。

---

## Step 0: 新伺服器前置準備（買回來第一次開機）

### 0.1 OS 安裝

- **Ubuntu Server 24.04 LTS**（優先於 Debian：CI runner 同為 Ubuntu，操作習慣一致）
- 安裝時確認 RAID1 已在 BIOS/主機板 RAID controller 層組好，OS 裝在 RAID1 陣列上
- 裝完立刻：`sudo apt update && sudo apt upgrade -y`

### 0.2 基礎安全設定

```bash
# 防火牆：預設 deny incoming，只開必要 port
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from <你的區網網段> to any port 22   # SSH 僅限區網，對外走 Tailscale/Tunnel
sudo ufw enable

# 時間同步（GLP 稽核鏈 + HMAC chain 對時間戳敏感）
sudo apt install -y chrony
sudo systemctl enable --now chrony
timedatectl status   # 確認 System clock synchronized: yes
```

### 0.3 遠端管理

- 設定 iDRAC/iLO 的獨立管理網路（走實體管理口，不跟業務網路混），供主機當機時遠端重開機/看畫面
- 裝 Tailscale 或用現有 Cloudflare Tunnel 加一條 SSH hostname，作為日常 SSH 管道（不對外開 22）

### 0.4 UPS

- 接上 Line-interactive UPS（USB 連接主機）
- 裝 `apcupsd`（APC）或 NUT（其他品牌），設定斷電後 graceful shutdown（`docker compose stop` → `poweroff`）
- 測試一次拔電源，確認真的會觸發 graceful shutdown 而不是硬斷電

### 0.5 Docker

```bash
# 官方安裝腳本（或用 apt 的 docker.io + docker-compose-plugin 亦可）
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# 重新登入後確認
docker compose version
```

### 0.6 GHCR 登入

```bash
docker login ghcr.io -u <GITHUB_USERNAME> --password-stdin < token.txt
```

---

## Step 1: 新伺服器建立目錄結構

```bash
sudo mkdir -p /opt/ipig/{repo,uploads}
sudo mkdir -p /opt/ipig/repo/secrets
sudo chown -R $USER:$USER /opt/ipig

# 最終結構：
# /opt/ipig/
# ├── repo/                              ← git clone ipig_system 於此
# │   ├── docker-compose.yml             ← 沿用 repo 原檔，不搬 nas 版
# │   ├── docker-compose.prod.yml
# │   ├── docs/deploy/server-migration/docker-compose.server.yml   ← 疊加層
# │   ├── .env
# │   └── secrets/                       ← ⚠️ 必須在 repo/ 底下，不是 /opt/ipig/secrets/
# │       ├── jwt_ec_private_key.pem     #   （compose secrets: 區塊用 ./secrets/... 相對路徑，
# │       ├── jwt_ec_public_key.pem      #   解析基準是執行 docker compose 當下的目錄，也就是 repo/）
# │       ├── db_url.txt
# │       ├── db_password.txt
# │       ├── smtp_password.txt
# │       ├── audit_hmac_key.txt
# │       ├── csrf_secret.txt
# │       ├── encryption_key.txt
# │       ├── admin_initial_password.txt
# │       ├── pdf_service_token.txt
# │       ├── alertmanager_webhook_token.txt
# │       ├── backup_gpg_pubkey.asc
# │       ├── rclone.conf                ← 內容不變，一樣只指向 DS918
# │       ├── google-service-account.json
# │       └── cloudflare_tunnel_token.txt ← 新增（見 Step 4d）
# └── uploads/                           ← UPLOAD_VOLUME 指到這裡
```

> 資料庫用 Docker named volume（不像舊版 NAS SOP 那樣 bind mount 到
> `/volume1/...`）——整台機器開機碟就是 RAID1，named volume 預設路徑
> `/var/lib/docker/volumes/` 本來就在 RAID1 上，不需要額外規劃資料碟路徑。

---

## Step 2: 本機匯出資料

```bash
# 在本機 ipig_system 專案根目錄執行

# 方法 A: 自動腳本（推薦）
chmod +x docs/deploy/server-migration/data-migration.sh
./docs/deploy/server-migration/data-migration.sh <SSH_USER> <新伺服器_IP>

# 方法 B: 手動操作（見下方）
```

### 手動匯出 PostgreSQL

```bash
# 停止寫入，確保一致性
docker compose stop api web

# 匯出完整 DB
docker compose exec -T db pg_dumpall -U postgres --clean > pg_dump.sql

# 確認檔案大小合理（2026-07-24 實測：prod DB 僅 48MB，uploads 僅 19MB，很小）
ls -lh pg_dump.sql

# 完成後停止所有服務
docker compose down
```

### 手動打包 uploads

```bash
tar czf uploads.tar.gz -C . uploads/
```

---

## Step 3: 傳輸到新伺服器

```bash
SRV="<SSH_USER>@<新伺服器_IP>"
BASE="/opt/ipig"

# repo（直接 git clone 較乾淨，不用 scp 整包程式碼）
ssh ${SRV} "git clone https://github.com/<org>/ipig_system.git ${BASE}/repo"

# DB dump
scp pg_dump.sql ${SRV}:${BASE}/repo/

# Uploads
scp uploads.tar.gz ${SRV}:${BASE}/
ssh ${SRV} "cd ${BASE} && tar xzf uploads.tar.gz && rm uploads.tar.gz"

# geoip（repo 內建，git clone 已包含，不用另外傳）

# Secrets（⚠️ 敏感資料，注意目的地是 repo/secrets/，不是 /opt/ipig/secrets/）
scp -r secrets/ ${SRV}:${BASE}/repo/
ssh ${SRV} "chmod 600 ${BASE}/repo/secrets/*"

# .env
scp .env ${SRV}:${BASE}/repo/.env
```

---

## Step 4: 新伺服器端設定

### 4a. 修改 `.env`

```bash
ssh ${SRV}
cd /opt/ipig/repo
nano .env
```

必須修改的項目：

```env
COOKIE_SECURE=true
SEED_DEV_USERS=false

CORS_ALLOWED_ORIGINS=https://app.yourdomain.com
APP_URL=https://app.yourdomain.com

UPLOAD_VOLUME=/opt/ipig/uploads

GHCR_OWNER=your-github-username
IMAGE_TAG=latest

# rclone 異地備份目標不變，一樣只推 DS918；DS918 → DS923+ 是 NAS 端另外設定的
# Hyper Backup / rsync 排程，跟這台伺服器無關
BACKUP_RCLONE_REMOTES=r2:ipig-backups-prod,ds918:ipigsystem_backup
```

### 4b. `secrets/` 檔案確認

沿用本機現有的完整 secrets 清單（EC 金鑰對、HMAC key、CSRF secret 等），
**不是**舊版 NAS SOP 裡簡化過的 `jwt_secret` 單一金鑰——那份是四月寫的，
跟現在的 secrets 結構已經不同步，忽略即可。

### 4c. rclone 設定不變

```bash
cat secrets/rclone.conf
# 應包含 [r2] 與 [ds918] 兩個 remote，內容跟本機一致，直接複製過來即可
```

### 4d. 新增 Cloudflare Tunnel token

Tunnel token 綁的是「跑 cloudflared 的那台機器」，不是網域本身，換機器要重新取得。
從 Cloudflare Dashboard 複製 token 後寫入檔案，**不要用 `echo` 直接帶明文參數**（會留在
shell history 裡）：

```bash
umask 077
read -r -s -p "貼上 tunnel token: " TUNNEL_TOKEN && echo
printf '%s' "$TUNNEL_TOKEN" > secrets/cloudflare_tunnel_token.txt
unset TUNNEL_TOKEN
chmod 600 secrets/cloudflare_tunnel_token.txt
```

### 4e. 啟動新 connector 並驗證，才切換 Public Hostname

⚠️ **順序很重要**——tunnel token 不綁定單一主機，同一個 token 可以同時在新舊兩台機器
上啟動 connector；利用這點做零停機切換，不要先切 DNS/Hostname 才發現新機連不上：

1. 先照 Step 6 在新伺服器上把 `cloudflared` 疊加服務起來（此時舊筆電的 tunnel 可以繼續跑，
   兩邊 connector 會同時註冊在同一個 tunnel 上）
2. 確認新伺服器這端註冊成功：`docker compose -f docker-compose.yml -f docker-compose.prod.yml
   -f docs/deploy/server-migration/docker-compose.server.yml logs cloudflared --tail 20`
   看到 `Registered tunnel connection`
3. 確認沒問題後，才到 Cloudflare Zero Trust Dashboard 設定/切換 Public Hostname：
   1. **Networks → Tunnels** → 選擇你的 tunnel
   2. **Public Hostname** → Add（或編輯既有規則）
   3. 設定：
      - Subdomain: `app`（或你想要的）
      - Domain: `yourdomain.com`
      - Type: `HTTP`
      - URL: `ipig-web:8080`
4. 實測 `https://app.yourdomain.com` 走的是新伺服器（見 Step 7）後，才停掉舊筆電的
   cloudflared，並考慮到 Dashboard 輪替 token（因為遷移期間 token 明文經手過 SSH/剪貼簿）

---

## Step 5: 匯入資料庫

```bash
cd /opt/ipig/repo

# 先只啟動 DB
docker compose up -d db

# 等待 DB 就緒
docker compose exec db pg_isready -U postgres
# 反覆執行直到回傳 "accepting connections"

# 匯入 dump
docker compose exec -T db psql -U postgres < pg_dump.sql

# 驗證
docker compose exec db psql -U postgres -d ipig_db -c "\dt"
# 應該看到所有 table

# 清理 dump 檔
rm pg_dump.sql
```

---

## Step 6: 啟動所有服務

```bash
cd /opt/ipig/repo

docker login ghcr.io -u <GITHUB_USERNAME> --password-stdin < token.txt
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull

# 啟動：疊加 server overlay、拿掉 watchtower（見該檔案開頭說明）
docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  -f docs/deploy/server-migration/docker-compose.server.yml \
  up -d --no-build --scale watchtower=0

# 檢查狀態
docker compose ps
# 所有服務應該都是 Up (healthy)，給 30 秒讓 healthcheck 通過
```

> **之後查 `cloudflared` 相關指令都要帶完整三個 `-f`**（它只定義在 server overlay 裡，
> 不在 `docker-compose.yml` base 檔，單純 `docker compose logs cloudflared` 會找不到
> service）。嫌麻煩可以設個 alias：
> ```bash
> alias ipig-dc='docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docs/deploy/server-migration/docker-compose.server.yml'
> ```
> 下面 Step 7 / 故障排除涉及 `cloudflared` 的指令都用 `ipig-dc` 取代 `docker compose`。

---

## Step 7: 驗證

### 基本健康檢查

```bash
docker compose ps
docker compose exec api /app/healthcheck
docker compose exec db psql -U postgres -d ipig_db -c "SELECT count(*) FROM users;"

# Cloudflare Tunnel 連線（cloudflared 只在 server overlay 裡，用 ipig-dc）
ipig-dc logs cloudflared --tail 20
# 應看到 "Registered tunnel connection" 或類似成功訊息
```

### 外部存取測試

1. 開啟 `https://app.yourdomain.com`
2. 確認能看到登入頁，用管理員帳號登入
3. 確認資料完整（使用者、動物、上傳的檔案等）

### 檔案上傳測試

```bash
docker compose exec api ls -la /app/uploads/
```

### 備份鏈驗證

```bash
# 確認新伺服器的備份還是有推到 DS918
docker compose exec db-backup rclone ls ds918:ipigsystem_backup/ | tail -5

# 到 DS918 DSM 確認 Hyper Backup / 排程同步工作有把新資料同步去 DS923+
# （這段是 NAS 對 NAS，在 DSM UI 操作，跟這台伺服器的 compose 無關）
```

---

## Step 8: 本機善後

確認新伺服器一切正常後：

```bash
# 1. 本機停止服務（如果還在跑）
docker compose down

# 2. 觀察新伺服器運行 1-2 天確認穩定

# 3. 舊筆電先當 cold spare 留著（2026-07-24 使用者裁定），
#    不要急著清空 postgres_data volume —— 至少留到新伺服器穩定跑
#    1-2 週 + 一次完整備份循環驗證過後
```

---

## 故障排除

### Cloudflare Tunnel 連不上

```bash
ipig-dc logs cloudflared
# 常見錯誤：token 過期或格式錯誤 → 到 Dashboard 重新取得 token

ipig-dc exec cloudflared wget -qO- http://ipig-web:8080/ 2>&1 | head -5
```

### API 啟動失敗

```bash
docker compose logs api --tail 50
# 常見原因：
# - DB 連線失敗 → 檢查 db_url.txt
# - secrets 檔案權限 → chmod 600 secrets/*
# - GHCR image 拉不到 → docker login ghcr.io
```

### DB 匯入失敗

```bash
# 本機重新匯出（單庫）：
docker compose exec -T db pg_dump -U postgres -Fc ipig_db > ipig_db.dump
# 新伺服器匯入：
docker compose exec -T db pg_restore -U postgres -d ipig_db --clean < ipig_db.dump
```

### uploads 權限問題

```bash
docker compose exec api id
sudo chown -R 1000:1000 /opt/ipig/uploads/
```

---

## 回滾計畫

如果新伺服器出問題，需要退回本機：

```bash
# 1. 新伺服器停止服務
ssh ${SRV} "cd /opt/ipig/repo && docker compose down"

# 2. Cloudflare Dashboard 把 tunnel hostname 指回本機（如果本機也有 tunnel）
#    或暫時移除 hostname

# 3. 本機重新啟動
docker compose up -d

# 4. 如果新伺服器上有新資料需要同步回本機：
ssh ${SRV} "cd /opt/ipig/repo && docker compose exec -T db pg_dumpall -U postgres --clean > /tmp/srv_dump.sql"
scp ${SRV}:/tmp/srv_dump.sql .
docker compose exec -T db psql -U postgres < srv_dump.sql
```
