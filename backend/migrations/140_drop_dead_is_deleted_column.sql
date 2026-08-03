-- 140: 移除死欄 animals.is_deleted / roles.is_deleted（單一真相源 = deleted_at / is_active）
--
-- 背景：animals 有兩個軟刪欄——is_deleted(BOOLEAN) 與 deleted_at(TIMESTAMPTZ)。
-- 正規軟刪路徑（services/animal/core/delete.rs）**只設 deleted_at**，全 codebase 從未把
-- is_deleted 設為 true（唯一寫 true 者是一支測試 fixture，本 PR 一併改為只用 deleted_at）。
-- 因此每一列 is_deleted 恆為 false，`WHERE is_deleted = false` 對每列恆真、與 `deleted_at IS NULL`
-- 完全等價——但兩者不同步時，凡以 is_deleted=false 過濾的查詢（AI/MCP 動物清單、病歷報告、
-- byproduct、部分通知）反而**看不到**軟刪效果、把已軟刪動物一併列入。本 PR 已將 19 處查詢改用
-- deleted_at IS NULL，此處移除死欄與其索引，落實單一真相源。
--
-- roles.is_deleted 同屬死欄：唯一讀取點（services/notification/routing.rs）從未寫入，
-- 真正的「停用角色」旗標是 is_active；一併刪除。
--
-- 鎖定/部署 tradeoff（已向維運者呈現並取得同意）：本 migration 全為 metadata-only 操作——
-- DROP INDEX 與 PostgreSQL 的 DROP COLUMN（不重寫表、僅毫秒級 ACCESS EXCLUSIVE lock）。
-- **不新建任何索引**，故無非並行 CREATE INDEX 的寫入阻塞問題。animals 為研究場動物表
-- （數百列規模、熱查詢 sub-2ms），於維護窗口部署時鎖定影響可忽略。

-- ── animals：移除引用 is_deleted 的索引與欄位 ──
DROP INDEX IF EXISTS idx_animals_not_deleted;              -- WHERE is_deleted=false 涵蓋全表，且與 idx_animals_active (deleted_at IS NULL) 重複
DROP INDEX IF EXISTS idx_animals_status_deleted_created;   -- 複合索引含死欄 is_deleted
-- 不新建替代索引：查詢已改 deleted_at IS NULL，且 idx_animals_status / idx_animals_active 已在、
-- 表小無瓶頸（見 db-perf baseline）。日後若規模成長需要 (status, created_at) 索引，
-- 另以交易外 runbook + CREATE INDEX CONCURRENTLY 補，不放本交易式 migration。
ALTER TABLE animals DROP COLUMN IF EXISTS is_deleted;

-- ── roles：刪死欄（無索引引用）──
ALTER TABLE roles DROP COLUMN IF EXISTS is_deleted;
