# 並行 session 互不干擾協議（PARALLEL_SESSIONS）

> 何時讀本檔：session 開場要建工作區、要跑本機測試、要部署、要碰別的分支之前。
> 撰寫：2026-07-30（Opus 5），依使用者當日四項裁定。事實依據：2026-07-30 實測同時有 5 個
> session 在同一 repo 上跑（`~/.claude/projects/C--System-Coding-ipig-system/*.jsonl`，5 分鐘內 4 份被寫入）。
>
> **核心原則：session 之間在檔案系統與行程上完全不接觸，唯一的交會點是 git。**
> 兩個 session 的工作要合併時，衝突在 PR 階段由分支擁有者用 git 解，不在硬碟上互相覆寫。

## 1. Session 短碼

每個 session 用自己的 **transcript UUID 前 8 碼**當識別碼（下稱 `<sid>`）。

取得方式：跑任何 `run_in_background` 指令，輸出檔路徑即
`…\Temp\claude\C--System-Coding-ipig-system\<UUID>\tasks\<id>.output`，取 UUID 前 8 碼。
（2026-07-30 實測：該 UUID 與 `~/.claude/projects/…/<UUID>.jsonl` 一致，可靠。）

`<sid>` 用於：工作區名稱、測試 DB 名稱、部署鎖內容。不要自己編號碼——兩個 session 撞號就失去隔離意義。

## 2. 工作區歸屬（1 session = 1 專屬 worktree）

| 規則 | 內容 |
|---|---|
| 命名 | `C:\System Coding\wt-<sid>`（例 `wt-45ba6593`） |
| 建立 | `git worktree add -b <branch> "C:/System Coding/wt-<sid>" origin/main`（從主 checkout 執行） |
| 所有權 | **只有建立它的 session 能讀寫該目錄**。裡面愛切幾支分支都行 |
| 別人的工作區 | 唯讀都不必——**不 checkout、不編輯、不 `worktree remove`、不 `worktree prune` 別人的**。`git worktree list` 只用來確認「哪些名字已被佔用」 |
| 結束 | 分支落地後刪自己的：`git worktree remove "C:/System Coding/wt-<sid>"`；若因 target 目錄殘留而失敗，先移除 `frontend/node_modules` junction（**用 `cmd /c rmdir` 只斷連結**，`rm -r` 會穿過去刪主 repo 的依賴），再 `worktree prune` |

**主 checkout `C:\System Coding\ipig_system` 是唯讀 + 部署專用**：可以 `git pull --ff-only`（部署前同步）、可以跑 docker compose、可以讀檔；
**不得**在其上 commit / checkout 分支 / `reset` / `stash` / `checkout -- .`。要改 code 一律回自己的 `wt-<sid>`。

歷史名稱 `ipig-claude`、`ipig-alert-unlock`、`ipig-alert-source-ip` 是本協議之前建的，沿用到各自分支落地為止，
不要新增這種無 `<sid>` 的工作區。

## 3. 分支歸屬（衝突只在 git 解）

- **只有建立分支的 session 能 commit / rebase / force-push 該分支**。看到別人的分支需要 rebase → 回報，不代做。
- 不得 checkout 別的 session 正在用的分支（git 本身會拒絕；硬繞過就是在破壞隔離）。
- 跨分支整合只走 **PR + git merge/rebase**，由分支擁有者解衝突。不得為了「先幫他解掉」而直接改別人的分支。
- 已知熱點檔（一定會衝突，屬正常）：
  - `docs/PROGRESS.md` §9 頂端 —— 兩邊各插一則 `###` 條目。**解法是保留兩則按時間排序，不是二選一。**
  - `docs/TODO.md`、`frontend/src/locales/{zh-TW,en}.json` —— locale JSON 多數能自動合併。
  - 同一功能區的元件（例：`AuditAlertDetailDialog.tsx`）。
- N ≥ 6 支 PR 同改同區塊 → 改走 `integration/<代號>` 長期分支，一次解一次衝突。
- 事前試算衝突（唯讀，不動任何分支）：`git merge-tree --write-tree --name-only <A> <B>`，exit 1 即有衝突。

## 4. 共用 cargo target（磁碟是硬約束）

全部工作區共用一份 target：`CARGO_TARGET_DIR=C:\System Coding\.cargo-target-shared`

