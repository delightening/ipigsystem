# AGENTS.md — 指標檔（勿在此新增規則）

本專案的 agent 工作規範**唯一權威來源是 `CLAUDE.md`**（repo 根目錄）。
請完整讀取並遵守 `CLAUDE.md`，包括其路由表指向的 `docs/agents/RULES_BACKEND.md`、
`docs/agents/RULES_FRONTEND.md`、`docs/agents/DOCS_PROTOCOL.md` 等檔案。

歷史背景：本檔曾是 CLAUDE.md 的完整鏡像（給 Codex CLI 讀），兩份人工同步且已漂移。
2026-07-04 起指標化，舊全文備份於 `docs/agents/backup/AGENTS.md.2026-07-04.bak`。

Codex 專屬注意事項：
- 所有 shell 指令同樣適用 `rtk` 前綴規則與 Bash deny 清單（見 CLAUDE.md §環境事實）。
- 產出規格：只回結論與 `檔案:行號`，長產物寫檔後回傳路徑（見 `docs/agents/DISPATCH.md` §4 回報合約）。
