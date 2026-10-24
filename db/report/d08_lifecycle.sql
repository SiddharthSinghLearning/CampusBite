SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 120
SET PAGESIZE 100
DECLARE
  v_order NUMBER;
  v_code  VARCHAR2(6);
  v_o     NUMBER;
  v_t     NUMBER;
BEGIN
  SELECT MAX(order_id) INTO v_order FROM orders WHERE user_id = 7;
  canteen_pkg.update_order_status(v_order, 'ACCEPTED',  4);
  canteen_pkg.update_order_status(v_order, 'PREPARING', 4);
  canteen_pkg.update_order_status(v_order, 'READY',     4);
  SELECT pickup_code INTO v_code FROM orders WHERE order_id = v_order;
  canteen_pkg.verify_pickup(3, v_code, v_order, 4, v_o, v_t);
  DBMS_OUTPUT.PUT_LINE('Order #' || v_o || ' (token ' || v_t || ') handed over after QR check');
END;
/
COLUMN old_status FORMAT A10
COLUMN new_status FORMAT A10
SELECT log_id, old_status, new_status, TO_CHAR(changed_at, 'HH24:MI:SS') AS at
  FROM order_status_log
 WHERE order_id = (SELECT MAX(order_id) FROM orders WHERE user_id = 7) ORDER BY log_id;
COLUMN full_name FORMAT A14
SELECT full_name, loyalty_points FROM app_user WHERE user_id = 7;
EXIT
