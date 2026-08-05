# ipig_system — Claude 工作規範（2026-07-04 重構版）

> 本檔是唯一入口與最高文件權威。長規則抽到 `docs/agents/`，按下方路由表按需讀取。
> 舊版全文備份：`docs/agents/backup/CLAUDE.md.2026-07-04.bak`。維護本檔前先讀 `docs/agents/MAINTENANCE.md`。

# 語言與交付

- 一律用**繁體中文（zh-TW）**回覆；程式碼識別字 / 檔名 / commit message 維持原文。
- 產出 / 交付任何檔案：回覆中附**完整 Windows 路徑**（`C:\System Coding\ipig_system\...`），同時用 SendUserFile 傳檔。
- 每次工作完成時，回覆最後顯示「工作完成」。
- 回報 CI / 日誌時間一律轉 GMT+8。

# 環境事實（每個 session 都適用，不要重新踩坑）

- **這是 prod**：系統跑在這台筆電的 Docker 上，一人開發+維運。observability 不可停，動 infra 前想清楚。
- **Bash 有 deny 清單**（來源 `~/.claude/settings.json`）：`ls / cat / grep / head / tail / find / sed / awk / rg`
  以及 `sudo` / `rm -rf` / `echo >檔` / `cargo publish` 走 Bash 會被拒。
  替代：讀檔用 Read、搜尋用 Grep 工具、列檔用 Glob、其餘用 `rtk ls` / `rtk grep` / `rtk head` / `rtk tail`
  （`rtk grep` 可能警告 rg 不在 PATH，是 fallback 警告，結果仍可用）。
  這是 prod 機器上刻意設的護欄：被拒不要重試同一條、也不要提議放寬，直接換原生工具。
- **大範圍掃描會 timeout**：`du` / 遞迴 Glob 掃整個 repo 或整顆磁碟常逾時，逾時的部分結果會低估總量。
  做法：一次限一個目錄逐層下鑽，回報時標明「已掃範圍」，不拿逾時的數字當結論（2026-07 清磁碟事故）。
- **RTK 前綴**：所有 cargo / git / gh / docker / npm / pnpm / npx / tsc / vitest 指令一律加 `rtk` 前綴
  （token 過濾器，無 filter 時自動 passthrough，永遠安全）。`&&` 鏈中每段都要加。
- `rtk vitest` 顯示 PASS 但 exit code 非 0 = 真的紅，必修。
- 前端驗證用 `rtk tsc` + `npx eslint`，**不要跑 `npm run build`**（干擾 Docker prod）。
- **禁止在 prod 跑 backend 整合測試**：`rtk cargo test` 的 harness 沒設 `TEST_DATABASE_URL` 會 fallback 到 `DATABASE_URL`（＝prod DB），測試會寫真資料污染正式表與稽核鏈。要跑先設 `TEST_DATABASE_URL` 指向獨立丟棄 DB（`TEST_DATABASE_URL=<獨立丟棄 DB> rtk cargo test`）；正確性驗證靠 CI，不在本機打 prod。
- `docker compose restart` 不會 reload .env；要 `up -d`（會連帶重建依賴 container）。
- merge 後**不會**自動部署：部署 = 手動 `docker compose build` + `up -d` + 健檢。
- **多個 session 同時在跑**（2026-07-30 實測 5 個）：每個 session 用**自己的** worktree
  `C:\System Coding\wt-<session短碼>`，所有 branch / commit / rebase 在那邊做；不碰別人的工作區、
  分支、容器。主 checkout `ipig_system` 只讀 + 部署專用，不改其 git 狀態。
  cargo 一律帶共用 `CARGO_TARGET_DIR`、部署前先押鎖——**完整規則見 `docs/agents/PARALLEL_SESSIONS.md`，
  動手前必讀**（2026-07-29 曾因兩個 session 共用工作區，已編輯的檔案被切分支還原）。

# 任務路由表（動手前先讀對應檔案）

