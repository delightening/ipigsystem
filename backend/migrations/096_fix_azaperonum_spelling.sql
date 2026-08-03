-- 096：修正麻醉類型 enum 值拼寫 azeperonum_atropine → azaperonum_atropine
--
-- 藥名 azaperone（畜舒坦）正確學名為 Azaperonum；原值誤拼為 Azeperonum（第二字母 e）。
-- 本 migration 為「全庫統一拼寫」的資料層一環（i18n 顯示字串、藥名範本、Python
-- 列印服務於同一 PR 同步調整）。
--
-- 範圍決策（audit-integrity）：
--   ✅ 僅遷移 protocols.working_content（live 可編輯草稿）——否則既有草稿開啟編輯頁時，
--      麻醉類型下拉的舊值對不上新的 SelectItem value（azaperonum_atropine），選項會變空白。
--   ⛔ 不動 protocol_versions.content_snapshot / amendment_versions.content_snapshot
--      （append-only 不可變版本快照＝稽核軌跡，竄改違反合規）。歷史快照中的舊值改由
--      讀取端（services/print-pdf adapter）向後相容同時接受新舊兩值處理。
--
-- jsonb_set 僅改 anesthesia_type 一個 path，不影響 working_content 其他欄位；
-- WHERE 限定恰為舊值的列，無相符列時為 no-op。

UPDATE protocols
SET working_content = jsonb_set(
        working_content,
        '{design,anesthesia,anesthesia_type}',
        '"azaperonum_atropine"'::jsonb
    )
WHERE working_content #>> '{design,anesthesia,anesthesia_type}' = 'azeperonum_atropine';
