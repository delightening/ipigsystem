# GLP 受控文件編號清單

> 產出時間：2026-05-12
> 範圍：所有屬於 GLP 受控文件的 PDF / Word / Excel 匯出範本
> 用途：稽核時快速比對「系統匯出的檔案是否正確帶上文件編號」

## 文件編號對照表

| GLP 文件 | Template 檔 | 文件編號 | 嵌入位置 |
|---|---|---|---|
| **AUP 計畫書 PDF** | `templates/aup_protocol.docx` | **AD-04-01-01F** | Word section header 表格 |
| **審查意見回覆表** | `templates/review_reply.docx` | **AD-04-01-04C** | Word section header 表格 |
| **審核結果 PDF** | `templates/review_result.docx` | **AD-04-01-10B** | Word section header 表格 |
| **欄位狀態表** | `templates/vet_patrol_template.xlsx` | **AD-05-01-02C** | Excel `oddHeader`（每頁列印頁首） |
| **獸醫巡場報告** | `templates/vet_patrol.docx` | **AD-02-02-01** | Word section header 表格 |

5 / 5 文件**全部都有文件編號**，且編號嵌在 template 的「每頁頁首」位置（列印 / PDF 渲染時每一頁都會顯示）。

## 系統所有列印文件分類

> 涵蓋 `pdf-service` 所有 `/render-*/from-*` 端點對應的 11 張業務報表。
> 用途：HTML 遷移 / 新 template 設計時知道是否該掛文件編號於頁眉。

### A. GLP 受控（5 張）— 必含文件編號

| Template | 文件編號 | 業務功能 |
|---|---|---|
| `aup_protocol.docx` | AD-04-01-01F | AUP 計畫書 |
| `review_reply.docx` | AD-04-01-04C | 審查意見回覆表 |
| `review_result.docx` | AD-04-01-10B | 審核結果 |
| `vet_patrol_template.xlsx` | AD-05-01-02C | 欄位狀態表 |
| `vet_patrol.docx` | AD-02-02-01 | 獸醫巡場報告 |

### B. 已確認非 GLP（6 張）— 不掛文件編號

| Template | 業務功能 | 備註 |
|---|---|---|
| `warehouse.docx` | 倉庫現況報表 | 純營運報表 |
| `blood_test.docx` | 血液檢查紀錄 | 2026-05-12 user 確認非 GLP；**未來可能升級為 GLP**，見 TODO R45-future-GLP |
| `surgery.docx` | 手術紀錄 | 同上 |
| `medical_record.docx` | 單豬病歷表 | 同上 |
| `medical_record.docx`（zip 批次）| 全試驗豬病歷 | 同上 |
| `audit_log.docx` | 系統操作日誌 | 系統 audit，性質與紙本 SOP 表單不同；未來升級機率低 |

### 決策表（給 HTML template 設計者用）

```
新增 / 遷移 template 時：
  ├─ 屬 GLP 受控文件？
  │    └─ 是 → 頁眉左側必含「文件編號 AD-XX-XX-XXX」，編號 hardcode 不變數化
  │       └─ 否 → 頁眉左側放公司名 / 報表名，不掛編號
  └─ 不確定 → 預設不掛，問 vet/QA 後補
```

### 未來可能升級為 GLP

`blood_test` / `surgery` / `medical_record`（單 + 批次）四份報表性質上接近研究數據紀錄，未來可能納入 GLP 受控文件範圍。若升級時需要的動作：

1. vet/QA 指派文件編號（沿用 `AD-XX-XX-XXX` 格式）
2. 對應 HTML template 加 `@top-left { content: "文件編號 AD-..." }`
3. 把該 template 從本檔 §B 移到 §A
4. 此事項已記於 `docs/TODO.md`（R45-future-GLP）


## 設計原則

### 1. 文件編號 hardcoded 在 template 內（不是 Jinja 變數）

對 GLP 是**正確做法**：文件編號屬「受控文件」的一部分，不能由 runtime 動態改。修改編號必須走 docx / xlsx 改版流程（受版本控制 + 變更紀錄）。

### 2. Schema field vs 實際渲染來源

`pdf-service/app/schemas/vet_patrol.py` 有 `document_no: str = "AD-05-01-02C"` schema 欄位，**但實際渲染用的是 xlsx `oddHeader` 的硬編碼字串**，不是這個 schema field。

兩處目前**一致**。但若未來要改編號，需**同步**更新：
- (a) xlsx template `oddHeader` 字串
- (b) `schemas/vet_patrol.py` 的 default value

否則會出現「schema 宣告的編號 ≠ 實際 PDF 上的編號」的不一致。

### 3. 渲染器 fidelity

文件編號的呈現依賴渲染器：
- **Word COM daemon** / **Excel COM daemon**（healthy 路徑）：100% fidelity，header 內容與手動 Save As PDF 一致。
- **Gotenberg LibreOffice**（fallback 路徑）：docx header table / xlsx oddHeader 都支援，但字型 / 排版可能略有差異。

降級時 `X-PDF-Renderer: gotenberg_fallback` header 會通知前端 toast 提示使用者（見 [`pdf-render-paths.md`](../dev/pdf-render-paths.md)）。

## 稽核 / Spot Check 流程

若需驗證系統匯出的 GLP 文件編號正確：

1. 匯出該文件（PDF 格式）
2. 開啟後檢查每頁頁首左側 / 右側區塊
3. 比對本表中對應的「文件編號」欄
4. 若不符 → 排查順序：
   - (a) 是否拿到舊版 template？檢查 `templates/` 目錄 git history
   - (b) 是否走了 fallback Gotenberg 但 oddHeader 解析錯誤？看 response 的 `X-PDF-Renderer` header
   - (c) 是否 schema default 與 template hardcoded 字串不同步？

## 驗證腳本（一次性檢查）

```python
# scripts/check_glp_doc_numbers.py（建議補上 — 目前尚未存在）
import sys
sys.stdout.reconfigure(encoding='utf-8')
from docx import Document
from openpyxl import load_workbook
import re

EXPECTED = {
    'aup_protocol.docx': 'AD-04-01-01F',
    'review_reply.docx': 'AD-04-01-04C',
    'review_result.docx': 'AD-04-01-10B',
    'vet_patrol.docx': 'AD-02-02-01',
    'vet_patrol_template.xlsx': 'AD-05-01-02C',
}

def scan_docx(path: str) -> set[str]:
    found = set()
    pat = re.compile(r'AD-\d{2}-\d{2}-\d{2,}\w*')
    doc = Document(path)
    for section in doc.sections:
        for hf in [section.header, section.first_page_header]:
            for table in hf.tables:
                for row in table.rows:
                    for cell in row.cells:
                        found.update(pat.findall(cell.text))
    return found

def scan_xlsx(path: str) -> set[str]:
    pat = re.compile(r'AD-\d{2}-\d{2}-\d{2,}\w*')
    wb = load_workbook(path, data_only=False)
    found = set()
    for ws in wb.worksheets:
        found.update(pat.findall(ws.HeaderFooter.oddHeader.text or ''))
    return found

for fname, expected in EXPECTED.items():
    path = f'templates/{fname}'
    found = scan_xlsx(path) if fname.endswith('.xlsx') else scan_docx(path)
    status = '✅' if expected in found else '❌'
    print(f'{status} {fname}: expect={expected}, found={found or "(none)"}')
```

執行於 `templates/` 目錄上層即可（一次性 GLP audit）。

## 變更紀錄

| 日期 | 事件 |
|---|---|
| 2026-05-12 | 初次盤點，5 份 GLP 文件全部有編號 ✅ |
