# Docker Secrets 管理 Runbook

> **目的**：盤點 ipig_system 所有 docker secret 檔（`secrets/` 目錄），規範 fresh deploy 該怎麼 seed、輪換週期、撤銷流程。
>
> **適用對象**：第一次部署 / 還原災難 / 新人 onboarding / 定期輪換。
>
> **建立**：2026-05-09（R37-11 收尾）。

---

## 1. 為什麼用 secret file 而不是 .env

| 風險 | .env 明文 | Secret file |
|---|---|---|
| `docker inspect <container>` 能看到 | ✅ 看得到 | ❌ 看不到（mount 為 file） |
| 進 container shell `env` 列出 | ✅ 看得到 | ❌ 看不到（檔案在 `/run/secrets/`，不是 env） |
| 容易誤 commit 到 git | ⚠️ 是（即使 gitignored 也可能 force-add） | 同樣風險，但檔名/路徑更明顯標示「secret」 |
| 多 service 共用 | 必須複製到每個 service `environment:` | 一個 file，多 service mount 即可 |
| 輪換時需重啟服務 | ✅ 是 | ✅ 是（同樣需要） |

**結論**：secret file 不是「銀彈」，但**最小化曝露面**且更符合 docker / kubernetes 慣例。

---

## 2. Secret 檔案完整清單

### 2.1 既有（R37 之前就在的）

| 檔案 | 用途 | 哪個 service 讀 | 來源 |
|---|---|---|---|
| `secrets/db_password.txt` | Postgres password（給 api / outbox / db-backup） | 多個 | 部署人員產生 |
| `secrets/db_url.txt` | 完整 DATABASE_URL connection string | api / outbox / seed | 部署人員拼接 |
| `secrets/smtp_password.txt` | api 對 SMTP 主帳號密碼 | api / outbox | Gmail app password |
| `secrets/jwt_ec_private_key.pem` | JWT 簽章私鑰（ES256 EC P-256） | api | `openssl ecparam -name prime256v1 -genkey ...` |
| `secrets/jwt_ec_public_key.pem` | JWT 驗證公鑰 | api | 從上面 derive |
| `secrets/google-service-account.json` | Google Calendar API service account | api | GCP Console 下載 |
| `secrets/grafana_smtp_password.txt` | Grafana 自己發 alert email 用 | grafana | Gmail app password #2 |
| `secrets/alert_smtp_password.txt` | Alertmanager 發 critical alert email 用 | alertmanager | Gmail app password #3 |
| `secrets/grafana_pg_password.txt` | Grafana datasource → Postgres readonly 連線 | grafana | 部署人員產 |
| `secrets/prometheus_password.txt` | Prometheus basic auth | grafana / promtail | 部署人員產 |
| `secrets/metrics_token.txt` | api `/metrics` Bearer token | api / prometheus | `openssl rand -hex 32` |
| `secrets/alertmanager_webhook_token.txt` | Alertmanager → api webhook 認證 | api | `openssl rand -hex 32`（檔案先前已存在；R37-7 移除 `.env` 內重複的明文後，此檔成為唯一來源） |
| `secrets/cloudflare_tunnel_token.txt` | Cloudflare Tunnel 連線 token | cloudflared | Cloudflare dashboard |
| `secrets/backup_gpg_pubkey.asc` | Backup GPG 加密公鑰 | db-backup | 詳見 `backup-private-key-handling.md` |
| `secrets/rclone.conf` | Backup 異地上傳 rclone 設定（R2 + DS918 SMB） | db-backup | 詳見 `backup-setup.md` |

### 2.2 R37 新增（2026-05-09）

| 檔案 | 用途 | 哪個 service 讀 | 種子值/產生方式 |
|---|---|---|---|
| `secrets/audit_hmac_key.txt` | HMAC chain 完整性 key（GLP §11.10(e)） | api | `openssl rand -base64 32`（**不可變更**否則 chain 斷，需走 HMAC versioning 流程） |
| `secrets/admin_initial_password.txt` | 首次部署建 admin 用 | api | `openssl rand -base64 18` 或 Bitwarden 產 16+ 字元 |
| `secrets/grafana_admin_password.txt` | Grafana admin login 密碼 | grafana | Bitwarden 產 16+ 字元 |
| `secrets/pdf_service_token.txt` | pdf-service 服務間認證 | api / pdf-service | `openssl rand -hex 32` |

> 註：`secrets/image_processor_token.txt` 原本是 R37-5 的計劃項目，但 R37-12 review 發現 image-processor 是 dead code 已整個服務刪除（不再需要此 secret）。

---

## 3. Fresh Deploy 步驟（順序很重要）

> 假設你 clone 了 repo，正在第一台機器部署 prod。

### Step 1：建 `secrets/` 目錄
```bash
mkdir -p secrets
chmod 700 secrets       # 只有 owner 能讀
```

### Step 2：產生加密金鑰（一次性，永遠不變）

