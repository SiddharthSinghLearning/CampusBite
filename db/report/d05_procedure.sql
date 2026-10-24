SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 130
SET PAGESIZE 100
DECLARE
  v_bal   NUMBER;
  v_order NUMBER;
  v_token NUMBER;
  v_total NUMBER;
BEGIN
  canteen_pkg.topup_wallet(7, 300, 'Report demo top-up', v_bal);
  DBMS_OUTPUT.PUT_LINE('Wallet after top-up : Rs.' || v_bal);
  canteen_pkg.place_order(
    p_user_id     => 7,
    p_outlet_id   => 3,
    p_cart_json   => '[{"item_id":21,"qty":2},{"item_id":26,"qty":1}]',
    p_coupon      => 'EXAM10',
    p_pickup_slot => NULL,
    p_notes       => 'Extra spicy',
    o_order_id    => v_order,
    o_token_no    => v_token,
    o_total       => v_total);
  DBMS_OUTPUT.PUT_LINE('Order placed        : #' || v_order || '  token ' || v_token || '  total Rs.' || v_total);
END;
/
COLUMN customer FORMAT A12
COLUMN items_text FORMAT A32
COLUMN slot FORMAT A5
SELECT order_id, token_no, status, customer, subtotal, discount, tax, total_amount,
       TO_CHAR(pickup_slot, 'HH24:MI') AS slot, items_text
  FROM v_order_details WHERE order_id = (SELECT MAX(order_id) FROM orders);
COLUMN remarks FORMAT A22
SELECT txn_type, amount, balance_after, remarks
  FROM wallet_txn WHERE user_id = 7 ORDER BY txn_id DESC FETCH FIRST 2 ROWS ONLY;
EXIT
