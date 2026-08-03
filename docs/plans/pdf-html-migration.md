# PDF 渲染路徑 HTML 化遷移計畫（R45）

> 立案日：2026-05-12
> 預估工期：solo part-time 2.5–4 週（不含 AUP 計畫書 8–14 工作天，含則 12–19 工作天）
> 目標狀態：HTML+Chromium 為**主路徑**；Word/Excel COM daemon 退居 high-fidelity backup；LibreOffice 子路徑全退。

---

## 1. 背景與決策

### 三條現有路徑
| # | 路徑 | 現況 | 目標終態 |
|---|---|---|---|
| 1 | docx/xlsx → **Gotenberg LibreOffice** → PDF | 主要 fallback；fidelity 問題（OOXML escape `_x000a_` 渲染為字面字串、字型 / 排版細節失真） | **退休** |
| 2 | docx/xlsx → **Word/Excel COM daemon** → PDF | 100% Word fidelity，但單執行緒、Windows 鎖定、批次序列化 | **保留**：作為 docx 下載 + IRB 公文 backup |
| 3 | HTML/Jinja → **Gotenberg Chromium** → PDF | 尚未使用 | **新主路徑** |

### 為什麼走 HTML
- 速度：~300–800ms vs LibreOffice 3–8s（5–10×）
- 並行：Chromium 多 tab，無 `threads=1` 鎖
- 版面控制：CSS `@page` / `@bottom-center` / `<br>` 完全標準，無 OOXML escape 怪癖
- 跨平台：未來搬 NAS Linux 不卡 Windows
- 維運成本：HTML/CSS 可 review、可 diff、可 version control（不像 binary docx）

### 為什麼 Word COM daemon 不全退
1. **下載 .docx 功能**：使用者部分情境要拿 .docx 二次編輯（送審、簽核），這條只 docxtpl 能做
2. **AUP 計畫書 IRB 送審**：版面 fidelity 由外部審查單位挑剔，HTML 版若無法 1:1 對齊，風險過高 — 此 case 維持 docx → Word COM 直到驗證等效
3. **複雜 xlsx**（如 vet_patrol 欄位狀態表 floor plan 嵌圖）：HTML 等效實作前的安全網

---

## 2. 端點 × 模板盤點（16 個端點，14 個業務 caller）

### 分級標準
- 🟢 **簡單**：純表格 / 欄位清單，HTML/CSS 半天 / 張
- 🟡 **中**：多區塊、嵌圖、跨頁表格、公文格式
- 🔴 **高**：嚴格外部版面要求 / 複雜佈局，HTML 1:1 不可保證

### 盤點表

| # | 端點 | 模板 | 業務功能 | 級別 | HTML 遷移建議 |
|---|---|---|---|:---:|---|
| 1 | `/render/{doc_type}` | (legacy HTML) | — | n/a | 已是 HTML 但無 caller，**直接刪** |
| 2 | `/render-docx/{type}?format=pdf` | 多 | 泛 docx → PDF | n/a | 包裝層，跟隨業務端點遷移而瘦身 |
| 3 | `/render-docx/{type}?format=docx` | 多 | 直接回 .docx | n/a | **保留**（下載功能） |
| 4 | `/render-xlsx/{type}?format=pdf` | 多 | 泛 xlsx → PDF | n/a | 包裝層 |
| 5 | `/render-xlsx/{type}?format=xlsx` | 多 | 直接回 .xlsx | n/a | **保留** |
| 6 | `/render-aup/from-working-content` | `aup_protocol.docx` | AUP 計畫書 | 🔴 | **保留 docx 路徑**；HTML 版本作 phase 4 可選實驗 |
| 7 | `/render-project-medical/from-project-data` | `medical_record.docx` (per-animal zip) | 全試驗豬病歷 zip | 🟡 | 遷移；HTML 路徑可並行加速 zip 批次 |
| 8 | `/render-medical-record/from-animal-data` | `medical_record.docx` | 單豬病歷表 | 🟡 | 遷移 |
| 9 | `/render-review-reply/from-review-data` | `review_reply.docx` | 審查意見回覆表 | 🟡 | 遷移 |
| 10 | `/render-review-result/from-review-data` | `review_result.docx` | 審核結果 | 🟡 | 遷移 |
| 11 | `/render-surgery/from-surgery-data` | `surgery.docx` | 手術紀錄 | 🟡 | 遷移 |
| 12 | `/render-blood-test/from-blood-test-data` | `blood_test.docx` | 血液檢查 | 🟢 | 遷移 |
| 13 | `/render-audit-log/from-export-data` | `audit_log.docx` | 操作日誌 | 🟢 | 遷移 |
| 14 | `/render-warehouse/from-report-data` | `warehouse.docx` | 倉庫現況 | 🟢 | 遷移 |
| 15 | `/render-vet-patrol/from-animals` | `vet_patrol_template.xlsx` | 欄位狀態表（含 floor plan） | 🟢→🟡 | 遷移；floor plan 需 SVG 化或 pre-render PNG |
| 16 | `/render-vet-patrol-report/from-report-data` | `vet_patrol.docx` | 獸醫巡場報告 | 🟡 | 遷移 |

