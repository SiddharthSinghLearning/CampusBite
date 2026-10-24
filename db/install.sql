-- Runs the full database build. Usage (from the db folder):
--   sqlplus canteen/<password>@localhost:1521/XEPDB1 @install.sql
SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100

PROMPT ===== 1. Schema =====
@@01_schema.sql
PROMPT ===== 2. Triggers =====
@@02_triggers.sql
PROMPT ===== 3. Package and views =====
@@03_package.sql

PROMPT ===== Compilation errors (should be none) =====
COLUMN name FORMAT A25
COLUMN text FORMAT A100
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

PROMPT ===== 4. Demo data =====
@@04_seed.sql
EXIT
