// Auth, outlets, menu, ordering, wallet and reviews.
const express = require('express');
const db = require('../db');
const { hashPassword, verifyPassword, requireLogin } = require('../auth');
const wrap = require('../wrap');

const r = express.Router();

// ---------------------------------------------------------------- auth
function sessionUser(u) {
  return { user_id: u.user_id, full_name: u.full_name, email: u.email, role: u.role, reg_no: u.reg_no };
}

r.post('/auth/login', wrap(async (req, res) => {
  const { email, password } = req.body || {};
  const u = await db.one(
    `SELECT user_id, full_name, email, role, reg_no, password_hash, is_active
       FROM app_user WHERE LOWER(email) = LOWER(:email)`, { email: String(email || '').trim() });
  if (!u || !verifyPassword(String(password || ''), u.password_hash)) {
    return res.status(401).json({ error: 'Wrong email or password' });
  }
  if (u.is_active !== 'Y') return res.status(403).json({ error: 'This account is deactivated' });
  req.session.user = sessionUser(u);
  res.json({ user: req.session.user });
}));

r.post('/auth/register', wrap(async (req, res) => {
  const { full_name, email, phone, reg_no, password } = req.body || {};
  if (!full_name || !email || !password) return res.status(400).json({ error: 'Name, email and password are required' });
  if (String(password).length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters' });
  if (phone && !/^[0-9]{10}$/.test(phone)) return res.status(400).json({ error: 'Phone must be 10 digits' });

  const result = await db.exec(
    `INSERT INTO app_user (full_name, email, phone, reg_no, password_hash, role)
     VALUES (:full_name, LOWER(:email), :phone, UPPER(:reg_no), :hash, 'STUDENT')
     RETURNING user_id INTO :id`,
    {
      full_name: String(full_name).trim(), email: String(email).trim(),
      phone: phone || null, reg_no: reg_no ? String(reg_no).trim() : null,
      hash: hashPassword(String(password)), id: db.OUT_NUM,
    });
  const u = await db.one(`SELECT user_id, full_name, email, role, reg_no FROM app_user WHERE user_id = :id`,
    { id: result.outBinds.id[0] });
  req.session.user = sessionUser(u);
  res.json({ user: req.session.user });
}));

r.post('/auth/logout', (req, res) => {
  req.session = null;
  res.json({ ok: true });
});

r.get('/auth/me', wrap(async (req, res) => {
  if (!req.session.user) return res.json({ user: null });
  const u = await db.one(
    `SELECT user_id, full_name, email, phone, reg_no, role, wallet_balance, loyalty_points, created_at
       FROM app_user WHERE user_id = :id`, { id: req.session.user.user_id });
  res.json({ user: u });
}));

// ------------------------------------------------------- outlets & menu
r.get('/outlets', wrap(async (req, res) => {
  res.json(await outletList());
}));

const OUTLET_COLS = `
  o.outlet_id, o.name, o.location, o.tagline, o.cover_url, o.open_time, o.close_time, o.is_open,
  canteen_pkg.outlet_is_open(o.outlet_id)        AS open_now,
  canteen_pkg.estimate_wait_minutes(o.outlet_id) AS wait_minutes,
  TO_CHAR(canteen_pkg.next_available_slot(o.outlet_id), 'HH:MI AM') AS next_slot,
  (SELECT COUNT(*) FROM menu_item m WHERE m.outlet_id = o.outlet_id AND m.is_available = 'Y') AS items,
  (SELECT ROUND(AVG(NULLIF(m.rating_avg, 0)), 1) FROM menu_item m WHERE m.outlet_id = o.outlet_id) AS rating,
  (SELECT COUNT(*) FROM orders x WHERE x.outlet_id = o.outlet_id
      AND x.status IN ('PLACED','ACCEPTED','PREPARING')) AS queue`;

function outletList() {
  return db.query(`SELECT ${OUTLET_COLS} FROM outlet o ORDER BY o.outlet_id`);
}

const MENU_COLS = `item_id, outlet_id, outlet_name, category, name, description, price, is_veg,
                   stock_qty, prep_minutes, is_available, rating_avg, rating_count, image_url`;

r.get('/outlets/:id/menu', wrap(async (req, res) => {
  const id = Number(req.params.id);
  const outlet = await db.one(`SELECT ${OUTLET_COLS} FROM outlet o WHERE o.outlet_id = :id`, { id });
  if (!outlet) return res.status(404).json({ error: 'Outlet not found' });
  const items = await db.query(
    `SELECT ${MENU_COLS} FROM v_menu WHERE outlet_id = :id ORDER BY category_id, name`, { id });
  res.json({ outlet, items });
}));

// Next pickup slots with free places (pipelined function canteen_pkg.get_slots).
r.get('/outlets/:id/slots', wrap(async (req, res) => {
  const rows = await db.query(
    `SELECT TO_CHAR(slot_start, 'YYYY-MM-DD"T"HH24:MI') AS slot,
            TO_CHAR(slot_start, 'HH:MI AM') AS label,
            capacity, booked, available
       FROM TABLE(canteen_pkg.get_slots(:id, 16))`, { id: Number(req.params.id) });
  res.json(rows);
}));

// Home screen feed: offers, campus best sellers, the user's usual dishes.
r.get('/home', requireLogin, wrap(async (req, res) => {
  const uid = req.session.user.user_id;
  const [outlets, offers, popular, again] = await Promise.all([
    outletList(),
    db.query(`SELECT code, discount_pct, max_discount, min_order, valid_to
                FROM coupon
               WHERE TRUNC(SYSDATE) BETWEEN valid_from AND valid_to AND used_count < usage_limit
               ORDER BY discount_pct DESC`),
    db.query(`SELECT ${MENU_COLS}, sold FROM (
                SELECT v.*, (SELECT NVL(SUM(oi.qty), 0) FROM order_item oi JOIN orders o ON o.order_id = oi.order_id
                              WHERE oi.item_id = v.item_id AND o.status <> 'CANCELLED'
                                AND o.placed_at >= TRUNC(SYSDATE) - 7) AS sold
                  FROM v_menu v WHERE v.is_available = 'Y')
               ORDER BY sold DESC, rating_avg DESC FETCH FIRST 8 ROWS ONLY`),
    db.query(`SELECT ${MENU_COLS}, times FROM (
                SELECT v.*, COUNT(*) OVER (PARTITION BY v.item_id) AS times,
                       ROW_NUMBER() OVER (PARTITION BY v.item_id ORDER BY o.placed_at DESC) AS rn,
                       MAX(o.placed_at) OVER (PARTITION BY v.item_id) AS last_at
                  FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
                  JOIN v_menu v ON v.item_id = oi.item_id
                 WHERE o.user_id = :p_user AND o.status = 'PICKED_UP')
               WHERE rn = 1 ORDER BY times DESC, last_at DESC FETCH FIRST 8 ROWS ONLY`, { p_user: uid }),
  ]);
  res.json({ outlets, offers, popular, again });
}));

r.get('/search', requireLogin, wrap(async (req, res) => {
  const q = String(req.query.q || '').trim().toLowerCase();
  if (q.length < 2) return res.json([]);
  res.json(await db.query(
    `SELECT ${MENU_COLS} FROM v_menu
      WHERE LOWER(name) LIKE :q OR LOWER(category) LIKE :q OR LOWER(description) LIKE :q
      ORDER BY is_available DESC, rating_avg DESC FETCH FIRST 20 ROWS ONLY`, { q: `%${q}%` }));
}));

// --------------------------------------------------------------- coupons
r.post('/coupons/check', requireLogin, wrap(async (req, res) => {
  const { code, subtotal } = req.body || {};
  const row = await db.one(`SELECT canteen_pkg.calc_coupon_discount(:code, :subtotal) AS discount FROM dual`,
    { code: String(code || ''), subtotal: Number(subtotal) || 0 });
  res.json({ code: String(code).trim().toUpperCase(), discount: row.discount });
}));

// ---------------------------------------------------------------- orders
r.post('/orders', requireLogin, wrap(async (req, res) => {
  const { outlet_id, items, coupon, pickup_slot, notes } = req.body || {};
  const cart = (Array.isArray(items) ? items : [])
    .map((i) => ({ item_id: Number(i.item_id), qty: Number(i.qty) }))
    .filter((i) => i.item_id > 0 && i.qty > 0);

  const out = await db.plsql(
    `BEGIN canteen_pkg.place_order(:user_id, :outlet_id, :cart, :coupon,
                                   TO_DATE(:pickup, 'YYYY-MM-DD"T"HH24:MI'), :notes,
                                   :order_id, :token_no, :total); END;`,
    {
      user_id: req.session.user.user_id,
      outlet_id: Number(outlet_id),
      cart: JSON.stringify(cart),
      coupon: coupon ? String(coupon) : null,
      pickup: /^\d{4}-\d\d-\d\dT\d\d:\d\d$/.test(pickup_slot || '') ? pickup_slot : null,
      notes: notes ? String(notes) : null,
      order_id: db.OUT_NUM, token_no: db.OUT_NUM, total: db.OUT_NUM,
    });
  res.json(out);
}));

r.get('/orders/mine', requireLogin, wrap(async (req, res) => {
  const rows = await db.query(
    `SELECT order_id, token_no, status, outlet_id, outlet_name, cover_url, total_amount, items_text,
            pickup_slot, placed_at, updated_at
       FROM v_order_details WHERE user_id = :id
      ORDER BY placed_at DESC FETCH FIRST 50 ROWS ONLY`, { id: req.session.user.user_id });
  res.json(rows);
}));

r.get('/orders/:id', requireLogin, wrap(async (req, res) => {
  const id = Number(req.params.id);
  const me = req.session.user;
  const order = await db.one(`SELECT * FROM v_order_details WHERE order_id = :id`, { id });
  if (!order) return res.status(404).json({ error: 'Order not found' });

  if (order.user_id !== me.user_id && me.role !== 'ADMIN') {
    const own = await db.one(`SELECT 1 AS ok FROM outlet WHERE outlet_id = :o AND owner_id = :u`,
      { o: order.outlet_id, u: me.user_id });
    if (!own) return res.status(403).json({ error: 'Not your order' });
  }
  // the pickup code is the student's proof of ownership - the outlet must scan it
  if (order.user_id !== me.user_id) delete order.pickup_code;

  const [items, log] = await Promise.all([
    db.query(
      `SELECT oi.item_id, m.name, m.is_veg, m.image_url, oi.qty, oi.unit_price, oi.line_total,
              rv.rating AS my_rating
         FROM order_item oi
         JOIN menu_item m ON m.item_id = oi.item_id
         LEFT JOIN review rv ON rv.order_id = oi.order_id AND rv.item_id = oi.item_id
        WHERE oi.order_id = :id ORDER BY m.name`, { id }),
    db.query(`SELECT old_status, new_status, changed_at FROM order_status_log
               WHERE order_id = :id ORDER BY log_id`, { id }),
  ]);
  const wait = ['PLACED', 'ACCEPTED', 'PREPARING'].includes(order.status)
    ? (await db.one(`SELECT canteen_pkg.estimate_wait_minutes(:o) AS w FROM dual`, { o: order.outlet_id })).w
    : null;
  res.json({ order, items, log, wait_minutes: wait });
}));

r.post('/orders/:id/cancel', requireLogin, wrap(async (req, res) => {
  await db.plsql(`BEGIN canteen_pkg.cancel_order(:id, :actor); END;`,
    { id: Number(req.params.id), actor: req.session.user.user_id });
  res.json({ ok: true });
}));

r.post('/orders/:id/review', requireLogin, wrap(async (req, res) => {
  const { item_id, rating, comments } = req.body || {};
  await db.plsql(`BEGIN canteen_pkg.add_review(:o, :i, :u, :r, :c); END;`, {
    o: Number(req.params.id), i: Number(item_id), u: req.session.user.user_id,
    r: Number(rating), c: comments ? String(comments) : null,
  });
  res.json({ ok: true });
}));

// ---------------------------------------------------------------- wallet
r.get('/wallet', requireLogin, wrap(async (req, res) => {
  const id = req.session.user.user_id;
  const [bal, txns] = await Promise.all([
    db.one(`SELECT canteen_pkg.get_wallet_balance(:id) AS balance,
                   (SELECT loyalty_points FROM app_user WHERE user_id = :id) AS loyalty_points
              FROM dual`, { id }),
    db.query(`SELECT txn_id, txn_type, amount, balance_after, order_id, remarks, created_at
                FROM wallet_txn WHERE user_id = :id
               ORDER BY created_at DESC, txn_id DESC FETCH FIRST 50 ROWS ONLY`, { id }),
  ]);
  res.json({ ...bal, txns });
}));

// Payment gateway is simulated: the amount is credited straight away.
r.post('/wallet/topup', requireLogin, wrap(async (req, res) => {
  const out = await db.plsql(`BEGIN canteen_pkg.topup_wallet(:id, :amt, :rem, :bal); END;`, {
    id: req.session.user.user_id, amt: Number(req.body?.amount), rem: 'UPI top-up (demo)', bal: db.OUT_NUM,
  });
  res.json({ balance: out.bal });
}));

module.exports = r;
