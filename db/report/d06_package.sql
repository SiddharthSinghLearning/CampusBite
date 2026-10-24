SET ECHO ON
SET LINESIZE 100
SET PAGESIZE 100
COLUMN member FORMAT A24
COLUMN kind FORMAT A9
SELECT p.procedure_name AS member,
       CASE WHEN EXISTS (SELECT 1 FROM user_arguments a
                          WHERE a.package_name = 'CANTEEN_PKG' AND a.object_name = p.procedure_name
                            AND a.position = 0) THEN 'FUNCTION' ELSE 'PROCEDURE' END AS kind
  FROM user_procedures p
 WHERE p.object_name = 'CANTEEN_PKG' AND p.procedure_name IS NOT NULL
 ORDER BY kind, member;
EXIT
