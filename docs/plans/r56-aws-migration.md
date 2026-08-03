# R56 — AWS Migration Plan（prod-on-laptop → AWS hybrid）

**建立日期**：2026-05-15
**目標**：將 prod 從筆電遷移至 AWS hybrid 架構（Ubuntu EC2 + Windows EC2 + RDS + S3 + ECR）
**動機**：
1. Solo 玩具 → prod-grade reliability（24/7 uptime）
2. 筆電需離開現場 / 無法持續 24/7 開機
3. Cloudflare Tunnel 依賴筆電本機 daemon 不可靠
4. 對外品牌化、外部 reviewer 接受度

**驅動者**：使用者一人開發 + 維運。預估投入：100-150 小時工程 + ~3 個月日曆時間。

**月費目標**：~NT$5,000/mo（5 年 TCO ~NT$300,000）

---

## 1. Target Architecture

```
                    ┌──────────────────────────────────────────────────┐
                    │              VPC (10.0.0.0/16)                    │
                    │  ap-northeast-1 (Tokyo)                           │
  Internet ──►  Cloudflare proxy ──► ALB (public subnet)                │
                                              │                         │
                          ┌───────────────────┼──────────────────┐      │
                          │                   ▼                  │      │
                          │    ┌──────────────────────────┐      │      │
                          │    │ Ubuntu EC2 t3.medium     │      │      │
                          │    │ (Public subnet)          │      │      │
                          │    │ docker compose:          │      │      │
                          │    │  - api / web             │      │      │
                          │    │  - pdf-service           │      │      │
                          │    │  - gotenberg             │      │      │
                          │    │  - outbox-worker         │      │      │
                          │    │  - grafana / prometheus  │      │      │
                          │    │  - loki / promtail       │      │      │
                          │    │  - alertmanager          │      │      │
                          │    │  - node-exporter         │      │      │
                          │    └─────┬─────────┬──────────┘      │      │
                          │          │         │                 │      │
                          │   HTTPS  │         │ port 5432       │      │
                          │   9099/  │         │                 │      │
                          │   9100   ▼         ▼                 │      │
                          │    ┌──────────────┐  ┌──────────────┐│      │
                          │    │ Windows EC2  │  │ RDS Postgres ││      │
                          │    │ t3.medium    │  │ db.t3.micro  ││      │
                          │    │ (Private)    │  │ (Private)    ││      │
                          │    │ Office LTSC  │  │ multi-AZ     ││      │
                          │    │ Word daemon  │  │ snapshots    ││      │
                          │    │ Excel daemon │  └──────────────┘│      │
                          │    └──────────────┘                  │      │
                          └─────────────────────────────────────┘      │
                                       ▲                                │
                                       │ pull images                    │
                                       ▼                                │
                              ┌─────────────────┐                       │
                              │ ECR registry    │                       │
                              │ ipig-api/web/   │                       │
                              │ pdf-service     │                       │
                              └─────────────────┘                       │
                                       ▲                                │
                                       │ OIDC push                      │
                                       │                                │
                              [GH Actions]                              │
                                                                        │
                              ┌─────────────────┐                       │
                              │ S3 buckets:     │                       │
                              │  uploads/       │ ← Backend writes      │
                              │  db-backups/    │ ← RDS automated       │
                              │  audit-archive/ │ ← R34 audit_archive   │
                              └─────────────────┘                       │
                                                                        │
                              ┌─────────────────┐                       │
                              │ Secrets Manager │ ← EC2 IAM role read   │
                              │  hmac/csrf/jwt  │                       │
                              │  db-password    │                       │
                              │  smtp-password  │                       │
                              └─────────────────┘                       │
                    └──────────────────────────────────────────────────┘
```

---

## 2. Cost Breakdown

