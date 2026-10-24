SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
SELECT order_id, status, total_amount FROM orders WHERE order_id = 88;
COLUMN remarks FORMAT A36
SELECT txn_type, amount, balance_after, remarks FROM wallet_txn WHERE order_id = 88 ORDER BY txn_id;
SELECT stock_qty FROM menu_item WHERE item_id = 17;
SELECT booked FROM pickup_slot WHERE (outlet_id, slot_start) IN (SELECT outlet_id, pickup_slot FROM orders WHERE order_id = 88);
COLUMN new_status FORMAT A10
SELECT old_status, new_status FROM order_status_log WHERE order_id = 88 ORDER BY log_id;
EXIT
