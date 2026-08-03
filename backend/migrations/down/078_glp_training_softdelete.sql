-- down: 078_glp_training_softdelete
-- 注意：若已有 soft-deleted 列且與 active 列 (role_code, training_topic) 重複，
-- 還原全表 UNIQUE 約束會失敗（rollback 假設無此類重複）。
DROP INDEX IF EXISTS idx_training_requirements_active;
ALTER TABLE role_training_requirements
    DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE role_training_requirements
    ADD CONSTRAINT role_training_requirements_role_code_training_topic_key
    UNIQUE (role_code, training_topic);
