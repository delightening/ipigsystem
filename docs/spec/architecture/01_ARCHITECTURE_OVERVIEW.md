# 系統架構概覽

> **版本**：7.1
> **最後更新**：2026-07-07（部署/版本事實對齊現行 prod）
> **對象**：全體團隊成員
>
> ⚠️ **部署拓樸權威文件為 [`ARCHITECTURE.md`](./ARCHITECTURE.md) §1**（含完整容器清單與網路隔離）。
> 本檔已校正主要 prod 事實（React 19、無 Redis、無 Vite dev server、migrations 001–124+、
> print-pdf 改用 Playwright/Chromium）；部分細粒度前端函式庫版本號未逐一重新核對，以 `package.json` 為準。

---

## 1. 系統目的

iPig（豬博士動物科技系統）是一套整合型實驗動物管理平台，設計目的為：

- **實驗動物管理**：動物生命週期追蹤、醫療紀錄、血液檢查
- **AUP 審查**：IACUC 計畫書提交、多層審查、變更申請
- **進銷存管理**：採購、庫存、倉庫儲位、SKU 管理
- **人事管理**：出勤打卡、請假、加班、Google 行事曆同步
- **安全合規**：GLP 稽核追蹤、電子簽章、安全異常偵測

---

## 2. 系統架構

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                              iPig System                                     │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐    │
│  │   登入/認證     │ ── │  角色權限控制    │ ── │   模組路由              │    │
│  │   (JWT + Cookie)│    │  (RBAC)         │    │   (前端 + 後端)         │    │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘    │
│                                                                               │
│  ┌───────────────────────────────────────────────────────────────────────┐    │
│  │                        功能模組                                       │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐    │    │
│  │  │  AUP 審查    │  │  iPig ERP    │  │  動物管理                │    │    │
│  │  │  • 計畫書    │  │  • 產品/SKU  │  │  • 動物紀錄              │    │    │
│  │  │  • 審查流程  │  │  • 庫存管理  │  │  • 觀察/手術             │    │    │
│  │  │  • 變更申請  │  │  • 倉庫儲位  │  │  • 血液檢查              │    │    │
│  │  │  • 核准作業  │  │  • 成本追蹤  │  │  • 安樂死管理            │    │    │
│  │  │  • PDF 匯出  │  │  • 夥伴管理  │  │  • 犧牲/病理             │    │    │
│  │  │  • 手寫簽章  │  └──────────────┘  │  • 動物轉讓              │    │    │
│  │  └──────────────┘                     │  • 猝死登記              │    │    │
│  │                                       │  • 電子簽章（手寫）      │    │    │
│  │                                       └──────────────────────────┘    │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐    │    │
│  │  │  人事管理    │  │  通知/排程   │  │  安全與稽核              │    │    │
│  │  │  • 出勤打卡  │  │  • Email     │  │  • Activity Logger       │    │    │
│  │  │  • 請假/加班 │  │  • 站內通知  │  │  • Session Manager       │    │    │
│  │  │  • 特休管理  │  │  • 排程報表  │  │  • Login Tracker         │    │    │
│  │  │  • 行事曆    │  │  • 低庫存    │  │  • GeoIP                 │    │    │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘    │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
│  ┌───────────────────────────────────────────────────────────────────────┐    │
│  │                        橫切關注點                                     │    │
│  │  Rate Limiter · Real IP · CORS · Error Handling · File Upload        │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 技術堆疊

### 3.1 前端

