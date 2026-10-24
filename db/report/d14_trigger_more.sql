SET ECHO ON
SET SERVEROUTPUT ON FORMAT WRAPPED
SET LINESIZE 130
SET PAGESIZE 100
-- trg_wallet_guard: a direct UPDATE that would make the wallet negative
UPDATE app_user SET wallet_balance = wallet_balance - 100000 WHERE user_id = 8;
-- trg_order_slot (capacity), trg_loyalty_points, trg_review_rating
DECLARE
  v_order NUMBER; v_token NUMBER; v_total NUMBER; v_code VARCHAR2(6);
  v_o NUMBER; v_t NUMBER; v_slot DATE; v_pts0 NUMBER; v_pts1 NUMBER;
  v_avg0 VARCHAR2(20); v_avg1 VARCHAR2(20);
BEGIN
  -- slot capacity: allow only 1 order in a new slot
  UPDATE outlet SET slot_capacity = 1 WHERE outlet_id = 2;
  COMMIT;
  SELECT MAX(slot_start) INTO v_slot FROM TABLE(canteen_pkg.get_slots(2, 8));
  canteen_pkg.place_order(6, 2, '[{"item_id":14,"qty":1}]', NULL, v_slot, NULL, v_order, v_token, v_total);
  DBMS_OUTPUT.PUT_LINE('Slot ' || TO_CHAR(v_slot, 'HH24:MI') || ': first order #' || v_order || ' accepted');
  BEGIN
    canteen_pkg.place_order(7, 2, '[{"item_id":14,"qty":1}]', NULL, v_slot, NULL, v_o, v_t, v_total);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Slot ' || TO_CHAR(v_slot, 'HH24:MI') || ': second order -> ' || SQLERRM);
  END;
  UPDATE outlet SET slot_capacity = 8 WHERE outlet_id = 2;
  COMMIT;

  -- take Priya's order (from d13) to pickup and rate it
  SELECT MAX(order_id) INTO v_order FROM orders WHERE user_id = 8;
  SELECT loyalty_points INTO v_pts0 FROM app_user WHERE user_id = 8;
  SELECT rating_avg || ' (' || rating_count || ')' INTO v_avg0 FROM menu_item WHERE item_id = 17;
  canteen_pkg.update_order_status(v_order, 'ACCEPTED', 3);
  canteen_pkg.update_order_status(v_order, 'PREPARING', 3);
  canteen_pkg.update_order_status(v_order, 'READY', 3);
  SELECT pickup_code INTO v_code FROM orders WHERE order_id = v_order;
  canteen_pkg.verify_pickup(2, v_code, v_order, 3, v_o, v_t);
  SELECT loyalty_points INTO v_pts1 FROM app_user WHERE user_id = 8;
  DBMS_OUTPUT.PUT_LINE('trg_loyalty_points : order #' || v_order || ' picked up, points ' || v_pts0 || ' -> ' || v_pts1);
  canteen_pkg.add_review(v_order, 17, 8, 5, 'Perfect cold coffee');
  SELECT rating_avg || ' (' || rating_count || ')' INTO v_avg1 FROM menu_item WHERE item_id = 17;
  DBMS_OUTPUT.PUT_LINE('trg_review_rating  : Cold Coffee rating ' || v_avg0 || ' -> ' || v_avg1);
END;
/
COLUMN old_status FORMAT A10
COLUMN new_status FORMAT A10
SELECT log_id, old_status, new_status, TO_CHAR(changed_at, 'HH24:MI:SS') AS changed
  FROM order_status_log WHERE order_id = (SELECT MAX(order_id) FROM orders WHERE user_id = 8) ORDER BY log_id;
EXIT