- 每次跑 cargo 都帶上（或設進 shell profile）：
  `CARGO_TARGET_DIR="C:/System Coding/.cargo-target-shared" SQLX_OFFLINE=true rtk cargo check --tests`
- **相依 crate 只編一次**（411 個 crate，全新編約 15 分鐘）；切換分支只重編本 workspace 的 crate。
- 同時 build 會看到 `Blocking waiting for file lock on build directory` —— **這是排隊，不是壞掉，等它**。
  不要為了避開鎖而另開 target 目錄。
- 依據：2026-07-30 實測三個工作區各自的 target 共 **33.4 GB**，C: 僅剩 84 GB（83% 已用）。
  這台同時跑 prod，磁碟耗盡會拖垮正式服務（2026-07 已有清磁碟事故）。
- 遷移舊工作區：改用共用 target 後，舊的 `wt-*/backend/target` 可刪回收空間，
  但**只刪自己工作區的**，且不要在別的 session 正在 build 時做。

## 5. 本機測試資料庫（共用容器，各自 database）

- 容器只有一個：`ipig-db-test`（`127.0.0.1:5432`，tmpfs）。第一個需要的 session 建：
  `rtk docker compose -f docker-compose.test.yml up -d db-test`
- **任何 session 都不得 `docker rm` / `stop` 這個容器**——別的 session 可能正在跑測試。它是 tmpfs，重啟即空，不需要清。
- 每個 session 用自己的 database：`ipig_db_test_<sid>`
  ```bash
  docker exec ipig-db-test psql -U postgres -c "CREATE DATABASE ipig_db_test_<sid>"
  ```
  跑測試時兩個變數都指自己的 DB（harness 未設 `TEST_DATABASE_URL` 會 fallback 到 `DATABASE_URL`）：
  ```bash
  TEST_DATABASE_URL="postgres://postgres:password@127.0.0.1:5432/ipig_db_test_<sid>" \
  DATABASE_URL="postgres://postgres:password@127.0.0.1:5432/ipig_db_test_<sid>" \
  CARGO_TARGET_DIR="C:/System Coding/.cargo-target-shared" SQLX_OFFLINE=true \
  rtk cargo test -j2 --test <名稱>
  ```
- 🚫 **不得對整份 `docker-compose.test.yml` 下 `up`**：裡面的 `api-test` 對外是 **host 8000**，
  與 prod 的 `ipig-api` 同埠，會直接打到正式服務。永遠只 `up -d db-test`。
- 🚫 **不得對任何 compose 檔用 `down` 或 `--remove-orphans`**：test compose 與 prod 共用 project 名，
  prod 的 12 個容器會被列為 orphan（2026-07-29 實測警告），`--remove-orphans` 等於殺 prod。
- 只 `rm` 自己建的容器，且先確認名稱不在 prod 清單內。

## 6. 部署鎖（使用者 2026-07-30 裁定）

任何 session 都可依常設授權部署 prod，但**必須先押鎖**：

1. 取鎖（`set -o noclobber` 走 `O_EXCL`，檔案已存在時整條寫入直接失敗＝原子）：
   ```bash
   set -o noclobber
   if printf 'sid=%s at=%s\n' "<sid>" "$(date -Iseconds)" \
        > "C:/System Coding/.deploy.lock" 2>/dev/null
   then echo LOCK_ACQUIRED
   else echo LOCK_BUSY; rtk head "C:/System Coding/.deploy.lock"
   fi
   ```
   （只能一條 redirect 建檔並寫內容——先 `>` 建空檔再第二次 `>` 寫入，第二次會被 noclobber 擋掉。
   鎖已被佔時 shell 會另外印一行 `cannot overwrite existing file` 到 stderr，`2>/dev/null` 攔不掉
   那是 shell 自己發的，屬預期輸出、不是錯誤。2026-07-30 已實測整段行為。）
2. `LOCK_BUSY` → **停下回報**「部署鎖被 sid=X 佔住（取鎖時間 T）」，不要等、不要硬上。
3. 部署：主 checkout `git pull --ff-only` → `docker compose build <服務>` → `up -d` → 健檢。
4. 完成或失敗都要釋放：`rm -f "C:/System Coding/.deploy.lock"`。
5. **陳舊鎖**：鎖內時間超過 40 分鐘 → 可接手，但必須在回報中寫明「接手了 sid=X 的陳舊鎖」。

