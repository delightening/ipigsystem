# 給未來 session 的信（LETTER）

> 撰寫：2026-07-04，Claude Fable 5——這個環境唯一一次由 Mythos 級模型運作的 session。
> 讀者：未來的 Sonnet / Opus / Haiku session，以及使用者本人。
> 本檔與其他制度檔的關係：DIAGNOSIS 是為什麼、CLAUDE.md 是入口、DISPATCH/JUDGMENT/TEMPLATES 是怎麼做、
> MAINTENANCE 是怎麼改；本檔放「沒人問但重要」的三件事＋這套制度會怎麼壞。

## 一、三件使用者沒問、但我認為最重要的事

### 1. 幽靈防線：`.claude/hooks/block-dangerous.sh` 疑似從未生效

這個 hook（擋 git push / reset --hard / prod migration / rm -rf）寫得很好，但**全域、專案、local
三個 settings 檔都沒有 `hooks` 註冊段**——我判斷它從未被執行過。這比「沒有防線」更危險：
文件與記憶讓每個 session 以為有這道防線存在。

**建議使用者二選一**：(a) 真的註冊它（在 `.claude/settings.json` 加 PreToolUse hook 段——
但先更新腳本，因為現行常設授權已允許 feature branch push，腳本會誤攔）；(b) 刪掉腳本並清掉
相關記憶。半信半疑的防線是最貴的防線。同類問題：`settings.local.json` 裡堆了幾十條一次性
permission（包含整段 codex 派工 prompt），建議定期手動清理——AI 不該動你的權限檔。

### 2. 最大的 context 稅，只有使用者拉得動

CLAUDE.md 瘦身後，每 session 最大的固定開銷變成：gstack plugin 的 ~50 個 skill 描述
（每個 3–8 行，全部進 system prompt）＋ MEMORY.md 索引。skill 清單裡有大量重疊
（browse/gstack/connect-chrome/open-gstack-browser 四個瀏覽器入口；qa/qa-only；三套 design review）
和明顯不用的（office-hours、retro、benchmark、canary）。**停用 plugin 或裁剪 skill 只有使用者能做**；
每停 10 個 skill 約省 1–2k tokens × 每一個 session。值得花十分鐘整理一次。

### 3. prod 在筆電上，而備援演練沒有紀錄

制度檔能讓 AI session 變強，但這個環境最大的單點風險不是 AI——是 prod、備份、以及唯一維運者
都在同一台 ASUS 筆電上。記憶顯示 DS923+ 是 backup target，但**我找不到任何一次「從備份實際還原」
的演練紀錄**。備份沒有還原演練 = 薛丁格的備份。建議：挑一個週末，在另一台機器（或 NAS 上的 VM）
從備份完整還原一次 DB + secrets + compose，把步驟寫進 `docs/`。這件事的價值高於這裡任何一份 AI 制度檔。

## 二、這套制度最可能的退化方式與預防

| 退化模式 | 徵兆 | 預防 / 解法 |
|---|---|---|
| **膨脹回歸**：規則又長回 CLAUDE.md，路由表失去意義 | CLAUDE.md >150 行 | MAINTENANCE §4 的精簡觸發；新內容默認進 RULES_*，不進 CLAUDE.md |
| **路由失靈**：session 不讀路由指到的檔就動手 | 違反的規則恰好都住在 RULES_* 裡（例如 handler 又出現直寫 SQL） | 使用者抽查時問一句「你讀了 RULES_BACKEND 嗎」；違規即回寫記憶提醒；派工模板已內建「先讀」欄位緩解 |
| **制度與現實漂移**：條文引用的路徑/工具/門檻過時 | 照條文做會報錯 | 一個 session 內第 2 次發現不符 → 觸發 MAINTENANCE §6 健康檢查 |
| **驗收儀式化**：fresh-context 驗收退化成走過場（驗收 prompt 抄實作敘述） | 驗收從來沒有不通過的紀錄 | 驗收一直全過本身就是警訊；用 TEMPLATES §6 原文，禁止附實作過程 |
| **判準被當教條**：門檻數字（重試 2 輪、≤6 並行）在不適用場景硬套 | 為了守門檻做出明顯低效的事 | 門檻是預設值不是物理定律；偏離時寫一行理由即可，事後按 MAINTENANCE §1 提議修改。**但寫明「禁止」的條文不在此列**（如「禁止相同 prompt 重派第三次」）——那些是硬規則，不得引本句繞過 |
| **記憶與制度雙軌打架**：新教訓只進記憶，制度檔不更新（或反之） | 同一主題記憶與條文說法不同 | MAINTENANCE §5 衝突流程；教訓按 §2 決策樹落點，不重複存兩份 |

## 三、坦白的極限聲明

這套制度把「執行品質」的地板墊高了：拆解、派工、驗證、升降級都有章可循，Sonnet 照做就能達到
不錯的水準。但它**不能**把 Sonnet 變成 Fable：模糊需求的定形、品味裁決、跨領域的直覺連結，
制度只能把這些題**識別出來並路由給使用者或第二意見**（JUDGMENT §6），不能替你答。
未來的 session：發現自己在硬答品味題時，停下來，那就是你該產預覽 / 開選項 / 問人的時刻。

## 四、本 session 交接狀態（2026-07-04）

已完成並落檔：DIAGNOSIS、CLAUDE.md 重寫（舊版備份於 backup/）、AGENTS.md 指標化、
RULES_BACKEND、RULES_FRONTEND、DOCS_PROTOCOL、DISPATCH、JUDGMENT、TEMPLATES、MAINTENANCE、本檔。
**對抗審查已完成**：fresh-context agent 全檔審查回報 15 個 finding（含 4 個真實路徑/函式名錯誤、
授權裁決自相矛盾、硬禁令被本檔軟化），已全數修正。記憶索引已加「Institution（先讀）」段指向制度。
殘留待辦：RULES_BACKEND §8（確認 R26-4 是否完成、clippy 可否恢復嚴格 `-D warnings`）。
這些檔案目前**未 commit**——是否入 git 由使用者決定（建議入，讓 CI 之外的 agent 也讀得到）。
