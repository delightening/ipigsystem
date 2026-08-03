# AUP 計畫書 PDF Output 修復 — 需求規格（已鎖定）

> Worktree：`C:\System Coding\ipig_pdf_output`　分支：`feat/aup-pdf-output`（off `origin/main` @ 5dcfb223）
> 來源：使用者 8 項回饋 + 釐清問答（2026-06-10）
> 參考 PDF：`豬隻血管內血壓與穿戴式電訊號校正試驗計畫書_2026-06-09.pdf`

## 範圍決策

- **全部一起做**：含 print-pdf 模板（#1/#2/#3/#5/#6/#8）+ 前端編輯表單（#4/#7）。
- **基底分支**：從 `main` 獨立開（原本考慮疊在 `integration/aup-print-parity`，但查證後該 ref 並未改 `aup_protocol.html`，且夾帶 22 個未合入的不相關 infra commit、遠端已刪，故改獨立開）。

---

## A. print-pdf 模板（`services/print-pdf/templates/aup_protocol.html`）

### #1 PI / 聯絡 email 爆版 → 重排「計畫主持人資料」表

長 email 目前擠在 25% 窄格（與電話同列）撐爆。改為下列列結構（email 各自整行 colspan）：

**計畫主持人資料**

| 欄1（label｜值） | 欄2（label｜值） |
|---|---|
| 計畫主持人｜name | **試驗單位**｜sponsor_name |
| 聯絡電話｜phone | 職稱｜title |
| 電子信箱｜email（**整行 colspan**） | |
| 地址｜address（整行） | |
| 聯絡人｜contact_person | 聯絡電話｜contact_phone |
| 電子信箱｜contact_email（**整行 colspan**） | |

- label 由「試驗單位名稱」**簡化為「試驗單位」**並上移到第 1 列（與計畫主持人配對）。
- 地址位置依使用者排法：放在第一個 email 之下、聯絡人之上。

**專案主持人資料**（拆成兩行、各整行）

| |
|---|
| 專案主持人｜sd.name（整行） |
| 電子信箱｜sd.email（整行） |

### #2 研究名稱無英文 → 直接略過，不印 "N/A"

研究名稱（title）若無英文版本，PDF 英文欄位**整段略過**，不顯示 "N/A" 或空白佔位。
（注意：此為研究名稱專屬規則，非全域 `L()` 行為。）

### #3 SD 資料未填 → 顯示「待填」，不顯示 "N/A"

專案主持人（sd.*）欄位空值 fallback 改為 **「待填」**，不沿用共用 `na()` 巨集的 "N/A"。
→ 新增專用 fallback（如 `tbd()` 巨集或 `na(val, '待填')` 參數化）。

### #5 checkbox 放大 → 1.4×（約 15pt）

`.cb`（☑/☐ glyph，目前無顯式 font-size、繼承 ~11pt）→ `font-size: 15pt`（約 1.4×）。
需確認 `.cb-label` 行高不被撐破（必要時 `line-height` 微調 / `vertical-align`）。

### #6 內文孤行 → 分散對齊 + 末行靠左 + 防孤行

內文段落（`.summary-text` / `.free-text` 等）：
- `text-align: justify;`（分散對齊）
- `text-align-last: left;`（末行靠左，避免末行字距被拉開）
- `orphans: 2; widows: 2;`（防段落首/尾單行落在頁界）
- 標題與其下第一段 `page-break-after: avoid`（沿用既有規則，確認涵蓋）

> 註：WeasyPrint 無法自動偵測「末行字數」防 2 字孤字，可控槓桿僅對齊方式；以上為實際可行範圍。

### #8 無手術 → §6 動物手術規劃全部 N/A（含 6.1 / 6.3 / 6.10）

當計畫**無手術**時，§6 所有子節（6.1 手術種類、6.3 無菌技術、6.4 內容、6.6/6.7、…、6.10）一律顯示 "N/A"。
→ 需定位「無手術」判定條件（surgery_type 全空 / has_surgery 旗標），整節包一層條件。

---

## B. 前端編輯表單（`frontend/src/pages/protocols/protocol-edit/`）

### #4 試驗單位名稱輸入欄位 — 已查證存在

`ResearchBasicFields.tsx:238`「委託單位」區塊 `basic.sponsor.name` 即試驗單位名稱輸入欄。
→ 實作時**驗證資料接線**：PDF 模板 `pi.sponsor_name` 確實餵自 `basic.sponsor.name`（避免兩邊沒接上）。無接線問題則本項不需改 code。

### #7 大型文字欄位自動展開 + 每欄個別收合按鈕

- textarea 內容多時**自動長高**（auto-grow，預設行為）。
- 每個大型欄位右上角一個小按鈕，可把**該欄**縮回固定高度（內部捲動）。
- 採**逐欄個別收合**（非全表一鍵）。
- 抽成共用元件（如 `AutoGrowTextarea` / `CollapsibleField`），≥2 處使用。

---

## 驗證標準

- **PDF 模板**：以參考 PDF 的資料 re-render，目視確認 6 項（建議用 `services/print-pdf/_tools` 既有 smoke/preview 流程）。
- **前端**：`tsc` + `eslint` 零警告（不跑 prod build；新 worktree 先 junction node_modules from 主 repo）。
- 中文為 master、英文為 reference；不孤立改 English audit/error 訊息。

## 待辦切分（建議 commit 粒度）

1. #5 checkbox 放大 + #6 對齊/孤行（純 CSS，低風險）
2. #1 PI/SD 表重排（含 email 整行、試驗單位 label）
3. #2 研究名稱英文略過 + #3 SD 待填 fallback
4. #8 §6 無手術 N/A 包條件
5. #4 驗證接線（必要時修）
6. #7 AutoGrowTextarea + 個別收合（前端，獨立 commit）
