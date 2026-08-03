-- down 132：資料對帳無法可靠回滾。
-- up 將 stock_ledger.warehouse_id 對齊其 storage_location 所屬倉，未保留原 warehouse_id，
-- 故無從還原每列的原值。若需回退，請自備份還原（見 docs/runbooks/DR_RUNBOOK.md）。
-- 此處為安全 no-op，避免 down 誤改資料。
SELECT 1;
