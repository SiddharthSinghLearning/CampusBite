SET ECHO ON
SET SERVEROUTPUT ON FORMAT WRAPPED
SET LINESIZE 120
SET PAGESIZE 100
-- Triggers fired by one place_order call: before / after values
DECLARE
  v_stock0 NUMBER; v_stock1 NUMBER; v_bal0 NUMBER; v_bal1 NUMBER;
  v_order NUMBER; v_token NUMBER; v_total NUMBER;
  v_code orders.pickup_code%TYPE; v_slot DATE; v_booked NUMBER; v_price NUMBER;
BEGIN
  SELECT stock_qty INTO v_stock0 FROM menu_item WHERE item_id = 17;
  SELECT wallet_balance INTO v_bal0 FROM app_user WHERE user_id = 8;
  DBMS_OUTPUT.PUT_LINE('BEFORE  Cold Coffee stock = ' || v_stock0 || ',  Priya wallet = Rs.' || v_bal0);

  canteen_pkg.place_order(8, 2, '[{"item_id":17,"qty":2}]', NULL, NULL, NULL, v_order, v_token, v_total);

  SELECT pickup_code, pickup_slot INTO v_code, v_slot FROM orders WHERE order_id = v_order;
  SELECT booked INTO v_booked FROM pickup_slot WHERE outlet_id = 2 AND slot_start = v_slot;
  SELECT unit_price INTO v_price FROM order_item WHERE order_id = v_order AND item_id = 17;
  SELECT stock_qty INTO v_stock1 FROM menu_item WHERE item_id = 17;
  SELECT wallet_balance INTO v_bal1 FROM app_user WHERE user_id = 8;
  DBMS_OUTPUT.PUT_LINE('ORDER   #' || v_order || ' placed, total Rs.' || v_total);
  DBMS_OUTPUT.PUT_LINE('AFTER   trg_order_token      -> token ' || v_token || ', pickup code ' || v_code);
  DBMS_OUTPUT.PUT_LINE('        trg_order_slot       -> slot ' || TO_CHAR(v_slot, 'HH24:MI') || ' booked = ' || v_booked);
  DBMS_OUTPUT.PUT_LINE('        trg_order_item_stock -> unit price Rs.' || v_price || ' (from menu), stock ' || v_stock0 || ' -> ' || v_stock1);
  DBMS_OUTPUT.PUT_LINE('        wallet debit         -> Rs.' || v_bal0 || ' -> Rs.' || v_bal1);
END;
/
COLUMN old_status FORMAT A10
COLUMN new_status FORMAT A10
SELECT log_id, order_id, old_status, new_status
  FROM order_status_log WHERE order_id = (SELECT MAX(order_id) FROM orders);
EXIT
