# docs/design — 設計與工作底稿索引

本資料夾收錄系統設計文件、規格、以及各項任務的工作底稿。
依**主題**分子資料夾；每個子夾再以「結果 vs 過程產物」區隔。

> 圖例：✅ **結果**（定案交付物，已 git 追蹤，長期保留） · 🟡 **過程產物**（工作底稿 / 中間資料，可清理或封存）

## 子資料夾總覽

| 子資料夾 | 內容 | 類型 |
|---|---|---|
| `architecture/` | 系統架構設計（r30-3 event outbox、r30-9 簽章稽核鏈、r75-p4 結構化授權） | ✅ 結果 |
| `features/` | 功能設計文件（admin 退件軟刪除、申請須知簽收、SOP 訓練簽收） | ✅ 結果 |
| `aup-print/` | AUP 計畫書表單規格 / 列印一致性稽核 / 輸出需求 / 標籤底稿 / 範本預覽 docx | ✅ 結果（`*-worksheet` 為 🟡 底稿） |
| `db-performance/` | DB 效能：ER 圖、重構計畫、baseline、效能稽核（被 PROGRESS/TODO 引用） | ✅ 結果 |
| `dashboard/` | 儀表板佈局設計 + `flows/`（流程圖 SVG 與其產生器 `.mjs`） | ✅ 結果 |
| `animal-timeline/` | 動物時間軸 UI mockup（HTML） | ✅ 結果 |
| `table-previews/` | 各分頁表格 RWD 設計的 HTML 預覽 + `column-ruler.html` 欄寬量尺工具 | 🟡 過程產物 |
| `inventory-audit/` | 庫存「未分配」對帳 CSV（任務已結案） | 🟡 過程產物 |
| `print-previews/` | Chromium 渲染的列印預覽 PDF（可隨時重生） | 🟡 過程產物 |
| `protocol-import/` | 舊計劃書匯入工作底稿（進行中）；`_artifacts/` 為一次性腳本 + 中間 JSON | 🟡 過程產物 |
| `assets/` | 視覺素材：品牌 logo、器官 SVG | ✅ 結果 |

> 根目錄散檔：`euthanasia-sacrifice-flow.html`（犧牲 / 安樂死 / byproduct 流程示意圖，HTML+CSS）。

## 注意事項

- **`db-performance/`** 三份文件被 `docs/PROGRESS.md` / `docs/TODO.md` 以路徑引用，搬移時已同步更新引用。
- **`dashboard/flows/generate-flow-diagrams.mjs`** 由 repo 根目錄執行，輸出路徑已改為 `docs/design/dashboard/flows/`。
- **`protocol-import/_artifacts/`** 內的 `_phase*.py` 是已完成的一次性匯入腳本（硬編絕對路徑），JSON 為其中間產物；匯入任務結案後整夾可封存或刪除。
  - ⚠️ **中間 JSON 一律不進版控**（`.gitignore` 已排除 `_artifacts/*.json`，2026-07-31 使用者裁定）。管線是「原始申請表 docx → `_phase*.py` → JSON → `backend/src/bin/` 的 CLI → DB」，JSON 只是中間那一手：**真相源是 DB、憑證是原始申請表**，執行期沒有任何程式讀它。工作檔放 repo 外（本機慣例 `C:\System Coding\_import-artifacts\`），需要時重跑腳本產生；不要 `git add -f`。
  - 已追蹤的既有 JSON（`protocol-content-enrich.json` 等 14 檔，約 1 MB）是此決定之前留下的，不受 `.gitignore` 影響；要不要清出 git 歷史另案處理。
  - 對應的 CLI（`import_legacy_protocols` / `enrich_imported_protocols` / `backfill_import_reviews` / `patch_milestone_timeline`）**必須顯式帶 `--file`**，不再有 repo 內的預設路徑。
- `__pycache__/`（Python 編譯快取）已於整理時刪除，不再保留。
