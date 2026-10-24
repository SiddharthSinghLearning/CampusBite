-- =====================================================================
-- CampusBite : 04_seed.sql  -  demo data
-- All demo accounts share the password documented in README.md
-- =====================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------
DECLARE
  c_hash CONSTANT VARCHAR2(200) :=
    'scrypt$0a7fe199ae47b899b5fb0a0eab3b187b$40faed963e375c8150a40f30b1dba2764fca25bdb3aa176b5c91c8f9e7f6648d';

  PROCEDURE add_user (p_id NUMBER, p_name VARCHAR2, p_email VARCHAR2, p_phone VARCHAR2,
                      p_reg VARCHAR2, p_role VARCHAR2) IS
  BEGIN
    INSERT INTO app_user (user_id, full_name, email, phone, reg_no, password_hash, role)
    VALUES (p_id, p_name, p_email, p_phone, p_reg, c_hash, p_role);
  END;
BEGIN
  add_user(1, 'Campus Admin',    'admin@campusbite.in',     '9000000001', NULL,        'ADMIN');
  add_user(2, 'Ramesh Kumar',    'foodcourt@campusbite.in', '9000000002', NULL,        'VENDOR');
  add_user(3, 'Lakshmi Devi',    'juice@campusbite.in',     '9000000003', NULL,        'VENDOR');
  add_user(4, 'Arjun Reddy',     'night@campusbite.in',     '9000000004', NULL,        'VENDOR');
  add_user(5, 'Siddharth Singh', 'siddharth@student.in',    '9876500001', '24BCI0158', 'STUDENT');
  add_user(6, 'Ananya Iyer',     'ananya@student.in',       '9876500002', '23BCE1002', 'STUDENT');
  add_user(7, 'Rahul Verma',     'rahul@student.in',        '9876500003', '23BIT1003', 'STUDENT');
  add_user(8, 'Priya Nair',      'priya@student.in',        '9876500004', '23BEC1004', 'STUDENT');
END;
/

-- ---------------------------------------------------------------------
-- Outlets (opened round the clock while seeding; real hours set below)
-- ---------------------------------------------------------------------
INSERT INTO outlet (outlet_id, name, location, owner_id, open_time, close_time, parallel_slots, slot_capacity, tagline, cover_url)
VALUES (1, 'Main Food Court', 'Ground floor, Academic Block 1', 2, '00:00', '23:59', 3, 10,
        'South Indian breakfasts, thalis, biryani and Indo-Chinese',
        'https://images.unsplash.com/photo-1736239092023-ba677fd6751c');
INSERT INTO outlet (outlet_id, name, location, owner_id, open_time, close_time, parallel_slots, slot_capacity, tagline, cover_url)
VALUES (2, 'Juice Junction', 'Near Central Library', 3, '00:00', '23:59', 2, 8,
        'Fresh juices, shakes, cold coffee and quick bites',
        'https://images.unsplash.com/photo-1780409903230-5d7c9d13f745');
INSERT INTO outlet (outlet_id, name, location, owner_id, open_time, close_time, parallel_slots, slot_capacity, tagline, cover_url)
VALUES (3, 'Night Canteen', 'Men''s Hostel Block C', 4, '00:00', '23:59', 2, 6,
        'Late-night Maggi, rolls and hot chocolate',
        'https://images.unsplash.com/photo-1514327567052-1eed4e4902c1');

-- ---------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------
INSERT INTO category (category_id, name) VALUES (1, 'Breakfast');
INSERT INTO category (category_id, name) VALUES (2, 'Meals');
INSERT INTO category (category_id, name) VALUES (3, 'Snacks');
INSERT INTO category (category_id, name) VALUES (4, 'Chinese');
INSERT INTO category (category_id, name) VALUES (5, 'Beverages');
INSERT INTO category (category_id, name) VALUES (6, 'Desserts');