| 任務涉及 | 必讀 |
|---|---|
| `backend/` 任何 .rs / migration | `docs/agents/RULES_BACKEND.md` |
| `frontend/` 任何 .ts/.tsx | `docs/agents/RULES_FRONTEND.md` |
| UI 視覺（色彩/字體/間距/版面） | `DESIGN.md`（= 本專案品牌指南）；先產 HTML 預覽讓使用者選，再改 code |
| React 表格元件（新增或改） | 強制先跑 `/system_table_chats` skill |
| 更新 TODO.md / PROGRESS.md / DESIGN.md | `docs/agents/DOCS_PROTOCOL.md` |
| 多步驟任務 / 大範圍讀取掃描 / 需要 subagent | `docs/agents/DISPATCH.md`（含派工模板 `TEMPLATES.md`） |
| 建工作區 / 跑本機整合測試 / 部署 / 要碰別的分支 | `docs/agents/PARALLEL_SESSIONS.md`（多 session 並行協議） |
| 修改本檔或 docs/agents/ 下任何制度檔 | `docs/agents/MAINTENANCE.md` |
| 除錯 | `/systematic-debugging`；明顯 typo 直接修 |
| .docx/.xlsx/.pptx/PDF | 對應 skill（`/docx` `/xlsx` `/pptx`；PDF ≤10頁 `/pdf`，複雜 `/pdf-reading`）；一般文字檔直接 Read |

# 精簡的底線（絕不為省事砍）

信任邊界輸入驗證、防資料遺失錯誤處理、安全 / 稽核 / 合規路徑（HMAC chain、權限、CSP、SoD）、
a11y、使用者明確要求的功能。

# 授權現況（single source of truth；與記憶衝突時以本節為準）

## 常設授權（不必問）
- 所有檔案讀寫、glob 搜尋、dev DB migration（app 啟動自動跑）。
- commit（隨時可做，不需條件）。
- push 自己的 feature branch + 開 PR：**僅當**使用者說「finish them」、任務明含 ship/部署、或使用者本次明確要求時；否則 commit 完停下回報。
- force-push 僅限自己的 feature branch，必用 `--force-with-lease`；**永不對 main / master**。
- **Auto-merge + 部署**（2026-06-01 常設授權）：PR 滿足「CI 全綠 + bot 0 建議」→ squash merge +
  delete-branch → 自動部署 prod（rebuild 映像 → `up -d` → 健檢）。
  （「CI 全綠」**不含 coverage job**——📊 分片 + aggregate，2026-07-22 裁定：coverage 照跑
  不擋 merge，merge 後轉紅要主動回報並補救。）例外：
  (a) 本機在別分支且有未提交 WIP → 部署那步停下問，別 build 半成品。
  (b) infra / 依賴更新 → rebuild 全部映像（api+web+outbox-worker），不是只 api/web。
  (c) merge 帶 `--delete-branch` 前，先確認沒有 base 指向此分支的 stacked PR（會被自動 CLOSE）。
  (d) 純文件 PR：可不等 CI，但「bot 0 建議」仍要，且 merge 前須 fresh-context read-back 通過
      （TEMPLATES.md §6），不得以自己的宣稱當「內容正確」。
  (e) **部署前必須押 `C:\System Coding\.deploy.lock`**（2026-07-30 裁定，多 session 並行）：
      取不到鎖就停下回報，不等不硬上；完成或失敗都要釋放。程序見 `PARALLEL_SESSIONS.md` §6。
      「bot 0 建議」的判準同時收緊：CodeRabbit commit status 的 description 必須是
      `Review completed`——`Review rate limited` / `skipped` 都不算（兩者 `state` 皆為 `success`）。
  (f) **純依賴更新 PR 免 bot 閘**（2026-08-03 裁定）：diff 只含 lockfile／版本號、**零 code
      變更**的 PR（Dependabot 開的，或手動更新 lockfile），閘改為「CI 全綠 +
      **該 stack 對應的依賴漏洞掃描 job 綠**」，**不要求 bot review**。理由：CodeRabbit
      預設用 `!**/*.lock` 這類路徑過濾排除這些檔案，結構上無從置喙，等它等不到。
      對應表（2026-08-04 補全）：Rust=`🔒 Security: cargo audit`／
      Node=`🔒 Security: pnpm audit`（實作為 osv-scanner 掃 `pnpm-lock.yaml`）／
      Python=`🔒 Security: Python 依賴掃描`（osv-scanner 掃
      `services/print-pdf/requirements.txt`）。
      ⚠️ **某 stack 若尚無對應掃描 job，(f) 對它不成立**，須退回一般閘。本條初立時
      只寫了 cargo/pnpm，而 CI 當時根本沒有 Python 掃描，等於對 `requirements.txt`
      的更新完全無把關——2026-08-03 的 #11 pillow／#13 pypdf 正是這樣合進去的
      （結果正確，但靠人工進容器驗版本，非規則保證）。新增語言/套件管理器時，
      先確認掃描 job 存在再套用本例外。
      ⚠️ **同時補上 (e) 判準的漏洞**：CodeRabbit commit status 顯示 `Review completed`
      **但 PR 留言是 `Review skipped due to path filters`** 時＝**它一個檔案都沒看**，
      等同未審，不得當乾淨章（2026-08-03 PR #14 實例：status=success / desc=Review
      completed，實際因 `backend/Cargo.lock` 被路徑過濾而完全跳過）。判斷 bot 是否真的
      審過，要看 PR 留言內容，不能只看 status description。