| 項目 | 月費 | 5 年 TCO |
|---|---|---|
| Ubuntu EC2 t3.medium (4GB) | $30 | $1,800 |
| Windows EC2 t3.medium (4GB) | $60 | $3,600 |
| RDS db.t3.micro (single-AZ) | $15 | $900 |
| RDS multi-AZ uplift | +$15 | +$900 |
| S3 (50GB + requests) | $5 | $300 |
| EBS gp3 (50GB × 2) | $10 | $600 |
| ALB | $20 | $1,200 |
| Egress (~50GB/mo) | $5 | $300 |
| ECR storage + pull | $2 | $120 |
| RDS snapshots + S3 backup | $5 | $300 |
| Secrets Manager (~5 secrets) | $2 | $120 |
| **AWS 月費合計** | **~$169** | **~$10,140** |
| Office LTSC 2021 Standard | $439 一次 | $439 |
| **5 年 TCO** | | **~$10,580 = NT$320,000** |

**單機選項**（省 Windows EC2 + Office）：把 Word daemon 改用 LibreOffice on Ubuntu → 失去 R45 GLP daemon-only 路徑、IQ/PQ 須重做、文件 fidelity 不保證。**不推薦**。

**Reserved Instance**：rsv 1-year all upfront 可省 ~40%。預估第 1 個月跑穩後切 RI。

---

## 3. Phase-by-Phase Migration

### Phase 0: AWS Account + Foundation（~10h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-0-1 | 建 AWS account + billing alert（$200 警報線） | 1h | [ ] |
| R56-0-2 | Root account 開 MFA + 建 IAM admin user + 不再用 root | 1h | [ ] |
| R56-0-3 | VPC 設計：10.0.0.0/16，public subnet `10.0.1.0/24`、private `10.0.2.0/24`，NAT gateway 或 NAT instance | 2h | [ ] |
| R56-0-4 | Route53 hosted zone（如果走 ALB）或 Cloudflare DNS 規劃 | 1h | [ ] |
| R56-0-5 | ACM TLS 憑證簽 `ipigsystem.asia` + `*.ipigsystem.asia` | 1h | [ ] |
| R56-0-6 | IAM roles 規劃文件：`ec2-ubuntu-role`、`ec2-windows-role`、`gh-actions-deploy-role`、各 policy least-privilege | 4h | [ ] |

### Phase 1: ECR + GH Actions OIDC（~15h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-1-1 | 建 ECR repos：`ipig-api`、`ipig-web`、`ipig-pdf-service`、`ipig-outbox-worker`、`ipig-gotenberg`（若自打）、observability stack（grafana/prometheus 等用 public image，不需 ECR） | 1h | [ ] |
| R56-1-2 | AWS IAM 加 OIDC IdP `token.actions.githubusercontent.com` | 0.5h | [ ] |
| R56-1-3 | IAM role `gh-actions-ecr-push` 帶 ECR push policy；trust policy 限 `repo:delightening/ipig_system:ref:refs/heads/main` | 2h | [ ] |
| R56-1-4 | `.github/workflows/deploy-aws.yml`：build → OIDC → push ECR；初版 dry-run（不部署） | 4h | [ ] |
| R56-1-5 | 驗證 ECR images 本機 pull + docker compose up 仍 work（regression test） | 3h | [ ] |
| R56-1-6 | 設定 image lifecycle policy（保留最近 10 個 tag，舊的自動清） | 1h | [ ] |
| R56-1-7 | （可選）R52 SHA-pin 延伸：ECR images 也用 immutable tags（per-commit SHA）；EC2 pull by SHA 不用 `:latest` | 3h | [ ] |

### Phase 2: Windows EC2 + Office + daemons（~25h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-2-1 | Provision Windows EC2 t3.medium，private subnet，無 public IP | 1h | [ ] |
| R56-2-2 | 安裝 Office LTSC 2021 Standard via Volume License 安裝程式 | 2h | [ ] |
| R56-2-3 | Word + Excel licensing activate（offline）+ disable auto-update | 2h | [ ] |
| R56-2-4 | 複製 `services/word-convert/`（R32-A3 / R44-9 daemon）到 Windows EC2 | 2h | [ ] |
| R56-2-5 | 配置 Word daemon 為 Windows Service（自動啟動、crash restart） | 3h | [ ] |
| R56-2-6 | 同 R56-2-5 for Excel daemon | 3h | [ ] |
| R56-2-7 | 開內部 firewall + security group：只允許 Ubuntu EC2 sg 進 9099 / 9100 | 1h | [ ] |
| R56-2-8 | IQ：版本記錄（Word build / Excel build / .docx template hash） | 2h | [ ] |
| R56-2-9 | PQ：本地測試 5 個 GLP 文件 type（AUP / 巡場報告 / 審查回覆 / 結案報告 / 欄位狀態表）→ output bit-identical with 筆電 prod | 6h | [ ] |
| R56-2-10 | CloudWatch agent 收 daemon log + 設 alarm（crash → email） | 3h | [ ] |