-- ---------------------------------------------------------------------
-- Menu (high stock while seeding; realistic stock set below)
-- ---------------------------------------------------------------------
DECLARE
  PROCEDURE add_item (p_id NUMBER, p_outlet NUMBER, p_cat NUMBER, p_name VARCHAR2,
                      p_desc VARCHAR2, p_price NUMBER, p_veg CHAR, p_prep NUMBER) IS
  BEGIN
    INSERT INTO menu_item (item_id, outlet_id, category_id, name, description, price, is_veg, stock_qty, prep_minutes)
    VALUES (p_id, p_outlet, p_cat, p_name, p_desc, p_price, p_veg, 500, p_prep);
  END;
BEGIN
  -- Main Food Court
  add_item( 1, 1, 1, 'Masala Dosa',        'Crisp dosa with potato masala, chutney and sambar', 60, 'Y', 8);
  add_item( 2, 1, 1, 'Idli Vada Combo',    'Two idlis and one medu vada with sambar',           50, 'Y', 5);
  add_item( 3, 1, 1, 'Poha',               'Flattened rice with peanuts and sev',               40, 'Y', 5);
  add_item( 4, 1, 2, 'South Indian Thali', 'Rice, sambar, rasam, two curries, curd, papad',    110, 'Y', 6);
  add_item( 5, 1, 2, 'North Indian Thali', 'Two rotis, dal, paneer curry, jeera rice, salad',  130, 'Y', 8);
  add_item( 6, 1, 2, 'Chicken Biryani',    'Hyderabadi dum biryani with raita',                160, 'N', 10);
  add_item( 7, 1, 2, 'Veg Biryani',        'Vegetable dum biryani with raita',                 120, 'Y', 10);
  add_item( 8, 1, 3, 'Samosa (2 pcs)',     'Potato samosas with mint chutney',                  30, 'Y', 3);
  add_item( 9, 1, 3, 'Pav Bhaji',          'Spiced mashed vegetables with buttered pav',        80, 'Y', 7);
  add_item(10, 1, 4, 'Veg Fried Rice',     'Wok-tossed rice with vegetables',                   90, 'Y', 10);
  add_item(11, 1, 4, 'Chilli Paneer',      'Paneer cubes tossed in chilli sauce',              120, 'Y', 12);
  add_item(12, 1, 4, 'Chicken Noodles',    'Hakka noodles with chicken',                       110, 'N', 12);
  add_item(13, 1, 6, 'Gulab Jamun (2 pcs)','Warm gulab jamun',                                  35, 'Y', 2);
  -- Juice Junction
  add_item(14, 2, 5, 'Fresh Lime Soda',    'Sweet or salted',                                   30, 'Y', 3);
  add_item(15, 2, 5, 'Watermelon Juice',   'Fresh watermelon, no added sugar',                  50, 'Y', 4);
  add_item(16, 2, 5, 'Mango Shake',        'Alphonso mango pulp with milk',                     70, 'Y', 5);
  add_item(17, 2, 5, 'Cold Coffee',        'Blended iced coffee with ice cream',                80, 'Y', 5);
  add_item(18, 2, 5, 'Masala Chai',        'Ginger cardamom tea',                               15, 'Y', 3);
  add_item(19, 2, 3, 'Veg Sandwich',       'Grilled sandwich with cheese',                      60, 'Y', 6);
  add_item(20, 2, 6, 'Fruit Bowl',         'Seasonal cut fruits',                               60, 'Y', 4);
  -- Night Canteen
  add_item(21, 3, 4, 'Maggi Masala',       'Classic masala noodles',                            40, 'Y', 5);
  add_item(22, 3, 4, 'Egg Fried Rice',     'Fried rice with scrambled egg',                     90, 'N', 10);
  add_item(23, 3, 3, 'Bread Omelette',     'Double-egg omelette with toasted bread',            50, 'N', 6);
  add_item(24, 3, 3, 'Paneer Roll',        'Paneer tikka wrapped in a paratha',                 80, 'Y', 8);
  add_item(25, 3, 3, 'Chicken Roll',       'Chicken tikka wrapped in a paratha',                90, 'N', 8);
  add_item(26, 3, 5, 'Hot Chocolate',      'Rich cocoa with milk',                              60, 'Y', 4);
END;
/

