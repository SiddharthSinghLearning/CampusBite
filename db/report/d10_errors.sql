SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 140
DECLARE
  o NUMBER; t NUMBER; tot NUMBER;
  PROCEDURE try (p_label VARCHAR2, p_cart VARCHAR2, p_coupon VARCHAR2 DEFAULT NULL) IS
  BEGIN
    canteen_pkg.place_order(8, 3, p_cart, p_coupon, NULL, NULL, o, t, tot);
    DBMS_OUTPUT.PUT_LINE(p_label || ' -> accepted (unexpected)');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(RPAD(p_label, 20) || ' -> ' || SQLERRM);
  END;
BEGIN
  try('More than stock',   '[{"item_id":21,"qty":99}]');
  try('Sold-out dish',     '[{"item_id":25,"qty":1}]');
  try('Other outlet item', '[{"item_id":1,"qty":1}]');
  try('Expired coupon',    '[{"item_id":21,"qty":1}]', 'FEST50');
  try('Empty cart',        '[]');
END;
/
EXIT
