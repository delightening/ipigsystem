-- 139: 沖銷單關聯欄位地基（R84-5 正式沖銷單 / 紅字沖銷）
--
-- 背景：已核准單據作廢目前無正式機制，系統提示「請用沖銷（reversal）」但未實作，
-- 實務只能用調整單硬改、追溯鏈斷一次。R84-5 導入「紅字沖銷」：沖銷單原封不動地鏡射
-- 原單實際寫入的 stock_ledger / journal_entries（方向、借貸相反），符合 GLP append-only。
--
-- 本 migration 僅建立**資料地基**（欄位 + 約束）；沖銷 service 邏輯與兩階段核准工作流
-- （WAREHOUSE_MANAGER 發起 + ADMIN 核准）於後續 PR 在可跑整合測試的環境實作。
--
-- 設計依據：docs/spec/modules/ERP流程.md §6.3.1（設計已定案、PR #1026 合併）。
--
-- reverses_doc_id：放在「沖銷單」身上，指向被沖銷的原單；原單不動。
-- partial UNIQUE index：資料庫層保證「一張原始單據最多只能有一張沖銷單」，不靠應用層
--   check-then-create（並發下兩請求都查到未沖銷而各建一張的 race condition，只有 DB
--   unique 約束是可靠的最後防線）。WHERE reverses_doc_id IS NOT NULL 讓一般單據（NULL）
--   不受唯一性限制。
ALTER TABLE documents
    ADD COLUMN reverses_doc_id UUID REFERENCES documents(id);

CREATE UNIQUE INDEX idx_documents_reverses_doc_id_unique
    ON documents(reverses_doc_id)
    WHERE reverses_doc_id IS NOT NULL;

COMMENT ON COLUMN documents.reverses_doc_id IS
    'R84-5 紅字沖銷：本單為哪一張原始單據的沖銷單（放在沖銷單身上，指向原單；一般單據為 NULL）。partial unique index 保證一張原單最多一張沖銷單。';