-- dish photos (Unsplash, free licence)
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1668236543090-82eba5ee5976' WHERE item_id = 1;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc' WHERE item_id = 2;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1789991184412-c29c9dfa2b39' WHERE item_id = 3;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1742281257687-092746ad6021' WHERE item_id = 4;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1680993032090-1ef7ea9b51e5' WHERE item_id = 5;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1782541370275-6761522e39d1' WHERE item_id = 6;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1589302168068-964664d93dc0' WHERE item_id = 7;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1601050690597-df0568f70950' WHERE item_id = 8;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1753357303396-704b5abe8945' WHERE item_id = 9;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1603133872878-684f208fb84b' WHERE item_id = 10;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1567188040759-fb8a883dc6d8' WHERE item_id = 11;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1634864572865-1cf8ff8bd23d' WHERE item_id = 12;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1666190092159-3171cf0fbb12' WHERE item_id = 13;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1621263764928-df1444c5e859' WHERE item_id = 14;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1683531658992-b78c311900a3' WHERE item_id = 15;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1623065422902-30a2d299bbe4' WHERE item_id = 16;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1461023058943-07fcbe16d735' WHERE item_id = 17;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1761483281417-778013dc0177' WHERE item_id = 18;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af' WHERE item_id = 19;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1490474418585-ba9bad8fd0ea' WHERE item_id = 20;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1612927601601-6638404737ce' WHERE item_id = 21;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1609570324378-ec0c4c9b6ba8' WHERE item_id = 22;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1563690449029-d6e1b8d6003d' WHERE item_id = 23;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f' WHERE item_id = 24;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1778168199427-4e839943d20f' WHERE item_id = 25;
UPDATE menu_item SET image_url = 'https://images.unsplash.com/photo-1637572815755-c4b80092dce1' WHERE item_id = 26;

-- ---------------------------------------------------------------------
-- Coupons
-- ---------------------------------------------------------------------
INSERT INTO coupon (code, discount_pct, max_discount, min_order, valid_from, valid_to, usage_limit)
VALUES ('WELCOME20', 20, 50, 100, TRUNC(SYSDATE) - 30, TRUNC(SYSDATE) + 60, 500);
INSERT INTO coupon (code, discount_pct, max_discount, min_order, valid_from, valid_to, usage_limit)
VALUES ('EXAM10', 10, 30, 0, TRUNC(SYSDATE) - 7, TRUNC(SYSDATE) + 30, 1000);
INSERT INTO coupon (code, discount_pct, max_discount, min_order, valid_from, valid_to, usage_limit)
VALUES ('FEST50', 50, 100, 200, TRUNC(SYSDATE) - 60, TRUNC(SYSDATE) - 30, 100);
COMMIT;

-- identity columns continue after the explicit ids used above
ALTER TABLE app_user  MODIFY user_id     GENERATED BY DEFAULT AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE outlet    MODIFY outlet_id   GENERATED BY DEFAULT AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE category  MODIFY category_id GENERATED BY DEFAULT AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE menu_item MODIFY item_id     GENERATED BY DEFAULT AS IDENTITY (START WITH LIMIT VALUE);

-- ---------------------------------------------------------------------
-- Order history for the last 7 days, created through the package so
-- every trigger fires exactly as it does in the live application.
-- ---------------------------------------------------------------------
DECLARE
  TYPE t_ids IS TABLE OF NUMBER;
  v_items    t_ids;
  v_bal      NUMBER;
  v_order    NUMBER;
  v_token    NUMBER;
  v_total    NUMBER;
  v_outlet   NUMBER;
  v_student  NUMBER;
  v_cart     VARCHAR2(400);
  v_n        PLS_INTEGER;
  v_vendor   NUMBER;
  v_when     TIMESTAMP;
  v_coupon   VARCHAR2(20);
  v_roll     NUMBER;
  v_code     VARCHAR2(6);
  v_slot     DATE;
