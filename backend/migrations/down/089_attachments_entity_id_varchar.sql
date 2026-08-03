-- 反向 089：attachments.entity_id VARCHAR(100) → UUID。
-- 注意：若已存非 UUID entity_id（如 vet_recommendation 的「{record_type}_{record_id}」
-- 複合鍵），回轉 UUID 會失敗——需先清除或轉換該等列（dev rollback 場景）。
ALTER TABLE attachments
    ALTER COLUMN entity_id TYPE UUID USING entity_id::uuid;
