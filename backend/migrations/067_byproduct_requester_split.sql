-- R53-14: byproduct samples 財務 schema 升級
--
-- 背景：使用者 2026-05-17 review R53-A 時明確指出 byproduct samples **不只是
-- GLP 紀錄，也是財務紀錄**（樣品給其他研究方時要算錢）。對應兩塊 schema 升級：
--
-- A. Requester 分機構 / 聯絡人雙層
--    現有 requester_text 一欄合併「機構 + 人」 → 帳務難對。改成：
--    - requester_org_name   （機構，如「國防醫學大學」）
--    - requester_contact_name（聯絡人，如「王教授」）
--    in-system FK 路徑 `requester_user_id` 仍保留不動（從 user 推導 org）。
--    舊 `requester_text` 直接 DROP — R53-1 migration 066 剛上線（同日），尚無
--    production 資料。
--
-- B. Billing 欄位（per 2026-05-17 老闆指定報表欄位）
--    - special_equipment_used   TEXT       — 特殊儀器使用
--    - work_started_at          TIMESTAMPTZ — 開始時間
--    - work_ended_at            TIMESTAMPTZ — 結束時間
--    總時數由報表 query 計算 `(work_ended_at - work_started_at)`，不持久化
--    （避免兩欄資料不一致風險）。
--
-- CHECK constraints：
--   - 重新定義 requester present 條件：FK 或（org + contact 兩欄都非空）
--   - work time 區間：兩欄都有值時，end >= start
--
-- 依賴：migration 066（建立 euthanasia_byproduct_samples 表）。

-- Requester 兩層
ALTER TABLE euthanasia_byproduct_samples
    ADD COLUMN requester_org_name     TEXT,
    ADD COLUMN requester_contact_name TEXT;

-- Billing 三欄
ALTER TABLE euthanasia_byproduct_samples
    ADD COLUMN special_equipment_used TEXT,
    ADD COLUMN work_started_at        TIMESTAMPTZ,
    ADD COLUMN work_ended_at          TIMESTAMPTZ;

-- 舊 CHECK 因 requester_text drop 而失效，先 drop
ALTER TABLE euthanasia_byproduct_samples
    DROP CONSTRAINT IF EXISTS byproduct_samples_requester_present;

-- 舊欄位 drop（migration 066 剛上線當日，無 prod 資料需 backfill）
ALTER TABLE euthanasia_byproduct_samples
    DROP COLUMN requester_text;

-- 新 CHECK：in-system FK 或（org + contact 兩欄都非空）
ALTER TABLE euthanasia_byproduct_samples
    ADD CONSTRAINT byproduct_samples_requester_present CHECK (
        requester_user_id IS NOT NULL
        OR (
            requester_org_name     IS NOT NULL AND length(trim(requester_org_name))     > 0
            AND requester_contact_name IS NOT NULL AND length(trim(requester_contact_name)) > 0
        )
    );

-- 工作時間區間：兩欄都有值時 end >= start（其中一欄 NULL 也允許）
ALTER TABLE euthanasia_byproduct_samples
    ADD CONSTRAINT byproduct_samples_work_time_order CHECK (
        work_started_at IS NULL
        OR work_ended_at IS NULL
        OR work_ended_at >= work_started_at
    );

COMMENT ON COLUMN euthanasia_byproduct_samples.requester_org_name IS
    'R53-14: external requester 機構名（如「國防醫學大學」）。FK 為 NULL 時必填，並要求 contact 也填。';
COMMENT ON COLUMN euthanasia_byproduct_samples.requester_contact_name IS
    'R53-14: external requester 聯絡人姓名（如「王教授」）。FK 為 NULL 時必填，並要求 org 也填。';
COMMENT ON COLUMN euthanasia_byproduct_samples.special_equipment_used IS
    'R53-14: 特殊儀器使用紀錄（billing 報表欄位，自由文字）。';
COMMENT ON COLUMN euthanasia_byproduct_samples.work_started_at IS
    'R53-14: 採樣 / 處理工作開始時間。total hours 由 report query 即算（end - start），不持久化。';
COMMENT ON COLUMN euthanasia_byproduct_samples.work_ended_at IS
    'R53-14: 採樣 / 處理工作結束時間。兩欄都有值時 CHECK 要求 end >= start。';