鎖檔放在 repo 之外（`C:\System Coding\`），不會被 git 追蹤，也不會出現在任何 worktree 的 status。

## 7. 共用外部額度

- **CodeRabbit review 額度跨 session 共用**。2026-07-29 實測 #1088 拿到 `Review rate limited`。
  額度綁「開 PR 的身分」，所有 session 都以 `delightening` 推送＝算同一份。
- **配額實況（CodeRabbit 官方 2026-08-05 回信 + docs 核對）**：本 repo 走 OSS 方案，
  PR review 上限是**浮動的 1–10 次／開發者／小時**（依專案社群規模與熱門度，rolling window——
  舊的逐筆退出視窗，不是整點歸零）。小型新 repo 落在低端。
  Marketplace 的「Pro Plus 對開源免費」**只指功能集，不含配額**。
  付費方案為保證值：Pro=5／Pro+=10／Enterprise=12。
- **bot 開的 PR 不佔人類額度**：bot 被當成獨立 user 計算（也可單獨配 seat）。
  ⚠️ 因此 `.coderabbit.yaml` 擋 Dependabot **省不到配額**——保留該設定的理由是避免假綠 status，
  不是省額度（2026-08-04 #21 的原始理由已被推翻，詳見該檔註解）。
- **PR 開立密度自我節流（使用者 2026-08-05 裁定）**：同一小時內**最多開 3 支自己的 PR**，
  其餘排隊等前面的 review 老化退出視窗再開。依據：2026-08-04 連開 #16／#17／#18／#20
  當場四支全撞 `Review rate limited`，撞牆的成本（人工逐支判斷是否放行）遠高於等待。
  多 session 並行時這條特別重要——三個 session 各開 2 支就已超標。
- 不得為了趕自己的 PR 反覆 `@coderabbitai review`——那會吃掉別的 session 的 review 額度。同一 PR 最多觸發一次。
- 判斷 bot 閘要看 commit status 的 **description**：`Review completed` 才算審過；
  `Review rate limited` / `skipped` 都**不是**乾淨章（`state` 兩者都是 `success`，只看 state 會誤判）。
  ⚠️ 更嚴格的判準見 CLAUDE.md 授權節 (f)：description 顯示 `Review completed` 但 PR 留言是
  `Review skipped due to path filters` 時＝它一個檔案都沒看，同樣不算乾淨章。
- CI runner 也是共用的：不要為了「試試看」重跑整套 CI。

## 8. 記憶檔併發寫入

`MEMORY.md` 與 `memory/` 目錄被所有 session 共讀共寫。

- 寫之前**重讀一次** `MEMORY.md`（可能已被別的 session 改過），只 append 自己那一行，不重排既有行。
- 記憶檔本身一檔一事實，兩個 session 同時寫不同檔不會撞；撞的只有 `MEMORY.md` 索引。
- 發現索引行重複或矛盾 → 依 `MAINTENANCE.md` §3 合併，不要各留一份。

## 9. Session 開場檢查清單（30 秒）

1. 取得 `<sid>`（§1）。
2. `git worktree list` → 確認 `wt-<sid>` 不存在也沒被別人佔名；建立自己的（§2）。
3. 要跑 cargo → 帶 `CARGO_TARGET_DIR`（§4）。要跑整合測試 → 建自己的 test database（§5）。
4. 要部署 → 先押鎖（§6）。
5. 全程不碰別人的工作區、分支、容器（§2、§3、§5）。

## 10. 強制機制（hook，2026-07-30 起）

> ⚠️ **2026-08-03 實測：本節描述的掛載並不存在。** `~/.claude/settings.json` 全檔沒有 `hooks` 區塊
> （只有 `permissions` / `statusLine` / `enabledPlugins` 等），腳本雖在版控內但從未被呼叫，
> 下表六條**一條都沒在執行**。當日即因此直接 Edit 了主 checkout 的檔案而未被攔下。
> 掛回去要改使用者全域 `settings.json` ＝ `MAINTENANCE.md` §1 的必問項，需使用者授權。
> **在掛上去之前，本節是規格，不是保證**——不要因為「有 hook 擋著」而放鬆自我檢查。

設計上規則不只靠自願遵守。守衛腳本 `.claude/hooks/guard-parallel-sessions.sh`（進版控、可 review）
應掛在 **`~/.claude/settings.json` 的 `PreToolUse`**（matcher `Bash` 與 `Write|Edit`），擋下：

| 擋 | 對應條文 |
|---|---|
| 任何 `--remove-orphans` | §5（prod 容器會被列 orphan 一併移除） |
| 對任何 compose 檔 `down` | §5 |
| `docker-compose.test.yml` 的 `up` 帶非 `db-test` 服務、或不指名服務 | §5（`api-test` 佔 host 8000＝prod api 同埠） |
| prod compose 的 `build` / `up` 而 `.deploy.lock` 不存在或握在別人手上 | §6 |
| `cd` 進主 checkout 後跑 `git commit/checkout/switch/reset/stash/rebase/merge/cherry-pick/apply/restore` | §2 |
| 指令或 Write/Edit 路徑出現別的 session 的 `wt-<其他短碼>` | §2 |
| Write/Edit 路徑落在主 checkout `ipig_system/` 內（反斜線／正斜線都比對） | §2（2026-08-03 補：上一條只比對「別人的 `wt-`」，主 checkout 自己不在任何檢查範圍） |

**刻意放行**（都經 pipe-test 驗證）：主 checkout 的唯讀 git 查詢與 `git pull --ff-only`、
`up -d db-test`、自己持鎖時的部署、在自己 `wt-<sid>` 內的任何 git 操作。

**已知副作用（2026-08-03 掛載當日實測）**：規則 1 與規則 5 比對的是**整條指令的文字**，
不是它實際會執行的動作。所以「只是提到」觸發字串的正當指令也會被擋——例如指令中出現
別的 session 的 `wt-<短碼>`，或字串裡帶了被禁的 compose 旗標。
**連這支腳本自己的 pipe-test 載荷都會被自己擋下**（測試 JSON 裡就含那些字串），
因此要驗證腳本請在自己的 `wt-<sid>` 內跑、或改用不含觸發字串的等價檢查。
被擋下時**不要改寫指令去規避**——那正是這條規則存在的理由。

掛在**使用者全域**而非專案 `.claude/settings.json`，原因有二：後者被 `.gitignore:70` 排除版控
（尊重既有決定，不反轉），且以 worktree 為 cwd 的 session 不會有那份檔案、等於漏掉最需要管的對象。
腳本本身進版控，改規則走 PR。

改動腳本後**必須 pipe-test**（它只吃 stdin JSON，可單獨驗）：
```bash
echo '{"session_id":"<完整UUID>","tool_input":{"command":"rtk docker compose down"}}' \
  | bash .claude/hooks/guard-parallel-sessions.sh