### Phase 3: RDS Postgres（~12h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-3-1 | Provision RDS db.t3.micro Postgres 16，private subnet，single-AZ（PoC）| 1h | [ ] |
| R56-3-2 | parameter group：對齊 docker-compose 設定（max_connections / shared_buffers） | 2h | [ ] |
| R56-3-3 | 自動 daily snapshot 7 天保留 + manual snapshot 點存 | 1h | [ ] |
| R56-3-4 | 本地 `pg_dump` → S3 → RDS `pg_restore` 流程演練 | 3h | [ ] |
| R56-3-5 | 驗證 schema migration（`sqlx::migrate!`）可在 RDS 跑 | 2h | [ ] |
| R56-3-6 | HMAC chain integrity verify 跑過：confirm row HMAC chain 未斷 | 2h | [ ] |
| R56-3-7 | 切 multi-AZ（cutover 前）| 1h | [ ] |

### Phase 4: Ubuntu EC2 docker stack（~20h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-4-1 | Provision Ubuntu 24.04 EC2 t3.medium，public subnet（給 ALB target） | 1h | [ ] |
| R56-4-2 | 安裝 docker + docker-compose-v2 | 1h | [ ] |
| R56-4-3 | EBS gp3 50GB attached to /var/lib/docker | 1h | [ ] |
| R56-4-4 | `docker-compose.prod.yml`：images 從 ECR pull，DB 指 RDS endpoint，Word/Excel daemon 指 Windows EC2 internal IP | 4h | [ ] |
| R56-4-5 | `secrets/*` 檔案棄用 → 全改 AWS Secrets Manager；docker entrypoint 用 IAM role 拉 | 5h | [ ] |
| R56-4-6 | systemd unit `ipig-system.service`：boot 自動 docker compose up | 2h | [ ] |
| R56-4-7 | CloudWatch agent + node-exporter 同 expose | 2h | [ ] |
| R56-4-8 | 第一次 staging cutover smoke test：手動觸發部署、跑 Playwright | 4h | [ ] |

### Phase 5: S3 + Object Storage（~10h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-5-1 | 建 S3 bucket：`ipig-prod-uploads`、`ipig-prod-db-backups`、`ipig-prod-audit-archive` | 1h | [ ] |
| R56-5-2 | Bucket policy：versioning ON、encryption SSE-S3、block public access | 1h | [ ] |
| R56-5-3 | 後端檔案儲存從 local volume 改為 S3（巡場報告照片 / 動物照片 / 計畫書附件） | 4h | [ ] |
| R56-5-4 | 本機 prod 既有 photo files 遷移 S3（`aws s3 sync` / `rclone`） | 2h | [ ] |
| R56-5-5 | RDS daily snapshot 自動 export 到 S3 + retention 90 天 | 1h | [ ] |
| R56-5-6 | `audit_archive` bin 改寫到 S3 而非本地 disk | 1h | [ ] |

