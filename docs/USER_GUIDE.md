# 使用者操作指南

> 本文件提供系統一般使用者的操作步驟說明。功能需求 / 系統設定請見 [`PROGRESS.md`](PROGRESS.md) 與 [`TODO.md`](TODO.md)。

---

## PDF 匯出（R32 新版，2026-05-04 起）

### 哪些頁面支援 PDF 匯出

| 頁面 | 報表 | 對應 docx 範本 |
|---|---|---|
| 計畫詳情頁 | AUP 動物試驗計畫書 | `templates/AUP 動物試驗計畫書範例.docx` |
| 動物詳情頁 → 病歷 Tab | 實驗豬隻病歷總表 | `templates/實驗豬隻病歷總表範例.docx` |
| 動物詳情頁 → 觀察 Tab | 實驗觀察試驗紀錄 | `templates/from ipig/001-實驗觀察試驗紀錄-*.docx` |
| 動物詳情頁 → 手術 Tab | 手術紀錄表 | `templates/from ipig/001-手術紀錄表-*.docx` |
| 操作日誌頁 | Audit log 報表 | （新建，見開發者指南） |

### 操作步驟

每個支援匯出的詳情頁，標題列右側有三顆按鈕：

1. **「預覽 PDF」** — 開啟對話框，內嵌即時產出的 PDF 預覽。產出時間約 3-8 秒（含 LibreOffice 渲染）。看完按右上角 X 或 Esc 關閉。
2. **「下載 docx」** — 直接下載 Word 檔案。可在本機 Word / LibreOffice 編輯後重新匯入或寄出。
3. **「下載 PDF」** — 直接下載 PDF 檔案。檔名格式 `{報表類型}_{資源編號}.pdf`，例如 `medical_record_P-2025-001_007.pdf`。

> **注意**：「下載 PDF」會在後台寫入 `pdf_artifacts` 表（GLP §11.10(c) 永久存證）。每次下載皆有完整稽核紀錄（誰、何時、IP、簽章 ID）。「下載 docx」與「預覽 PDF」**不**寫入存證表（前者是工作中的草稿；後者是即時產生）。

### 簽章與 PDF

若該報表流程要求 21 CFR §11.50 簽章（如正式提交版本），系統會在按「下載 PDF」前彈出簽章對話框（密碼 + 手寫雙因子）。簽章成功後 PDF 與 `electronic_signatures` row 自動關聯（透過 `pdf_artifacts.electronic_signature_id` FK）。

未要求簽章的匯出（如內部 review 用 audit log）則直接下載。

### 紙張與字型

- **紙張**：所有報表 A4。手術紀錄表為**直橫混用**（基本資訊直式 + 術後追蹤疼痛評估 58×15 表橫式）。
- **字型**：使用 OS 內建字型（中文標楷體、英文 Times New Roman），由 LibreOffice headless 渲染。若你的伺服器無中文字型 → PDF 中文會變方框，請聯絡系統管理員配置 Gotenberg image（見 [docs/dev/docx-template-guide.md](dev/docx-template-guide.md)）。

### 常見問題

**Q: 預覽很慢？**
A: 第一次預覽會冷啟 LibreOffice（~8 秒），同 session 後續 2-3 秒。若超過 15 秒未顯示，刷新後重試或聯絡管理員。

**Q: 下載的 PDF 跟 web 看到的版面不一樣？**
A: 這是預期 — Web 用原生 React UI（適合螢幕瀏覽 / 編輯），PDF 走 GLP 標準 docx 範本（A4 / 章節編號 / 簽名欄位）。**內容相同，版型不同**。

**Q: 下載的 docx 編輯後可以重新匯入系統嗎？**
A: **不行**。docx 下載僅供你寄給外部審查者 / 列印 / 留底。系統內資料修改請走原本的 web 表單（修改後重新匯出 PDF 取得新版本）。

**Q: 已經下載過的 PDF 之後找不到，可以重下嗎？**
A: 可以。Admin 在「PDF 存證紀錄」頁可查每份報表的所有歷史版本（按產出時間 DESC 排序），重新下載任一版（HMAC chain 驗證該檔未被竄改）。一般使用者只能取得最新版（重新點「下載 PDF」會產新一份 + 寫新存證 row）。

---