| 技術 | 版本 | 用途 |
|------|------|------|
| React | 19.2.7 | UI 框架 |
| TypeScript | 5.x | 型別安全 |
| Vite | 8.1 | 建置工具（**prod 為 production build → Nginx 靜態，無 dev server**）|
| React Router | 7.18 | 客戶端路由 |
| TailwindCSS | 3.4 | 工具優先 CSS |
| shadcn/ui (Radix) | — | 元件庫 |
| Zustand | 4.5 | 狀態管理 |
| @tanstack/react-query | 5.17 | 伺服器狀態 |
| @tanstack/react-table | 8.11 | 表格元件 |
| Recharts | 3.7 | 圖表 |
| FullCalendar | 6.1 | 行事曆 |
| React Hook Form + Zod | — | 表單驗證 |
| i18next | 25.8 | 國際化 |
| Axios | 1.6 | HTTP 用戶端 |
| date-fns | 3.3 | 日期處理 |
| Lucide React | 0.323 | 圖標 |
| jsPDF + html2canvas | — | 前端 PDF 產生 |
| XLSX | 0.18 | 前端 Excel 處理 |
| signature_pad | 5.x | 手寫簽名擷取 |

### 3.2 後端

| 技術 | 版本 | 用途 |
|------|------|------|
| Rust | 2021 edition | 系統語言 |
| Axum | 0.7 | Web 框架 |
| SQLx | 0.9 | 資料庫驅動（compile-time 驗證；MSRV rustc 1.94）|
| Tokio | 1.x | 非同步 Runtime |
| Serde | 1.x | 序列化/反序列化 |
| jsonwebtoken | 9 | JWT 處理 |
| Argon2 | 0.5 | 密碼雜湊 |
| Lettre | 0.11 | SMTP Email |
| utoipa | 4 | OpenAPI 文件 |
| Tower / Tower-HTTP | 0.4/0.5 | 中間件 (CORS, Trace) |
| tokio-cron-scheduler | 0.11 | 排程任務 |
| maxminddb | 0.24 | GeoIP 查詢 |
| printpdf | 0.7 | 後端 PDF 產生 |
| rust_xlsxwriter | 0.92 | Excel 產生 |
| calamine | 0.24 | Excel/CSV 解析 |
| reqwest | 0.12 | HTTP 用戶端（Google Calendar API）|
| validator | 0.16 | 輸入驗證 |

### 3.3 資料庫

| 技術 | 版本 | 說明 |
|------|------|------|
| PostgreSQL | 16-alpine | 主資料庫（pg_stat_statements preload）|
| GeoLite2-City | — | MaxMind GeoIP 資料庫 |
| 快取 | moka 0.12 | 應用內 in-memory 快取（權限 5min TTL / AUP PDF 30min）；**無 Redis** |

### 3.4 部署

| 技術 | 說明 |
|------|------|
| Docker Compose | 現行 prod 容器：api / web(Nginx 靜態) / db / **outbox-worker** / **print-pdf** / db-backup / 監控(Prometheus·Grafana·Alertmanager) / 日誌(Loki·Promtail·node-exporter)。完整清單見 ARCHITECTURE.md §1 |
| Nginx | 前端 production build 靜態服務 & `/api` 反向代理（Brotli 壓縮）|
| PDF 服務 | print-pdf（FastAPI + **Playwright/Chromium** HTML→PDF；已由 WeasyPrint 汰換）|
| WAF | Cloudflare WAF（流量經 Cloudflare Tunnel，由 Dashboard 管理；服務綁 127.0.0.1）|
| 監控 / 日誌 | Prometheus + Grafana + Alertmanager + Loki + Promtail + node-exporter |
| Cloudflare Tunnel | 具名隧道腳本（scripts/）|
| Vite dev server | **僅 `--profile dev` 手動啟用，不在 prod 拓樸內** |

---

## 4. 分層架構

