-- 126: 回填既有 27 筆補登計畫的 source_form_version（依案子→版本對照）
--
-- 依 docs/design/protocol-import/version-manifest-backfill-plan.md §7（使用者 2026-07-09 提供，權威）。
-- 版本逐案認定、橫跨 C/D/E/F（與資料夾年份無關）。
-- 非目標環境（dev/test 無這些 iacuc_no）→ 更新 0 列，冪等安全；重跑亦冪等。
UPDATE protocols SET source_form_version = 'C'
 WHERE iacuc_no IN ('PIG-114003', 'PIG-114004', 'PIG-114005', 'PIG-114006', 'PIG-114010');

UPDATE protocols SET source_form_version = 'D'
 WHERE iacuc_no IN ('PIG-109032', 'PIG-113002', 'PIG-114009', 'PIG-114017');

UPDATE protocols SET source_form_version = 'E'
 WHERE iacuc_no IN (
   'PIG-113003', 'PIG-114016', 'PIG-114019', 'PIG-114022', 'PIG-114023', 'PIG-114025',
   'PIG-115001', 'PIG-115002', 'PIG-115003', 'PIG-115005', 'PIG-115006', 'PIG-115007',
   'PIG-115008', 'PIG-115009', 'PIG-115010', 'PIG-115011', 'PIG-115013'
 );

UPDATE protocols SET source_form_version = 'F'
 WHERE iacuc_no = 'PIG-115012';
