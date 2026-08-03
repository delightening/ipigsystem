-- down 135：已清除的殘留 pen_location 無法可靠還原（未保留原始欄位值，且原值本就是
-- 應被清除的髒資料）。若需回退，請自備份還原（見 docs/runbooks/DR_RUNBOOK.md）。安全 no-op。
SELECT 1;
