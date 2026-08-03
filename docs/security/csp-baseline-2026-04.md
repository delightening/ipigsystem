# CSP 收緊基準掃描（R31-1）

**建立日期**：2026-04-29
**任務**：R31-1（CSP report 基準掃描）
**目的**：為 R31-4 ~ R31-10 收緊步驟提供決策依據

---

## 1. 當前 enforce CSP（`frontend/security-headers.conf:12`）

```text
default-src 'self';
script-src 'self' 'unsafe-inline' 'unsafe-eval' https://static.cloudflareinsights.com;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
font-src 'self' https://fonts.gstatic.com data:;
img-src 'self' data: blob:;
connect-src 'self' https://cloudflareinsights.com;
frame-ancestors 'none';
report-uri /api/v1/csp-report
```

> **R31-14（本 PR 已處理）**：移除 `https://www.google-analytics.com` / `https://analytics.google.com`
> 從 `connect-src`。grep 確認前端 codebase 無 `gtag(` / `googletagmanager` / `G-XXXXXXXX` ID，
> 屬未使用的預留白名單。少一個白名單 = 少一個潛在資料外洩管道。

**已知破口**：
- `script-src 'unsafe-inline' 'unsafe-eval'` — XSS script 注入幾乎無防線
- `style-src 'unsafe-inline'` — inline style 注入無防線

---

## 2. 靜態分析結果（不需等 Report-Only 收集）

### 2.1 `frontend/index.html` inline 內容

| 位置 | 類型 | 說明 |
|---|---|---|
| line 32 | `<style>` | `#static-landing{display:none}` — 1 行 |
| line 33 | `<style>` | `#static-landing{display:block}`（noscript 包裹）— 1 行 |
| line 36-51 | `<script type="application/ld+json">` | Schema.org Organization |
| line 54-62 | `<script type="application/ld+json">` | Schema.org WebSite |
| line 65-89 | `<script type="application/ld+json">` | Schema.org SoftwareApplication |
| line 92-123 | `<script type="application/ld+json">` | Schema.org FAQPage |
| line 240 | `<script src=...>` | external module（無問題） |

> **JSON-LD 仍受 `script-src` 管制**（即使 type 不是 JS），瀏覽器一律視為 script。
> 4 個 block 內容固定 → R31-7 nonce 化或 hash 化都可。

### 2.2 React inline style 用量

```bash
grep "style={{" frontend/src/  → 238 處 / 32 檔案
grep ".style.|setProperty"     → 8 處 / 6 檔案
```

**結論**：量級遠超 R31-3 設定的 50-處門檻 → **`style-src 'unsafe-inline'` 標記為 R31-13 已接受風險**，不主動收緊。

熱區檔案（≥10 處）：
- `PainAssessmentTab.tsx` (25)
- `SurgeriesTab.tsx`、`ObservationsTab.tsx` (各 17)
- `InvitationsPage.tsx` (15)
- `WeightsTab.tsx`、`VaccinationsTab.tsx`、`SurgeriesTab.tsx`、`AmendmentsTab.tsx`、`PersonnelSection.tsx`、`BloodTestTab.tsx` (各 13)
- `ReviewersTab.tsx`、`AttachmentsTab.tsx` (各 11)

### 2.3 動態 eval / Function 構造

```bash
grep "eval(\|new Function(" frontend/src/  → 0 處
```

**結論**：prod build 不需要 `'unsafe-eval'`。Vite **dev server** HMR 內部使用 eval-like 行為，但 `frontend/security-headers.conf` 僅在 prod nginx 容器內生效（`frontend/Dockerfile:51` 注入）；本地 `vite dev` 不經 nginx，不受此 CSP 影響。

### 2.4 R31-2b — `dangerouslySetInnerHTML` 用量盤點

```bash
rg "dangerouslySetInnerHTML" frontend/src  → 2 處 / 2 檔案
```

