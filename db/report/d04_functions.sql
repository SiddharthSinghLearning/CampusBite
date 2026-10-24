SET ECHO ON
SET LINESIZE 120
SET PAGESIZE 100
SELECT canteen_pkg.calc_coupon_discount('WELCOME20', 300) AS welcome20_on_300,
       canteen_pkg.calc_coupon_discount('EXAM10', 200)    AS exam10_on_200,
       canteen_pkg.get_wallet_balance(6)                  AS ananya_wallet,
       canteen_pkg.estimate_wait_minutes(1)               AS foodcourt_wait_min
  FROM dual;
COLUMN night_open FORMAT A10
COLUMN juice_open FORMAT A10
COLUMN placed_to_ready FORMAT A15
COLUMN ready_to_picked FORMAT A15
SELECT canteen_pkg.outlet_is_open(3)                        AS night_open,
       canteen_pkg.outlet_is_open(2)                        AS juice_open,
       canteen_pkg.is_valid_transition('PLACED','READY')    AS placed_to_ready,
       canteen_pkg.is_valid_transition('READY','PICKED_UP') AS ready_to_picked
  FROM dual;
COLUMN slot_start FORMAT A20
SELECT TO_CHAR(slot_start, 'DD-MON HH24:MI') AS slot_start, capacity, booked, available
  FROM TABLE(canteen_pkg.get_slots(3, 6));
EXIT
