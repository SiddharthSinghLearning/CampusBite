SET ECHO ON
SET LINESIZE 110
SET PAGESIZE 100
COLUMN object_name FORMAT A26
COLUMN object_type FORMAT A13
COLUMN status FORMAT A7
SELECT object_type, COUNT(*) AS total,
       SUM(CASE WHEN status = 'VALID' THEN 1 ELSE 0 END) AS valid
  FROM user_objects
 WHERE object_type IN ('TABLE','VIEW','PACKAGE','PACKAGE BODY','TRIGGER','TYPE','INDEX')
 GROUP BY object_type ORDER BY object_type;
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('PACKAGE','PACKAGE BODY','TRIGGER','VIEW','TYPE')
 ORDER BY object_type, object_name;
EXIT