# 有輸出（permissionDecision=deny）= 擋下；無輸出 = 放行
```

⚠️ **這是護欄不是權限系統**：它只看得到指令字串，換個寫法就能繞過。目的是攔住順手打錯，
不是防惡意。**被 hook 擋下時不要改寫指令去繞過**——那條規則本身才是重點。

## 11. 反面案例（2026-07-29/30 真實踩過）

| 現象 | 根因 | 正確做法 |
|---|---|---|
| 已編輯的檔案在腳下被還原成原狀 | 兩個 session 共用 `ipig-claude`，另一個把分支切走 | 各用 `wt-<sid>`（§2） |
| `gh pr merge --delete-branch` 刪不掉本地分支 | 該分支仍被別的 worktree checkout 著 | 先移除自己的 worktree 再 merge（§2） |
| 為了避開別人的 target 而另開工作區，付出全新 411 crate 編譯 | 沒有共用 target 約定 | 共用 `CARGO_TARGET_DIR`（§4） |
| `docker compose -f docker-compose.test.yml up` 把 prod 容器列為 orphan | test 與 prod 共用 project 名 | 只 `up -d db-test`，永不 `down` / `--remove-orphans`（§5） |
| PR 的 bot 閘拿到 `Review rate limited` 卻 `state=success` | CodeRabbit 額度被並行 session 吃掉 | 看 description 不看 state；不重複觸發（§7） |