BEGIN
  DBMS_RANDOM.SEED(2026);

  FOR s IN 5 .. 8 LOOP
    canteen_pkg.topup_wallet(s, 5000, 'Opening balance', v_bal);
  END LOOP;
  UPDATE wallet_txn SET created_at = SYSTIMESTAMP - INTERVAL '8' DAY;

  FOR d IN REVERSE 1 .. 7 LOOP
    FOR k IN 1 .. TRUNC(DBMS_RANDOM.VALUE(6, 11)) LOOP
      v_student := TRUNC(DBMS_RANDOM.VALUE(5, 9));
      v_roll    := DBMS_RANDOM.VALUE;
      v_outlet  := CASE WHEN v_roll < 0.55 THEN 1 WHEN v_roll < 0.8 THEN 2 ELSE 3 END;
      v_vendor  := v_outlet + 1;

      SELECT item_id BULK COLLECT INTO v_items FROM menu_item WHERE outlet_id = v_outlet;
      v_n    := TRUNC(DBMS_RANDOM.VALUE(1, 4));
      v_cart := '[';
      FOR j IN 1 .. v_n LOOP
        v_cart := v_cart || CASE WHEN j > 1 THEN ',' END ||
                  '{"item_id":' || v_items(TRUNC(DBMS_RANDOM.VALUE(1, v_items.COUNT + 1))) ||
                  ',"qty":' || TRUNC(DBMS_RANDOM.VALUE(1, 3)) || '}';
      END LOOP;
      v_cart := v_cart || ']';

      v_coupon := CASE WHEN DBMS_RANDOM.VALUE < 0.15 THEN 'EXAM10' END;
      canteen_pkg.place_order(v_student, v_outlet, v_cart, v_coupon, NULL, NULL, v_order, v_token, v_total);

      IF DBMS_RANDOM.VALUE < 0.08 THEN
        canteen_pkg.cancel_order(v_order, v_student);
      ELSE
        canteen_pkg.update_order_status(v_order, 'ACCEPTED',  v_vendor);
        canteen_pkg.update_order_status(v_order, 'PREPARING', v_vendor);
        canteen_pkg.update_order_status(v_order, 'READY',     v_vendor);
        SELECT pickup_code INTO v_code FROM orders WHERE order_id = v_order;
        canteen_pkg.verify_pickup(v_outlet, v_code, v_order, v_vendor, v_order, v_token);
      END IF;

      -- move the order back in time
      v_when := CAST(TRUNC(SYSDATE) - d AS TIMESTAMP)
                + NUMTODSINTERVAL(CASE v_outlet WHEN 3 THEN 20 + DBMS_RANDOM.VALUE(0, 3.5)
                                               ELSE 8 + DBMS_RANDOM.VALUE(0, 11) END, 'HOUR');
      UPDATE orders SET placed_at = v_when, updated_at = v_when + INTERVAL '20' MINUTE,
                        picked_up_at = CASE WHEN status = 'PICKED_UP' THEN v_when + INTERVAL '22' MINUTE END
       WHERE order_id = v_order;
      -- move the pickup booking to the matching past slot (TRG_ORDER_SLOT re-books)
      v_slot := TRUNC(CAST(v_when AS DATE), 'HH24')
                + (CEIL(TO_NUMBER(TO_CHAR(v_when, 'MI')) / 15) * 15 + 15) / 1440;
      UPDATE orders SET pickup_slot = v_slot WHERE order_id = v_order AND status <> 'CANCELLED';
      UPDATE wallet_txn SET created_at = v_when WHERE order_id = v_order;
      -- status events 5 minutes apart, in their original order
      UPDATE order_status_log l
         SET changed_at = v_when + NUMTODSINTERVAL(5 * (l.log_id -
               (SELECT MIN(x.log_id) FROM order_status_log x WHERE x.order_id = v_order)), 'MINUTE')
       WHERE l.order_id = v_order;
    END LOOP;
  END LOOP;
  COMMIT;
END;
/

-- re-number past tokens per outlet per day and fix the counters
MERGE INTO orders o
USING (SELECT order_id,
              ROW_NUMBER() OVER (PARTITION BY outlet_id, TRUNC(placed_at) ORDER BY placed_at) AS rn
         FROM orders) x
   ON (o.order_id = x.order_id)
 WHEN MATCHED THEN UPDATE SET o.token_no = x.rn;

DELETE FROM token_counter;
INSERT INTO token_counter (outlet_id, token_date, last_token)
SELECT outlet_id, TRUNC(placed_at), MAX(token_no) FROM orders GROUP BY outlet_id, TRUNC(placed_at);
COMMIT;

