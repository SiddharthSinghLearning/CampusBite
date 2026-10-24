SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
COLUMN slot FORMAT A5
COLUMN coupon_code FORMAT A10
SELECT order_id, token_no, pickup_code, status, subtotal, discount, tax, total_amount, coupon_code,
       TO_CHAR(pickup_slot, 'HH24:MI') AS slot
  FROM orders WHERE order_id = 87;
SELECT order_id, item_id, qty, unit_price, line_total FROM order_item WHERE order_id = 87;
COLUMN name FORMAT A12
SELECT item_id, name, stock_qty FROM menu_item WHERE item_id IN (1, 9) ORDER BY item_id;
SELECT outlet_id, TO_CHAR(slot_start, 'HH24:MI') AS slot, capacity, booked
  FROM pickup_slot WHERE (outlet_id, slot_start) IN (SELECT outlet_id, pickup_slot FROM orders WHERE order_id = 87);
COLUMN remarks FORMAT A12
SELECT txn_type, amount, balance_after, remarks FROM wallet_txn WHERE order_id = 87;
EXIT