### Phase 6: DNS + Ingress（~8h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-6-1 | ALB provision：HTTPS listener → Ubuntu EC2 target group | 2h | [ ] |
| R56-6-2 | ACM 憑證綁定 ALB | 1h | [ ] |
| R56-6-3 | Cloudflare DNS → ALB DNS name（CNAME / `ipigsystem.asia` apex 用 ALIAS）| 1h | [ ] |
| R56-6-4 | Cloudflare proxy mode 啟用（保留 WAF / DDoS 免費 + CDN）| 1h | [ ] |
| R56-6-5 | 移除 Cloudflare Tunnel（cloudflared service 從筆電卸下） | 1h | [ ] |
| R56-6-6 | CSP `Reporting-Endpoints` URL 改成新 AWS prod host | 2h | [ ] |
| R56-6-7 | **R66-B5 proxy header 信任收窄（從 R66 延入）**：ingress 換 ALB 後，`real_ip.rs` 的 trusted-proxy 來源從「CF Tunnel + docker nginx」變「ALB」。改為驗證 TCP peer ∈ ALB/已知 proxy CIDR 才信任 `X-Forwarded-For`，並確認 `cf-connecting-ip` 仍由 CF authoritative 設定。此時 CIDR pin 才 durable（現役拓樸已由 API-不對外 + nginx-loopback 緩解，見 R66-B5 accepted-risk） | 2h | [ ] |

### Phase 7: Observability migration（~12h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-7-1 | 評估：保留 self-hosted Prometheus/Grafana/Loki 或改 CloudWatch | 2h | [ ] |
| R56-7-2 | 決策落地（推薦：保留 self-hosted 在 Ubuntu EC2，CloudWatch 只當 infra 監控） | - | [ ] |
| R56-7-3 | Prometheus retention 從 local volume 改 S3（cheaper for long-term） | 4h | [ ] |
| R56-7-4 | Grafana data source URL 更新（RDS endpoint）| 1h | [ ] |
| R56-7-5 | Loki retention policy 對 S3 | 3h | [ ] |
| R56-7-6 | CloudWatch alarm：EC2 CPU / RAM / disk + RDS connections / storage + ALB target health | 2h | [ ] |

### Phase 8: GH Actions Deploy Automation（~10h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-8-1 | `.github/workflows/deploy-aws.yml` 加 SSM Run Command step：build → push ECR → SSM run `docker compose pull && up` on Ubuntu EC2 | 4h | [ ] |
| R56-8-2 | IAM role for GH Actions：ECR push + SSM SendCommand to 特定 EC2 instance id | 2h | [ ] |
| R56-8-3 | 部署成功 webhook 通知（Slack / email） | 2h | [ ] |
| R56-8-4 | 部署失敗 auto rollback：previous image tag pin + SSM rollback command | 2h | [ ] |

### Phase 9: Cutover（~15h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-9-1 | 安排 maintenance window（週日凌晨 02:00-04:00 GMT+8） | 0.5h | [ ] |
| R56-9-2 | 公告 maintenance window（所有 user）| 0.5h | [ ] |
| R56-9-3 | Pre-cutover smoke test：staging URL 跑 Playwright E2E 全綠 | 3h | [ ] |
| R56-9-4 | Final DB sync：筆電 `pg_dump` → S3 → RDS `pg_restore`（停 write） | 2h | [ ] |
| R56-9-5 | DNS 切換 → Cloudflare cache purge | 1h | [ ] |
| R56-9-6 | Post-cutover smoke test：登入 / 動物 CRUD / AUP submit / PDF export / 巡場報告 | 2h | [ ] |
| R56-9-7 | 監看 48 小時：error rate / response time / DB connections | 6h | [ ] |

### Phase 10: Decommission（~5h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-10-1 | 筆電 prod containers 保持運行 hot-standby 1 週 | - | [ ] |
| R56-10-2 | Cloudflare Tunnel certificate revoke | 0.5h | [ ] |
| R56-10-3 | 1 週後 stop docker compose on 筆電 | - | [ ] |
| R56-10-4 | DB snapshot 移 NAS（per memory `nas-setup` 既有 DS923+ backup target） | 2h | [ ] |
| R56-10-5 | 筆電 reformatted 或留作 dev only | 1h | [ ] |
| R56-10-6 | TODO.md / PROGRESS.md 全套同步 + memory 更新 prod-on-laptop → prod-on-aws | 1.5h | [ ] |

---

## 4. 工時總計

