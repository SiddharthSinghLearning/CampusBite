SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
COLUMN name FORMAT A12
SELECT item_id, name, stock_qty FROM menu_item WHERE item_id IN (1, 9) ORDER BY item_id;
SELECT wallet_balance, loyalty_points FROM app_user WHERE user_id = 5;
EXIT
