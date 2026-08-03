# R45-7：PagedJS / WeasyPrint PoC 計畫

> 立案：2026-05-13
> 預估工期：1-2 天 PoC + 0.5 天 head-to-head 比較
> 目的：解掉 Chromium 不支援 `target-counter()` 的限制，未來 GLP 文件也能走 HTML 路徑。

---

## 1. 問題複習

R45 final 後現況：
- 非 GLP 走 daemon → HTML → Gotenberg 三階 fallback ✅
- GLP 仍走 daemon-only ❌ 沒退路（HTML 在 R45 Phase 3 PoC 時 park 了）
- 主因：Chromium 不支援 CSS `target-counter()` → AUP TOC 自動頁碼做不出來

PagedJS 試過但在 Gotenberg pinning-proxy 環境內**沒成功觸發 layout 重寫**（bundled 上傳 + waitDelay 5s 都沒用）。

R45-7 要驗證的核心問題：**怎樣讓 GLP HTML 版的 TOC 能自動帶頁碼？**

如果這條解掉：
- GLP 也能走 HTML → 不依賴 Office license + 跨平台
- 未來搬 NAS Linux 不卡 Word COM
- daemon 整套可退役（只剩 .docx 下載功能）

---

## 2. 兩條候選路徑

### 候選 A：PagedJS 分兩步驟（雙 pass）

不在 Gotenberg 內跑 PagedJS，改先用 puppeteer/playwright 跑一次 PagedJS layout，輸出已分頁 HTML，再餵 Gotenberg Chromium 印 PDF。

```
[Jinja HTML] → [pdf-service Playwright]
              ↓ PagedJS auto-runs → 解析 + 注入 .pagedjs_pages
            [pre-paginated HTML] → [Gotenberg Chromium] → [PDF]
```

**優點**：
- 保留 Chromium 為最終 PDF 渲染（速度快、字體與其他路徑一致）
- PagedJS 是 web 標準的 paged media polyfill，社群成熟
- 改動範圍：pdf-service 內加 playwright + node-pagedjs，pdf-service Dockerfile 加 ~150MB

**缺點**：
- 兩步驟 → 單張 PDF 渲染時間從 ~500ms → ~2-3s
- pdf-service container 變肥（+150MB 含 Chromium / Node）
- playwright 跟 Gotenberg 都有 Chromium，重複

**工作量**：~1-1.5 天
- 加 playwright + node-pagedjs 進 pdf-service Dockerfile
- 寫 `html_renderer.py::render_html_with_pagedjs(template, ctx)`，先跑 PagedJS pre-render
- 接著餵 Gotenberg `/forms/chromium/convert/html`
- 用 aup_protocol_real_data.json 驗證 TOC 頁碼正確

### 候選 B：換 WeasyPrint engine

WeasyPrint 是純 Python 的 PDF 渲染引擎，**原生支援 `target-counter()` + bookmark-level + footnote** 等 paged-media CSS3 完整規範。

```
[Jinja HTML] → [WeasyPrint] → [PDF]
```

**優點**：
- 一步到位，無需雙 pass
- 原生支援 paged media 完整規範（比 Chromium 強）
- 同一 pdf-service container 內，不需 Gotenberg call
- 渲染速度差不多（500ms-1s）

**缺點**：
- CSS 支援不如 Chromium 全面 — flexbox grid 部分缺、modern CSS 部分不支援
- 之前做的 4 個非 GLP HTML 可能需要調 CSS 才能在 WeasyPrint 正常渲染
- pdf-service Dockerfile 加 weasyprint + cairo/pango 系統 lib (~80MB)
- 字體 fontconfig 路徑要重設

**工作量**：~1.5-2 天
- `pip install weasyprint` + Dockerfile 系統 lib
- 改 `html_renderer.html_to_pdf()` 用 `weasyprint.HTML(string=html).write_pdf()`
- 4 個非 GLP HTML template 各做一輪 CSS 驗證 + 微調
- aup_protocol HTML 補齊 TOC 自動頁碼 + 驗證

---

## 3. PoC 步驟（雙路並行評估）

### Phase 1：基礎可行性（半天）

