-- =====================================================================
-- CampusBite : 03_package.sql
-- CANTEEN_PKG - all business operations used by the web application
-- =====================================================================

CREATE OR REPLACE PACKAGE canteen_pkg AS
  c_gst_rate   CONSTANT NUMBER := 0.05;   -- 5% GST on food
  c_max_topup  CONSTANT NUMBER := 5000;   -- per top-up limit

  -- error codes raised by this package
  --  -20001 user  -20002 outlet closed  -20003 empty cart  -20004 coupon
  --  -20005 status transition  -20006 cancel  -20007 amount
  --  -20008 not authorised  -20009 review  -20011 pickup time
  --  -20012 pickup code  -20013 slot full

  -- ---------- functions ----------
  FUNCTION get_wallet_balance (p_user_id NUMBER) RETURN NUMBER;
  FUNCTION outlet_is_open     (p_outlet_id NUMBER) RETURN VARCHAR2;
  FUNCTION is_open_at         (p_outlet_id NUMBER, p_when DATE) RETURN VARCHAR2;
  FUNCTION earliest_slot      (p_outlet_id NUMBER) RETURN DATE;
  FUNCTION next_available_slot (p_outlet_id NUMBER) RETURN DATE;
  FUNCTION get_slots          (p_outlet_id NUMBER, p_count NUMBER DEFAULT 12) RETURN t_slot_tab PIPELINED;
  FUNCTION calc_coupon_discount (p_code VARCHAR2, p_subtotal NUMBER) RETURN NUMBER;
  FUNCTION estimate_wait_minutes (p_outlet_id NUMBER) RETURN NUMBER;
  FUNCTION is_valid_transition (p_from VARCHAR2, p_to VARCHAR2) RETURN VARCHAR2;

  -- ---------- procedures ----------
  PROCEDURE topup_wallet (
    p_user_id  IN  NUMBER,
    p_amount   IN  NUMBER,
    p_remarks  IN  VARCHAR2 DEFAULT NULL,
    o_balance  OUT NUMBER);

  PROCEDURE place_order (
    p_user_id     IN  NUMBER,
    p_outlet_id   IN  NUMBER,
    p_cart_json   IN  CLOB,        -- [{"item_id":1,"qty":2}, ...]
    p_coupon      IN  VARCHAR2,
    p_pickup_slot IN  DATE,        -- NULL = earliest free slot
    p_notes       IN  VARCHAR2,
    o_order_id    OUT NUMBER,
    o_token_no    OUT NUMBER,
    o_total       OUT NUMBER);

  PROCEDURE verify_pickup (
    p_outlet_id IN  NUMBER,
    p_code      IN  VARCHAR2,
    p_order_id  IN  NUMBER,       -- from the QR; NULL when the code is typed
    p_actor_id  IN  NUMBER,
    o_order_id  OUT NUMBER,
    o_token_no  OUT NUMBER);

  PROCEDURE update_order_status (
    p_order_id   IN NUMBER,
    p_new_status IN VARCHAR2,
    p_actor_id   IN NUMBER);

  PROCEDURE cancel_order (
    p_order_id IN NUMBER,
    p_actor_id IN NUMBER);

  PROCEDURE add_review (
    p_order_id IN NUMBER,
    p_item_id  IN NUMBER,
    p_user_id  IN NUMBER,
    p_rating   IN NUMBER,
    p_comments IN VARCHAR2);

  PROCEDURE generate_daily_summary (
    p_date IN  DATE DEFAULT TRUNC(SYSDATE),
    o_rows OUT NUMBER);

  PROCEDURE get_low_stock (
    p_outlet_id IN  NUMBER,
    p_threshold IN  NUMBER,
    o_cur       OUT SYS_REFCURSOR);

  PROCEDURE get_top_items (
    p_outlet_id IN  NUMBER,
    p_days      IN  NUMBER,
    p_limit     IN  NUMBER,
    o_cur       OUT SYS_REFCURSOR);

  PROCEDURE get_sales_report (
    p_outlet_id IN  NUMBER,
    p_from      IN  DATE,
    p_to        IN  DATE,
    o_cur       OUT SYS_REFCURSOR);
END canteen_pkg;
/

