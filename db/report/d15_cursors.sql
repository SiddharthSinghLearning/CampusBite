SET ECHO ON
SET SERVEROUTPUT ON FORMAT WRAPPED
SET LINESIZE 120
SET PAGESIZE 100
DECLARE
  -- 1. explicit, parameterised cursor
  CURSOR c_menu (p_outlet NUMBER, p_max_price NUMBER) IS
    SELECT name, price, stock_qty FROM menu_item
     WHERE outlet_id = p_outlet AND price <= p_max_price ORDER BY price, name;
  r c_menu%ROWTYPE;
  c_low SYS_REFCURSOR;
  v_id NUMBER; v_name VARCHAR2(80); v_outlet VARCHAR2(80); v_stock NUMBER; v_av CHAR(1);
BEGIN
  DBMS_OUTPUT.PUT_LINE('1) Explicit cursor c_menu(outlet => 2, max price => 60)');
  OPEN c_menu(2, 60);
  DBMS_OUTPUT.PUT_LINE('   %ISOPEN after OPEN  = ' || CASE WHEN c_menu%ISOPEN THEN 'TRUE' ELSE 'FALSE' END);
  LOOP
    FETCH c_menu INTO r;
    EXIT WHEN c_menu%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE('   row ' || c_menu%ROWCOUNT || ': ' || RPAD(r.name, 18) || ' Rs.' || r.price);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('   %NOTFOUND ended the loop, %ROWCOUNT = ' || c_menu%ROWCOUNT);
  CLOSE c_menu;
  DBMS_OUTPUT.PUT_LINE('   %ISOPEN after CLOSE = ' || CASE WHEN c_menu%ISOPEN THEN 'TRUE' ELSE 'FALSE' END);

  DBMS_OUTPUT.PUT_LINE('2) Cursor FOR loop: kitchen wait per outlet');
  FOR o IN (SELECT outlet_id, name FROM outlet ORDER BY outlet_id) LOOP
    DBMS_OUTPUT.PUT_LINE('   ' || RPAD(o.name, 18) || ' ~' || canteen_pkg.estimate_wait_minutes(o.outlet_id) || ' min');
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('3) Implicit cursor attributes after an UPDATE');
  UPDATE menu_item SET prep_minutes = prep_minutes WHERE outlet_id = 1 AND category_id = 1;
  DBMS_OUTPUT.PUT_LINE('   SQL%FOUND = ' || CASE WHEN SQL%FOUND THEN 'TRUE' ELSE 'FALSE' END || ', SQL%ROWCOUNT = ' || SQL%ROWCOUNT);
  ROLLBACK;

  DBMS_OUTPUT.PUT_LINE('4) REF CURSOR from canteen_pkg.get_low_stock(NULL, 10)');
  canteen_pkg.get_low_stock(NULL, 10, c_low);
  LOOP
    FETCH c_low INTO v_id, v_name, v_outlet, v_stock, v_av;
    EXIT WHEN c_low%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE('   ' || RPAD(v_name, 16) || RPAD(v_outlet, 17) || 'stock ' || v_stock || '  available ' || v_av);
  END LOOP;
  CLOSE c_low;
END;
/
EXIT