- [ ] **A-1**：playwright + node-pagedjs 進 pdf-service container，跑一個最小 HTML 帶 TOC（5 個 anchor），驗證輸出 PDF 含正確頁碼
- [ ] **B-1**：weasyprint 進 pdf-service container，同一個最小 HTML，驗證輸出 PDF 含正確頁碼
- [ ] **Gate**：兩者都 work → 進 Phase 2；任一不 work → 該路徑 fail，另一條走完整 PoC

### Phase 2：實戰測試（半天）

用 aup_protocol 真實資料（C:/tmp/proto-real.json）：

| 測試 | 候選 A | 候選 B |
|---|---|---|
| 渲染時間 | __ s | __ s |
| 輸出 PDF 大小 | __ KB | __ KB |
| TOC 頁碼正確 | ✓ / ✗ | ✓ / ✗ |
| 字型嵌入 | __ 個 | __ 個 |
| 中文標楷體渲染 | ✓ / ✗ | ✓ / ✗ |
| 表格邊框 / 勾選格 | ✓ / ✗ | ✓ / ✗ |
| 跨頁表頭重複 | ✓ / ✗ | ✓ / ✗ |
| @page header/footer | ✓ / ✗ | ✓ / ✗ |
| Image base64 嵌入 | ✓ / ✗ | ✓ / ✗ |
| Daemon 視覺等效度 | __ % | __ % |

### Phase 3：非 GLP HTML regression（0.5 天）

用 4 個非 GLP HTML（audit_log / blood_test / medical_record / surgery）跟現有 Chromium 對照：

- [ ] 候選 A：PagedJS 雙 pass 是否影響現有 4 張非 GLP 視覺
- [ ] 候選 B：4 張非 GLP 換 WeasyPrint 後視覺差異 + 是否需 CSS 微調

### Phase 4：決策（0.5 天）

整理比較表，user decide：
- 走 A：保留 Chromium，加 PagedJS pre-render 為 GLP-only 模式
- 走 B：換 WeasyPrint 為主 engine，Gotenberg Chromium 退役
- 都不走：daemon-only for GLP 保持現狀，HTML TOC 頁碼問題 park

---

## 4. 風險與回退

| 風險 | 緩解 |
|---|---|
| 候選 A：playwright 在 Gotenberg pinning-proxy 環境一樣會被擋 | 改成 pdf-service 內 playwright 自己跑（不用 Gotenberg），輸出 PDF 直接回 |
| 候選 B：WeasyPrint CSS 支援不全，4 張既有 HTML 大改 | 先 PoC 1 張，預估改動量 → 不接受就走 A |
| 兩個 PoC 都失敗 | 保持現狀（GLP daemon-only），R45-7 永久 park |
| 字體相容性問題 | 把現有 Times/Arial/Segoe/標楷體 都裝進新 engine container |

**回退**：完全可逆。PoC 結束前不動 prod 路由，純 spike work。

---

## 5. 驗收標準

完成 PoC 後產出：

1. `docs/plans/r45-7-poc-results.md` — 兩條路徑實測比較表 + 推薦 + 風險
2. 1 個跑得起來的 PoC commit（branch `spike/r45-7-pagedjs` 或 `spike/r45-7-weasyprint`）
3. 同 payload 渲染 PDF 給 user 目視（含 TOC 頁碼）

---

## 6. 不做的事

- **不**動目前 prod 路由（GLP daemon-only / 非 GLP 三階 fallback 維持）
- **不**改 4 個 _parked GLP HTML（PoC 過了再考慮搬回）
- **不**追像素級 match daemon（接受 95% 視覺等效，重點在 TOC 頁碼）
- **不**包裝 PoC 進 release — PoC 結束 user 拍板後再做正式 implement

---

## 7. 觸發時機

R45-7 是 park 狀態，**等以下任一條件成立才啟動**：

- 採購 NAS（R36-11）通過 → 確定要搬 prod 上 Linux，daemon 必退役
- vet/QA 提出「GLP 也要走 HTML」需求（例如 IRB 接受 HTML 渲染）
- Office license 出問題 / Word COM daemon 在實戰崩潰太頻繁

否則維持 R45 final 現狀就好。
