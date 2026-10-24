SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
COLUMN old_status FORMAT A10
COLUMN new_status FORMAT A10
SELECT log_id, old_status, new_status, TO_CHAR(changed_at, 'HH24:MI:SS') AS changed_at
  FROM order_status_log WHERE order_id = 87 ORDER BY log_id;
SELECT status, TO_CHAR(picked_up_at, 'HH24:MI:SS') AS picked_up_at FROM orders WHERE order_id = 87;
SELECT wallet_balance, loyalty_points FROM app_user WHERE user_id = 5;
COLUMN name FORMAT A12
SELECT r.order_id, m.name, r.rating, m.rating_avg, m.rating_count
  FROM review r JOIN menu_item m ON m.item_id = r.item_id WHERE r.order_id = 87;
EXIT