```
┌─────────────────────────────────────────────────────────────────┐
│                      展示層                                       │
│  React SPA • 頁面 • 元件 • Hooks • Stores                       │
│  62+ pages • 67+ components • lib/api/ 業務域拆分                │
└─────────────────────────────────────────────────────────────────┘
                              │
                         HTTP / JSON
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      中間件層                                     │
│  Rate Limiter • Auth • Activity Logger • Real IP • CORS          │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      處理層 (Handlers)                            │
│  路由定義 (routes/ 11 檔案) • 59 handler 檔案                    │
│  請求解析 • 回應序列化                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      服務層 (Services)                            │
│  94 service 檔案 • 商業邏輯 • 驗證 • 排程 • 存取控制             │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                   資料存取層 (Repositories)                       │
│  6 repository 檔案 • 封裝可複用 SQL 查詢                          │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      模型層 (Models)                              │
│  26 model 檔案 • 結構定義 • 列舉                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                   PostgreSQL 16 資料庫                            │
│  124+ 遷移檔案 • 資料表 • 分割表 • 視圖 • pg_stat_statements     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. 認證與授權

### 5.1 認證流程

```
使用者                  前端                     後端                   資料庫
  │                        │                         │                       │
  │──── 登入 ────────────►│                         │                       │
  │                        │──── POST /auth/login ──►│                       │
  │                        │                         │──── 驗證帳密 ────────►│
  │                        │                         │◄──── 使用者資料 ──────│
  │                        │◄──── JWT + Cookie ──────│                       │
  │◄─── 登入成功 ──────────│                         │                       │
  │                        │                         │                       │
  │──── 操作 ────────────►│                         │                       │
  │                        │──── 請求 (Cookie) ────►│                       │
  │                        │                         │──── 驗證 JWT ────────►│
  │                        │                         │◄──── Claims ──────────│
  │                        │◄──── 回應 ──────────────│                       │
  │◄─── 資料 ──────────────│                         │                       │
```

### 5.2 Token 結構

| Token 類型 | 有效期限 | 儲存位置 | 用途 |
|------------|----------|----------|------|
| Access Token | 可設定（預設 15 分鐘，env `JWT_EXPIRATION_MINUTES`）；useProactiveRefresh 在 80% TTL silent refresh，使用者無感 | HttpOnly Cookie | API 認證 |
| Refresh Token | 30 天（`REFRESH_TOKEN_EXPIRY_DAYS`），每次 refresh rotation | HttpOnly Cookie | Token 更新 |
| Reauth Token | 5 分鐘 | 請求 Header | 敏感操作二級認證 |
| Temp Token (2FA) | 5 分鐘 | 回應 JSON | TOTP 驗證登入 |

### 5.3 安全機制

| 機制 | 說明 |
|------|------|
| **Rate Limiting** | 分級限流：Auth 100/min、寫入 120/min、上傳 30/min、一般 API 600/min |
| **TOTP 2FA** | 可選雙因素認證（setup/confirm/verify/disable），支援備用碼 |
| **CSRF** | 寫入操作需 X-CSRF-Token header |
| **Login Tracker** | 偵測登入異常（多次失敗、帳號鎖定）|
| **Real IP** | 透過 X-Forwarded-For 取得真實 IP |
| **GeoIP** | MaxMind GeoLite2 查詢 IP 地理位置 |
| **Session Manager** | 工作階段追蹤、強制登出、活動心跳 |
| **Activity Logger** | 中間件自動記錄所有操作 |
| **首次密碼變更** | 新使用者必須變更初始密碼 |
| **敏感操作二級認證** | 刪除使用者/角色、重設密碼、模擬登入需重新輸入密碼 |
| **Heartbeat** | 前端定期回報活動狀態 |

---

## 6. 部署架構

### 6.1 Docker Compose 服務

| 服務 | 映像檔 | 連接埠（皆綁 127.0.0.1）| 說明 |
|------|--------|--------|------|
| `db` | postgres:16-alpine | 5433→5432 | PostgreSQL 資料庫（localhost-only）|
| `api` | 自建 Rust (cargo-chef) | 8000 | 後端 API（非 root、read-only rootfs）|
| `outbox-worker` | 自建 (Dockerfile.outbox-worker) | — | Event outbox 事件外送（email/line/webhook，保證投遞）|
| `web` | 自建 Nginx (Brotli) | 8080 | 前端 production build 靜態檔案 |
| `print-pdf` | 自建 (services/print-pdf) | 9210→9200 | HTML→PDF（Playwright/Chromium）|
| `db-backup` | 自建 (scripts/backup) | — | 排程備份（cron + pg_dump + GPG + rclone→R2/NAS）|
| `prometheus` / `grafana` / `alertmanager` | prom·grafana 官方 | 9090 / 3001 / 9093 | 監控堆疊 |
| `loki` / `promtail` / `node-exporter` | grafana·prom 官方 | 3100 / — / — | 集中式日誌 + 主機指標 |
| `web-dev` | node:22-alpine | 5173（`--profile dev` only）| **僅開發用，不在 prod 拓樸** |

### 6.2 Volume 與 Secret

```
volumes:
  postgres_data       # 資料庫持久化
  ./uploads           # 檔案上傳目錄
  ./geoip             # GeoIP 資料庫 (唯讀)

