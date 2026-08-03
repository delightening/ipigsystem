# Harness 快速診斷（A）

> 撰寫：2026-07-04，Claude Fable 5（一次性高階 session）。
> 用途：本檔是後續所有制度檔（CLAUDE.md 重寫、DISPATCH、JUDGMENT、TEMPLATES、MAINTENANCE、LETTER）的依據。
> 讀者：未來在此環境工作的較小模型（Sonnet / Opus / Haiku）與維護者。

## 診斷方法

實際盤點了：專案 CLAUDE.md（~560 行）、AGENTS.md、`~/.claude/CLAUDE.md`（RTK 規則）、
`MEMORY.md` 索引、三個 settings 檔（全域 / 專案 / local）、`.claude/hooks/block-dangerous.sh`、
可用 subagent 型別與 skill 清單。以下為代價最高的前三名問題。

---

## 問題 1：每 session 固定 context 稅過重，且同一內容雙份維護

**證據**
- 專案 CLAUDE.md ~560 行全文載入每個 session；其中「執行紀律」「代碼規範 §1–10」等長段落在多數 session 根本用不到。
- `AGENTS.md`（給 Codex 讀）是 CLAUDE.md 的 ~98% 鏡像，且已漂移：AGENTS.md 引用
  `C:/Users/admin/.Codex/plans/...`、寫「Codex 自主 loop」；CLAUDE.md 對應處寫 `.claude/plans`、「Claude 自主 loop」。
  兩份都要人工同步，漂移只會越來越大。
- `MEMORY.md` 索引 60+ 行，多行超過 150 字元，等於把記憶內文塞進索引，每 session 全文載入。
- gstack plugin 註冊約 50 個 skill，每個 3–8 行描述全部進 system prompt。

**代價**：每 session 開場固定燒掉估計 25–35k tokens 在規則與索引上；更糟的是弱模型「讀了但沒吸收」——
規則越長，單條規則被遵守的機率越低。

**修法**（本 session 已執行的部分標 ✅）
1. ✅ CLAUDE.md 瘦身為「路由表 + 核心紀律 + 授權現況」（~110 行），長內容抽到 `docs/agents/RULES_*.md` 按需讀取。
2. ✅ AGENTS.md 改為指標檔（內容以 CLAUDE.md 為準），消滅雙份維護。
3. MEMORY.md 索引行遵守「≤80 字 hook」規範（見 `MAINTENANCE.md` §3；既有超長行在日常維護時逐步修剪，不一次大改）。
4. 建議使用者盤點 gstack skills，停用長期不用者（AI 不得自行停用 plugin — 見 LETTER.md）。

---

## 問題 2：主對話（指揮官）自己下場做大量讀取與掃描

**證據**
- 本環境過去完全沒有派工制度：CLAUDE.md 對 subagent 隻字未提，每個 session 靠模型即興決定。
- 記憶中多次出現整包在主對話做的大型掃描（PR #0–600 review、20-round CSO sweep、全 repo audit）。
  部分用了多代理，但沒有固定的「派工三件套 / 回報合約」，結果品質不穩定。
- 主對話讀大檔案（如 TODO.md、PROGRESS.md 全文）後，長對話觸發摘要，早期讀到的內容失真，
  後半 session 依據失真摘要做決策。

**代價**：context 燒光 → 觸發摘要 → 資訊失真 → 錯誤決策；且大量 raw 檔案內容留在主對話裡擠掉工作空間。

**修法**：`docs/agents/DISPATCH.md`（✅ 本 session 產出）。核心三條：
指揮官不下場（大量讀取一律派 subagent，主對話只收結論）、派工三件套（目標動機 / 驗收條件 / 回報格式）、
回報合約（subagent 只回結論 + `檔案:行號`，長產物落檔傳路徑）。

---

## 問題 3：規則互相打架且部分過時，弱模型只能隨機選邊

**證據**
- (a) **授權對撞**：舊 CLAUDE.md「執行紀律」寫 `git push` / merge PR 必經明確同意；
  但記憶有 2026-06-01 常設授權「CI 全綠 + bot 0 建議 → 自動 merge + 自動部署 prod」與
  「finish them = 授權 auto push + 開 PR」。弱模型會在該 push 時反覆問、或在不該 merge 時自動 merge。
- (b) **殭屍條文**：「執行紀律」引用的計畫檔（plan-for-the-critical-validated-pebble，R26 時代
  PR #1~#6 停機節奏）早已完結，條文仍以現在式存在，讀起來像現行規則。
- (c) **幽靈防線**：`.claude/hooks/block-dangerous.sh` 存在，但全域 / 專案 / local 三個 settings 檔
  都沒有 `hooks` 段 → 該 hook 疑似從未生效。文件與記憶（hook-shlex-not-grep）卻讓人以為有這道防線。
- (d) **沒寫下來的環境事實**：全域 settings deny 了 Bash 的 `ls / cat / grep / head / tail / find / sed / awk / rg`，
  CLAUDE.md 沒講，每個新 session 都會撞一次 denied 再自己學一次（本 session 開場即重演）。

**代價**：弱模型面對矛盾規則的行為是不可預測的——有時過度保守（反覆問）、有時過度大膽（誤 merge）。
兩種都比「規則一致」貴。

**修法**
1. ✅ 常設授權（auto push / merge / deploy 的條件與例外）寫進新 CLAUDE.md「授權現況」章，成為 single source of truth。
2. ✅ 過時執行紀律不再進 CLAUDE.md；durable 的部分（測試標準、clippy 門檻）併入 `RULES_BACKEND.md`。
3. ✅ 衝突裁決順序寫進 CLAUDE.md §衝突裁決（本次指示 > 較新的使用者明確決定（比日期）> 問；
   授權現況節例外——只有使用者能蓋。發現衝突 → 按 MAINTENANCE.md 修文件）。
4. ✅ 「Bash 被 deny 的指令 → 用哪個工具替代」對照表寫進 CLAUDE.md。
5. hook 未註冊問題交使用者裁定（登記於 LETTER.md — AI 不自行註冊 hook，因為那會改變全域行為）。

---

## 次要問題（有記錄價值，但不進前三）

- **settings.local.json 堆滿一次性 permission**（整段 codex 派工 prompt 被存成 allow 規則）：不影響 context，
  但會讓 permission 清單難以審計。建議使用者定期清理；AI 不主動清（屬使用者安全設定）。
- **驗證靠自驗**：過去「做完 → 自己說做完」占多數，缺 fresh-context 驗收。修法在 DISPATCH.md §驗證不自驗。
- **RTK 前綴規則本身沒問題**（省的比花的多），維持現狀。

## 引用關係

| 問題 | 對應制度檔 |
|---|---|
| 1 context 稅 | `CLAUDE.md`（重寫版）、`AGENTS.md`（指標化）、`MAINTENANCE.md` §3 |
| 2 指揮官下場 | `DISPATCH.md` |
| 3 規則打架 | `CLAUDE.md` §授權現況 + §衝突裁決、`MAINTENANCE.md` §2 |
| 驗證自驗 | `DISPATCH.md` §驗證不自驗、`JUDGMENT.md` §何時算完成 |