| Phase | 工時 |
|---|---|
| 0 Foundation | 10h |
| 1 ECR + OIDC | 15h |
| 2 Windows EC2 | 25h |
| 3 RDS | 12h |
| 4 Ubuntu EC2 | 20h |
| 5 S3 | 10h |
| 6 DNS | 8h |
| 7 Observability | 12h |
| 8 GH Actions | 10h |
| 9 Cutover | 15h |
| 10 Decommission | 5h |
| **合計** | **142h** |

加 contingency（測試、不可預期）× 1.3 = **~180-200h**。

日曆時間：solo 每週可投入 ~15h → **~3 個月**。

---

## 5. 風險與停機規則

### 🔴 Critical risks

| 風險 | 影響 | 緩解 |
|---|---|---|
| Office LTSC IQ/PQ 不過 | Phase 2 卡死、daemon output 與筆電版本不一致 | 詳細記錄筆電當前 Word build；採購 Office LTSC 後第一週驗證 |
| RDS pg_restore 失敗（schema mismatch / type incompat）| Phase 3/9 卡死 | 先在 staging RDS 驗證；保留筆電 DB 1 個月 |
| HMAC audit chain 斷鏈 | GLP 合規不可恢復 | Phase 3-6 跑 `audit_chain_verify`；異常立即停 |
| Cutover 後 DNS propagation 慢 | 部分使用者長時間 service down | 切換前 DNS TTL 降至 60s；切後 48h 監看 |
| Cloudflare proxy → ALB latency 過高 | 使用者體驗變差 | Phase 9 measure；如 > 200ms p95 考慮 ALB direct（無 Cloudflare proxy） |
| Word/Excel daemon Windows EC2 boot 後沒 auto-start | Cutover 後 GLP 文件全 503 | Phase 2-5/6 設 Windows Service + IQ 包含 reboot test |

### 🟡 High risks

| 風險 | 緩解 |
|---|---|
| 月費超 budget | CloudWatch billing alarm at $200/$300/$400 |
| Reserved Instance 鎖死 1 年但中途想搬 | 第一個月 on-demand 跑穩才轉 RI |
| Egress cost 爆掉（S3 download 大檔）| 用 CloudFront 前置 + browser cache |
| Secrets Manager 用量超 free tier | 預估 5 secrets × $0.40 = $2/mo，控制在小範圍 |

### 必停點

每個 Phase 結束 → 必停確認下一 Phase 風險：
- Phase 2 結束（daemon 驗證）必停 — IQ/PQ 沒過絕不進 Phase 4
- Phase 4 結束（staging cutover）必停 — Playwright 沒全綠絕不進 Phase 9
- Phase 9 cutover 中 — 每步必有 rollback 路徑 + 5 分鐘決斷時間

---

## 6. Rollback

Cutover 失敗：
1. DNS revert 回筆電 IP（TTL 60s → 1-2 分鐘生效）
2. 筆電 prod 仍跑著（per R56-10-1 hot standby 1 週）
3. RDS 保留：使用者資料不丟，下次 cutover 再用
4. 標 R56-9 重做

Phase 失敗：
- Phase 0-7：尚未 cutover，純技術風險，重做即可
- Phase 8：deploy automation 失敗回 manual `docker compose pull && up`
- Phase 9：rollback DNS 即可

---

## 7. 對應 memory / 既有規範

- [[prod-on-laptop]]：完成 cutover 後此 memory 改為 `prod-on-aws`，記錄此次遷移
- [[no-self-imposed-limits]]：移至 AWS 後，docker exec 仍可直接讀（透過 SSM）
- [[nas-setup]]：NAS DS923+ 改為 cold backup（從 RDS S3 snapshot rsync）
- [[word-daemon-already-implemented]]：daemon 從 Windows host 搬到 Windows EC2，code 不動
- R37 `secrets/*` → AWS Secrets Manager（per R56-4-5）
- R51 watcher → 廢案（per R56-8-1 GH Actions SSM Run Command）
- R45 GLP daemon-only 路由：維持不變，daemon hostname 從 localhost 變 Windows EC2 IP
- R52 SHA-pin GH Actions：延伸到 ECR tag immutable（per R56-1-7）

---