**遷移範圍**：#7–#16 共 10 個業務端點 + #1 刪除 + #2/#4 包裝層瘦身。

---

## 3. docx 雙輸出策略

每個業務端點繼續支援 **PDF + .docx 雙輸出**：

```
backend 呼叫 pdf-service /render-xxx/from-yyy
  ├─ format=pdf  → Jinja render HTML → Gotenberg Chromium → PDF   ← 新主路徑
  └─ format=docx → docxtpl render → .docx                          ← 保留
```

**adapter 層共用**：`from_xxx_data(...)` 仍是單一函式回傳 dict context。Jinja HTML template 和 docxtpl docx template 都吃同一個 context。維護兩套 template，但資料層只動一次。

**取捨**：
- 優點：使用者下載 .docx 功能不變；PDF 路徑直接加速 5–10×
- 缺點：要維護兩份 template（HTML + docx）— 對 🟢🟡 報表是合理代價，🔴 AUP 不划算
- 長期：若觀察到 .docx 下載量極低，可分批退役 docx template

---

## 4. 技術架構

### pdf-service 新增模組

```
pdf-service/app/
  html_renderer.py          ← 新增：Jinja2 env + base layout + Chromium convert
  templates/
    base.html               ← 新增：CSS @page / 頁眉頁腳 / 字型 / GLP 文件編號預設
    warehouse.html          ← 新增（覆 warehouse.docx）
    audit_log.html
    blood_test.html
    medical_record.html
    surgery.html
    review_reply.html
    review_result.html
    vet_patrol.html
    vet_patrol_report.html
    aup_protocol.html       ← phase 4 可選
  adapters/                 ← 既有不動，from_xxx_data context dict 兩條 template 共用
  main.py                   ← 加 /render-{name}/from-{thing}?format=pdf 路由分發
```

### base.html 共用骨架

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <style>
    @page {
      size: A4;
      margin: 2.5cm 2cm 2cm 2cm;
      @top-left   { content: "{{ doc_number }}"; font: 9pt 標楷體; }
      @top-center { content: "{{ company_name }}"; font: 9pt 標楷體; }
      @top-right  { content: "頁次/總頁數 " counter(page) " of " counter(pages); font: 9pt 標楷體; }
      @bottom-center {
        content: "{{ copyright_zh }}\A {{ copyright_en }}";
        white-space: pre;
        font: 8pt 標楷體 bold;
      }
    }
    body { font-family: "DFKai-SB", "標楷體", "TW-Kai", serif; }
    table { border-collapse: collapse; width: 100%; }
    thead { display: table-header-group; }  /* 跨頁重複表頭 */
    .page-break { page-break-after: always; }
  </style>
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```

### Gotenberg Chromium 呼叫

```python
async def html_to_pdf(html: str, doc_number: str | None = None) -> bytes:
    files = {
        "index.html": ("index.html", html.encode("utf-8"), "text/html"),
    }
    data = {
        "paperWidth": "8.27",  # A4 in inches
        "paperHeight": "11.7",
        "marginTop": "0.4",
        # ...
    }
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(
            f"{config.gotenberg_url}/forms/chromium/convert/html",
            files=files, data=data,
        )
    return resp.content
