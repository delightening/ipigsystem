-- 097: HMAC chain 已知斷鏈白名單（C：既有 35 筆斷鏈處置）
--
-- 2026-06-09 對 user_activity_logs 全史做權威 HMAC chain 驗證，發現 35 筆斷鏈，全部早於當日。
-- 三類成因（皆「寫入 bug / 早期 era / CLI bin 限制」產物，非竄改）：
--   (1) 16 筆：多筆 audit 同一 transaction、created_at=now() 固定 + 隨機 id → 排序歧義
--       （已於 migration 095 改 clock_timestamp() 根治，不再新增）；
--   (2) 17 筆：2026-04-23~05-05 早期 era（v2 + legacy hmac_version=NULL）編碼/JSON 正規化；
--   (3) 2 筆：CLI bin（provision_legacy_pi_accounts）寫入時未載 HMAC 金鑰（已於 #656 修）。
--
-- 本表登記這 35 個 id 為「已知斷鏈」。verifier（verify_chain_range）將其歸類為
-- acknowledged_breaks，不計入觸發告警的 broken_links；新斷鏈仍正常偵測。
-- 不修改任何既有 audit row（保留 GLP 不可變性；以白名單誠實標註歷史例外）。
--
-- 無 FK（允許在 test/dev 等無這些 row 的環境安全 seed；verifier 僅對實際出現的 row 比對）。
CREATE TABLE IF NOT EXISTS audit_chain_known_breaks (
    log_id      UUID        PRIMARY KEY,
    reason      TEXT        NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    recorded_by TEXT
);

COMMENT ON TABLE audit_chain_known_breaks IS
    'HMAC chain 已知斷鏈白名單：寫入 bug/早期 era/CLI bin 無金鑰 產物（非竄改）。verifier 歸類為 acknowledged、不告警；新斷鏈仍偵測。詳見 2026-06-09 調查（migration 095/097、PR #654/#656）。';

INSERT INTO audit_chain_known_breaks (log_id, reason, recorded_by) VALUES
  ('606b1d34-68e8-4224-b732-05ef1138ce71', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('d978deb8-b93f-450e-91c6-73628c9c3fca', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('dc90bd7c-80c4-44ef-b06b-b46cdd59e255', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('0c0df9fc-5568-488d-9cfb-aa15f0cd7ae3', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('b8a0cb72-76a0-4863-a563-e6518b98ef32', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('45875671-ee79-4871-b57f-acb7434c07b0', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('535cd103-15e3-4181-9fb9-e374a64239c5', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('bf0b7236-ead7-4a4a-bdd2-9ab19d6129bf', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('e613fdb8-96b4-4f25-a54f-9ced1a606846', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('98433596-123b-46ff-9b69-323cedb4869e', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('6e868cbc-7126-4ba8-8019-01cc85013568', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('db3359cb-1eaa-460d-b2ac-31524ec8d80e', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('fa25bda7-e3bf-4866-a56d-8ef4824c555f', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('bd5aa838-cb97-4ed3-ac76-c74a1e00e5fb', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('aacd371b-08fc-4fda-9c39-a2e764034ebb', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('8678446e-ca81-46a4-a63e-755f2193d40b', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('55c59410-5792-4218-a64e-a99eecf5970b', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('baca6ad8-ac5d-4a87-919a-12b1f6d4f6b7', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('631059e2-9218-4eeb-8aef-d76d3d7549bd', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('6c4429ad-fb09-43b7-b442-15e2c0d6c2dd', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('29a5e066-d611-49b7-b61b-715cfeb5120b', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('456c9610-9579-4557-96bd-aea2b7cc1826', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('dd29c11c-fa0d-44f8-8a6f-cbbf04f59dc3', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('c57e7b22-3c3e-41d0-995c-4cdb38780286', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('f3c114af-cd70-4c27-b765-f057eb794ffa', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('295bbef7-543a-4ce6-bd4c-e54818d9b527', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('a3bffc6a-5132-425a-98c7-f585746d5f5d', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('b977edec-c025-4b2f-a60b-bc44ab3f0d47', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('a18bbfec-6d50-488a-9824-7419a33ab3dc', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('d8ae0791-093e-4a61-b04c-1f9500298d9d', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('924d5e8a-fa1c-45a7-8b2f-204f5c4d1fc3', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('4264a57d-cc5f-49c6-97ad-e276729a39d6', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('6064140d-fdea-4d73-8554-d3cf6d1a258b', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('a03f3d61-1b98-4caa-ba1e-3fb41266cdd9', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09'),
  ('a374055a-ad84-485f-b30a-c781cd1d8f48', '2026-06-09 全史驗證確認之歷史斷鏈（非竄改）；成因見 migration 097 註解', 'audit-chain-investigation-2026-06-09')
ON CONFLICT (log_id) DO NOTHING;