## 8. Open decisions（執行前需敲定）

| # | 決策 | 提案 |
|---|------|------|
| D1 | DNS 入口：Cloudflare proxy vs ALB direct | **Cloudflare proxy**（保留 WAF + DDoS + CDN 免費），ALB 隱藏在後 |
| D2 | RDS Multi-AZ 立刻啟用 vs 先 single-AZ | **先 single-AZ**（省 $15/mo），cutover 後 1 個月跑穩切 multi-AZ |
| D3 | EC2 Reserved Instance 何時切 | 跑穩 1-2 個月後 1-year all-upfront（省 ~40%）|
| D4 | Office LTSC 採購管道 | 透過 Microsoft Partner 台灣經銷商 |
| D5 | Migration 起跑日 | 待定 |
| D6 | 是否並行做（不擋既有 prod）| 是 — Phase 0-7 全程不影響筆電 prod；只 Phase 9 短暫 maintenance |
| D7 | 是否找一位顧問 review AWS infra setup | 推薦（Phase 0-1 IAM 設計階段請 1 小時專業 review）|

---

## 9. 後續

- R56 立 TODO entry（10 個 sub-section）
- 第一次推進前：與使用者敲 D1-D7
- 每個 Phase 結束：commit progress note 到 PROGRESS.md §9
- Cutover 完成：寫一篇 retrospective `docs/retros/r56-aws-migration-retro.md`

---

## 10. 補充（2026-05-15）：前端拆 CloudFront + S3，後端走 Cloudflare → EC2

使用者敲定更精確的部署設計：

> **前端**：Cloudflare DNS + CloudFront CDN + S3（瀏覽器檔案）
> **後端**：Cloudflare + EC2 主機（nginx 防攻擊 + docker）+ RDS

這比 §1 原始架構更乾淨 — **靜態 SPA 與動態 API 完全分離**，符合業界標準的 SPA + Backend 拆分模式。

### 10.1 新架構

```
                  Cloudflare DNS（純 DNS，不 proxy）
                        │
       ┌────────────────┴────────────────┐
       │                                  │
       │ ipigsystem.asia                  │ api.ipigsystem.asia
       │                                  │
       ▼                                  ▼
  CloudFront (CDN)                  Cloudflare proxy
       │                                  │ (DDoS / WAF / hide origin IP)
       │ OAC                              │
       │ (Origin Access Control)          │
       ▼                                  ▼
    S3 bucket                       ALB (or direct EC2)
   ipig-prod-spa                          │
   (vite build output)                    ▼
                                    Ubuntu EC2
                                    ├── nginx
                                    │   ├── rate limit (R22)
                                    │   ├── IDOR detect
                                    │   ├── security headers
                                    │   └── reverse-proxy /api/ → api:3000
                                    └── docker compose
                                        ├── api (Rust)
                                        ├── pdf-service
                                        ├── gotenberg
                                        ├── outbox-worker
                                        └── observability stack
                                              │
                                              ▼
                                         RDS Postgres
                                              │
                                              ▼
                                         (Word/Excel daemon @ Windows EC2)
                                              │
                                         S3 (uploads / backups)
```

### 10.2 為什麼這比原方案好

| 面向 | 原方案（單一 EC2 nginx 服務全部） | 新方案（CDN 拆前端）|
|---|---|---|
| 靜態檔案載入速度 | EC2 origin pull，Tokyo 30-50ms | CloudFront edge cache，Asia 各地 < 20ms |
| EC2 RAM 占用 | `web` container ~50MB | 移除 `web` container，省 RAM |
| 部署模式 | nginx 重 build/restart | S3 sync 即時生效，cache invalidation 5-30s |
| 流量成本 | EC2 egress $0.09/GB | CloudFront edge cache → 大部分流量 0 egress 給 EC2 |
| TLS 卸載 | EC2 nginx | CloudFront / Cloudflare 邊緣處理 |
| DDoS 對前端 | EC2 暴露 | CloudFront / Cloudflare 邊緣吸收 |
| Cache invalidation | nginx reload | `aws cloudfront create-invalidation` |

