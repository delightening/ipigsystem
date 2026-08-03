-- 099: signature_meaning 新增 ACKNOWLEDGE（動物試驗申請須知簽署用）。
-- 用於「申請須知」簽署紀錄的電子簽章 meaning（21 CFR §11.50 責任表示之一：申請人
-- 確認已閱讀並同意當前生效版本須知）。
--
-- HMAC 安全註記：簽章 HMAC 的 canonical input（services/signature/mod.rs::
-- signature_canonical_input）為 `signer_id : content_hash : timestamp : hash_input`，
-- **不含 meaning**，故新增此 enum 值不影響既有或新簽章的 HMAC 計算 / 驗證。
ALTER TYPE signature_meaning ADD VALUE IF NOT EXISTS 'ACKNOWLEDGE';
