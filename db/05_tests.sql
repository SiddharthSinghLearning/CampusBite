-- =====================================================================
-- CampusBite : 05_tests.sql  -  automated test cases
-- Uses its own test outlet / users and removes them at the end, so the
-- demo data is left untouched.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET LINESIZE 200

DECLARE
  v_pass   PLS_INTEGER := 0;
  v_fail   PLS_INTEGER := 0;
  v_stu    NUMBER;   -- test student
  v_poor   NUMBER;   -- student with an empty wallet
  v_ven    NUMBER;   -- vendor of the test outlet
  v_other  NUMBER;   -- vendor of another outlet
  v_out    NUMBER;   -- test outlet
  v_i1     NUMBER;   -- item  Rs.100, stock 50
  v_i2     NUMBER;   -- item  Rs.40,  stock 7
  v_i3     NUMBER;   -- item  unavailable
  v_order  NUMBER;
  v_token  NUMBER;
  v_total  NUMBER;
  v_bal    NUMBER;
  v_bal0   NUMBER;
  v_n      NUMBER;
  v_txt    VARCHAR2(400);
  v_cur    SYS_REFCURSOR;
  v_code   VARCHAR2(6);
  v_slot   DATE;
  v_slot2  DATE;

  PROCEDURE result (p_id VARCHAR2, p_desc VARCHAR2, p_expected VARCHAR2, p_actual VARCHAR2) IS
    v_ok BOOLEAN := (p_expected = p_actual);
  BEGIN
    IF v_ok THEN v_pass := v_pass + 1; ELSE v_fail := v_fail + 1; END IF;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_id, 6) || RPAD(p_desc, 52) ||
                         RPAD(SUBSTR(p_expected, 1, 22), 23) || RPAD(SUBSTR(p_actual, 1, 22), 23) ||
                         CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);
  END;

  FUNCTION err (p_sqlcode NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'ORA' || TO_CHAR(p_sqlcode);
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE(RPAD('TC', 6) || RPAD('Description', 52) || RPAD('Expected', 23) || RPAD('Actual', 23) || 'Result');
  DBMS_OUTPUT.PUT_LINE(RPAD('-', 110, '-'));

  -- ---------- fixtures ----------
  INSERT INTO app_user (full_name, email, reg_no, password_hash, role)
  VALUES ('Test Student', 'tc.student@test.in', 'TC0001', 'x', 'STUDENT') RETURNING user_id INTO v_stu;
  INSERT INTO app_user (full_name, email, reg_no, password_hash, role)
  VALUES ('Broke Student', 'tc.poor@test.in', 'TC0002', 'x', 'STUDENT') RETURNING user_id INTO v_poor;
  INSERT INTO app_user (full_name, email, password_hash, role)
  VALUES ('Test Vendor', 'tc.vendor@test.in', 'x', 'VENDOR') RETURNING user_id INTO v_ven;
  SELECT owner_id INTO v_other FROM outlet WHERE outlet_id = 2;
  INSERT INTO outlet (name, location, owner_id, open_time, close_time, slot_capacity)
  VALUES ('TC Test Kitchen', 'Lab', v_ven, '00:00', '23:59', 50) RETURNING outlet_id INTO v_out;
  INSERT INTO menu_item (outlet_id, category_id, name, price, stock_qty, prep_minutes)
  VALUES (v_out, 2, 'TC Meal', 100, 50, 10) RETURNING item_id INTO v_i1;
  INSERT INTO menu_item (outlet_id, category_id, name, price, stock_qty, prep_minutes)
  VALUES (v_out, 3, 'TC Snack', 40, 7, 5) RETURNING item_id INTO v_i2;
  INSERT INTO menu_item (outlet_id, category_id, name, price, stock_qty, is_available)
  VALUES (v_out, 3, 'TC Hidden', 30, 10, 'N') RETURNING item_id INTO v_i3;
  COMMIT;

  -- TC01 wallet top-up
  canteen_pkg.topup_wallet(v_stu, 1000, NULL, v_bal);
  result('TC01', 'Top-up Rs.1000 credits the wallet', '1000', TO_CHAR(canteen_pkg.get_wallet_balance(v_stu)));

  -- TC02 invalid top-up amount
  BEGIN
    canteen_pkg.topup_wallet(v_stu, -50, NULL, v_bal);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC02', 'Negative top-up is rejected', 'ORA-20007', v_txt);

  -- TC03 valid order: token, price from menu, stock, wallet, ledger, audit
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i1 || ',"qty":2},{"item_id":' || v_i2 || ',"qty":1}]',
                          NULL, NULL, 'TC03', v_order, v_token, v_total);
  result('TC03a', 'Order total = (2x100 + 40) + 5% GST', '252', TO_CHAR(v_total));
  result('TC03b', 'Pickup token assigned by trigger', 'Y', CASE WHEN v_token >= 1 THEN 'Y' ELSE 'N' END);
  SELECT stock_qty INTO v_n FROM menu_item WHERE item_id = v_i1;
  result('TC03c', 'Stock deducted by trigger (50 - 2)', '48', TO_CHAR(v_n));
  result('TC03d', 'Wallet debited (1000 - 252)', '748', TO_CHAR(canteen_pkg.get_wallet_balance(v_stu)));
  SELECT COUNT(*) INTO v_n FROM wallet_txn WHERE order_id = v_order AND txn_type = 'DEBIT';
  result('TC03e', 'Debit entry written to wallet ledger', '1', TO_CHAR(v_n));
  SELECT COUNT(*) INTO v_n FROM order_status_log WHERE order_id = v_order AND new_status = 'PLACED';
  result('TC03f', 'Status audit row written on insert', '1', TO_CHAR(v_n));

  -- TC04 insufficient balance: error and nothing saved
  SELECT COUNT(*) INTO v_n FROM orders;
  BEGIN
    canteen_pkg.place_order(v_poor, v_out, '[{"item_id":' || v_i1 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC04a', 'Order with empty wallet is rejected', 'ORA-20010', v_txt);
  SELECT COUNT(*) - v_n INTO v_n FROM orders;
  result('TC04b', 'Failed order fully rolled back', '0', TO_CHAR(v_n));
  SELECT stock_qty INTO v_n FROM menu_item WHERE item_id = v_i1;
  result('TC04c', 'Stock unchanged after failed order', '48', TO_CHAR(v_n));

  -- TC05 more than in stock
  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":15}]', NULL, NULL, NULL, v_order, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC05', 'Ordering more than stock is rejected', 'ORA-20023', v_txt);

  -- TC06 unavailable item
  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i3 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC06', 'Unavailable item cannot be ordered', 'ORA-20022', v_txt);

  -- TC07 item of another outlet
  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[{"item_id":14,"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC07', 'Item from a different outlet is rejected', 'ORA-20021', v_txt);

  -- TC08 coupon arithmetic and use
  result('TC08a', 'WELCOME20 on Rs.300 = min(20%, Rs.50)', '50', TO_CHAR(canteen_pkg.calc_coupon_discount('WELCOME20', 300)));
  result('TC08b', 'EXAM10 on Rs.200 = 10%', '20', TO_CHAR(canteen_pkg.calc_coupon_discount('exam10', 200)));

  -- TC09 expired / invalid / below-minimum coupons
  BEGIN v_n := canteen_pkg.calc_coupon_discount('FEST50', 500); v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE); END;
  result('TC09a', 'Expired coupon is rejected', 'ORA-20004', v_txt);
  BEGIN v_n := canteen_pkg.calc_coupon_discount('NOPE', 500); v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE); END;
  result('TC09b', 'Unknown coupon is rejected', 'ORA-20004', v_txt);
  BEGIN v_n := canteen_pkg.calc_coupon_discount('WELCOME20', 80); v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE); END;
  result('TC09c', 'Coupon below minimum order is rejected', 'ORA-20004', v_txt);

  -- TC10 coupon applied in an order
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i1 || ',"qty":2}]', 'WELCOME20', NULL, NULL, v_order, v_token, v_total);
  SELECT discount INTO v_n FROM orders WHERE order_id = v_order;
  result('TC10', 'Order with WELCOME20 gets Rs.40 off Rs.200', '40', TO_CHAR(v_n));

  -- TC11 illegal life-cycle jump
  BEGIN
    canteen_pkg.update_order_status(v_order, 'READY', v_ven);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC11', 'PLACED -> READY is not allowed', 'ORA-20005', v_txt);

  -- TC12 vendor of another outlet
  BEGIN
    canteen_pkg.update_order_status(v_order, 'ACCEPTED', v_other);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC12', 'Other outlet''s vendor cannot update', 'ORA-20008', v_txt);

  -- TC13 full life-cycle and loyalty points
  SELECT loyalty_points INTO v_bal0 FROM app_user WHERE user_id = v_stu;
  canteen_pkg.update_order_status(v_order, 'ACCEPTED',  v_ven);
  canteen_pkg.update_order_status(v_order, 'PREPARING', v_ven);
  canteen_pkg.update_order_status(v_order, 'READY',     v_ven);
  SELECT pickup_code INTO v_code FROM orders WHERE order_id = v_order;
  canteen_pkg.verify_pickup(v_out, v_code, v_order, v_ven, v_n, v_token);
  SELECT loyalty_points - v_bal0 INTO v_n FROM app_user WHERE user_id = v_stu;
  result('TC13a', 'Loyalty points = FLOOR(168 / 10) on pickup', '16', TO_CHAR(v_n));
  SELECT COUNT(*) INTO v_n FROM order_status_log WHERE order_id = v_order;
  result('TC13b', 'Audit log has 5 status rows', '5', TO_CHAR(v_n));

  -- TC14 reviews
  canteen_pkg.add_review(v_order, v_i1, v_stu, 4, 'Good');
  SELECT rating_avg || '/' || rating_count INTO v_txt FROM menu_item WHERE item_id = v_i1;
  result('TC14a', 'Review updates item rating (trigger)', '4/1', v_txt);
  BEGIN
    canteen_pkg.add_review(v_order, v_i1, v_stu, 5, NULL);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC14b', 'Second review of same item is rejected', 'ORA-20009', v_txt);

  -- TC15 student cancels a PLACED order: refund + stock back
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i1 || ',"qty":3}]', NULL, NULL, NULL, v_order, v_token, v_total);
  v_bal0 := canteen_pkg.get_wallet_balance(v_stu);
  SELECT stock_qty INTO v_n FROM menu_item WHERE item_id = v_i1;
  canteen_pkg.cancel_order(v_order, v_stu);
  result('TC15a', 'Cancel refunds the full amount (Rs.315)', TO_CHAR(v_bal0 + 315), TO_CHAR(canteen_pkg.get_wallet_balance(v_stu)));
  SELECT stock_qty - v_n INTO v_n FROM menu_item WHERE item_id = v_i1;
  result('TC15b', 'Cancel puts the 3 items back in stock', '3', TO_CHAR(v_n));
  BEGIN
    canteen_pkg.add_review(v_order, v_i1, v_stu, 5, NULL);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC15c', 'Cancelled order cannot be reviewed', 'ORA-20009', v_txt);

  -- TC16 student cannot cancel once the outlet has accepted
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i1 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
  canteen_pkg.update_order_status(v_order, 'ACCEPTED', v_ven);
  BEGIN
    canteen_pkg.cancel_order(v_order, v_stu);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC16', 'Student cannot cancel an ACCEPTED order', 'ORA-20006', v_txt);

  -- TC17 tokens increase within the day
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i1 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
  SELECT COUNT(*) INTO v_n FROM orders WHERE outlet_id = v_out;
  result('TC17', 'Token equals today''s order count at outlet', TO_CHAR(v_n), TO_CHAR(v_token));

  -- TC18 low-stock alert and sold-out hiding
  UPDATE menu_item SET stock_qty = 3 WHERE item_id = v_i1;
  SELECT COUNT(*) INTO v_n FROM stock_alert WHERE item_id = v_i1 AND is_resolved = 'N';
  result('TC18a', 'Stock 3 raises a low-stock alert', '1', TO_CHAR(v_n));
  UPDATE menu_item SET stock_qty = 0 WHERE item_id = v_i1;
  SELECT is_available INTO v_txt FROM menu_item WHERE item_id = v_i1;
  result('TC18b', 'Stock 0 hides the item automatically', 'N', v_txt);
  UPDATE menu_item SET stock_qty = 20 WHERE item_id = v_i1;
  SELECT is_available || COUNT(a.alert_id) INTO v_txt
    FROM menu_item m LEFT JOIN stock_alert a ON a.item_id = m.item_id AND a.is_resolved = 'N'
   WHERE m.item_id = v_i1 GROUP BY is_available;
  result('TC18c', 'Restock re-lists item, resolves alert', 'Y0', v_txt);
  COMMIT;

  -- TC19 price audit
  UPDATE menu_item SET price = 110 WHERE item_id = v_i1;
  SELECT old_price || '->' || new_price INTO v_txt FROM price_history WHERE item_id = v_i1;
  result('TC19', 'Price change recorded in history', '100->110', v_txt);
  COMMIT;

  -- TC20 empty cart
  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[]', NULL, NULL, NULL, v_order, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC20', 'Empty cart is rejected', 'ORA-20003', v_txt);

  -- TC21 outlet closed
  UPDATE outlet SET is_open = 'N' WHERE outlet_id = v_out;
  COMMIT;
  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC21', 'Closed outlet does not accept orders', 'ORA-20002', v_txt);
  UPDATE outlet SET is_open = 'Y' WHERE outlet_id = v_out;
  COMMIT;

  -- TC22 wait-time estimate (cursor over the live queue)
  v_n := canteen_pkg.estimate_wait_minutes(v_out);
  result('TC22', 'Wait estimate is at least 5 minutes', 'Y', CASE WHEN v_n >= 5 THEN 'Y' ELSE 'N' END);

  -- TC23 daily summary (explicit cursor over outlets)
  canteen_pkg.generate_daily_summary(TRUNC(SYSDATE), v_n);
  SELECT COUNT(*) INTO v_n FROM daily_sales_summary WHERE summary_date = TRUNC(SYSDATE) AND outlet_id = v_out;
  result('TC23', 'Daily summary row created for outlet', '1', TO_CHAR(v_n));

  -- TC24 REF CURSOR report
  canteen_pkg.get_low_stock(v_out, 10, v_cur);
  v_n := 0;
  LOOP
    FETCH v_cur INTO v_order, v_txt, v_txt, v_token, v_txt;
    EXIT WHEN v_cur%NOTFOUND;
    v_n := v_n + 1;
  END LOOP;
  CLOSE v_cur;
  result('TC24', 'Low-stock REF CURSOR returns 2 items', '2', TO_CHAR(v_n));

  -- ---------- QR pickup ----------
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
  SELECT pickup_code INTO v_code FROM orders WHERE order_id = v_order;
  result('TC25', 'Trigger issues a 6-digit pickup code', 'Y', CASE WHEN REGEXP_LIKE(v_code, '^[0-9]{6}$') THEN 'Y' ELSE 'N' END);

  BEGIN
    canteen_pkg.verify_pickup(v_out, v_code, v_order, v_ven, v_n, v_token);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC26', 'Pickup before READY is rejected', 'ORA-20005', v_txt);

  canteen_pkg.update_order_status(v_order, 'ACCEPTED',  v_ven);
  canteen_pkg.update_order_status(v_order, 'PREPARING', v_ven);
  canteen_pkg.update_order_status(v_order, 'READY',     v_ven);
  BEGIN
    canteen_pkg.update_order_status(v_order, 'PICKED_UP', v_ven);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC27', 'Hand-over without QR scan is blocked', 'ORA-20012', v_txt);

  BEGIN
    canteen_pkg.verify_pickup(v_out, CASE WHEN v_code = '000000' THEN '111111' ELSE '000000' END, v_order, v_ven, v_n, v_token);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC28', 'Wrong pickup code is rejected', 'ORA-20012', v_txt);

  canteen_pkg.verify_pickup(v_out, v_code, NULL, v_ven, v_n, v_token);
  SELECT status || CASE WHEN picked_up_at IS NOT NULL THEN '+time' END INTO v_txt FROM orders WHERE order_id = v_order;
  result('TC29', 'Typed code hands over the READY order', 'PICKED_UP+time', v_txt);

  BEGIN
    canteen_pkg.verify_pickup(v_out, v_code, v_order, v_ven, v_n, v_token);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC30', 'Same QR cannot be used twice', 'ORA-20005', v_txt);

  -- ---------- pickup slots ----------
  SELECT COUNT(*) INTO v_n FROM TABLE(canteen_pkg.get_slots(v_out, 6));
  result('TC31', 'Pipelined get_slots returns 6 slots', '6', TO_CHAR(v_n));

  UPDATE outlet SET slot_capacity = 1 WHERE outlet_id = v_out;
  COMMIT;
  SELECT MAX(slot_start) INTO v_slot FROM TABLE(canteen_pkg.get_slots(v_out, 6));
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":1}]', NULL, v_slot, NULL, v_order, v_token, v_total);
  SELECT booked || '/' || capacity INTO v_txt FROM pickup_slot WHERE outlet_id = v_out AND slot_start = v_slot;
  result('TC32', 'Slot booking counted by trigger', '1/1', v_txt);

  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":1}]', NULL, v_slot, NULL, v_n, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC33', 'Order in a full slot is rejected', 'ORA-20013', v_txt);

  SELECT available INTO v_n FROM TABLE(canteen_pkg.get_slots(v_out, 6)) WHERE slot_start = v_slot;
  result('TC34', 'get_slots shows the slot as full', '0', TO_CHAR(v_n));

  canteen_pkg.cancel_order(v_order, v_stu);
  SELECT booked INTO v_n FROM pickup_slot WHERE outlet_id = v_out AND slot_start = v_slot;
  result('TC35', 'Cancel frees the slot again', '0', TO_CHAR(v_n));

  BEGIN
    canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":1}]', NULL, v_slot + 7 / 1440, NULL, v_n, v_token, v_total);
    v_txt := 'no error';
  EXCEPTION WHEN OTHERS THEN v_txt := err(SQLCODE);
  END;
  result('TC36', 'Pickup time off the 15-min grid rejected', 'ORA-20011', v_txt);

  v_slot2 := canteen_pkg.next_available_slot(v_out);
  canteen_pkg.place_order(v_stu, v_out, '[{"item_id":' || v_i2 || ',"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
  SELECT pickup_slot INTO v_slot FROM orders WHERE order_id = v_order;
  result('TC37', 'ASAP order gets next free slot', TO_CHAR(v_slot2, 'HH24:MI'), TO_CHAR(v_slot, 'HH24:MI'));


  -- ---------- clean up ----------
  DELETE FROM wallet_txn WHERE user_id IN (v_stu, v_poor);
  DELETE FROM orders     WHERE outlet_id = v_out;
  DELETE FROM pickup_slot WHERE outlet_id = v_out;
  DELETE FROM outlet     WHERE outlet_id = v_out;
  DELETE FROM app_user   WHERE user_id IN (v_stu, v_poor, v_ven);
  COMMIT;
  canteen_pkg.generate_daily_summary(TRUNC(SYSDATE), v_n);

  DBMS_OUTPUT.PUT_LINE(RPAD('-', 110, '-'));
  DBMS_OUTPUT.PUT_LINE('Total: ' || (v_pass + v_fail) || '   Passed: ' || v_pass || '   Failed: ' || v_fail);
END;
/
EXIT