```

### Gotenberg 已就緒
- `ipig-gotenberg-cjk:8` image 已內含 Noto CJK + 標楷體 kaiu.ttf（R44-9 完成）
- Chromium 字型載入機制與 LibreOffice 共用 fontconfig，**不需額外配置**

---

## 5. 分期計畫

### Phase 0：Foundation（1–2 天）
**目標**：HTML 渲染管線可用，1 張 demo template 走通端到端。

- [ ] `pdf-service/app/html_renderer.py`：Jinja2 env + Chromium convert wrapper
- [ ] `pdf-service/app/templates/base.html`：CSS @page / 字型 / 頁眉頁腳
- [ ] `main.py` 加 `/render-html-demo` 端點測試 Chromium 鏈
- [ ] 驗證標楷體在 Chromium 渲染正確 + GLP 文件編號定位正確
- [ ] X-PDF-Renderer header L2 加 `chromium` 值，前端 L3 不變

**驗證**：post demo HTML → 拿到 PDF，內嵌字型有 DFKai-SB，頁眉頁腳定位準確。

### Phase 1：簡單 🟢（2–3 天）
**目標**：4 張純表格報表 HTML 化、實戰驗證、daemon 路徑保留（safety net）。

| 順序 | 端點 | 工時 |
|---|---|---|
| 1 | warehouse | 半天 |
| 2 | audit_log | 半天 |
| 3 | blood_test | 半天 |
| 4 | vet_patrol_template（含 floor plan SVG）| 1–1.5 天 |

**每張表 sub-tasks**：
1. 抓 adapter 現有 context dict
2. 寫 `templates/<name>.html` 繼承 base
3. `main.py` 端點加 `format=pdf` 分支走 HTML
4. 比對：舊（docx → Word COM）vs 新（HTML → Chromium）視覺 diff
5. UAT：使用者 dogfood 一次

**Phase 1 結束 stop point**：暫停 commit，由使用者確認 HTML 路徑 fidelity 可接受，再進 Phase 2。

### Phase 2：中等 🟡（3–5 天）
| 順序 | 端點 | 工時 |
|---|---|---|
| 5 | medical_record（單豬）| 1 天 |
| 6 | project_medical（zip 多豬）| 0.5 天（重用 #5 template，加 zip 邏輯 + 並行 chromium 呼叫）|
| 7 | surgery | 1 天 |
| 8 | review_reply | 0.5 天 |
| 9 | review_result | 0.5 天 |
| 10 | vet_patrol_report | 1 天 |

**注意**：
- #6 是批次 zip 痛點，HTML 並行可從「N × 6s 序列」變「~N × 0.5s」— 對 30 隻試驗豬 zip 從 3 分鐘變 15 秒
- 嵌圖（手術前後照、巡場照片）用 `<img src="data:image/png;base64,...">` 內嵌

### Phase 3：高難度 🔴 AUP 計畫書（**conditional**，3–5 天）
**前置決策**：先用 1–2 天做 PoC，把 aup_protocol 一節（最複雜的 section）HTML 化，與現行 docx 版本對比。

- 若 PoC 視覺等效且 IRB 審查端可接受 → 進入完整遷移
- 若 PoC 偏離 IRB 慣例（例如表格格式、編號樣式不可控）→ **放棄 HTML 路徑**，aup_protocol 永久走 docx → Word COM

**這條 Skip 是 OK 的** — AUP 是極少數高 fidelity 需求，docx 路徑保留也不會拖累其他端點。

### Phase 4：清理 + 路徑退役（1 天）
- 刪 `/render/{doc_type}` legacy HTML 端點（無 caller）
- pdf-service 內 docx fallback Gotenberg LibreOffice 路徑：HTML 主路徑穩定後改為「只給 .docx 下載編譯（不含 PDF 轉換）」
- 確認 Word/Excel COM daemon 角色：
  - **Excel daemon**：vet_patrol xlsx 若已 HTML 化 → 可全退；否則保留
  - **Word daemon**：保留供 .docx 下載 + AUP（若 phase 3 不遷）
- 更新 `docs/dev/pdf-render-paths.md` 標明 HTML 為主路徑、各 daemon 角色
- 更新 `CLAUDE.md` 列入「新增 PDF 報表 → 預設 HTML 路徑」規範

---

## 6. 風險與緩解

| 風險 | 機率 | 影響 | 緩解 |
|---|---|---|---|
| Chromium 渲染中文行距 / 字距與 Word 微小差異 | 高 | 低 | base.html 統一 line-height / letter-spacing；UAT 視覺驗收 |
| Floor plan（vet_patrol）需重做 | 中 | 中 | 用 SVG 從資料動態生成；現行 Excel 版本已有 cell-mapping，遷移為座標映射不難 |
| AUP IRB 不接受 HTML 版面 | 中 | 高 | Phase 3 預先 PoC，不接受就維持 docx 路徑（不阻擋其他 phase） |
| 嵌圖跨頁切斷 | 低 | 低 | CSS `break-inside: avoid` |
| GLP 文件編號每頁顯示 | 已解決 | — | `@top-left { content: "{{ doc_number }}" }` |
| 字型授權（kaiu.ttf 已在 image） | 低 | 低 | NAS 部署改 TW-Kai（OFL）— 計畫已記於 `services/gotenberg/fonts/README.md` |
| 雙 template 維護成本（HTML + docx）| 中 | 低 | 共用 adapter context；若 .docx 下載量低於門檻則退役 |
| pdf-service test coverage 不足 | 中 | 中 | 每個 HTML template 加 snapshot test：固定 context → 固定 PDF page count + 文字層比對 |

---

## 7. 成功標準

| 指標 | 目標 |
|---|---|
| HTML 路徑覆蓋率 | ≥ 9/10 業務端點（AUP 可選） |
| 單張 PDF 渲染時間（warehouse / blood_test） | ≤ 1s（目前 daemon 3–8s） |
| 30 隻試驗豬 zip 匯出 | ≤ 20s（目前 ~3 分鐘） |
| Gotenberg LibreOffice 子路徑流量 | 0%（完全退役） |
| Word COM daemon 流量 | < 5%（只剩 .docx 下載 + AUP） |
| 視覺 UAT 通過 | 全部遷移端點 vet/QA 簽收 |

---

## 8. 不做的事

- **不**改 `frontend` 前端 — 端點 URL 與 response 維持，前端無感
- **不**動 backend handler — `pdf_service_client.rs` 介面不變
- **不**動 adapters/ context 結構 — 雙 template 共用同 context
- **不**追求 Word 與 HTML 1:1 像素級對齊 — 視覺等效即可，差異記於 UAT 紀錄
- **不**在 Phase 0–2 動 AUP — 它是 Phase 3 獨立決策

---

## 9. 開工檢核 checklist

開始 Phase 0 前確認：
- [x] Gotenberg image 含 CJK + 標楷體（已完成 2026-05-12）
- [x] Word COM daemon 暫退（.env 已註解，可隨時 rollback）
- [x] PDF L2/L3 fallback header 機制完整（X-PDF-Renderer + usePdfFallbackToast hook）
- [ ] 使用者確認 Phase 0 demo 後再啟動 Phase 1
- [ ] 每個 Phase 結束 stop point 由使用者簽收