```bash
# JWT EC 金鑰（ES256）
openssl ecparam -name prime256v1 -genkey -noout \
  | openssl pkcs8 -topk8 -nocrypt > secrets/jwt_ec_private_key.pem
openssl ec -in secrets/jwt_ec_private_key.pem -pubout > secrets/jwt_ec_public_key.pem

# HMAC chain key（R37-1）— 一旦產生不可變更
openssl rand -base64 32 | tr -d '\n' > secrets/audit_hmac_key.txt
```

### Step 3：產生服務間 token（隨機，可輪換）

```bash
openssl rand -hex 32 | tr -d '\n' > secrets/metrics_token.txt
openssl rand -hex 32 | tr -d '\n' > secrets/alertmanager_webhook_token.txt
openssl rand -hex 32 | tr -d '\n' > secrets/image_processor_token.txt
openssl rand -hex 32 | tr -d '\n' > secrets/pdf_service_token.txt
```

### Step 4：DB 密碼（你自己選 + 拼 URL）

```bash
# 自己選個強密碼
echo -n 'YOUR_STRONG_DB_PASSWORD' > secrets/db_password.txt

# 拼 connection string（替換 IP / port）
echo -n 'postgresql://postgres:YOUR_STRONG_DB_PASSWORD@db:5432/ipig_db' > secrets/db_url.txt

# Grafana datasource 用唯讀帳號（建議建獨立 readonly user，不要用 superuser）
echo -n 'GRAFANA_DATASOURCE_PG_PASSWORD' > secrets/grafana_pg_password.txt
```

### Step 5：Admin / Grafana 密碼（人類記得住的）

```bash
# Admin 初始密碼（首次登入會強制改）
echo -n 'AdminIpig2026!SetMeAtFirstLogin' > secrets/admin_initial_password.txt

# Grafana admin（Bitwarden 產強密碼，存 Bitwarden item「Grafana admin」）
echo -n 'PASTE_BITWARDEN_GENERATED_HERE' > secrets/grafana_admin_password.txt
```

### Step 6：Email / SMTP（Gmail app passwords，每個 service 獨立）

到 https://myaccount.google.com/apppasswords 產三個獨立 app password：

```bash
echo -n 'app_pw_for_api_smtp' > secrets/smtp_password.txt
echo -n 'app_pw_for_grafana_smtp' > secrets/grafana_smtp_password.txt
echo -n 'app_pw_for_alertmanager_smtp' > secrets/alert_smtp_password.txt
```

> 為什麼三個不一個？**每個 service 獨立 = 哪個服務洩漏單獨輪換不影響其他**。

### Step 7：第三方服務 token

```bash
# Cloudflare Tunnel（Cloudflare dashboard → Zero Trust → Networks → Tunnels）
echo -n 'PASTE_TUNNEL_TOKEN' > secrets/cloudflare_tunnel_token.txt

# Google Calendar service account JSON
# GCP Console → IAM → Service Accounts → 建 key → 下載 JSON
mv ~/Downloads/your-service-account.json secrets/google-service-account.json
```

### Step 8：Backup（GPG + rclone）

詳見：
- [`backup-private-key-handling.md`](backup-private-key-handling.md) — GPG keypair 產生 + USB 備份
- [`backup-setup.md`](backup-setup.md) — Cloudflare R2 + DS923+ SMB 設定

### Step 9：Prometheus password

```bash
echo -n 'STRONG_BASIC_AUTH_PASSWORD_FOR_PROMETHEUS' > secrets/prometheus_password.txt
```

### Step 10：權限收緊

```bash
chmod 600 secrets/*.txt secrets/*.pem secrets/*.json
```

### Step 11：驗證

```bash
ls -la secrets/
# 應該看到全部 16 個檔案，permissions 都是 -rw-------（600）

docker compose config 2>&1 | grep -i error
# 不應該有 "Failed to read secret file" 之類錯誤

docker compose up -d
# 全部 healthy
```

如果 `docker compose up` 報 `secret file not found ./secrets/<name>.txt`，回去看哪步漏了。

---

## 4. 輪換週期

| Secret | 建議週期 | 觸發時機 |
|---|---|---|
| `db_password.txt` | 每 6 個月 | 或 DB 用戶離職 |
| `smtp_password.txt` / 兩個 grafana/alert SMTP | 每 6 個月 | 或懷疑外洩 / Gmail 帳號異常 |
| `jwt_ec_private_key.pem` | **不輪換**（除非洩漏） | 輪換 = 所有 user 強制重新登入 |
| `audit_hmac_key.txt` | **不輪換**（除非洩漏） | 輪換需走 HMAC versioning 流程，舊 audit 用舊 key 驗、新 audit 用新 key |
| `admin_initial_password.txt` | 一次性使用 | 首次登入後此檔不再用，可保留作 disaster recovery |
| `grafana_admin_password.txt` | 每 6 個月 | 或唯一管理者離職 |
| `metrics_token.txt` / `alertmanager_webhook_token.txt` / `image_processor_token.txt` / `pdf_service_token.txt` | 每 12 個月 | 服務間 token，影響面小 |
| `cloudflare_tunnel_token.txt` | Cloudflare 自動管理 | 跟著 Cloudflare 警告做 |
| `google-service-account.json` | 每 12 個月 | GCP 政策可能要求 |
| `prometheus_password.txt` | 每 6 個月 | — |

