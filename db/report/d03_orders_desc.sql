SET ECHO ON
SET LINESIZE 120
SET PAGESIZE 100
DESC orders
COLUMN constraint_name FORMAT A18
COLUMN type FORMAT A4
COLUMN rule FORMAT A70 WORD_WRAPPED
SELECT constraint_name, constraint_type AS type,
       NVL(search_condition_vc, r_constraint_name) AS rule
  FROM user_constraints
 WHERE table_name = 'ORDERS' AND constraint_name NOT LIKE 'SYS%'
 ORDER BY constraint_type, constraint_name;
EXIT
