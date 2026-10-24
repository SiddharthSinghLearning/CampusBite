SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
SELECT order_id, status, total_amount, TO_CHAR(pickup_slot, 'HH24:MI') AS slot FROM orders WHERE order_id = 88;
SELECT stock_qty FROM menu_item WHERE item_id = 17;
SELECT booked FROM pickup_slot WHERE (outlet_id, slot_start) IN (SELECT outlet_id, pickup_slot FROM orders WHERE order_id = 88);
EXIT