CREATE OR REPLACE PACKAGE BODY canteen_pkg AS

  -- -------------------------------------------------------------------
  -- private helpers
  -- -------------------------------------------------------------------
  FUNCTION get_user (p_user_id NUMBER, p_lock BOOLEAN DEFAULT FALSE) RETURN app_user%ROWTYPE IS
    v_user app_user%ROWTYPE;
  BEGIN
    IF p_lock THEN
      SELECT * INTO v_user FROM app_user WHERE user_id = p_user_id FOR UPDATE;
    ELSE
      SELECT * INTO v_user FROM app_user WHERE user_id = p_user_id;
    END IF;
    IF v_user.is_active = 'N' THEN
      RAISE_APPLICATION_ERROR(-20001, 'User account is deactivated');
    END IF;
    RETURN v_user;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'User ' || p_user_id || ' not found');
  END get_user;

  -- may the actor manage orders of this outlet?
  FUNCTION can_manage (p_actor app_user%ROWTYPE, p_outlet_id NUMBER) RETURN BOOLEAN IS
    v_cnt NUMBER;
  BEGIN
    IF p_actor.role = 'ADMIN' THEN
      RETURN TRUE;
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM outlet
     WHERE outlet_id = p_outlet_id AND owner_id = p_actor.user_id;
    RETURN v_cnt > 0;
  END can_manage;

  -- refund, restore stock and mark the order cancelled
  PROCEDURE do_cancel (p_order orders%ROWTYPE, p_reason VARCHAR2) IS
    CURSOR c_lines IS
      SELECT item_id, qty FROM order_item WHERE order_id = p_order.order_id;
    v_balance app_user.wallet_balance%TYPE;
  BEGIN
    FOR r IN c_lines LOOP
      UPDATE menu_item SET stock_qty = stock_qty + r.qty WHERE item_id = r.item_id;
    END LOOP;

    IF p_order.total_amount > 0 THEN
      UPDATE app_user SET wallet_balance = wallet_balance + p_order.total_amount
       WHERE user_id = p_order.user_id
       RETURNING wallet_balance INTO v_balance;

      INSERT INTO wallet_txn (user_id, txn_type, amount, balance_after, order_id, remarks)
      VALUES (p_order.user_id, 'REFUND', p_order.total_amount, v_balance, p_order.order_id, p_reason);
    END IF;

    IF p_order.coupon_code IS NOT NULL THEN
      UPDATE coupon SET used_count = GREATEST(used_count - 1, 0) WHERE code = p_order.coupon_code;
    END IF;

    UPDATE orders SET status = 'CANCELLED' WHERE order_id = p_order.order_id;
  END do_cancel;

  -- -------------------------------------------------------------------
  -- F1. current wallet balance
  -- -------------------------------------------------------------------
  FUNCTION get_wallet_balance (p_user_id NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN get_user(p_user_id).wallet_balance;
  END get_wallet_balance;

  -- -------------------------------------------------------------------
  -- F2. 'Y' when the outlet is switched on and inside its working hours
  --     (supports hours that run past midnight, e.g. 18:00 - 02:00)
  -- -------------------------------------------------------------------
  FUNCTION outlet_is_open (p_outlet_id NUMBER) RETURN VARCHAR2 IS
    v_flag outlet.is_open%TYPE;
  BEGIN
    SELECT is_open INTO v_flag FROM outlet WHERE outlet_id = p_outlet_id;
    RETURN CASE WHEN v_flag = 'Y' THEN is_open_at(p_outlet_id, SYSDATE) ELSE 'N' END;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN 'N';
  END outlet_is_open;

  -- -------------------------------------------------------------------
  -- F2b. is a given moment inside the outlet's working hours?
  -- -------------------------------------------------------------------
  FUNCTION is_open_at (p_outlet_id NUMBER, p_when DATE) RETURN VARCHAR2 IS
    v_open  outlet.open_time%TYPE;
    v_close outlet.close_time%TYPE;
    v_at    VARCHAR2(5) := TO_CHAR(p_when, 'HH24:MI');
  BEGIN
    SELECT open_time, close_time INTO v_open, v_close FROM outlet WHERE outlet_id = p_outlet_id;
    IF v_open <= v_close THEN
      RETURN CASE WHEN v_at BETWEEN v_open AND v_close THEN 'Y' ELSE 'N' END;
    ELSE
      RETURN CASE WHEN v_at >= v_open OR v_at <= v_close THEN 'Y' ELSE 'N' END;
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN 'N';
  END is_open_at;

  -- -------------------------------------------------------------------
  -- F3. discount for a coupon (raises -20004 when not applicable)
  -- -------------------------------------------------------------------
  FUNCTION calc_coupon_discount (p_code VARCHAR2, p_subtotal NUMBER) RETURN NUMBER IS
    v_c coupon%ROWTYPE;
  BEGIN
    IF p_code IS NULL THEN
      RETURN 0;
    END IF;

    SELECT * INTO v_c FROM coupon WHERE code = UPPER(TRIM(p_code));

    IF TRUNC(SYSDATE) NOT BETWEEN v_c.valid_from AND v_c.valid_to THEN
      RAISE_APPLICATION_ERROR(-20004, 'Coupon ' || v_c.code || ' has expired');
    ELSIF v_c.used_count >= v_c.usage_limit THEN
      RAISE_APPLICATION_ERROR(-20004, 'Coupon ' || v_c.code || ' usage limit reached');
    ELSIF p_subtotal < v_c.min_order THEN
      RAISE_APPLICATION_ERROR(-20004, 'Coupon ' || v_c.code || ' needs a minimum order of Rs.' || v_c.min_order);
    END IF;

    RETURN LEAST(ROUND(p_subtotal * v_c.discount_pct / 100, 2), v_c.max_discount);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20004, 'Invalid coupon code');
  END calc_coupon_discount;

  -- -------------------------------------------------------------------
  -- F4. estimated wait for a new order, using a cursor over the queue:
  --     each queued order needs as long as its slowest dish, and the
  --     kitchen works on PARALLEL_SLOTS orders at the same time.
  -- -------------------------------------------------------------------
  FUNCTION estimate_wait_minutes (p_outlet_id NUMBER) RETURN NUMBER IS
    CURSOR c_queue IS
      SELECT o.order_id, o.status, MAX(m.prep_minutes) AS prep
        FROM orders o
        JOIN order_item oi ON oi.order_id = o.order_id
        JOIN menu_item  m  ON m.item_id   = oi.item_id
       WHERE o.outlet_id = p_outlet_id
         AND o.status IN ('PLACED','ACCEPTED','PREPARING')
       GROUP BY o.order_id, o.status;
    v_total  NUMBER := 0;
    v_slots  outlet.parallel_slots%TYPE;
  BEGIN
    SELECT parallel_slots INTO v_slots FROM outlet WHERE outlet_id = p_outlet_id;

    FOR q IN c_queue LOOP
      -- an order already being prepared is assumed half done
      v_total := v_total + CASE WHEN q.status = 'PREPARING' THEN q.prep / 2 ELSE q.prep END;
    END LOOP;

    RETURN GREATEST(5, CEIL(v_total / v_slots) + 5);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END estimate_wait_minutes;

  -- -------------------------------------------------------------------
  -- F6. first 15-minute slot the kitchen can realistically meet
  -- -------------------------------------------------------------------
  FUNCTION earliest_slot (p_outlet_id NUMBER) RETURN DATE IS
    v_ready DATE := SYSDATE + NVL(estimate_wait_minutes(p_outlet_id), 10) / 1440;
    v_hour  DATE := TRUNC(v_ready, 'HH24');
  BEGIN
    RETURN v_hour + CEIL(ROUND((v_ready - v_hour) * 1440, 4) / 15) * 15 / 1440;
  END earliest_slot;

  -- -------------------------------------------------------------------
  -- F7. pipelined table function: the next open slots and free places
  --     SELECT * FROM TABLE(canteen_pkg.get_slots(1, 8));
  -- -------------------------------------------------------------------
  FUNCTION get_slots (p_outlet_id NUMBER, p_count NUMBER DEFAULT 12) RETURN t_slot_tab PIPELINED IS
    v_slot    DATE := earliest_slot(p_outlet_id);
    v_cap     NUMBER;
    v_booked  NUMBER;
    v_default outlet.slot_capacity%TYPE;
    v_sent    PLS_INTEGER := 0;
  BEGIN
    SELECT slot_capacity INTO v_default FROM outlet WHERE outlet_id = p_outlet_id;

    FOR k IN 0 .. 95 LOOP                       -- look at most 24 hours ahead
      EXIT WHEN v_sent >= NVL(p_count, 12);
      IF is_open_at(p_outlet_id, v_slot) = 'Y' THEN
        BEGIN
          SELECT capacity, booked INTO v_cap, v_booked
            FROM pickup_slot WHERE outlet_id = p_outlet_id AND slot_start = v_slot;
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            v_cap := v_default;
            v_booked := 0;
        END;
        PIPE ROW (t_slot_row(v_slot, v_cap, v_booked, v_cap - v_booked));
        v_sent := v_sent + 1;
      END IF;
      v_slot := v_slot + 15 / 1440;
    END LOOP;
    RETURN;
  END get_slots;

  -- -------------------------------------------------------------------
  -- F8. earliest slot that still has a free place (NULL if none)
  -- -------------------------------------------------------------------
  FUNCTION next_available_slot (p_outlet_id NUMBER) RETURN DATE IS
    v_slot DATE;
  BEGIN
    SELECT MIN(slot_start) INTO v_slot
      FROM TABLE(get_slots(p_outlet_id, 96))
     WHERE available > 0;
    RETURN v_slot;
  END next_available_slot;

  -- -------------------------------------------------------------------
  -- F5. order life-cycle rules
  --     PLACED -> ACCEPTED -> PREPARING -> READY -> PICKED_UP
  --     PLACED / ACCEPTED -> CANCELLED
  -- -------------------------------------------------------------------
  FUNCTION is_valid_transition (p_from VARCHAR2, p_to VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE
      WHEN p_from = 'PLACED'    AND p_to IN ('ACCEPTED','CANCELLED')  THEN 'Y'
      WHEN p_from = 'ACCEPTED'  AND p_to IN ('PREPARING','CANCELLED') THEN 'Y'
      WHEN p_from = 'PREPARING' AND p_to = 'READY'                    THEN 'Y'
      WHEN p_from = 'READY'     AND p_to = 'PICKED_UP'                THEN 'Y'
      ELSE 'N'
    END;
  END is_valid_transition;

  -- -------------------------------------------------------------------
  -- P1. add money to the wallet
  -- -------------------------------------------------------------------
  PROCEDURE topup_wallet (
    p_user_id  IN  NUMBER,
    p_amount   IN  NUMBER,
    p_remarks  IN  VARCHAR2 DEFAULT NULL,
    o_balance  OUT NUMBER)
  IS
    v_user app_user%ROWTYPE;
  BEGIN
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > c_max_topup THEN
      RAISE_APPLICATION_ERROR(-20007, 'Top-up amount must be between Rs.1 and Rs.' || c_max_topup);
    END IF;

    v_user := get_user(p_user_id, TRUE);

    UPDATE app_user SET wallet_balance = wallet_balance + ROUND(p_amount, 2)
     WHERE user_id = p_user_id
     RETURNING wallet_balance INTO o_balance;

    INSERT INTO wallet_txn (user_id, txn_type, amount, balance_after, remarks)
    VALUES (p_user_id, 'TOPUP', ROUND(p_amount, 2), o_balance, NVL(p_remarks, 'Wallet top-up'));
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END topup_wallet;

  -- -------------------------------------------------------------------
  -- P2. place a pre-order paid from the wallet
  --     The cart arrives as JSON and is read through an explicit
  --     parameterised cursor over JSON_TABLE. Triggers on ORDER_ITEM
  --     price each line and deduct stock; one failure undoes it all.
  -- -------------------------------------------------------------------
  PROCEDURE place_order (
    p_user_id     IN  NUMBER,
    p_outlet_id   IN  NUMBER,
    p_cart_json   IN  CLOB,
    p_coupon      IN  VARCHAR2,
    p_pickup_slot IN  DATE,
    p_notes       IN  VARCHAR2,
    o_order_id    OUT NUMBER,
    o_token_no    OUT NUMBER,
    o_total       OUT NUMBER)
  IS
    CURSOR c_cart (cp_json CLOB) IS
      SELECT jt.item_id, SUM(jt.qty) AS qty
        FROM JSON_TABLE(cp_json, '$[*]'
               COLUMNS (item_id NUMBER PATH '$.item_id',
                        qty     NUMBER PATH '$.qty')) jt
       WHERE jt.item_id IS NOT NULL
       GROUP BY jt.item_id;

    v_line      c_cart%ROWTYPE;
    v_user      app_user%ROWTYPE;
    v_lines     PLS_INTEGER := 0;
    v_subtotal  NUMBER;
    v_discount  NUMBER;
    v_tax       NUMBER;
    v_balance   NUMBER;
    v_coupon    coupon.code%TYPE := UPPER(TRIM(p_coupon));
    v_slot      DATE;
  BEGIN
    SAVEPOINT sp_place_order;

    v_user := get_user(p_user_id, TRUE);

    -- a paused outlet takes no orders; outside working hours students can
    -- still pre-order for a slot after opening (checked below)
    SELECT COUNT(*) INTO v_lines FROM outlet WHERE outlet_id = p_outlet_id AND is_open = 'Y';
    IF v_lines = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'This outlet is not taking orders right now');
    END IF;

    IF p_pickup_slot IS NULL THEN
      v_slot := next_available_slot(p_outlet_id);
      IF v_slot IS NULL THEN
        RAISE_APPLICATION_ERROR(-20013, 'All pickup slots are full - please try again later');
      END IF;
    ELSE
      v_slot := p_pickup_slot;
      IF MOD(TO_NUMBER(TO_CHAR(v_slot, 'MI')), 15) <> 0 OR TO_CHAR(v_slot, 'SS') <> '00' THEN
        RAISE_APPLICATION_ERROR(-20011, 'Pickup time must be a 15-minute slot');
      ELSIF v_slot <= SYSDATE OR v_slot > SYSDATE + 1 THEN
        RAISE_APPLICATION_ERROR(-20011, 'Pickup time must be within the next 24 hours');
      ELSIF is_open_at(p_outlet_id, v_slot) = 'N' THEN
        RAISE_APPLICATION_ERROR(-20011, 'The outlet is closed at ' || TO_CHAR(v_slot, 'HH:MI AM'));
      END IF;
    END IF;

    -- TRG_ORDER_SLOT books the slot (ORA-20013 when it is full)
    INSERT INTO orders (user_id, outlet_id, status, pickup_slot, notes)
    VALUES (p_user_id, p_outlet_id, 'PLACED', v_slot, SUBSTR(p_notes, 1, 200))
    RETURNING order_id, token_no INTO o_order_id, o_token_no;

    OPEN c_cart(p_cart_json);
    LOOP
      FETCH c_cart INTO v_line;
      EXIT WHEN c_cart%NOTFOUND;
      -- unit_price and line_total are filled by TRG_ORDER_ITEM_STOCK
      INSERT INTO order_item (order_id, item_id, qty, unit_price, line_total)
      VALUES (o_order_id, v_line.item_id, v_line.qty, 0, 0);
    END LOOP;
    v_lines := c_cart%ROWCOUNT;
    CLOSE c_cart;

    IF v_lines = 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Cart is empty');
    END IF;

    SELECT SUM(line_total) INTO v_subtotal FROM order_item WHERE order_id = o_order_id;

    v_discount := calc_coupon_discount(v_coupon, v_subtotal);
    IF v_discount > 0 THEN
      UPDATE coupon SET used_count = used_count + 1 WHERE code = v_coupon;
    END IF;

    v_tax   := ROUND((v_subtotal - v_discount) * c_gst_rate, 2);
    o_total := v_subtotal - v_discount + v_tax;

    UPDATE orders
       SET subtotal = v_subtotal, discount = v_discount, tax = v_tax,
           total_amount = o_total,
           coupon_code = CASE WHEN v_discount > 0 THEN v_coupon END
     WHERE order_id = o_order_id;

    -- TRG_WALLET_GUARD stops the order if the balance is too low
    UPDATE app_user SET wallet_balance = wallet_balance - o_total
     WHERE user_id = p_user_id
     RETURNING wallet_balance INTO v_balance;

    INSERT INTO wallet_txn (user_id, txn_type, amount, balance_after, order_id, remarks)
    VALUES (p_user_id, 'DEBIT', o_total, v_balance, o_order_id, 'Order #' || o_order_id);

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      IF c_cart%ISOPEN THEN
        CLOSE c_cart;
      END IF;
      ROLLBACK TO sp_place_order;
      o_order_id := NULL;
      o_token_no := NULL;
      o_total    := NULL;
      RAISE;
  END place_order;

  -- -------------------------------------------------------------------
  -- P3. vendor moves an order through its life-cycle
  -- -------------------------------------------------------------------
  PROCEDURE update_order_status (
    p_order_id   IN NUMBER,
    p_new_status IN VARCHAR2,
    p_actor_id   IN NUMBER)
  IS
    v_order orders%ROWTYPE;
    v_actor app_user%ROWTYPE;
    v_new   orders.status%TYPE := UPPER(p_new_status);
  BEGIN
    v_actor := get_user(p_actor_id);

    BEGIN
      SELECT * INTO v_order FROM orders WHERE order_id = p_order_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20008, 'Order ' || p_order_id || ' not found');
    END;

    IF NOT can_manage(v_actor, v_order.outlet_id) THEN
      RAISE_APPLICATION_ERROR(-20008, 'You do not manage this outlet');
    END IF;

    IF is_valid_transition(v_order.status, v_new) = 'N' THEN
      RAISE_APPLICATION_ERROR(-20005, 'Cannot move order from ' || v_order.status || ' to ' || v_new);
    ELSIF v_new = 'PICKED_UP' THEN
      RAISE_APPLICATION_ERROR(-20012, 'Scan the student''s pickup QR code to hand over the order');
    END IF;

    IF v_new = 'CANCELLED' THEN
      do_cancel(v_order, 'Cancelled by outlet, order #' || p_order_id);
    ELSE
      UPDATE orders SET status = v_new WHERE order_id = p_order_id;
    END IF;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END update_order_status;

  -- -------------------------------------------------------------------
  -- P3b. hand-over: the vendor scans the student's QR (order id + code)
  --      or types the 6-digit code; only a READY order is released.
  -- -------------------------------------------------------------------
  PROCEDURE verify_pickup (
    p_outlet_id IN  NUMBER,
    p_code      IN  VARCHAR2,
    p_order_id  IN  NUMBER,
    p_actor_id  IN  NUMBER,
    o_order_id  OUT NUMBER,
    o_token_no  OUT NUMBER)
  IS
    v_actor app_user%ROWTYPE;
    v_order orders%ROWTYPE;
    v_code  orders.pickup_code%TYPE := TRIM(p_code);
  BEGIN
    v_actor := get_user(p_actor_id);
    IF NOT can_manage(v_actor, p_outlet_id) THEN
      RAISE_APPLICATION_ERROR(-20008, 'You do not manage this outlet');
    END IF;

    BEGIN
      IF p_order_id IS NOT NULL THEN
        SELECT * INTO v_order FROM orders WHERE order_id = p_order_id FOR UPDATE;
      ELSE
        SELECT * INTO v_order FROM orders
         WHERE outlet_id = p_outlet_id AND pickup_code = v_code AND status = 'READY'
           AND ROWNUM = 1
           FOR UPDATE;
      END IF;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20012, 'No ready order found for this pickup code');
    END;

    IF v_order.outlet_id <> p_outlet_id THEN
      RAISE_APPLICATION_ERROR(-20012, 'This QR code belongs to an order at another outlet');
    ELSIF v_order.pickup_code <> v_code OR v_code IS NULL THEN
      RAISE_APPLICATION_ERROR(-20012, 'Pickup code does not match this order');
    ELSIF v_order.status = 'PICKED_UP' THEN
      RAISE_APPLICATION_ERROR(-20005, 'Token ' || v_order.token_no || ' was already handed over');
    ELSIF v_order.status <> 'READY' THEN
      RAISE_APPLICATION_ERROR(-20005, 'Token ' || v_order.token_no || ' is not ready yet (' || v_order.status || ')');
    END IF;

    UPDATE orders SET status = 'PICKED_UP', picked_up_at = SYSTIMESTAMP
     WHERE order_id = v_order.order_id;

    o_order_id := v_order.order_id;
    o_token_no := v_order.token_no;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END verify_pickup;

  -- -------------------------------------------------------------------
  -- P4. cancel with full refund. Students may cancel only while the
  --     order is PLACED; the outlet may also cancel an ACCEPTED order.
  -- -------------------------------------------------------------------
  PROCEDURE cancel_order (
    p_order_id IN NUMBER,
    p_actor_id IN NUMBER)
  IS
    v_order orders%ROWTYPE;
    v_actor app_user%ROWTYPE;
  BEGIN
    v_actor := get_user(p_actor_id);

    BEGIN
      SELECT * INTO v_order FROM orders WHERE order_id = p_order_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20008, 'Order ' || p_order_id || ' not found');
    END;

    IF v_order.user_id = p_actor_id THEN
      IF v_order.status <> 'PLACED' THEN
        RAISE_APPLICATION_ERROR(-20006, 'The outlet has already accepted this order; it can no longer be cancelled');
      END IF;
      do_cancel(v_order, 'Cancelled by student, order #' || p_order_id);
    ELSIF can_manage(v_actor, v_order.outlet_id) THEN
      IF is_valid_transition(v_order.status, 'CANCELLED') = 'N' THEN
        RAISE_APPLICATION_ERROR(-20006, 'An order in status ' || v_order.status || ' cannot be cancelled');
      END IF;
      do_cancel(v_order, 'Cancelled by outlet, order #' || p_order_id);
    ELSE
      RAISE_APPLICATION_ERROR(-20008, 'You cannot cancel this order');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END cancel_order;

  -- -------------------------------------------------------------------
  -- P5. rate an item from a picked-up order
  -- -------------------------------------------------------------------
  PROCEDURE add_review (
    p_order_id IN NUMBER,
    p_item_id  IN NUMBER,
    p_user_id  IN NUMBER,
    p_rating   IN NUMBER,
    p_comments IN VARCHAR2)
  IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt
      FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
     WHERE o.order_id = p_order_id AND oi.item_id = p_item_id
       AND o.user_id = p_user_id AND o.status = 'PICKED_UP';

    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(-20009, 'You can rate only items from orders you have picked up');
    END IF;

    INSERT INTO review (order_id, item_id, user_id, rating, comments)
    VALUES (p_order_id, p_item_id, p_user_id, p_rating, SUBSTR(p_comments, 1, 300));
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20009, 'You have already rated this item for this order');
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END add_review;

  -- -------------------------------------------------------------------
  -- P6. end-of-day summary for every outlet (explicit cursor with
  --     OPEN / FETCH / CLOSE and the %NOTFOUND / %ROWCOUNT attributes)
  -- -------------------------------------------------------------------
  PROCEDURE generate_daily_summary (
    p_date IN  DATE DEFAULT TRUNC(SYSDATE),
    o_rows OUT NUMBER)
  IS
    CURSOR c_outlets IS
      SELECT outlet_id, name FROM outlet ORDER BY outlet_id;

    v_outlet     c_outlets%ROWTYPE;
    v_day        DATE := TRUNC(p_date);
    v_orders     NUMBER;
    v_cancelled  NUMBER;
    v_items      NUMBER;
    v_revenue    NUMBER;
    v_top_item   NUMBER;
  BEGIN
    OPEN c_outlets;
    LOOP
      FETCH c_outlets INTO v_outlet;
      EXIT WHEN c_outlets%NOTFOUND;

      SELECT COUNT(*),
             COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END),
             NVL(SUM(CASE WHEN status <> 'CANCELLED' THEN total_amount END), 0)
        INTO v_orders, v_cancelled, v_revenue
        FROM orders
       WHERE outlet_id = v_outlet.outlet_id
         AND placed_at >= v_day AND placed_at < v_day + 1;

      SELECT NVL(SUM(oi.qty), 0) INTO v_items
        FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
       WHERE o.outlet_id = v_outlet.outlet_id AND o.status <> 'CANCELLED'
         AND o.placed_at >= v_day AND o.placed_at < v_day + 1;

      BEGIN
        SELECT item_id INTO v_top_item FROM (
          SELECT oi.item_id, SUM(oi.qty) AS q
            FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
           WHERE o.outlet_id = v_outlet.outlet_id AND o.status <> 'CANCELLED'
             AND o.placed_at >= v_day AND o.placed_at < v_day + 1
           GROUP BY oi.item_id
           ORDER BY q DESC, oi.item_id)
         WHERE ROWNUM = 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN v_top_item := NULL;
      END;

      MERGE INTO daily_sales_summary d
      USING (SELECT v_day AS summary_date, v_outlet.outlet_id AS outlet_id FROM dual) s
         ON (d.summary_date = s.summary_date AND d.outlet_id = s.outlet_id)
       WHEN MATCHED THEN UPDATE SET
            total_orders = v_orders, cancelled_orders = v_cancelled, items_sold = v_items,
            gross_revenue = v_revenue, top_item_id = v_top_item, generated_at = SYSTIMESTAMP
       WHEN NOT MATCHED THEN INSERT
            (summary_date, outlet_id, total_orders, cancelled_orders, items_sold, gross_revenue, top_item_id)
            VALUES (v_day, v_outlet.outlet_id, v_orders, v_cancelled, v_items, v_revenue, v_top_item);

      DBMS_OUTPUT.PUT_LINE(RPAD(v_outlet.name, 25) || ' orders=' || v_orders ||
                           ' items=' || v_items || ' revenue=' || v_revenue);
    END LOOP;
    o_rows := c_outlets%ROWCOUNT;
    CLOSE c_outlets;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      IF c_outlets%ISOPEN THEN
        CLOSE c_outlets;
      END IF;
      ROLLBACK;
      RAISE;
  END generate_daily_summary;

  -- -------------------------------------------------------------------
  -- P7. REF CURSOR: items at or below a stock threshold
  -- -------------------------------------------------------------------
  PROCEDURE get_low_stock (
    p_outlet_id IN  NUMBER,
    p_threshold IN  NUMBER,
    o_cur       OUT SYS_REFCURSOR)
  IS
  BEGIN
    OPEN o_cur FOR
      SELECT m.item_id, m.name, o.name AS outlet_name, m.stock_qty, m.is_available
        FROM menu_item m JOIN outlet o ON o.outlet_id = m.outlet_id
       WHERE (p_outlet_id IS NULL OR m.outlet_id = p_outlet_id)
         AND m.stock_qty <= NVL(p_threshold, 5)
       ORDER BY m.stock_qty, m.name;
  END get_low_stock;

  -- -------------------------------------------------------------------
  -- P8. REF CURSOR: best sellers over the last N days
  -- -------------------------------------------------------------------
  PROCEDURE get_top_items (
    p_outlet_id IN  NUMBER,
    p_days      IN  NUMBER,
    p_limit     IN  NUMBER,
    o_cur       OUT SYS_REFCURSOR)
  IS
  BEGIN
    OPEN o_cur FOR
      SELECT m.item_id, m.name, SUM(oi.qty) AS qty_sold,
             SUM(oi.line_total) AS revenue, m.rating_avg
        FROM orders o
        JOIN order_item oi ON oi.order_id = o.order_id
        JOIN menu_item  m  ON m.item_id   = oi.item_id
       WHERE (p_outlet_id IS NULL OR o.outlet_id = p_outlet_id)
         AND o.status <> 'CANCELLED'
         AND o.placed_at >= TRUNC(SYSDATE) - NVL(p_days, 7) + 1
       GROUP BY m.item_id, m.name, m.rating_avg
       ORDER BY qty_sold DESC, revenue DESC
       FETCH FIRST NVL(p_limit, 5) ROWS ONLY;
  END get_top_items;

  -- -------------------------------------------------------------------
  -- P9. REF CURSOR: day-wise sales between two dates
  -- -------------------------------------------------------------------
  PROCEDURE get_sales_report (
    p_outlet_id IN  NUMBER,
    p_from      IN  DATE,
    p_to        IN  DATE,
    o_cur       OUT SYS_REFCURSOR)
  IS
  BEGIN
    OPEN o_cur FOR
      SELECT TRUNC(o.placed_at) AS sale_date,
             COUNT(*) AS orders,
             SUM(o.subtotal) AS subtotal,
             SUM(o.discount) AS discount,
             SUM(o.tax) AS tax,
             SUM(o.total_amount) AS revenue
        FROM orders o
       WHERE (p_outlet_id IS NULL OR o.outlet_id = p_outlet_id)
         AND o.status <> 'CANCELLED'
         AND o.placed_at >= TRUNC(p_from) AND o.placed_at < TRUNC(p_to) + 1
       GROUP BY TRUNC(o.placed_at)
       ORDER BY sale_date;
  END get_sales_report;