-- ---------------------------------------------------------------------
-- Reviews for some picked-up orders
-- ---------------------------------------------------------------------
DECLARE
  v_i PLS_INTEGER := 0;
BEGIN
  FOR r IN (SELECT o.order_id, oi.item_id, o.user_id
              FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
             WHERE o.status = 'PICKED_UP'
             ORDER BY o.order_id, oi.item_id) LOOP
    v_i := v_i + 1;
    IF MOD(v_i, 2) = 0 THEN
      canteen_pkg.add_review(r.order_id, r.item_id, r.user_id,
                             CASE WHEN MOD(v_i, 7) = 0 THEN 3 WHEN MOD(v_i, 3) = 0 THEN 4 ELSE 5 END,
                             CASE WHEN MOD(v_i, 5) = 0 THEN 'Tasty and quick!' END);
    END IF;
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- Daily summaries for the history
-- ---------------------------------------------------------------------
DECLARE
  v_rows NUMBER;
BEGIN
  FOR d IN 1 .. 7 LOOP
    canteen_pkg.generate_daily_summary(TRUNC(SYSDATE) - d, v_rows);
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- Realistic stock levels (TRG_MENU_STOCK_WATCH raises alerts for the
-- low ones and hides the sold-out one) and real opening hours
-- ---------------------------------------------------------------------
UPDATE menu_item SET stock_qty = 60;
UPDATE menu_item SET stock_qty = 25 WHERE item_id IN (4, 5, 6, 7);
UPDATE menu_item SET stock_qty = 4  WHERE item_id IN (11, 16);
UPDATE menu_item SET stock_qty = 0  WHERE item_id = 20;
COMMIT;

-- today's live queue so the vendor board has something to show
DECLARE
  v_order NUMBER;
  v_token NUMBER;
  v_total NUMBER;
BEGIN
  canteen_pkg.place_order(6, 1, '[{"item_id":1,"qty":1},{"item_id":8,"qty":1}]', NULL, NULL, NULL, v_order, v_token, v_total);
  canteen_pkg.update_order_status(v_order, 'ACCEPTED', 2);
  canteen_pkg.update_order_status(v_order, 'PREPARING', 2);
  canteen_pkg.place_order(7, 1, '[{"item_id":6,"qty":1}]', NULL, NULL, 'Extra raita please', v_order, v_token, v_total);
  canteen_pkg.update_order_status(v_order, 'ACCEPTED', 2);
  canteen_pkg.place_order(8, 1, '[{"item_id":4,"qty":2}]', 'WELCOME20', NULL, NULL, v_order, v_token, v_total);
  canteen_pkg.place_order(6, 2, '[{"item_id":17,"qty":2}]', NULL, NULL, NULL, v_order, v_token, v_total);
  canteen_pkg.update_order_status(v_order, 'ACCEPTED', 3);
  canteen_pkg.update_order_status(v_order, 'PREPARING', 3);
  canteen_pkg.update_order_status(v_order, 'READY', 3);
END;
/

UPDATE outlet SET open_time = '07:00', close_time = '23:30' WHERE outlet_id = 1;
UPDATE outlet SET open_time = '08:00', close_time = '23:00' WHERE outlet_id = 2;
UPDATE outlet SET open_time = '18:00', close_time = '04:00' WHERE outlet_id = 3;

-- a few price revisions for the history table
UPDATE menu_item SET price = 65 WHERE item_id = 1;
UPDATE menu_item SET price = 170 WHERE item_id = 6;
COMMIT;

SELECT 'users' t, COUNT(*) n FROM app_user UNION ALL
SELECT 'items', COUNT(*) FROM menu_item UNION ALL
SELECT 'orders', COUNT(*) FROM orders UNION ALL
SELECT 'reviews', COUNT(*) FROM review UNION ALL
SELECT 'stock alerts', COUNT(*) FROM stock_alert WHERE is_resolved = 'N';

-- the identity changes above invalidate dependent views; recompile them now
ALTER VIEW v_menu COMPILE;
ALTER VIEW v_order_details COMPILE;
ALTER PACKAGE canteen_pkg COMPILE;
