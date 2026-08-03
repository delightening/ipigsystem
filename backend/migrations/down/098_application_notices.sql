-- 還原 098：移除申請須知簽署 schema（先子表後父表）。
DROP TABLE IF EXISTS protocol_notice_acknowledgements;
DROP TABLE IF EXISTS application_notices;
