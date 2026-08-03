-- down 133：已刪除的 orphan 倉庫無法可靠還原（未保留原始欄位值）。
-- 若需回退，請自備份還原（見 docs/runbooks/DR_RUNBOOK.md）。安全 no-op。
SELECT 1;
