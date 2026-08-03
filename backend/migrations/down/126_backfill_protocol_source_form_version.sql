-- 還原 126：清掉本次回填的 source_form_version（回 NULL）。
-- 註：down 依序執行（126 → 125）；若隨後 125 down DROP COLUMN，本檔僅為前置清值、冪等安全。
UPDATE protocols SET source_form_version = NULL
 WHERE iacuc_no IN (
   'PIG-114003', 'PIG-114004', 'PIG-114005', 'PIG-114006', 'PIG-114010',
   'PIG-109032', 'PIG-113002', 'PIG-114009', 'PIG-114017',
   'PIG-113003', 'PIG-114016', 'PIG-114019', 'PIG-114022', 'PIG-114023', 'PIG-114025',
   'PIG-115001', 'PIG-115002', 'PIG-115003', 'PIG-115005', 'PIG-115006', 'PIG-115007',
   'PIG-115008', 'PIG-115009', 'PIG-115010', 'PIG-115011', 'PIG-115013',
   'PIG-115012'
 );
