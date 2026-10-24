-- =====================================================================
-- CampusBite : 02_triggers.sql
-- Business rules enforced inside the database
-- =====================================================================

-- ---------------------------------------------------------------------
-- T1. TRG_ORDER_TOKEN
-- Assigns a pickup token that restarts at 1 every day for each outlet,
-- and a secret 6-digit pickup code that the student shows as a QR.
-- A separate counter table avoids the mutating-table problem and the
-- row lock on it serialises concurrent orders at the same outlet.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_order_token
BEFORE INSERT ON orders
FOR EACH ROW
DECLARE
  v_token token_counter.last_token%TYPE;
BEGIN
  MERGE INTO token_counter tc
  USING (SELECT :NEW.outlet_id AS outlet_id, TRUNC(SYSDATE) AS token_date FROM dual) src
     ON (tc.outlet_id = src.outlet_id AND tc.token_date = src.token_date)
   WHEN MATCHED THEN UPDATE SET tc.last_token = tc.last_token + 1
   WHEN NOT MATCHED THEN INSERT (outlet_id, token_date, last_token)
                         VALUES (src.outlet_id, src.token_date, 1);

  SELECT last_token INTO v_token
    FROM token_counter
   WHERE outlet_id = :NEW.outlet_id AND token_date = TRUNC(SYSDATE);

  :NEW.token_no    := v_token;
  :NEW.pickup_code := LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 1000000)), 6, '0');
  :NEW.placed_at   := SYSTIMESTAMP;
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- ---------------------------------------------------------------------
-- T2. TRG_ORDER_ITEM_STOCK
-- Before an order line is saved: takes the price from the menu (so a
-- client cannot tamper with it), checks availability, outlet match and
-- stock, then deducts the stock.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_order_item_stock
BEFORE INSERT ON order_item
FOR EACH ROW
DECLARE
  v_item        menu_item%ROWTYPE;
  v_outlet_id   orders.outlet_id%TYPE;
BEGIN
  SELECT * INTO v_item FROM menu_item WHERE item_id = :NEW.item_id FOR UPDATE;
  SELECT outlet_id INTO v_outlet_id FROM orders WHERE order_id = :NEW.order_id;

  IF v_item.outlet_id <> v_outlet_id THEN
    RAISE_APPLICATION_ERROR(-20021, 'Item "' || v_item.name || '" is not sold at this outlet');
  END IF;
  IF v_item.is_available = 'N' THEN
    RAISE_APPLICATION_ERROR(-20022, 'Item "' || v_item.name || '" is currently unavailable');
  END IF;
  IF v_item.stock_qty < :NEW.qty THEN
    RAISE_APPLICATION_ERROR(-20023, 'Only ' || v_item.stock_qty || ' left of "' || v_item.name || '"');
  END IF;

  :NEW.unit_price := v_item.price;
  :NEW.line_total := v_item.price * :NEW.qty;

  UPDATE menu_item SET stock_qty = stock_qty - :NEW.qty WHERE item_id = :NEW.item_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20020, 'Menu item ' || :NEW.item_id || ' does not exist');
END;
/

-- ---------------------------------------------------------------------
-- T3. TRG_MENU_STOCK_WATCH
-- Auto-hides sold-out items, re-lists them when stock returns, and
-- raises a stock alert when stock drops to 5 or below.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_menu_stock_watch
BEFORE UPDATE OF stock_qty ON menu_item
FOR EACH ROW
BEGIN
  IF :NEW.stock_qty = 0 THEN
    :NEW.is_available := 'N';
  ELSIF :OLD.stock_qty = 0 AND :NEW.stock_qty > 0 THEN
    :NEW.is_available := 'Y';
  END IF;

  IF :NEW.stock_qty <= 5 AND :OLD.stock_qty > 5 THEN
    INSERT INTO stock_alert (item_id, stock_qty) VALUES (:NEW.item_id, :NEW.stock_qty);
  ELSIF :NEW.stock_qty > 5 THEN
    UPDATE stock_alert SET is_resolved = 'Y'
     WHERE item_id = :NEW.item_id AND is_resolved = 'N';
  END IF;
END;
/

-- ---------------------------------------------------------------------
-- T4. TRG_MENU_PRICE_AUDIT
-- Keeps a history of every price change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_menu_price_audit
AFTER UPDATE OF price ON menu_item
FOR EACH ROW
WHEN (OLD.price <> NEW.price)
BEGIN
  INSERT INTO price_history (item_id, old_price, new_price)
  VALUES (:NEW.item_id, :OLD.price, :NEW.price);
END;
/

