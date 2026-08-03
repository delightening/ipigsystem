# Cold-Start Runbook — 筆電完全掛時的恢復步驟

> **觸發情境**：prod 筆電（ASUS ExpertBook）硬體故障 / 系統無法開機 / 不可逆斷電損壞。
> **目標 RTO**：≤ 4 小時讓系統重新上線（可降級至唯讀模式）。
> **依賴**：DS923+ NAS（已配置為 backup target，跑 daily 備份 + Restic snapshot）。
> **R36-10 (2026-05-13)**：填補 backup-setup.md 缺的 cold-start + DNS reroute 章節。
> **⚠️ 2026-07-24**：已決定買獨立伺服器跑 prod（見 `docs/deploy/server-migration/`），
> DS923+ 未來只當備份的備份，不再是 compute 候選。伺服器到位、遷移完成前，
> 本篇「用 DS923+ 頂著跑」仍是目前唯一可行的緊急預案，維持原樣；伺服器上線後
> 這篇要改成指向新伺服器（而非 DS923+）當 cold-start 目標。

---

## 0. 故障判斷 — 確認真的需要 cold start

先排除「以為掛了其實沒掛」：

| 症狀 | 可能解 | 試試 |
|---|---|---|
| 網頁 502 / timeout | 容器掛、不是機器掛 | SSH 進機器 `docker ps`、必要時 `docker compose restart api` |
| 機器無回應、Ping 不通 | 網路 / 路由器 | 重啟路由器、檢查 cloudflare tunnel 狀態 |
| 機器開不了機 | **真 cold start 場景** | 進入下方流程 |
| 機器能開機但檔案損毀 | DB / 上傳檔案損壞 | 走 [DR_RUNBOOK.md](DR_RUNBOOK.md) restore，不需要 cold start |

---

## 1. 啟動 NAS Docker 環境（DS923+ 接手）

**現況**：DS923+ 跑 DSM 7.2，Container Manager 已安裝。已存 backup 目標 + Restic snapshots。

### 1.1 確認 NAS 可登入

```bash
ssh admin@nas.local
# 或從外網（如果 NAS 有設 QuickConnect / Cloudflare tunnel 到 NAS）
```

### 1.2 還原 ipig_system 程式碼到 NAS

NAS 有 2 種選項（依事前準備狀態）：

**選項 A：NAS 已有 ipig_system clone（推薦）**
```bash
cd /volume1/docker/ipig_system
git fetch origin
git checkout main
git pull
```

**選項 B：NAS 沒 clone**（從 GitHub 拉，需要憑證）
```bash
cd /volume1/docker
git clone https://github.com/delightening/ipig_system.git
cd ipig_system
git checkout main
```

### 1.3 還原 secrets

`.env` + `secrets/` 是 gitignored，需從備份還原：

```bash
# 從 Restic backup 還原 secrets
restic -r /volume1/backup/restic restore latest \
    --target /volume1/docker/ipig_system \
    --include "/ipig_system/.env" \
    --include "/ipig_system/secrets/"
```

或：手動建 `.env`（從 `.env.example` 複製，填入 prod 密碼，從密碼管理器拿）。

關鍵 secrets：
- `JWT_EC_PRIVATE_KEY` + `JWT_EC_PUBLIC_KEY`
- `DB_PASSWORD`
- `ADMIN_INITIAL_PASSWORD`
- `PDF_SERVICE_TOKEN`
- `SMTP_PASSWORD`（如有）

---

## 2. 還原資料庫

### 2.1 啟動 DB container

```bash
cd /volume1/docker/ipig_system
docker compose up -d db
docker compose logs -f db   # 等到看到 "database system is ready to accept connections"
```

### 2.2 還原最新 backup

```bash
# 找最新 backup 檔（Restic snapshot 或 .sql.gz）
ls -lh /volume1/backup/postgres/

# 套用
gunzip -c /volume1/backup/postgres/ipig_db_2026-05-13_03-00.sql.gz | \
    docker exec -i ipig-db psql -U postgres -d ipig_db
```

### 2.3 row-count check

```bash
docker exec ipig-db psql -U postgres -d ipig_db -c "
SELECT 'users' AS t, count(*) FROM users
UNION ALL SELECT 'animals', count(*) FROM animals
UNION ALL SELECT 'protocols', count(*) FROM protocols
UNION ALL SELECT 'observations', count(*) FROM observations
UNION ALL SELECT 'user_activity_logs', count(*) FROM user_activity_logs;
"
```

