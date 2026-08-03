# CSP Enforce Cutover SOP（R31-9 / R31-10）

> **目的**：把 CSP 從「舊 enforce + 新 Report-Only 並存」切換為「新 enforce 單一 header」。
> **風險點**：切換瞬間若有遺漏的 inline `<script>` / `<style>` / eval()，prod 立即白屏。
> **依賴**：R31-7（nonce 注入）+ R31-8（strict-dynamic）+ R31-11（Reporting-Endpoints）已落地（dual-header at `frontend/security-headers.conf`）。

---

## 現況（2026-05-13）

`frontend/security-headers.conf` 有兩個 CSP header 並存：

```nginx
# Line 12：舊 enforce header（目前實際擋）
add_header Content-Security-Policy
  "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' ...";

# Line 24：新 Report-Only header（觀察用，不擋）
add_header Content-Security-Policy-Report-Only
  "default-src 'self'; script-src 'self' 'nonce-$cspNonce' 'strict-dynamic' ...";
```

差異重點：
| Directive | 舊 enforce | 新 Report-Only |
|---|---|---|
| script-src | `'unsafe-inline' 'unsafe-eval'` | `'nonce-$cspNonce' 'strict-dynamic' 'wasm-unsafe-eval'` |
| report-uri | `/api/v1/csp-report` | `/api/v1/csp-report?mode=ro` |

**`?mode=ro` 是 R31-9 的關鍵**：backend 端能從 query 區分「新策略下的 violation」vs「舊策略下的 violation」。

---

## R31-9：Report-Only 觀察期（1-2 週）

### 1. 確認 Report-Only 已上 prod

```bash
curl -I https://ipigsystem.asia/ | grep -i content-security-policy
# 應看到兩條 header：一條 enforce、一條 Report-Only
```

### 2. 監看 violation reports

#### 2.1 從 backend logs

backend `POST /api/v1/csp-report` handler 應記在 user_activity_logs 或 stdout。查：

```bash
docker logs --since 1h ipig-api 2>&1 | grep -i "csp.*violation\|csp.*report" | head -50
```

#### 2.2 從 audit logs

```sql
-- 連 DB
SELECT created_at, event_type, change_summary, ip_address
  FROM user_activity_logs
 WHERE event_type LIKE '%CSP%'
 ORDER BY created_at DESC
 LIMIT 100;
```

#### 2.3 從 Prometheus（如果 metrics 有接）

```promql
sum by (violated_directive, blocked_uri) (
  increase(csp_violations_total{mode="ro"}[1h])
)
```

### 3. 分類 violations

針對每筆 violation 判斷：

| violation 類型 | 例 | 處置 |
|---|---|---|
| 自己的 inline `<script>` 沒帶 nonce | `script-src-elem` blocked `<script>...</script>` | **修 code**：找到該 inline script，加 nonce 或改 external |
| 自己的 inline `<style>` | `style-src-elem` blocked inline `<style>` | 改 external CSS 或加 nonce |
| 自己的 eval() | `script-src` blocked `eval` | 找 code 改寫，或加 `'wasm-unsafe-eval'` 在 directive（不開 `'unsafe-eval'`） |
| 第三方 CDN（Cloudflare insights、Fonts） | `script-src` blocked `https://...` | 加進 allow-list directive |
| 瀏覽器 extension 注入 | blocked-uri 為 `chrome-extension://...` | **忽略**（不可控、不影響功能） |

### 4. 觀察期結束標準

連續 **7 個工作日** 滿足以下條件才可進 R31-10：

- [ ] 0 個「自己 inline script/style/eval」未處理的 violation
- [ ] 0 個第三方 CDN violation（除非 allow-list 已加）
- [ ] 瀏覽器 extension 噪音可忽略（≤ 1% 流量 / 不影響功能）
- [ ] 有跨足夠瀏覽器：Chrome、Safari、Firefox、Edge 至少都有看到 R-O header 觸發過

實際觀察用：

```sql
-- 過去 7 天 violation 分類
SELECT
  json_data->>'csp-report' as csp_report,
  count(*) as cnt
  FROM user_activity_logs
 WHERE event_type = 'CSP_VIOLATION_REPORT_ONLY'
   AND created_at >= NOW() - INTERVAL '7 days'
 GROUP BY 1
 ORDER BY cnt DESC
 LIMIT 50;
```

---

## R31-10：切換到 enforce（cutover）

### 前置檢核

確認 R31-9 觀察期完成（上方 checklist 全綠）。**沒過不要做下去**。

### 切換動作

1. 編輯 `frontend/security-headers.conf`：
   ```nginx
   # 刪掉 Line 12 舊 enforce header
   # 把 Line 24 從 `Content-Security-Policy-Report-Only` 改成 `Content-Security-Policy`
   # report-uri 從 `?mode=ro` 拿掉
   add_header Content-Security-Policy
     "default-src 'self'; script-src 'self' 'nonce-$cspNonce' 'strict-dynamic' ...";
   ```

2. nginx reload：
   ```bash
   docker compose exec web nginx -s reload
   ```

3. **立即測試** — 開 prod 在無痕模式 + 4 個主要瀏覽器（Chrome、Safari、Firefox、Edge），每個都：
   - [ ] 登入頁面正常
   - [ ] 進入 dashboard
   - [ ] 開 DevTools Console — **沒有任何紅色 CSP violation**
   - [ ] 跑核心流程：登入 → 動物列表 → 新增觀察 → 匯出 PDF
   - [ ] 檢查網路 tab — fonts/CSS 都載入正常

### 切換失敗 — Rollback

5 分鐘內若有任何瀏覽器白屏：

```bash
git revert <commit-hash>
docker compose exec web nginx -s reload
```

立即回到 dual-header 狀態。記錄 violation 細節後回 R31-9。

### 切換成功 — 後續

- 標 `TODO.md` R31-9 + R31-10 完成
- 在 `docs/security/security.md` 紀錄切換日期
- 連結到 [`docs/security/csp-baseline-2026-04.md`](../security/csp-baseline-2026-04.md)（如有）
- 一週後評估 R31-12（移除 legacy `report-uri`，Reporting-Endpoints 取代）

---

## 觀察期間若發現第三方 CDN 沒加 allow-list

範例：使用者 click 某個按鈕觸發了之前沒注意到的 CDN：

1. 在 R-O violations 看到 `blocked-uri: https://cdn.example.com/...`
2. 判斷是否該 allow（業務功能 vs 第三方分析）
3. 若 allow：
   ```nginx
   # security-headers.conf Report-Only header
   script-src 'self' 'nonce-$cspNonce' 'strict-dynamic'
     https://static.cloudflareinsights.com
     https://cdn.example.com;   # ← 新增
   ```
4. Reload nginx + 繼續觀察

---

## 故障時的快速 SOP（R31-10 切換後）

| 症狀 | 原因 | 解 |
|---|---|---|
| Console 滿屏 CSP violation | 沒過完整觀察期 | rollback 回 dual-header |
| 部分瀏覽器白屏（Safari/Firefox） | nonce 在某些瀏覽器有差異 | 看具體 violation，調整 directive |
| Cloudflare Insights 不再回報 | 沒加 CDN 到 allow-list | 加進 `script-src` |
| Login 進不去 | 通常是 inline script | 找 LoginPage.tsx 看有沒 inline `<script>` |

---

## 連結

- [`frontend/security-headers.conf`](../../frontend/security-headers.conf) — 雙 header 配置
- [`docs/security/security.md`](../security/security.md) — 整體安全文件
- TODO.md R31-9 / R31-10 / R31-12 / R35-12 — 切換相關工項
