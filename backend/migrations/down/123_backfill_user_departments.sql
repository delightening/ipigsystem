-- 還原 123：清掉本次回填的部門指派與試驗部主管。
UPDATE users SET department_id = NULL, updated_at = NOW()
WHERE email IN (
    'toccatico@gmail.com', 'raying80@gmail.com', 'q9182736455@gmail.com',
    'jliu90826@gmail.com', 'lisa82103031@gmail.com', 'keytyne@gmail.com',
    'museum1925@gmail.com', 'monkey20531@gmail.com',
    'smen1971@gmail.com', 'jason4617987@gmail.com'
);

UPDATE departments SET manager_id = NULL, updated_at = NOW()
WHERE code = 'EXPERIMENT';
