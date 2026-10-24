// Outlet dashboard (vendors see their outlets, admins see all) and admin overview.
const express = require('express');
const db = require('../db');
const { requireRole } = require('../auth');
const wrap = require('../wrap');

const r = express.Router();
r.use(requireRole('VENDOR', 'ADMIN'));

async function myOutlets(user) {
  return db.query(
    `SELECT outlet_id, name, location, cover_url, open_time, close_time, is_open, parallel_slots,
            slot_capacity, canteen_pkg.outlet_is_open(outlet_id) AS open_now
       FROM outlet WHERE :admin = 1 OR owner_id = :p_uid ORDER BY outlet_id`,
    { admin: user.role === "ADMIN" ? 1 : 0, p_uid: user.user_id });
}

// Resolves ?outlet_id / body.outlet_id to an outlet this user manages.
async function pickOutlet(req, res) {
  const outlets = await myOutlets(req.session.user);
  const wanted = Number(req.query.outlet_id || req.body?.outlet_id) || outlets[0]?.outlet_id;
  const o = outlets.find((x) => x.outlet_id === wanted);
  if (!o) {
    res.status(403).json({ error: 'You do not manage this outlet' });
    return null;
  }
  return o;
}

async function itemOutletCheck(req, res) {
  const item = await db.one(`SELECT item_id, outlet_id FROM menu_item WHERE item_id = :id`, { id: Number(req.params.id) });
  if (!item) {
    res.status(404).json({ error: 'Item not found' });
    return null;
  }
  req.query.outlet_id = item.outlet_id;
  return (await pickOutlet(req, res)) ? item : null;
}

r.get('/outlets', wrap(async (req, res) => {
  res.json(await myOutlets(req.session.user));
}));

r.patch('/outlets/:id', wrap(async (req, res) => {
  req.query.outlet_id = req.params.id;
  const o = await pickOutlet(req, res);
  if (!o) return;
  const { is_open, open_time, close_time, slot_capacity } = req.body || {};
  await db.exec(
    `UPDATE outlet SET is_open = NVL(:is_open, is_open),
                       open_time = NVL(:open_time, open_time),
                       close_time = NVL(:close_time, close_time),
                       slot_capacity = NVL(:cap, slot_capacity)
      WHERE outlet_id = :id`,
    {
      is_open: is_open ?? null, open_time: open_time ?? null, close_time: close_time ?? null,
      cap: slot_capacity ? Number(slot_capacity) : null, id: o.outlet_id,
    });
  res.json({ ok: true });
}));

// Hand-over: the scanned QR carries order id + code; a typed code has no order id.
r.post('/pickup', wrap(async (req, res) => {
  const o = await pickOutlet(req, res);
  if (!o) return;
  const out = await db.plsql(
    `BEGIN canteen_pkg.verify_pickup(:outlet, :code, :ord, :actor, :o_order, :o_token); END;`,
    {
      outlet: o.outlet_id, code: String(req.body?.code || ''),
      ord: req.body?.order_id ? Number(req.body.order_id) : null,
      actor: req.session.user.user_id, o_order: db.OUT_NUM, o_token: db.OUT_NUM,
    });
  const order = await db.one(
    `SELECT order_id, token_no, customer, reg_no, items_text, total_amount
       FROM v_order_details WHERE order_id = :id`, { id: out.o_order });
  res.json(order);
}));

// --------------------------------------------------------- live orders
r.get('/orders', wrap(async (req, res) => {
  const o = await pickOutlet(req, res);
  if (!o) return;
  const rows = await db.query(
    `SELECT order_id, token_no, status, customer, reg_no, total_amount, items_text, notes,
            pickup_slot, TO_CHAR(pickup_slot, 'HH:MI AM') AS slot_label, placed_at, updated_at
       FROM v_order_details
      WHERE outlet_id = :id
        AND (status IN ('PLACED','ACCEPTED','PREPARING','READY')
             OR updated_at >= SYSTIMESTAMP - INTERVAL '3' HOUR)
      ORDER BY pickup_slot, placed_at`, { id: o.outlet_id });
  const [wait, slots] = await Promise.all([
    db.one(`SELECT canteen_pkg.estimate_wait_minutes(:id) AS w FROM dual`, { id: o.outlet_id }),
    db.query(`SELECT TO_CHAR(slot_start, 'HH:MI AM') AS label, capacity, booked, available
                FROM TABLE(canteen_pkg.get_slots(:id, 8))`, { id: o.outlet_id }),
  ]);
  res.json({ outlet: o, orders: rows, wait_minutes: wait.w, slots });
}));

r.post('/orders/:id/status', wrap(async (req, res) => {
  await db.plsql(`BEGIN canteen_pkg.update_order_status(:id, :st, :actor); END;`,
    { id: Number(req.params.id), st: String(req.body?.status || ''), actor: req.session.user.user_id });
  res.json({ ok: true });
}));

// ---------------------------------------------------------------- menu
r.get('/menu', wrap(async (req, res) => {
  const o = await pickOutlet(req, res);
  if (!o) return;
  const [items, categories] = await Promise.all([
    db.query(`SELECT * FROM v_menu WHERE outlet_id = :id ORDER BY category_id, name`, { id: o.outlet_id }),
    db.query(`SELECT category_id, name FROM category ORDER BY category_id`),
  ]);
  res.json({ outlet: o, items, categories });
}));

