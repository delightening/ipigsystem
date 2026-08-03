# Git 整潔政策

## 核心原則

> **凡不屬於「clone 後立刻讓系統運作」的東西，就不應該進 git。**

---

## 什麼該進 repo

| 類型 | 範例 | 規則 |
|------|------|------|
| 原始碼 | `backend/src/**`, `frontend/src/**` | 全進 |
| 設定檔 | `docker-compose*.yml`, `.env.example` | 全進（含範本，不含實際 secret） |
| migration | `backend/migrations/*.sql` | 全進 |
| 測試碼 | `tests/test_*.py`, `backend/tests/**` | 全進 |
| CI 設定 | `.github/workflows/**` | 全進 |
| 文件 | `docs/**`, `README.md` | 全進 |
| Fuzz targets | `backend/fuzz/**` | 全進（正式安全測試） |
| 維運腳本（可重複使用） | `scripts/update_geoip.sh`, `scripts/deploy/**` | 全進 |

---

## 什麼不該進 repo

### 1. Runtime 資料與 artifact

| 類型 | 處理方式 |
|------|---------|
| GeoIP 資料庫（`.mmdb`, `.tar.gz`） | `.gitignore`，由 `scripts/update_geoip.sh` 下載 |
| 使用者上傳檔案（`uploads/`） | `.gitignore` |
| 資料備份、Export JSON（`backups/*.json`） | `.gitignore` |
| 編譯產物（`target/`, `dist/`, `build/`） | `.gitignore` |
| Log 檔（`*.log`, `logs_*/`） | `.gitignore` |

### 2. 一次性工具腳本

**判斷標準**：這個腳本是否可能被第二個人在第二個時機執行？

- **否** → 不進 repo。用 gist 或放在本機 `.gitignore` 的目錄
- **是** → 進 `scripts/`，命名清楚，加簡短說明注解

常見一次性腳本類型（不應 commit）：
- 除錯用的 example 程式（`backend/examples/`）
- 探索函式庫行為的 probe 腳本
- 資料清洗、格式轉換（已完成的歷史資料）
- 圖片轉換、favicon 生成（產出已入版本控制）
- 臨時 DB query 腳本

### 3. 業務資料檔案

| 類型 | 處理方式 |
|------|---------|
| CSV 匯入檔（`*.csv`） | `.gitignore` 已涵蓋（`!**/migrations/*.csv` 例外） |
| docx/pdf 業務文件 | 如需版本控制，放 `docs/`；一次性的不進 repo |
| 測試/填寫樣本 | `backend/resources/` 或 `tests/fixtures/`，不在根目錄 |

### 4. IDE 與 AI 工具輸出

| 類型 | 處理方式 |
|------|---------|
| AI retro 指標快照（`.context/retros/*.json`） | 不進 repo，或在 `.gitignore` 涵蓋 |
| 本機 IDE 設定（`.vscode/settings.json`，個人覆寫） | `.gitignore`（`.vscode/extensions.json` 可進） |

---

## 發現已追蹤的不該追蹤的檔案

```bash
# 步驟 1：從 git index 移除（不刪磁碟上的檔案）
git rm --cached <路徑>

# 步驟 2：在 .gitignore 加入對應規則

# 步驟 3：commit 兩個變更一起入
git commit -m "chore: untrack <說明> + 補 .gitignore 規則"
```

若需要**連歷史一起抹除**（含敏感資料或大型 binary 進了歷史）：

```bash
# 使用 git filter-repo（需另外安裝）
git filter-repo --path <路徑> --invert-paths
# 注意：這會改寫所有 commit hash，需所有協作者重新 clone
```

---

## 一次性腳本的正確歸宿

| 大小 | 建議做法 |
|------|---------|
| 幾十行的探索腳本 | GitHub Gist（不汙染主 repo，有版本控制） |
| 本機開發輔助工具 | 放在本機任意路徑，或 `scripts/dev/`（`.gitignore` 涵蓋 `/scripts/dev/`） |
| 有重複使用價值的工具 | 進 `scripts/`，寫清楚 usage 注解 |

---

## 定期 Housekeeping

每個 sprint（或每月）執行一次：

```bash
# 找根目錄的非標準檔案
ls *.md *.json *.csv *.py *.js *.ts 2>/dev/null

# 找沒有被 CI 或 compose 引用的 scripts/
# （人工確認，無法完全自動化）

# 找大型已追蹤檔案
git ls-files -z | xargs -0 ls -lh 2>/dev/null | sort -k5 -hr | head -20
```

---

## 目錄職責速查

| 目錄 | 只放什麼 |
|------|---------|
| `scripts/` | 可重複執行的維運腳本（部署、備份、更新） |
| `docs/` | 設計文件、架構文件、操作 SOP |
| `backend/examples/` | 不存在（一次性 example 不進 repo） |
| `tests/` | 正式整合測試（`test_*.py`），不含 debug 腳本 |
| `tests/_archive/` | 不存在（舊測試直接刪，git history 保留） |