| # | 檔案 | 位置 | 注入內容 | sanitize 機制 |
|---|---|---|---|---|
| 1 | `components/ui/handwritten-signature-pad.tsx` | line 165 | 簽名筆預覽 SVG | `lib/sanitize.ts::sanitizeSvg()` |
| 2 | `components/animal/SacrificeFormDialog.tsx` | line 127 | 安樂死簽名顯示 SVG | 同上 |

**`sanitizeSvg()` 防護機制**（DOMPurify 嚴格白名單）：

- **允許**：`svg / path / line / circle / rect / polyline / polygon / ellipse / g / defs / clipPath / use` 與對應的 geometry 屬性
- **禁止**：`script / iframe / object / embed / form / text / tspan / foreignObject / a / image / animate / set`
- **禁止屬性**：所有 `on*` event handlers（`onerror / onload / onclick / ...`）+ `xlink:href / href`

**對 R31-7 (CSP enforce) 的影響：零**

- 注入內容是 sanitize 過的 SVG geometry，**不含 `<script>`、不含 inline event handler、不含 inline style**
- 不會觸發 `script-src` / `style-src` / `script-src-elem` 違規
- enforce 後不會白屏，**無需 nonce 補救**

**結論**：✅ R31-2b 通過。`dangerouslySetInnerHTML` 用量乾淨且已防護，不需任何額外動作就能進 R31-7 nonce enforce 階段。

---

## 3. R31-1 Report-Only 部署（本 PR 內容）

新增 `Content-Security-Policy-Report-Only` header 與當前 enforce header 並存：

```text
script-src 'self' https://static.cloudflareinsights.com;     # 移除 'unsafe-inline' + 'unsafe-eval'
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;  # 維持 'unsafe-inline'（接受風險）
其餘同 enforce
report-uri /api/v1/csp-report?mode=ro
```

後端 `csp_report_handler` 加 `Query<CspReportQuery>` 解析 `?mode=ro`，違規寫入 `security_alerts` 時以 `alert_type = CSP_VIOLATION_REPORT_ONLY` 區分。

### 觀察期：1 週

#### 預期 Report-Only 違規來源

| 來源 | violated_directive | blocked_uri | 對策 |
|---|---|---|---|
| index.html JSON-LD ×4 | `script-src` | `inline` | R31-7 加 nonce |
| index.html `<style>` ×2 | `style-src` | `inline` | 已 accept；hash 化可選 |
| Cloudflare Insights | （應已白名單） | — | 確認 `connect-src` 未漏 |

#### 監控 SQL

```sql
SELECT
  context_data->>'violated_directive' AS directive,
  context_data->>'blocked_uri'        AS blocked,
  COUNT(*)                            AS hits
FROM security_alerts
WHERE alert_type = 'CSP_VIOLATION_REPORT_ONLY'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY 1, 2
ORDER BY hits DESC;
```

---

## 4. 後續決策樹（一週後）

```text
觀察 7 天 csp_report 結果
├── 只看到 index.html inline 違規 → 可進 R31-7（nonce 化）
├── 出現未預期第三方 connect-src 違規 → 補白名單；推遲 R31-10 enforce 切換
└── 出現大量 inline script 違規 → 有 React 注入 inline 風險，需先排查再收緊
```

### 4.1 已敲定決策（2026-04-29）

| 決策 | 結論 | 對應任務 |
|---|---|---|
| `style-src 'unsafe-inline'` | ✅ **永久 accept**（238 處 React inline style，CSS-in-JS 遷移工程量過大） | R31-13 標記為已接受風險 |
| 執行順序 | 先 B 段（R31-4~6 移除 prod `'unsafe-eval'`）後 C 段（R31-7~10 script nonce） | — |
| index.html 4 個 JSON-LD 處理 | ✅ **保留 + nonce 化**（公開 landing page 刻意設計 SEO + AI scraper 友善：robots index/follow + canonical + WebMCP + Schema.org + llms.txt） | R31-7 |
| 觀察期長度 | 7 天 | R31-9 |

---

## 5. 24h 觀察結果（2026-04-30 update — R31-15）

> 距 R31-1 部署 ~24 小時，已收集 74 筆 RO 違規 + 108 筆 enforce 違規。提早歸納以修訂 B/C 段策略。