### 10.3 拆分對既有代碼的影響

| 變動 | 影響 |
|---|---|
| **CORS 變必要** | frontend (`ipigsystem.asia`) ≠ backend (`api.ipigsystem.asia`) → 必須加 `Access-Control-Allow-Origin: https://ipigsystem.asia` + credentials 處理 |
| **CSRF cookie** | `SameSite=Lax` → `SameSite=None; Secure`（跨子網域需 None；要 Secure 確保 HTTPS only）|
| **CSP `connect-src`** | 從 `'self'` 改為 `'self' https://api.ipigsystem.asia` |
| **CSP `Reporting-Endpoints`** | 從前端 hostname 改為 backend hostname |
| **nginx 角色** | 移除 SPA static serving；保留 reverse-proxy `/api/` + security headers（限 API endpoint） |
| **Vite build output 部署** | 從 `docker compose build web` 改為 `aws s3 sync frontend/dist/ s3://ipig-prod-spa/` + CloudFront invalidate |
| **本機 dev** | 不變（Vite dev server proxy 到 localhost backend）|
| **Storybook、E2E**| Playwright 設 baseURL 為 staging CloudFront URL |

### 10.4 修正後的 Phase 規劃

原 Phase 4「Ubuntu EC2 docker stack」拆出新 phase：

#### Phase 4a — Backend-only Ubuntu EC2 docker（~15h，原 20h - web）
- 跑 `api / pdf-service / gotenberg / outbox-worker / observability`
- nginx 只當 API reverse-proxy + security
- 移除 `frontend` build target 從 docker-compose
- API hostname `api.ipigsystem.asia` 設定

#### Phase 4b — Frontend S3 + CloudFront（新，~15h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-4b-1 | 建 S3 bucket `ipig-prod-spa`，block public access | 0.5h | [ ] |
| R56-4b-2 | CloudFront distribution + OAC（Origin Access Control，禁直連 S3） | 2h | [ ] |
| R56-4b-3 | CloudFront 設 default root `/index.html` + 404 fallback `/index.html`（SPA routing）| 1h | [ ] |
| R56-4b-4 | ACM 憑證綁定 `ipigsystem.asia`（us-east-1 region for CloudFront） | 1h | [ ] |
| R56-4b-5 | Cloudflare DNS：`ipigsystem.asia` → CloudFront distribution domain | 0.5h | [ ] |
| R56-4b-6 | CloudFront response headers policy：CSP / X-Frame / HSTS 等 — 不再放 nginx | 2h | [ ] |
| R56-4b-7 | GH Actions：build vite + `aws s3 sync` + `cloudfront create-invalidation` | 3h | [ ] |
| R56-4b-8 | Cache rules：`/index.html` no-cache、`/assets/*` immutable cache 1 年 | 1h | [ ] |
| R56-4b-9 | CSP `Reporting-Endpoints` 改 backend hostname；reload prod CSP | 2h | [ ] |
| R56-4b-10 | 本地 Vite dev server 配合（CORS / proxy 設定 update） | 2h | [ ] |

#### Phase 4c — CORS + Cookie pivot（新，~10h）

| # | 項目 | 工時 | 狀態 |
|---|------|------|------|
| R56-4c-1 | backend 加 CORS middleware：`Access-Control-Allow-Origin: https://ipigsystem.asia` + `Allow-Credentials: true` + `Allow-Methods: GET,POST,PUT,DELETE,PATCH` + `Allow-Headers: Authorization, Content-Type, X-CSRF-Token` | 3h | [ ] |
| R56-4c-2 | Cookie 屬性切換：`SameSite=None; Secure; Domain=.ipigsystem.asia`（讓 frontend + backend 共用）| 2h | [ ] |
| R56-4c-3 | CSRF middleware（既有 R33-1）驗證仍 work（不同 origin 但同 parent domain） | 2h | [ ] |
| R56-4c-4 | E2E test 全套跑過：登入 / 動物 CRUD / file upload / PDF export 確認 cross-origin OK | 3h | [ ] |

### 10.5 月費更新

