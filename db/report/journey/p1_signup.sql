SET ECHO ON
SET LINESIZE 140
SET PAGESIZE 100
SET FEEDBACK ON
COLUMN full_name FORMAT A12
COLUMN reg_no FORMAT A10
COLUMN role FORMAT A8
COLUMN remarks FORMAT A20
SELECT user_id, full_name, reg_no, role, wallet_balance, SUBSTR(password_hash, 1, 20) || '...' AS password_hash
  FROM app_user WHERE email = 'aarav@student.in';
SELECT txn_id, txn_type, amount, balance_after, remarks
  FROM wallet_txn WHERE user_id = (SELECT user_id FROM app_user WHERE email = 'aarav@student.in');
EXIT
