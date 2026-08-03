-- 補登審查意見「項次」：對應計畫書章節編號（如 4.1.2），釐清「意見」指涉計畫書哪一項內容。
-- 命名為 section_no 以與匯出資料既有的序號欄位 item_no（1,2,3…）區隔。
-- nullable，僅補登審查文件 / 審查意見使用；既有 row 與 live review 不受影響。
ALTER TABLE review_comments ADD COLUMN section_no VARCHAR(50);

COMMENT ON COLUMN review_comments.section_no IS
    '審查意見對應的計畫書項次（如 4.1.2），補登審查文件填寫；nullable';
