SET ECHO ON
SET LINESIZE 120
SET PAGESIZE 100
COLUMN trigger_name FORMAT A22
COLUMN trigger_type FORMAT A16
COLUMN event FORMAT A26
COLUMN table_name FORMAT A11
SELECT trigger_name, trigger_type, triggering_event AS event, table_name, status
  FROM user_triggers ORDER BY table_name, trigger_name;
UPDATE menu_item SET stock_qty = 3 WHERE item_id = 24;
UPDATE menu_item SET stock_qty = 0 WHERE item_id = 25;
UPDATE menu_item SET price = 85 WHERE item_id = 24;
COMMIT;
COLUMN name FORMAT A14
SELECT item_id, name, stock_qty, is_available, price FROM menu_item WHERE item_id IN (24, 25);
SELECT a.alert_id, m.name, a.stock_qty, a.is_resolved
  FROM stock_alert a JOIN menu_item m ON m.item_id = a.item_id WHERE a.item_id = 24;
SELECT m.name, h.old_price, h.new_price
  FROM price_history h JOIN menu_item m ON m.item_id = h.item_id WHERE h.item_id = 24;
EXIT
