## 摘要 (Summary)

<!-- 用 1–3 個 bullet 說明這個 PR 做了什麼、為什麼做 -->

-

## 變更類型 (Type of Change)

<!-- 勾選適用項目（可複選） -->

- [ ] 🐛 **Bug fix** — 修復問題（非破壞性變更）
- [ ] ✨ **New feature** — 新功能（非破壞性變更）
- [ ] 💥 **Breaking change** — 破壞性變更（影響現有 API contract 或 DB schema）
- [ ] 📝 **Documentation** — 僅文件更新
- [ ] 🔧 **Refactor** — 重構（無功能變更）
- [ ] 🔒 **Security** — 資安修補
- [ ] ✅ **Compliance** — GLP / 21 CFR Part 11 相關
- [ ] 🗃️ **Migration** — 新增或修改資料庫 migration
- [ ] 🏗️ **Infrastructure** — CI/CD、Docker、監控、依賴更新

## 關聯 Issue

<!-- 使用關鍵字自動關閉 issue：Closes #123 / Refs #123 -->

Closes #

## 測試 (Testing)

<!-- 說明如何驗證此 PR 正確運作 -->

**測試方式：**

<!-- 簡述測試場景、測試指令或手動步驟 -->

**Checklist：**

- [ ] `cargo test --all-targets` 全綠
- [ ] `cargo clippy --all-targets -- -D warnings -A deprecated` 無新增警告
- [ ] 前端：`pnpm lint` 無警告 + `pnpm test` 通過
- [ ] 瀏覽器手動測試通過（若涉及 UI）
- [ ] 已新增或更新對應測試

## 資料庫變更 (Database Changes)

- [ ] 無資料庫變更
- [ ] 新增 migration，且已同時新增 `migrations/down/` 對稱 migration
  - Migration 名稱：`YYYYMMDDHHMMSS_description.sql`
  - 變更摘要：
  - 向下相容性說明：

## 合規檢查 (Compliance Checklist)

<!-- 若此 PR 不涉及任何資料 mutation，勾選「不適用」即可跳過 -->

- [ ] 不適用（純 infra / UI 修改 / 文件）
- [ ] 所有 mutation 已透過 Service-driven Audit Pattern（R26）寫入 HMAC-chained log
- [ ] actor 識別正確：HTTP request → `User`、Scheduler → `System`、登入前 → `Anonymous`
- [ ] 涉及電子簽章的操作已驗證密碼 + TOTP 重新認證流程
- [ ] 涉及紀錄鎖定的邏輯已確認 DB trigger 正確觸發
- [ ] 新增或修改合規功能後已更新 `docs/glp/traceability-matrix.md`

## Reviewer 注意事項 (Notes for Reviewer)

<!-- 特別需要 reviewer 關注的地方、已知 trade-off、架構決策 -->

## Follow-up（本 PR 刻意不處理，留待後續）

<!-- 相關但超出本 PR 範圍的事項，建議開 issue 追蹤 -->