secrets:
  google_service_account  # Google Calendar 服務帳號
```

### 6.3 部署架構圖

> 完整且權威的部署拓樸圖（含 outbox-worker / print-pdf / Loki·Promtail·node-exporter /
> Cloudflare Tunnel / 三層網路隔離 / 127.0.0.1 綁定）見 **[`ARCHITECTURE.md`](./ARCHITECTURE.md) §1**。
> 為避免兩份圖各自漂移，本檔不再維護獨立 ASCII 圖，改以該 mermaid 圖為單一事實來源。

核心資料路徑（簡述）：

```
瀏覽器 ──HTTPS──► Cloudflare Tunnel ──► web(Nginx 靜態, :8080) ──/api/*──► api(Rust/Axum, :8000)
                                                                              │
                              ┌───────────────────────────────────────────────┼─────────────┐
                              ▼                       ▼                         ▼             ▼
                       db(PostgreSQL 16)      print-pdf(Chromium)      Google Calendar     SMTP
                              ▲
              outbox-worker ──┘（事件外送）      db-backup ──► pg_dump + GPG ──► R2 / NAS 離站
```

---

## 7. 關鍵設計決策

| 決策 | 理由 |
|------|------|
| Rust + Axum | 高效能、型別安全、記憶體安全 |
| PostgreSQL 列舉 | 資料庫層級約束，避免非法值 |
| JWT + HttpOnly Cookie | 防止 XSS 攻擊存取 Token |
| SQLx compile-time 查詢 | 編譯期 SQL 驗證 |
| JSONB 欄位 | 彈性子結構（治療紀錄、麻醉、生理數值、AUP 表單）|
| 分割表 (Partition) | user_activity_logs 依日期分割，確保長期效能 |
| 中間件 Rate Limiter | 防止暴力攻擊與 DDoS |
| 前後端 PDF 產生 | printpdf (後端匯出)、jsPDF (前端列印) |

---

## 8. 安全與合規

### 8.1 GLP 合規

- 電子簽章（Electronic Signatures，支援密碼驗證與手寫簽名 2 種方式）
- 紀錄版本控制（Record Versions）
- 不可逆刪除追蹤（軟刪除 + 刪除原因）
- 完整稽核追蹤（Activity Logger 中間件）
- 紀錄鎖定（簽章後自動鎖定）
- 附註/更正（Record Annotations）

### 8.2 安全措施

- HttpOnly / Secure Cookie
- Rate Limiting（auth / API 雙層）
- CORS 控制
- 輸入驗證（前端 Zod + 後端 Validator）
- Argon2 密碼雜湊
- 帳號鎖定（多次登入失敗）
- 敏感操作日誌

---

## 9. 相關文件

- [核心領域模型](./02_CORE_DOMAIN_MODEL.md) - 實體詳情
- [模組與邊界](./03_MODULES_AND_BOUNDARIES.md) - 模組拆分
- [資料庫綱要](./04_DATABASE_SCHEMA.md) - 資料表定義
- [API 規格](./05_API_SPECIFICATION.md) - 完整端點
- [權限與 RBAC](./06_PERMISSIONS_RBAC.md) - 角色權限
- [安全與稽核](./07_SECURITY_AUDIT.md) - 安全架構
- [出勤模組](./08_ATTENDANCE_MODULE.md) - HR 系統
- [擴展性](./09_EXTENSIBILITY.md) - 未來規劃

---

*最後更新：2026-07-07（部署/版本事實對齊 prod）*