對照 `docs/runbooks/dr-drill-records.md` §5 上一次 drill 紀錄的數字。差距 < daily 變動量算正常。

---

## 3. 還原 uploads（豬隻照片 / 附件）

`uploads/` 目錄在筆電上是 ~10-20GB 視覺資料。

```bash
# 從 Restic snapshot 還原
restic -r /volume1/backup/restic restore latest \
    --target /volume1/docker/ipig_system \
    --include "/ipig_system/uploads/"
```

驗證：
```bash
du -sh /volume1/docker/ipig_system/uploads/
# 跟最後一次 drill 紀錄比對應該差不多大小
```

---

## 4. 啟動主要 services

### 4.1 不需要 Word daemon 的服務先起來（降級模式）

```bash
cd /volume1/docker/ipig_system
# 降級：不開 pdf-service（沒 daemon 沒意義）
docker compose up -d db api web outbox-worker
docker compose logs -f api  # 等看到 "Server listening on 0.0.0.0:8000"
```

此時系統大部分功能可用，**只有 PDF 匯出會 503**。

### 4.2 確認可登入

從本地 / 暫時 DNS：
- `http://nas.local:8080/login`（NAS 內網 + 端口直連）
- 用 admin 帳密測登入 → 進 dashboard → 看到動物列表

---

## 5. Cloudflare tunnel reroute

**現況**：cloudflare-tunnel 原本指向筆電。需要重新指向 NAS。

### 5.1 SSH 進 Cloudflare 設定

選 A：登入 Cloudflare dashboard → Networks → Tunnels → 找到 `ipigsystem-prod` tunnel → 改 origin。

選 B：NAS 上跑新 tunnel
```bash
# NAS 上安裝 cloudflared
docker run -d --name cloudflared \
    --restart unless-stopped \
    cloudflare/cloudflared:latest tunnel \
    --no-autoupdate run \
    --token <TUNNEL_TOKEN_FROM_PASSWORD_MANAGER>
```

### 5.2 驗證

```bash
curl -I https://ipigsystem.asia/api/health
# 應該 200 + "healthy"
```

---

## 6. （選擇性）切 DNS 到 NAS 直連

**僅當 Cloudflare tunnel 也壞時**才需要這步。

### 6.1 NAS 上裝 nginx + Let's Encrypt

NAS 已內建反向代理，DSM Control Panel → Login Portal → Reverse Proxy。
或直接跑 docker-compose.yml 內 `web` service 對外。

### 6.2 修改 DNS

到 Cloudflare DNS → A record `ipigsystem.asia` 改指向 NAS 公網 IP（如果 NAS 在 NAT 後面需開 port forward 443）。

⚠️ **DNS 變更會走 propagation 5-30 分鐘**。

---

## 7. （選擇性）Word/Excel daemon

NAS 上跑不了 Word COM daemon（Linux）。**GLP 匯出在此狀態下全 503**。

選 A：使用者改用「下載 .docx」格式（仍可工作）  
選 B：另一台 Windows 機器跑 daemon，pdf-service `WORD_CONVERT_URL` 指過去

恢復筆電後再切回。

---

## 8. 收尾 + 驗證

### 8.1 跑 row-count 驗證

對照 `dr-drill-records.md` §5 表，row count 應接近上次 drill。

### 8.2 通知 user

從 admin email 寄出「系統恢復通知」+ 已知降級（如 GLP PDF 暫不可用）。

### 8.3 紀錄事件

在 `dr-drill-records.md` 加一筆：
```markdown
### 2026-XX-XX cold-start 事件
- 觸發：[原因]
- RTO 實際：X 小時
- 降級項目：[列出]
- 學到的：[備忘]
```

---

## 9. 故障後檢視 — 為什麼要 cold start

事件結束後 1 週內檢視：
- 筆電是否還能修（送修評估）
- 是否該加速自建伺服器採購（R36-11，2026-07-24 已改方向為獨立主機，見 `docs/deploy/server-migration/`）
- 備份頻率是否足夠（current daily，evaluate hourly?）
- DNS / Cloudflare tunnel reroute 是否能進一步自動化

---

## 連結

- [DR_RUNBOOK.md](DR_RUNBOOK.md) — DB 損壞 / 部分損毀的還原流程
- [backup-setup.md](backup-setup.md) — 備份系統設定
- [dr-drill-records.md](dr-drill-records.md) — 過去 drill 紀錄
- [docs/deploy/server-migration/](../deploy/server-migration/) — 自建伺服器遷移計畫（將筆電 prod 搬到獨立主機）
