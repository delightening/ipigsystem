-- 為 users 補上 department_id（所屬部門），修復請假送審 500。
-- 緣由：PR #834（兩關審核）新增「L1 = 申請人部門主管」關卡，
--       services/hr/leave.rs 的 l1_has_eligible_approver / is_dept_manager_of
--       以 `users.department_id JOIN departments` 反查部門主管，但此欄位從未建立，
--       送審時 Postgres 回 42703（undefined column）→ 通用 500「資料庫操作失敗」。
-- 設計：nullable + ON DELETE SET NULL。既有使用者部門為 NULL 時，
--       l1_has_eligible_approver 自然回 false，送審依 #834 的「卡關自動跳關」
--       直接進「待行政審核（PENDING_HR）」關；待日後部門指派功能上線再填此欄啟用 L1。

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id) ON DELETE SET NULL;

-- FK 子欄位建索引（Postgres 不自動建），供 leave 審核反查與部門成員查詢。
CREATE INDEX IF NOT EXISTS idx_users_department_id
    ON users(department_id) WHERE department_id IS NOT NULL;

COMMENT ON COLUMN users.department_id IS '所屬部門，NULL 表示未指派；請假兩關審核以此反查 L1 部門主管';