r.post('/menu', wrap(async (req, res) => {
  const o = await pickOutlet(req, res);
  if (!o) return;
  const b = req.body || {};
  if (!b.name || !(Number(b.price) > 0)) return res.status(400).json({ error: 'Name and a positive price are required' });
  await db.exec(
    `INSERT INTO menu_item (outlet_id, category_id, name, description, price, is_veg, stock_qty, prep_minutes, image_url)
     VALUES (:o, :c, :n, :d, :p, :v, :s, :m, :img)`,
    {
      o: o.outlet_id, c: Number(b.category_id), n: String(b.name).trim(), d: b.description || null,
      p: Number(b.price), v: b.is_veg === 'N' ? 'N' : 'Y', s: Number(b.stock_qty) || 0, m: Number(b.prep_minutes) || 10,
      img: /^https:\/\//.test(b.image_url || '') ? String(b.image_url).slice(0, 300) : null,
    });
  res.json({ ok: true });
}));

// Plain UPDATEs: the stock and price triggers do the rest.
r.patch('/menu/:id', wrap(async (req, res) => {
  const item = await itemOutletCheck(req, res);
  if (!item) return;
  const { price, stock_qty, is_available } = req.body || {};
  await db.exec(
    `UPDATE menu_item SET price = NVL(:p, price), stock_qty = NVL(:s, stock_qty),
                          is_available = NVL(:a, is_available)
      WHERE item_id = :id`,
    {
      p: price != null && price !== '' ? Number(price) : null,
      s: stock_qty != null && stock_qty !== '' ? Number(stock_qty) : null,
      a: is_available ?? null, id: item.item_id,
    });
  res.json({ ok: true });
}));

// -------------------------------------------------------------- reports
r.get('/reports', wrap(async (req, res) => {
  const o = await pickOutlet(req, res);
  if (!o) return;
  const days = Math.min(Math.max(Number(req.query.days) || 7, 1), 90);
  const id = o.outlet_id;

  const procs = await db.plsql(
    `BEGIN
       canteen_pkg.get_sales_report(:id, TRUNC(SYSDATE) - :ndays + 1, TRUNC(SYSDATE), :o_sales);
       canteen_pkg.get_top_items(:id, :ndays, 5, :o_top);
       canteen_pkg.get_low_stock(:id, 10, :o_low);
     END;`,
    { id, ndays: days, o_sales: db.OUT_CURSOR, o_top: db.OUT_CURSOR, o_low: db.OUT_CURSOR });

  const [today, alerts, prices, summary] = await Promise.all([
    db.one(`SELECT COUNT(*) AS orders,
                   COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) AS cancelled,
                   NVL(SUM(CASE WHEN status <> 'CANCELLED' THEN total_amount END), 0) AS revenue,
                   NVL(ROUND(AVG(CASE WHEN status <> 'CANCELLED' THEN total_amount END), 2), 0) AS avg_order
              FROM orders WHERE outlet_id = :id AND placed_at >= TRUNC(SYSDATE)`, { id }),
    db.query(`SELECT a.alert_id, m.name, a.stock_qty, a.created_at
                FROM stock_alert a JOIN menu_item m ON m.item_id = a.item_id
               WHERE m.outlet_id = :id AND a.is_resolved = 'N' ORDER BY a.created_at DESC`, { id }),
    db.query(`SELECT m.name, h.old_price, h.new_price, h.changed_at
                FROM price_history h JOIN menu_item m ON m.item_id = h.item_id
               WHERE m.outlet_id = :id ORDER BY h.changed_at DESC FETCH FIRST 10 ROWS ONLY`, { id }),
    db.query(`SELECT d.summary_date, d.total_orders, d.cancelled_orders, d.items_sold, d.gross_revenue,
                     m.name AS top_item, d.generated_at
                FROM daily_sales_summary d LEFT JOIN menu_item m ON m.item_id = d.top_item_id
               WHERE d.outlet_id = :id ORDER BY d.summary_date DESC FETCH FIRST 14 ROWS ONLY`, { id }),
  ]);

  res.json({ outlet: o, days, today, sales: procs.o_sales, top: procs.o_top, low: procs.o_low, alerts, prices, summary });
}));

r.post('/summary', wrap(async (req, res) => {
  const out = await db.plsql(`BEGIN canteen_pkg.generate_daily_summary(TRUNC(SYSDATE), :n); END;`, { n: db.OUT_NUM });
  res.json({ outlets: out.n });
}));

// ------------------------------------------------------------ admin only
r.get('/admin/overview', requireRole('ADMIN'), wrap(async (req, res) => {
  const [stats, outlets, users] = await Promise.all([
    db.one(`SELECT (SELECT COUNT(*) FROM app_user WHERE role = 'STUDENT') AS students,
                   (SELECT COUNT(*) FROM orders) AS orders,
                   (SELECT NVL(SUM(total_amount), 0) FROM orders WHERE status <> 'CANCELLED') AS revenue,
                   (SELECT NVL(SUM(wallet_balance), 0) FROM app_user) AS wallet_float,
                   (SELECT COUNT(*) FROM orders WHERE placed_at >= TRUNC(SYSDATE)) AS orders_today
              FROM dual`),
    db.query(`SELECT o.outlet_id, o.name, u.full_name AS owner,
                     COUNT(x.order_id) AS orders,
                     NVL(SUM(CASE WHEN x.status <> 'CANCELLED' THEN x.total_amount END), 0) AS revenue
                FROM outlet o JOIN app_user u ON u.user_id = o.owner_id
                LEFT JOIN orders x ON x.outlet_id = o.outlet_id
               GROUP BY o.outlet_id, o.name, u.full_name ORDER BY revenue DESC`),
    db.query(`SELECT user_id, full_name, email, reg_no, role, wallet_balance, loyalty_points, is_active
                FROM app_user ORDER BY role, full_name`),
  ]);
  res.json({ stats, outlets, users });
}));

module.exports = r;
