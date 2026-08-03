# 📚 `docs/learn/` — 入門概念教學

寫給**這個專案的維運者**（你 = 異種器官移植研究獸醫，solo 開發 + 維運），不是教材也不是百科。每篇文件針對你**實際遇到 / 將要遇到的工程概念**，用比喻 + 具體場景說明，並對應 ipig_system 真實設定。

## 已有文件

| 主題 | 文件 | 適合什麼時候讀 |
|---|---|---|
| **CI/CD 是什麼、放什麼** | [`CI_CD_PRIMER.md`](CI_CD_PRIMER.md) | PR push 後看 GitHub 一堆綠勾紅叉時 / 想加新 CI 檢查時 / 收到 CI 失敗通知時 |

## 設計原則

1. **比喻優先**：每節先用日常 / 實驗室類比，技術細節放後面
2. **對齊真實系統**：所有範例引用 ipig_system 實際的檔案 / job / config，不抽象空談
3. **可掃讀**：表格 + bullet > 段落散文
4. **連結而非重複**：CI 細節去 `.github/workflows/ci.yml`，這裡只給概念地圖
5. **不教 best practice 給別人看**：你不是要面試 / 寫部落格，是要**搞懂自己系統在跑什麼**

## 將來可加（候選）

- `DOCKER_PRIMER.md` — container / image / volume / network 入門
- `OBSERVABILITY_PRIMER.md` — Prometheus / Grafana / logs 在你系統怎麼跑
- `AUTH_FLOWS.md` — JWT / refresh / sliding session 一條龍解釋（sliding session cutover 後好寫）
- `SQL_MIGRATIONS.md` — sqlx migration up/down 怎麼讀、怎麼修

新主題用前綴 issue number / R-section 連結回 TODO / PROGRESS 即可。