### 5.1 Enforce 違規（108）— 全部第三方注入，CSP 正確擋下

| 來源 | Directive | Hits | 備註 |
|---|---|---|---|
| `googletagmanager.com/gtag/js?id=G-4DRSC0MFNJ` | script-src-elem | 71 | referrer 多含 `dr=https://l.facebook.com/` |
| `region1.google-analytics.com/g/collect` | connect-src | 32 | 同上，GA collect endpoint |
| `connect.facebook.net/en_US/pcm.js` | script-src-elem | 5 | FB Pixel ConnectM |

- frontend codebase grep 確認無 `gtag(` / `googletagmanager` / `G-4DRSC0MFNJ`
- `G-4DRSC0MFNJ` 經使用者確認**非我方 GA4 measurement ID**（無 GA4 帳號）
- 來源研判：使用者從 FB 點連結進站，FB in-app browser / 部分 Brave / extensions 自動注入第三方追蹤 → CSP 擋下，**正確行為，不需處理**

### 5.2 Report-Only 違規（74）— 打臉 R31-4 假設

| Directive | Blocked | Hits | 主要熱點頁 |
|---|---|---|---|
| `script-src` | `wasm-eval` | 33 | `/` 18、`/documents/.../edit` 15 |
| `script-src` | `eval` | 29 | `/` 15、`/documents/.../edit` 10 |
| `script-src-elem` | `inline` | 12 | `/documents/.../edit` 6、`/` 4+2 |

#### 🔴 關鍵發現：R31-4「移除 prod `'unsafe-eval'`」**不可行**

R31-1 baseline 根據 `grep "eval(\|new Function(" frontend/src/  → 0 處` 推論 prod 不需 `'unsafe-eval'`。**24h 內 62 個 eval 違規（33 wasm-eval + 29 eval）打臉此假設**。

- frontend src 確實 0 處直接呼叫 → 違規來自 **transitive deps + 已允許第三方 script 的內部 eval**
- 集中 `/`(landing 33 hits) + `/documents/.../edit`(25 hits)：兩頁差異不大 → 是 **shared bundle / Cloudflare Insights beacon** 內部用 wasm/eval（任何頁都會中）
- frontend deps 候選：`html2canvas` / `jspdf` / `recharts` / `@fullcalendar` / Cloudflare Insights 自動注入 beacon

#### `/documents/.../edit` 6 處 inline script 違規

- 該頁原 import 全部 React + Radix + TanStack Query，無 `dangerouslySetInnerHTML`
- 推測同樣是 Cloudflare Insights beacon 動態插入的 inline `<script>`
- 待 R31-7 nonce 化後（CF beacon 走 sub_filter 注 nonce）即解

### 5.3 R31-15 採取行動

| 動作 | 變更 | 影響 |
|---|---|---|
| RO header 加 `'wasm-unsafe-eval'` | CSP3 窄化指令，允許 wasm 不允許 JS eval | 33 wasm-eval 違規降至 0，剩 29 eval 仍可見 |
| **R31-4~6 廢案** | 移除 prod `'unsafe-eval'` 不再追求 | 改用 R31-13b 接受風險，文件化 |
| **新增 R31-13b** | `'unsafe-eval'` 接受風險 | 待 R31-7 nonce + Reporting API 收 `script-sample` 後可重新評估 |

---

## 6. 風險與回滾

- **本 PR 風險**：Report-Only 不擋資源，**無使用者可見影響**；最壞情況是 violation 量爆掉 `security_alerts` 表 → 觀察 24h 若超量可立即移除 Report-Only header。
- **回滾**：revert 本 commit 即可，不涉及 schema 或不可逆變更。
- **R31-15 後續風險**：`'wasm-unsafe-eval'` 比 `'unsafe-eval'` 窄但仍允許 WebAssembly 執行；XSS 攻擊者若能透過已允許 script 載入惡意 wasm 仍可執行任意計算（但無法直接執行任意 JS）。為可接受縮小（vs 完全 `'unsafe-eval'`）。
