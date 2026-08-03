# 匯入計劃：研究資料 inline + 匯入後鎖定（Import Inline Basic & Lock）

> 立案：2026-06-01　／　狀態：**已落地（C1/C2/C3 完成，PR #544）**
> 受眾：專案負責人 + 維護者

## 目標（省步驟）

把完整「研究資料」章節搬進「匯入已核准計劃」頁面，匯入時一次填完；匯入後該章節在
編輯頁（補登作業）變**灰色唯讀**。研究資料 = 匯入當下定死的「身分資料」，填錯只能
**刪除整筆計劃 + 重新匯入**，不走編輯。全程 audit。

## 行為規格（使用者明定）

1. **匯入頁 inline 研究資料**：`ImportApprovedProtocolPage` 顯示完整「研究資料」欄位
   （研究名稱、GLP 符合性、預計試驗時程、計畫類型/種類、資金來源、計畫主持人、
   委託單位、試驗機構與設施），一次填完寫入 `working_content.basic`。
2. **編輯頁鎖定研究資料**：`/protocols/{id}/edit` 的「1. 研究資料」整段灰階唯讀
   （`fieldset disabled`），即使在 import_pending 補登期間也不可改。
3. **改錯路徑**：研究資料寫錯 → 不在編輯頁改 → 去「計畫書管理」**刪除** → 重新匯入。
4. **其他章節維持現狀**：研究目的/試驗物質/設計…等補登期間可編輯，finalize 後鎖定。
5. **Audit**：匯入（PROTOCOL_IMPORT_APPROVED，既有）、刪除、重新匯入皆入 audit。

## 與既有行為的差異

- 現狀：研究資料在編輯頁（補登期間）可改；title/日期會自動帶入，但系統內 PI 聯絡
  資料不會帶入要重打（見 amendment_import_backfill 討論的「重複欄位」缺口）。
- 改後：研究資料只在匯入頁填一次 → 缺口消失；編輯頁該段鎖定。

## 已裁定決策（2026-06-01）

- **D1 範圍**：✅ 研究資料整段全搬進匯入頁。
- **D2 刪除權限**：✅ 僅 admin。
- **D3 刪除語意**：✅ 硬刪 + 限無下游資料（無 amendment / 無 active byproduct）；僅
  imported_at 非 NULL 的匯入計劃可刪；scaffold 由 FK CASCADE 連帶刪。**已落地（C1）**。
- **D4 鎖定後改動**：✅ 走刪除重匯入（非 amendment）。
- **D5 PI 重疊**（C2 啟動前新增）：✅ 保留 PiSelector 當 PI 唯一來源，內嵌研究資料
  **不含 PI 段**；系統內 PI 的 basic.pi 由選定使用者自動帶入。

## 拆解與進度

- **C1 後端刪除**：✅ **已落地** — `ProtocolService::delete_imported_protocol`
  （admin gate handler + imported/amendment/byproduct 守衛 + FK 違反友善錯誤）+
  `DELETE /protocols/:id/imported` + 4 整合測試。
- **C2 匯入頁 inline 研究資料**：✅ **已落地**。抽 `ResearchBasicFields`（GLP/類型/種類/
  資金/委託單位/試驗機構，非 PI）受控元件，`SectionBasic`（編輯頁）與
  `ImportApprovedProtocolPage`（匯入頁）共用。匯入頁 submit 時 merge basic +
  衍生 pi（系統內 PI 取使用者名/email，外部 PI 取填寫值）。`ExternalPiData` 收斂為
  僅 PI（sponsor 移至 ResearchBasicFields）。
- **C3 編輯頁鎖定研究資料**：✅ **已落地**。`SectionBasic` 加 `disabled` prop（整段
  `fieldset disabled` 灰階唯讀），編輯頁對 `imported_at` 非 NULL 計劃傳 disabled。
  改錯走刪除重匯入（C1）。

## 已知 follow-up

- ResearchBasicFields 抽出後 SectionBasic 欄位視覺順序微調（GLP/類型/資金移至 PI 後）；
  功能等價，print 不受影響（print 讀 working_content 資料非表單順序）。
- 前端 lock 對既有 prod imports（pre-C2，研究資料原於編輯頁填）亦生效；該類多已 finalize
  （後端本就鎖定），edge case 可由 admin 刪除重匯入處理。

## 相關檔案（啟動時起點）

- `frontend/src/pages/protocols/ImportApprovedProtocolPage.tsx`（匯入頁，加 inline 研究資料）
- `frontend/src/pages/protocols/protocol-edit/SectionBasic.tsx`（研究資料章節，加 disabled gate）
- `frontend/src/pages/protocols/ProtocolEditPage.tsx`（編輯頁，傳 import-locked 旗標）
- `backend/src/services/protocol/core.rs`（import_approved 寫 working_content.basic；刪除 service）
- `backend/src/handlers/protocol/crud.rs`（刪除 handler + audit）