-- ---------------------------------------------------------------------
-- T5. TRG_ORDER_STATUS_AUDIT
-- Logs every status change and stamps updated_at.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_order_status_audit
FOR INSERT OR UPDATE OF status ON orders
COMPOUND TRIGGER
  BEFORE EACH ROW IS
  BEGIN
    IF UPDATING THEN
      :NEW.updated_at := SYSTIMESTAMP;
    END IF;
  END BEFORE EACH ROW;

  AFTER EACH ROW IS
  BEGIN
    IF INSERTING THEN
      INSERT INTO order_status_log (order_id, old_status, new_status)
      VALUES (:NEW.order_id, NULL, :NEW.status);
    ELSIF :OLD.status <> :NEW.status THEN
      INSERT INTO order_status_log (order_id, old_status, new_status)
      VALUES (:NEW.order_id, :OLD.status, :NEW.status);
    END IF;
  END AFTER EACH ROW;
END trg_order_status_audit;
/

-- ---------------------------------------------------------------------
-- T6. TRG_LOYALTY_POINTS
-- 1 loyalty point for every Rs.10 spent, credited on pickup.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_loyalty_points
AFTER UPDATE OF status ON orders
FOR EACH ROW
WHEN (NEW.status = 'PICKED_UP' AND OLD.status <> 'PICKED_UP')
BEGIN
  UPDATE app_user
     SET loyalty_points = loyalty_points + FLOOR(:NEW.total_amount / 10)
   WHERE user_id = :NEW.user_id;
END;
/

-- ---------------------------------------------------------------------
-- T7. TRG_WALLET_GUARD
-- Friendly error instead of a raw CHECK violation when the wallet
-- would go negative.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_wallet_guard
BEFORE UPDATE OF wallet_balance ON app_user
FOR EACH ROW
BEGIN
  IF :NEW.wallet_balance < 0 THEN
    RAISE_APPLICATION_ERROR(-20010,
      'Insufficient wallet balance: available Rs.' || TO_CHAR(:OLD.wallet_balance, 'FM99999990.00') ||
      ', required Rs.' || TO_CHAR(:OLD.wallet_balance - :NEW.wallet_balance, 'FM99999990.00'));
  END IF;
END;
/

-- ---------------------------------------------------------------------
-- T8. TRG_REVIEW_RATING
-- Maintains the running average rating of a menu item.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_review_rating
AFTER INSERT ON review
FOR EACH ROW
BEGIN
  UPDATE menu_item
     SET rating_avg   = ROUND((rating_avg * rating_count + :NEW.rating) / (rating_count + 1), 2),
         rating_count = rating_count + 1
   WHERE item_id = :NEW.item_id;
END;
/

-- ---------------------------------------------------------------------
-- T9. TRG_ORDER_SLOT
-- Books a place in the 15-minute pickup slot (creating the slot row on
-- first use), moves the booking when the slot changes and releases it
-- when the order is cancelled. A full slot raises ORA-20013.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_order_slot
BEFORE INSERT OR UPDATE OF pickup_slot, status ON orders
FOR EACH ROW
DECLARE
  PROCEDURE book (p_outlet NUMBER, p_slot DATE) IS
  BEGIN
    IF p_slot IS NULL THEN
      RETURN;
    END IF;
    MERGE INTO pickup_slot s
    USING (SELECT outlet_id, slot_capacity FROM outlet WHERE outlet_id = p_outlet) o
       ON (s.outlet_id = o.outlet_id AND s.slot_start = p_slot)
     WHEN NOT MATCHED THEN INSERT (outlet_id, slot_start, capacity, booked)
                           VALUES (o.outlet_id, p_slot, o.slot_capacity, 0);

    UPDATE pickup_slot SET booked = booked + 1
     WHERE outlet_id = p_outlet AND slot_start = p_slot AND booked < capacity;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20013,
        'The ' || TO_CHAR(p_slot, 'HH:MI AM') || ' pickup slot is full - please choose another time');
    END IF;
  END;

  PROCEDURE release (p_outlet NUMBER, p_slot DATE) IS
  BEGIN
    UPDATE pickup_slot SET booked = booked - 1
     WHERE outlet_id = p_outlet AND slot_start = p_slot AND booked > 0;
  END;
BEGIN
  IF INSERTING THEN
    IF :NEW.status <> 'CANCELLED' THEN
      book(:NEW.outlet_id, :NEW.pickup_slot);
    END IF;
  ELSIF :OLD.status <> 'CANCELLED' AND :NEW.status = 'CANCELLED' THEN
    release(:OLD.outlet_id, :OLD.pickup_slot);
  ELSIF :NEW.status <> 'CANCELLED'
        AND (:OLD.pickup_slot <> :NEW.pickup_slot
             OR (:OLD.pickup_slot IS NULL AND :NEW.pickup_slot IS NOT NULL)) THEN
    book(:NEW.outlet_id, :NEW.pickup_slot);
    release(:OLD.outlet_id, :OLD.pickup_slot);
  END IF;
END;
/