END canteen_pkg;
/

-- ---------------------------------------------------------------------
-- Views used by the application
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_menu AS
SELECT m.item_id, m.outlet_id, o.name AS outlet_name, m.category_id, c.name AS category,
       m.name, m.description, m.price, m.is_veg, m.stock_qty, m.prep_minutes,
       m.is_available, m.rating_avg, m.rating_count, m.image_url
  FROM menu_item m
  JOIN outlet   o ON o.outlet_id   = m.outlet_id
  JOIN category c ON c.category_id = m.category_id;

CREATE OR REPLACE VIEW v_order_details AS
SELECT o.order_id, o.token_no, o.pickup_code, o.status, o.user_id, u.full_name AS customer, u.reg_no,
       o.outlet_id, ot.name AS outlet_name, o.subtotal, o.discount, o.tax, o.total_amount,
       o.coupon_code, o.pickup_slot, o.notes, o.placed_at, o.updated_at, o.picked_up_at,
       ot.cover_url,
       (SELECT LISTAGG(m.name || ' x' || oi.qty, ', ') WITHIN GROUP (ORDER BY m.name)
          FROM order_item oi JOIN menu_item m ON m.item_id = oi.item_id
         WHERE oi.order_id = o.order_id) AS items_text
  FROM orders o
  JOIN app_user u ON u.user_id   = o.user_id
  JOIN outlet  ot ON ot.outlet_id = o.outlet_id;
