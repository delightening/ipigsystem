-- 動物預約與試驗規劃（Phase 0：schema only）。
-- 緣由：執行秘書需一頁看全場動物按試驗分組、需求 vs 已預約/已分配缺口，把未分配動物
--      「預約」進試驗（已核准 protocol 或規劃中預定試驗），再兩段式「正式分配」進實驗。
-- 見 docs/design/animal-reservation/implementation-plan.md（合併原 ①b-2 預定客戶 + ③ 體重報表）。
-- 範圍：本 migration 僅建 schema。CRUD / 預約·分配 / 搜尋 / 分組查詢 / 前端規劃頁皆於後續 Phase。

-- 1) 預定試驗（規劃中、未核准的試驗需求；執行秘書手填。核准後 protocol_id 連到真 protocol）
CREATE TABLE planned_experiments (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- 委託單位 / 客戶名（如「昱展新藥」）
    unit          TEXT        NOT NULL,
    -- 試驗內容概述
    description   TEXT,
    -- 需求動物數
    demand_count  INTEGER     NOT NULL DEFAULT 0 CHECK (demand_count >= 0),
    -- 核准後連結真 protocol（非空 = 此規劃試驗已核准）；protocol 硬刪時解除連結（罕見，protocols 走軟刪）
    protocol_id   UUID        REFERENCES protocols(id) ON DELETE SET NULL,
    created_by    UUID        NOT NULL REFERENCES users(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_planned_experiments_protocol
    ON planned_experiments (protocol_id) WHERE protocol_id IS NOT NULL;

-- 2) 動物預約連結（僅未分配動物 earmark；二擇一：預約給已核准 protocol 或規劃中 planned_experiment）。
--    正式分配進實驗（status → in_experiment）時，由 service 清空兩欄（Phase 2）。
--    刪除目標試驗 → SET NULL 自動解除預約（預約非關鍵資料，不阻擋刪除）。
ALTER TABLE animals
    ADD COLUMN reserved_protocol_id           UUID REFERENCES protocols(id)           ON DELETE SET NULL,
    ADD COLUMN reserved_planned_experiment_id UUID REFERENCES planned_experiments(id) ON DELETE SET NULL;

-- 至多預約一個目標（protocol 或 planned_experiment 二擇一）
ALTER TABLE animals
    ADD CONSTRAINT chk_animal_reservation_single
    CHECK (num_nonnulls(reserved_protocol_id, reserved_planned_experiment_id) <= 1);

-- 反查某試驗的已預約動物（缺口/已預約數計算用）
CREATE INDEX idx_animals_reserved_protocol
    ON animals (reserved_protocol_id) WHERE reserved_protocol_id IS NOT NULL;
CREATE INDEX idx_animals_reserved_planned
    ON animals (reserved_planned_experiment_id) WHERE reserved_planned_experiment_id IS NOT NULL;