---

## 5. 輪換流程（範例：service token）

以 `pdf_service_token.txt` 為例：

```bash
# 1. 產新 token
NEW_TOKEN=$(openssl rand -hex 32)

# 2. 寫入檔案（覆蓋舊值）
echo -n "$NEW_TOKEN" > secrets/pdf_service_token.txt

# 3. 重啟兩端服務（讀者 + 發送者）
docker compose restart pdf-service api

# 4. 驗證
docker exec ipig-pdf-service python -c 'from app.config import config; print(len(config.internal_token))'
# 應該是 64

# 5. 跑一次 PDF 產生（API 對 pdf-service 認證能通才算 OK）
curl -X POST https://localhost:8000/api/v1/animals/some-uuid/medical-record/pdf \
  -H "Authorization: Bearer YOUR_JWT" -o /tmp/test.pdf
file /tmp/test.pdf  # 應該說 "PDF document"
```

---

## 6. 撤銷流程（懷疑外洩）

> ⚠️ 假設 `secrets/grafana_smtp_password.txt` 被攻擊者拿到。

### 立即（5 分鐘內）

1. **撤銷外洩 token**：
   - Gmail app password → https://myaccount.google.com/apppasswords → Revoke
   - 即使檔案還在 prod，舊密碼已失效，攻擊者拿不到 SMTP 存取

2. **產新 token + 寫入新值**：
   ```bash
   # Gmail 產新 app password
   echo -n 'NEW_APP_PASSWORD' > secrets/grafana_smtp_password.txt
   ```

3. **重啟服務**：
   ```bash
   docker compose restart grafana
   ```

### 短期（24 小時內）

4. **檢查 audit log** 看有沒有可疑活動：
   ```sql
   SELECT * FROM user_activity_logs WHERE created_at > NOW() - INTERVAL '7 days' ORDER BY created_at DESC;
   ```

5. **更新 Bitwarden** item，標註輪換時間

6. **寫事故報告**：紀錄外洩時間、影響範圍、解決步驟、後續預防（是否升級 secret 鎖、是否擴大輪換範圍）

### 長期

7. **Post-mortem**：怎麼洩漏的？git push 不小心包進去？.env 留在 backup？電腦被偷？
8. **加自動化掃描**：CI 加 [`gitleaks`](https://github.com/gitleaks/gitleaks) / [`trufflehog`](https://github.com/trufflesecurity/trufflehog) 防 commit 到 secret

---

## 7. 對應 codebase 的讀取機制

| 服務 | 讀 secret 方式 |
|---|---|
| **api (Rust)** | `backend/src/config.rs::read_secret(name)` — 先試 `<NAME>_FILE` env 指向的檔，沒有則 fallback `<NAME>` env |
| **pdf-service (Python)** | `pdf-service/app/config.py::_read_secret(name)` — 同上 fallback 邏輯 |
| **image-processor (Node.js)** | `image-processor/src/config.js::readSecret(name)` — 同上 fallback 邏輯 |
| **Grafana** | 原生支援 `<KEY>__FILE`（**雙底線**），如 `GF_SECURITY_ADMIN_PASSWORD__FILE` |
| **Alertmanager** | 自寫 `monitoring/alertmanager/docker-entrypoint.sh` Plan B：env 空才讀 `/run/secrets/` |
| **db-backup container** | `scripts/backup/entrypoint.sh` 自動 import GPG 公鑰 + symlink rclone.conf |
| **Postgres** | docker `POSTGRES_PASSWORD_FILE` 原生支援 |

→ 三個自寫的 helper 都遵循同一語義：**檔在 = 用檔；檔讀失敗 / 沒設 = fallback env**。

---

## 8. .gitignore 確認

```bash
cat .gitignore | grep -A2 secrets
# 應該看到：
# secrets/
```

`secrets/` 整個目錄都 gitignored。永遠不要 `git add -f secrets/...`。

---

## 9. 反向引用

- 私鑰實體管理（USB / 紙本）：[`backup-private-key-handling.md`](backup-private-key-handling.md)
- Backup 異地設定：[`backup-setup.md`](backup-setup.md)
- HMAC chain 輪換：[`../security/HMAC_VERSIONING.md`](../security/HMAC_VERSIONING.md)
- TODO backlog：`docs/TODO.md` R37

---

## 10. 變更紀錄

| 日期 | 變更 | 操作者 |
|---|---|---|
| 2026-05-09 | R37-1/2/3/4/5/6/7：5 個新 secret 檔加入清單 | Jason |
| 2026-05-09 | 本 SOP 文件建立 | Jason |