| 項目 | 月費 |
|---|---|
| Ubuntu EC2 t3.small（縮編，移除 web container 後 2GB 可能夠） | $15（vs t3.medium $30） |
| Windows EC2 t3.medium | $60 |
| RDS db.t3.micro | $15 |
| **CloudFront**（前端 CDN，~50GB/mo + ~1M requests）| ~$5 |
| **S3 SPA bucket**（~100MB + GET requests）| ~$1 |
| S3 uploads / backups | $5 |
| EBS gp3 | $10 |
| **ALB**（如保留）vs Cloudflare proxy direct | $20 或 $0 |
| Egress | $5 → **$2**（CloudFront 吃掉 70% 流量） |
| ECR | $2 |
| Snapshots | $5 |
| Secrets Manager | $2 |
| **AWS 月費合計** | **~$147** （原 $169，**省 $22/mo**）|
| Office LTSC 攤提 | $7.30/mo |
| **總月費** | **~$155/mo（NT$4,800）** |

**5 年 TCO：~$10,300 ≈ NT$310,000**（vs 原 NT$320,000，**省 NT$10,000**）

如果 EC2 縮 t3.small（敢冒險）且 ALB 改 Cloudflare proxy direct（省 $20）：**~$112/mo（NT$3,500）**。

### 10.6 風險新增

| 風險 | 影響 | 緩解 |
|---|---|---|
| **CORS preflight 失敗** | OPTIONS request 沒返回正確 header → 整套 API 掛 | Phase 4c-1 設定後 E2E 全套跑；包含 OPTIONS preflight |
| **SameSite=None Cookie 在舊瀏覽器** | Safari 12 以下 / iOS 12 以下無法登入 | 不支援（vet/QAU 應使用現代瀏覽器；可加 user-agent 偵測 + 警告）|
| **CloudFront 缓存失效延遲** | deploy 後 5-30s 內舊版仍 served | 接受；`/index.html` no-cache 確保下次 reload 拿新；assets immutable hash 後綴 |
| **CloudFront ACM 憑證必在 us-east-1** | 區域限制需在不同 region 簽 ACM | Phase 4b-4 已記，記得不要簽錯 region |

### 10.7 修正後的工時總計

| Phase | 原工時 | 新工時 |
|---|---|---|
| 0 Foundation | 10h | 10h |
| 1 ECR + OIDC | 15h | 15h |
| 2 Windows EC2 | 25h | 25h |
| 3 RDS | 12h | 12h |
| 4 Ubuntu EC2 (原) | 20h | - |
| **4a Backend-only Ubuntu EC2** | - | 15h |
| **4b Frontend S3 + CloudFront** | - | 15h |
| **4c CORS + Cookie pivot** | - | 10h |
| 5 S3 (uploads / backups) | 10h | 10h |
| 6 DNS + Ingress (簡化，CloudFront 接前端，ALB 或 Cloudflare proxy 接後端) | 8h | 6h |
| 7 Observability | 12h | 12h |
| 8 GH Actions Deploy | 10h | 12h（多 frontend deploy step）|
| 9 Cutover | 15h | 15h |
| 10 Decommission | 5h | 5h |
| **合計** | **142h** | **162h** |

加 contingency × 1.3 = **~200-220h**，日曆 ~3-4 個月。

### 10.8 新增的 open decision

| # | 決策 | 提案 |
|---|------|------|
| D8 | 後端入口：Cloudflare proxy direct（省 ALB $20）vs ALB | **Cloudflare proxy direct**（單台 EC2 + Cloudflare 已足，ALB 在 1 台 EC2 沒實質意義；除非未來 multi-EC2）|
| D9 | EC2 縮 t3.small（移除 web container 後）vs 保留 t3.medium | 先 t3.medium 跑 1 個月觀察 RAM，後續評估縮 |
| D10 | CloudFront 是否啟用 origin shield | 暫不啟（low traffic），未來流量大時啟 |
| D11 | 前端 deploy 失敗 rollback | S3 versioning + CloudFront 改指舊版本 prefix；具體機制 Phase 8 設計 |
