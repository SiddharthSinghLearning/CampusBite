SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
COLUMN name FORMAT A16
SELECT item_id, name, stock_qty, is_available, price FROM menu_item WHERE item_id IN (3, 8, 13) ORDER BY item_id;
SELECT a.alert_id, m.name, a.stock_qty, a.is_resolved
  FROM stock_alert a JOIN menu_item m ON m.item_id = a.item_id WHERE a.item_id IN (3, 13) ORDER BY a.alert_id;
SELECT m.name, h.old_price, h.new_price, TO_CHAR(h.changed_at, 'HH24:MI:SS') AS changed_at
  FROM price_history h JOIN menu_item m ON m.item_id = h.item_id WHERE h.item_id = 8;
EXIT