- merge 落地 main 的本地分支直接刪（判斷靠 distinctive 檔已在 origin/main，非 ahead/behind）。
- 批次任務完成一項自動做下一項，不問「要繼續嗎？」。

## 必問（不可逆 / 高風險紅線）
- main 的 force-push、`git reset --hard` 到共享分支。
- **對主 checkout（`C:\System Coding\ipig_system`）跑 `rtk git reset` / `rtk git stash` /
  `rtk git checkout -- .` 或任何改寫歷史的指令**：先 `rtk git status` 確認沒有使用者未提交的變更 → 停下問。
  要撤銷優先用 `rtk git revert` 或補一個新 commit，不用 reset。
  commit 前確認 `rtk git log -1` 是自己預期的那個 commit（2026-07 曾 reset+stash 蓋掉使用者進行中的 commit，靠 reflog 救回）。
- migration 跑 staging / prod DB（選號程序不必問，照 `RULES_BACKEND.md` §9 做）。
- 新增 / 移除依賴（Cargo.toml / package.json）。
- 修改 `.env`、`secrets/`、CI 設定（`.github/workflows/*`）。
- 刪除重要檔案、呼叫外部付費 API。
- schema migration 設計、API contract 改動、合規路徑、安全決策、跨模組架構選擇 → 停下 surface tradeoff。
- 使用者指定了做法 X 但你確信 Y 更好 → 停下講「你指定 X，我認為 Y 更好，因為 Z」，不 silent 照做也不 silent 改。

## 衝突裁決順序
1. 使用者本次對話的明確指示。
2. 有較新日期、明確記錄使用者決定的來源（本檔 vs 記憶 vs docs，比日期）。
   **例外：§授權現況只有使用者本次指示能蓋**——記憶再新也不得擴大或縮小授權；
   發現授權相關的新記憶與本節不同 → 問使用者，由使用者改本節。
3. 無法判定 → 用 AskUserQuestion 問（使用者打「auq」也 = 要你問澄清問題）。
發現任何規則互相矛盾 → 當下先按裁決結果做，事後依 `MAINTENANCE.md` 把輸的那條修掉或標註。

# 測試與品質門檻

- 後端驗證標準與 clippy 門檻：`docs/agents/RULES_BACKEND.md` §7–8。
- CI「Backend: cargo test」job 若 <2min 早夭於 setup-rust = infra flake，re-run 即可（main 也常中）。
- CI 狀態 `UNSTABLE` = **已失敗待調查**，不是「還在跑」；看到就去查 log，不可當 pending 繼續等。
- 抓不到 CI log（`BlobNotFound`）不要重抓第二次：改在本機用同樣旗標重現那個 job
  （例：tarpaulin coverage），本機輸出比抓不到的 log 有用。
- **等 CI / bot review 最多輪詢 10 分鐘**（2026-07-28 裁定）。超過就停下回報「卡在什麼、下一步建議」，
  不無限等（CodeRabbit rate-limit、coverage pending 曾各拖住整個 session）。

# 文件記錄（完成任務後）

完成 TODO 項目：TODO.md 標 `[x]` → PROGRESS.md §9 加條目 → 涉及設計決策才動 DESIGN.md。
格式細節：`docs/agents/DOCS_PROTOCOL.md`。
