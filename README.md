# CampusBite – Campus Canteen Pre-Order System

BCSE302P DBMS mini project. Students pre-order food from campus outlets, choose a
15-minute pickup slot, pay from a wallet and collect their food by showing a QR code.
Vendors run a live order board, scan the QR to hand over orders, manage menu, stock
and slot capacity, and see sales reports. Business rules live in **Oracle PL/SQL** (package,
triggers, cursors). The front-end is a mobile-first web app (installable as a PWA).

## Stack
| Layer | Technology |
|---|---|
| Database | Oracle Database 21c XE (schema `CANTEEN` in `XEPDB1`) |
| Server | Node.js 24 + Express 4 + node-oracledb 6 (thin mode) |
| Front-end | HTML, CSS, vanilla JavaScript SPA + service worker |

## Run it
```bash
npm install
npm start
```
Open http://localhost:3000. On a phone on the same Wi-Fi, open `http://<laptop-IP>:3000`
(allow Node.js through Windows Firewall when asked).

## Rebuild / reset the database
```powershell
.\db\run.ps1 install.sql     # drops and recreates tables, triggers, package, demo data
.\db\run.ps1 05_tests.sql    # runs the 40 automated test cases (leaves demo data unchanged)
```
`.env` (not committed) holds the Oracle credentials and session secret.
`db/00_create_user.sql` creates the Oracle user (run once as SYSDBA).

## Demo accounts
Password for all: `Campus@123`

| Role | Email |
|---|---|
| Student | siddharth@student.in, ananya@student.in, rahul@student.in, priya@student.in |
| Vendor – Main Food Court | foodcourt@campusbite.in |
| Vendor – Juice Junction | juice@campusbite.in |
| Vendor – Night Canteen | night@campusbite.in |
| Admin | admin@campusbite.in |

Coupons: `WELCOME20` (20 %, max ₹50, min ₹100), `EXAM10` (10 %, max ₹30), `FEST50` (expired).

## Database objects
**Tables (15):** app_user, outlet, category, menu_item, coupon, pickup_slot, orders,
order_item, wallet_txn, order_status_log, token_counter, review, price_history,
stock_alert, daily_sales_summary. **Views:** v_menu, v_order_details.
**Object types:** t_slot_row, t_slot_tab (rows of the pipelined function).

**Package `canteen_pkg`**
| Kind | Name | Purpose |
|---|---|---|
| Function | get_wallet_balance | Current wallet balance |
| Function | outlet_is_open | Open flag + working hours (handles past-midnight hours) |
| Function | calc_coupon_discount | Validates coupon, returns discount |
| Function | is_open_at | Is a given time inside working hours |
| Function | estimate_wait_minutes | Cursor over the live queue → ETA |
| Function | earliest_slot | First 15-minute slot the kitchen can meet |
| Function | get_slots | **Pipelined** table function: next slots with free places |
| Function | next_available_slot | Earliest slot that is not full (used for ASAP orders) |
| Function | is_valid_transition | Order life-cycle rules |
| Procedure | topup_wallet | Credit wallet + ledger entry |
| Procedure | place_order | JSON cart → explicit cursor over JSON_TABLE, coupon, GST, wallet debit; all-or-nothing |
| Procedure | update_order_status | Vendor moves order along PLACED → ACCEPTED → PREPARING → READY |
| Procedure | verify_pickup | QR / 6-digit code check; the only way to mark an order PICKED_UP |
| Procedure | cancel_order | Refund, restore stock (cursor), release coupon |
| Procedure | add_review | Rate items from picked-up orders |
| Procedure | generate_daily_summary | Explicit cursor (OPEN/FETCH/CLOSE) over outlets → summary table |
| Procedure | get_low_stock / get_top_items / get_sales_report | REF CURSOR reports |

**Triggers (9)**
| Trigger | Fires | Does |
|---|---|---|
| trg_order_token | BEFORE INSERT orders | Daily per-outlet pickup token + secret 6-digit pickup code |
| trg_order_slot | BEFORE INSERT / UPDATE OF pickup_slot, status | Books, moves and releases pickup-slot places; full slot → ORA-20013 |
| trg_order_item_stock | BEFORE INSERT order_item | Price from menu, availability/outlet/stock checks, deducts stock |
| trg_menu_stock_watch | BEFORE UPDATE OF stock_qty | Hides sold-out items, re-lists on restock, low-stock alerts |
| trg_menu_price_audit | AFTER UPDATE OF price | Price history |
| trg_order_status_audit | Compound, INSERT/UPDATE OF status | Status audit log + updated_at |
| trg_loyalty_points | AFTER UPDATE OF status | 1 point per ₹10 on pickup |
| trg_wallet_guard | BEFORE UPDATE OF wallet_balance | Friendly insufficient-balance error |
| trg_review_rating | AFTER INSERT review | Running average rating |

## Hosting (free)
- **Database:** Oracle Autonomous Database, *Always Free* tier (Oracle Cloud). Run
  `db/00_create_user.sql` (as ADMIN, using tablespace `DATA`), then `install.sql` as CANTEEN.
- **App:** Vercel Hobby plan. `api/index.js` exposes the Express app as a serverless
  function; `public/` is served as static files. Set `DB_USER`, `DB_PASSWORD`,
  `DB_CONNECT` (the TLS connect string from the database's *Database connection* page)
  and `SESSION_SECRET` in the Vercel project settings.
- The camera QR scanner needs HTTPS, which Vercel provides; on plain HTTP vendors type the code.

## Project layout
```
db/        SQL scripts (schema, triggers, package, seed, tests) + run.ps1
server/    Express API (app.js, index.js, db.js, auth.js, routes/)
api/       Vercel serverless entry
public/    Front-end (index.html, app.js, styles.css, sw.js, manifest)
```
