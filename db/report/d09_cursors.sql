SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 120
SET PAGESIZE 100
DECLARE
  v_rows NUMBER;
BEGIN
  canteen_pkg.generate_daily_summary(TRUNC(SYSDATE), v_rows);
  DBMS_OUTPUT.PUT_LINE('Outlets processed by cursor: ' || v_rows);
END;
/
DECLARE
  c       SYS_REFCURSOR;
  v_id    NUMBER;
  v_name  VARCHAR2(80);
  v_qty   NUMBER;
  v_rev   NUMBER;
  v_rat   NUMBER;
BEGIN
  canteen_pkg.get_top_items(NULL, 7, 5, c);
  DBMS_OUTPUT.PUT_LINE(RPAD('Dish', 22) || LPAD('Sold', 6) || LPAD('Revenue', 10));
  LOOP
    FETCH c INTO v_id, v_name, v_qty, v_rev, v_rat;
    EXIT WHEN c%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(RPAD(v_name, 22) || LPAD(v_qty, 6) || LPAD(v_rev, 10));
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(c%ROWCOUNT || ' rows fetched');
  CLOSE c;
END;
/
EXIT
