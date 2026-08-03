-- DOWN for 096：還原 protocols.working_content 的麻醉類型值
-- azaperonum_atropine → azeperonum_atropine。
-- 僅供 staging / dev rollback；prod 採 forward-only。
--
-- 註：096 未修改任何 content_snapshot（不可變版本快照），故本 down 亦不涉及它們。

UPDATE protocols
SET working_content = jsonb_set(
        working_content,
        '{design,anesthesia,anesthesia_type}',
        '"azeperonum_atropine"'::jsonb
    )
WHERE working_content #>> '{design,anesthesia,anesthesia_type}' = 'azaperonum_atropine';
