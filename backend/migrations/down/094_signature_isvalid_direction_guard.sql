-- Down migration for 094_signature_isvalid_direction_guard
-- 用途：staging rollback；把 check_electronic_signatures_immutable 還原為 041 版本，
--       移除 094 新增的 (a) is_valid 方向鎖 (b) meaning / hmac_version 不可變檢查。
-- 注意：rollback 後簽章可被「作廢→復活」、meaning / hmac_version 可被直接 SQL 竄改，
--       僅剩應用層 (services/signature) 保護。trigger 綁定不變（CREATE OR REPLACE）。

CREATE OR REPLACE FUNCTION check_electronic_signatures_immutable()
RETURNS TRIGGER AS $$
BEGIN
    -- core fields (簽章本身的內容) 不可動
    IF OLD.entity_type IS DISTINCT FROM NEW.entity_type
       OR OLD.entity_id IS DISTINCT FROM NEW.entity_id
       OR OLD.signer_id IS DISTINCT FROM NEW.signer_id
       OR OLD.signature_type IS DISTINCT FROM NEW.signature_type
       OR OLD.content_hash IS DISTINCT FROM NEW.content_hash
       OR OLD.signature_data IS DISTINCT FROM NEW.signature_data
       OR OLD.signature_method IS DISTINCT FROM NEW.signature_method
       OR OLD.handwriting_svg IS DISTINCT FROM NEW.handwriting_svg
       OR OLD.stroke_data IS DISTINCT FROM NEW.stroke_data
       OR OLD.signed_at IS DISTINCT FROM NEW.signed_at THEN
        RAISE EXCEPTION 'electronic_signatures core fields immutable (GLP §11.70)。
僅 is_valid / invalidated_reason / invalidated_at / invalidated_by 可由 SignatureService::invalidate 修改。'
            USING ERRCODE = 'P0001';
    END IF;
    -- 走到這裡代表 core fields 都沒動 → 通過（is_valid + invalidated_* 可改）
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_electronic_signatures_immutable() IS
'GLP §11.70：簽章 core fields (entity / signer / hash / signature_data / handwriting / signed_at) 不可動。僅允許軟失效（is_valid + invalidated_* 4 欄）。';
