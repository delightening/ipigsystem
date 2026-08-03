-- =========================================================================
-- Low-1 (#273 code review)：electronic_signatures immutability trigger
-- 補上 is_valid 方向鎖
-- =========================================================================
-- 原 041 trigger（check_electronic_signatures_immutable）允許 is_valid 雙向變動，
-- 直接 SQL 可把已作廢簽章 is_valid=false→true「復活」而通過 trigger（core fields 未動）。
-- 應用層無此路徑（services/signature/mod.rs::invalidate 永遠只設 false），此為
-- defense-in-depth 缺口。本 migration CREATE OR REPLACE 同一函式，額外禁止
-- false→true，與 §11.70「作廢不可復原」一致。
--
-- 註：CREATE OR REPLACE FUNCTION 會整體取代 041 的定義；trigger 綁定不變、無需重建。

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
       OR OLD.signed_at IS DISTINCT FROM NEW.signed_at
       -- bot review #627：meaning（§11.50(a)(3) 簽章意義）與 hmac_version（R30-7）亦為核心
       -- 元數據，須鎖定，否則可竄改簽章法律意義（如 Review→Approve）或降級 HMAC 版本。
       -- 註：041 trigger 早於 043(meaning)/042(hmac_version) 兩欄存在，故原版漏列；此處補上。
       OR OLD.meaning IS DISTINCT FROM NEW.meaning
       OR OLD.hmac_version IS DISTINCT FROM NEW.hmac_version THEN
        RAISE EXCEPTION 'electronic_signatures core fields immutable (GLP §11.70)。
僅 is_valid / invalidated_reason / invalidated_at / invalidated_by 可由 SignatureService::invalidate 修改。'
            USING ERRCODE = 'P0001';
    END IF;
    -- Low-1：is_valid 僅能 true→false（作廢），不可 false→true（復活）。
    IF NEW.is_valid AND NOT OLD.is_valid THEN
        RAISE EXCEPTION '不可將已作廢的電子簽章重新生效 (GLP §11.70：作廢不可復原)。'
            USING ERRCODE = 'P0001';
    END IF;
    -- 走到這裡代表 core fields 都沒動且 is_valid 未被復活 → 通過。
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_electronic_signatures_immutable() IS
'GLP §11.70：簽章 core fields 不可動；is_valid 僅能 true→false（作廢不可復原）。僅允許軟失效（is_valid + invalidated_* 4 欄）。';
