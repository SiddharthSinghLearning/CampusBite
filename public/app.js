/* CampusBite front-end: a small single-page app on top of the /api routes. */
'use strict';

const GST = 0.05;
const view = document.getElementById('view');
const state = { me: null, timer: null, home: null };

// ------------------------------------------------------------------ utils
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const inr = (n) => '₹' + Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: Number(n) % 1 ? 2 : 0, maximumFractionDigits: 2 });
const round2 = (n) => Math.round(n * 100) / 100;
// dates arrive as campus wall-clock strings ("2026-10-22T13:45:00")
const D = (s) => (s instanceof Date ? s : new Date(s));
const time = (d) => D(d).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' });
const day = (d) => D(d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
const isToday = (d) => D(d).toDateString() === new Date().toDateString();
const when = (d) => (isToday(d) ? 'Today, ' : day(d) + ', ') + time(d);
const ago = (d) => {
  const m = Math.max(0, Math.round((Date.now() - D(d)) / 60000));
  return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : `${Math.floor(m / 60)} h ${m % 60} m ago`;
};
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const img = (url, w, h) => (url ? `${esc(url)}?w=${w}&h=${h}&fit=crop&auto=format&q=70` : 'icon.svg');
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch { /* storage blocked */ } },
};

function toast(msg, isErr = false) {
  $$('.toast').forEach((t) => t.remove());
  const t = document.createElement('div');
  t.className = 'toast' + (isErr ? ' err' : '');
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), isErr ? 4200 : 2600);
}

function beep() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    [0, 0.18].forEach((t) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.frequency.value = 880;
      g.gain.setValueAtTime(0.18, ctx.currentTime + t);
      g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.15);
      o.connect(g).connect(ctx.destination);
      o.start(ctx.currentTime + t);
      o.stop(ctx.currentTime + t + 0.16);
    });
  } catch { /* audio not allowed */ }
}

async function api(path, opts = {}) {
  const res = await fetch('/api' + path, {
    method: opts.method || (opts.body ? 'POST' : 'GET'),
    headers: opts.body ? { 'Content-Type': 'application/json' } : {},
    body: opts.body ? JSON.stringify(opts.body) : undefined,
    credentials: 'same-origin',
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && !path.startsWith('/auth')) {
    state.me = null;
    location.hash = '#/login';
  }
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

// runs an action, shows its error as a toast, returns undefined on failure
async function attempt(fn, btn) {
  if (btn) btn.disabled = true;
  try {
    return await fn();
  } catch (e) {
    toast(e.message, true);
  } finally {
    if (btn) btn.disabled = false;
  }
}

const STATUS = {
  PLACED: ['Placed', 'info'],
  ACCEPTED: ['Accepted', 'accent'],
  PREPARING: ['Preparing', 'warn'],
  READY: ['Ready', 'green'],
  PICKED_UP: ['Picked up', ''],
  CANCELLED: ['Cancelled', 'bad'],
};
const FLOW = ['PLACED', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP'];
const ACTIVE = ['PLACED', 'ACCEPTED', 'PREPARING', 'READY'];
const statusBadge = (s) => `<span class="badge ${STATUS[s][1]}"><span class="dot"></span>${STATUS[s][0]}</span>`;
const vegMark = (v) => `<span class="veg ${v === 'Y' ? '' : 'non'}" title="${v === 'Y' ? 'Veg' : 'Non-veg'}"></span>`;
const isBest = (i) => Number(i.rating_avg) >= 4.5 && i.rating_count >= 3;
const rating = (i) => (i.rating_count ? `<span class="small bold"><span class="star">★</span> ${Number(i.rating_avg).toFixed(1)} <span class="muted">(${i.rating_count})</span></span>` : '');

const ICONS = {
  home: '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>',
  orders: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6"/>',
  wallet: '<path d="M3 7h15a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3zM3 7l12-4v4M16 14h1"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>',
  board: '<rect x="3" y="4" width="5" height="16" rx="1"/><rect x="10" y="4" width="5" height="11" rx="1"/><rect x="17" y="4" width="4" height="7" rx="1"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  admin: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  back: '<path d="M15 18l-6-6 6-6"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  pin: '<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>',
  qr: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3M21 14v7h-4M14 21v-3"/>',
  check: '<path d="M5 12l5 5 9-10"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon: '<path d="M21 13A9 9 0 1 1 11 3a7 7 0 0 0 10 10z"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  up: '<path d="M7 17L17 7M9 7h8v8"/>',
  down: '<path d="M17 7L7 17M15 17H7V9"/>',
  refund: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5"/>',
  bolt: '<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>',
};
const icon = (n) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[n]}</svg>`;

// ------------------------------------------------------------------ theme
function paintThemeBtn() {
  const dark = document.documentElement.dataset.theme === 'dark'
    || (!document.documentElement.dataset.theme && matchMedia('(prefers-color-scheme: dark)').matches);
  $('#themeBtn').innerHTML = icon(dark ? 'sun' : 'moon');
  return dark;
}
$('#themeBtn').onclick = () => {
  const next = paintThemeBtn() ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  store.set('cb_theme', next);
  paintThemeBtn();
};
paintThemeBtn();

// ------------------------------------------------------------------- cart
const cart = {
  load() {
    try { return JSON.parse(store.get('cb_cart')) || { outlet_id: null, items: {} }; } catch { return { outlet_id: null, items: {} }; }
  },
  save(c) { store.set('cb_cart', JSON.stringify(c)); },
  count() { return Object.values(this.load().items).reduce((a, i) => a + i.qty, 0); },
  subtotal() { return Object.values(this.load().items).reduce((a, i) => a + i.qty * i.price, 0); },
  qty(outletId, itemId) {
    const c = this.load();
    return c.outlet_id === outletId && c.items[itemId] ? c.items[itemId].qty : 0;
  },
  set(outlet, item, qty) {
    let c = this.load();
    if (c.outlet_id && c.outlet_id !== outlet.outlet_id && Object.keys(c.items).length) {
      if (!confirm(`Your cart has items from ${c.outlet_name}. Start a new cart from ${outlet.name}?`)) return false;
      c = { outlet_id: null, items: {} };
    }
    c.outlet_id = outlet.outlet_id;
    c.outlet_name = outlet.name;
    if (qty <= 0) delete c.items[item.item_id];
    else {
      c.items[item.item_id] = {
        item_id: item.item_id, name: item.name, price: item.price, is_veg: item.is_veg,
        image_url: item.image_url, stock_qty: item.stock_qty, qty: Math.min(qty, 20),
      };
    }
    if (!Object.keys(c.items).length) c = { outlet_id: null, items: {} };
    this.save(c);
    renderNav();
    return true;
  },
  clear() { this.save({ outlet_id: null, items: {} }); },
};

// one ADD / stepper control used on every dish surface
function addControl(item, outlet, off) {
  if (off) return '<button class="add-btn" disabled>SOLD OUT</button>';
  const q = cart.qty(outlet.outlet_id, item.item_id);
  return q
    ? `<div class="stepper" data-step="${item.item_id}"><button data-d="-1" aria-label="Remove one">−</button><span>${q}</span><button data-d="1" aria-label="Add one">+</button></div>`
    : `<button class="add-btn" data-add="${item.item_id}">ADD</button>`;
}
// wires ADD / steppers inside root; items is the list the ids refer to
function bindAddControls(root, items, outletOf, redraw) {
  const change = (id, d) => {
    const item = items.find((i) => i.item_id === id);
    const outlet = outletOf(item);
    const next = cart.qty(outlet.outlet_id, id) + d;
    if (next > item.stock_qty) return toast(`Only ${item.stock_qty} left today`, true);
    if (cart.set(outlet, item, next)) {
      if (d > 0 && next === 1) toast(`${item.name} added`);
      redraw();
    }
  };
  $$('[data-add]', root).forEach((b) => b.onclick = (e) => { e.stopPropagation(); change(Number(b.dataset.add), 1); });
  $$('[data-step]', root).forEach((s) => $$('button', s).forEach((b) => b.onclick = (e) => { e.stopPropagation(); change(Number(s.dataset.step), Number(b.dataset.d)); }));
}

// ------------------------------------------------------------ bottom sheet
function openSheet(html, onMount) {
  closeSheet();
  const bg = document.createElement('div');
  bg.className = 'sheet-bg';
  bg.innerHTML = `<div class="sheet" role="dialog">${html}</div>`;
  bg.onclick = (e) => { if (e.target === bg) closeSheet(); };
  document.body.appendChild(bg);
  document.body.style.overflow = 'hidden';
  if (onMount) onMount($('.sheet', bg));
}
function closeSheet() {
  $$('.sheet-bg').forEach((s) => { if (s._cleanup) s._cleanup(); s.remove(); });
  document.body.style.overflow = '';
}

function dishSheet(item, outlet, after) {
  const off = item.is_available !== 'Y' || outlet.is_open === 'N';
  const draw = (sh) => {
    sh.innerHTML = `
      <div class="sheet-img"><img src="${img(item.image_url, 900, 600)}" alt="${esc(item.name)}">
        <button class="icon-btn glass" data-close aria-label="Close">${icon('close')}</button></div>
      <div class="sheet-body">
        <div class="row" style="gap:8px">${vegMark(item.is_veg)}${isBest(item) ? '<span class="tag-best">★ Bestseller</span>' : ''}</div>
        <div class="row between top"><h2>${esc(item.name)}</h2><h2 class="num">${inr(item.price)}</h2></div>
        <p class="soft">${esc(item.description || '')}</p>
        <div class="row wrap" style="gap:16px">${rating(item)}
          <span class="small soft row" style="gap:4px">${icon('clock').replace('<svg', '<svg width="15" height="15"')} ${item.prep_minutes} min prep</span>
          ${item.stock_qty <= 5 && !off ? `<span class="badge warn">Only ${item.stock_qty} left</span>` : ''}
          <span class="small muted">${esc(outlet.name)}</span></div>
        <div class="row between" style="margin-top:6px">
          <div>${addControl(item, outlet, off)}</div>
          ${cart.qty(outlet.outlet_id, item.item_id) ? `<a class="btn primary" href="#/cart" data-close>View cart · ${inr(cart.subtotal())}</a>` : ''}
        </div>
      </div>`;
    $$('[data-close]', sh).forEach((b) => b.addEventListener('click', closeSheet));
    bindAddControls(sh, [item], () => outlet, () => { draw(sh); if (after) after(); });
  };
  openSheet('', draw);
}

// ------------------------------------------------------------- navigation
const NAV = {
  STUDENT: [['#/', 'Home', 'home'], ['#/orders', 'Orders', 'orders'], ['#/wallet', 'Wallet', 'wallet'], ['#/profile', 'Profile', 'user']],
  VENDOR: [['#/v/board', 'Live orders', 'board'], ['#/v/menu', 'Menu', 'menu'], ['#/v/reports', 'Reports', 'chart'], ['#/profile', 'Profile', 'user']],
  ADMIN: [['#/a/overview', 'Overview', 'admin'], ['#/v/board', 'Orders', 'board'], ['#/v/menu', 'Menu', 'menu'], ['#/v/reports', 'Reports', 'chart'], ['#/profile', 'Profile', 'user']],
};

function renderNav() {
  const items = state.me ? NAV[state.me.role] : [];
  const path = location.hash || '#/';
  const isOn = (href) => (href === '#/' ? path === '#/' || path.startsWith('#/outlet') || path === '#/cart' : path.startsWith(href) || (href === '#/orders' && path.startsWith('#/order/')));
  $('#topnav').innerHTML = items.map(([h, l]) => `<a href="${h}" class="${isOn(h) ? 'active' : ''}">${l}</a>`).join('');
  const n = cart.count();
  $('#bottomnav').innerHTML = items.map(([h, l, i]) => `<a href="${h}" class="${isOn(h) ? 'active' : ''}">${icon(i)}${l}${h === '#/' && n ? '<span class="dot-badge"></span>' : ''}</a>`).join('');
  $('#bottomnav').classList.toggle('hidden', !state.me);
  const chip = $('#walletChip');
  chip.classList.toggle('hidden', !state.me || state.me.role !== 'STUDENT');
  if (state.me) chip.innerHTML = `${icon('wallet')}${inr(state.me.wallet_balance)}`;
}

async function refreshMe() {
  const { user } = await api('/auth/me');
  state.me = user;
  renderNav();
  return user;
}

function poll(fn, ms = 5000) {
  clearInterval(state.timer);
  state.timer = setInterval(() => { if (!document.hidden) fn(); }, ms);
}

const routes = [
  [/^#\/login$/, viewLogin, null],
  [/^#\/register$/, viewRegister, null],
  [/^#\/$/, viewHome, 'STUDENT'],
  [/^#\/outlet\/(\d+)$/, viewOutlet, 'STUDENT'],
  [/^#\/cart$/, viewCart, 'STUDENT'],
  [/^#\/orders$/, viewOrders, 'STUDENT'],
  [/^#\/order\/(\d+)$/, viewOrder, 'ANY'],
  [/^#\/wallet$/, viewWallet, 'STUDENT'],
  [/^#\/profile$/, viewProfile, 'ANY'],
  [/^#\/v\/board$/, viewBoard, 'STAFF'],
  [/^#\/v\/menu$/, viewVendorMenu, 'STAFF'],
  [/^#\/v\/reports$/, viewReports, 'STAFF'],
  [/^#\/a\/overview$/, viewAdmin, 'ADMIN'],
];
const homeFor = (role) => ({ STUDENT: '#/', VENDOR: '#/v/board', ADMIN: '#/a/overview' }[role]);

const skeleton = () => `<div class="stack"><div class="skel" style="height:34px;width:60%"></div><div class="skel" style="height:130px"></div>
  <div class="grid"><div class="skel" style="height:210px"></div><div class="skel" style="height:210px"></div><div class="skel" style="height:210px"></div></div></div>`;

async function router() {
  clearInterval(state.timer);
  closeSheet();
  const hash = location.hash || '#/';
  const match = routes.find(([re]) => re.test(hash));
  if (!match) { location.hash = state.me ? homeFor(state.me.role) : '#/login'; return; }
  const [re, fn, need] = match;

  if (need && !state.me) { location.hash = '#/login'; return; }
  if (!need && state.me) { location.hash = homeFor(state.me.role); return; }
  if (need === 'STUDENT' && state.me.role !== 'STUDENT') { location.hash = homeFor(state.me.role); return; }
  if (need === 'STAFF' && state.me.role === 'STUDENT') { location.hash = '#/'; return; }
  if (need === 'ADMIN' && state.me.role !== 'ADMIN') { location.hash = homeFor(state.me.role); return; }

  renderNav();
  window.scrollTo(0, 0);
  view.innerHTML = skeleton();
  try {
    await fn(...hash.match(re).slice(1));
  } catch (e) {
    view.innerHTML = `<div class="empty"><div class="big">⚠️</div><p>${esc(e.message)}</p><button class="btn" onclick="router()">Try again</button></div>`;
  }
}

// ================================================================== AUTH
const AUTH_PHOTOS = ['1668236543090-82eba5ee5976', '1753357303396-704b5abe8945', '1623065422902-30a2d299bbe4', '1782541370275-6761522e39d1']
  .map((id) => `https://images.unsplash.com/photo-${id}`);

function viewLogin() {
  view.innerHTML = `
    <div class="auth-mobile-art"><img src="${img(AUTH_PHOTOS[0], 900, 400)}" alt=""></div>
    <div class="auth-wrap">
      <div class="auth-art">
        <div class="mosaic">${AUTH_PHOTOS.map((u) => `<img src="${img(u, 600, 600)}" alt="">`).join('')}</div>
        <div class="copy">
          <span class="badge glass" style="justify-self:start">${icon('bolt').replace('<svg', '<svg width="14" height="14"')} Order ahead · Pick up with a QR</span>
          <h1>Your canteen food, ready when you are.</h1>
          <p style="opacity:.85">Browse every outlet on campus, book a pickup slot and skip the queue between classes.</p>
        </div>
      </div>
      <div class="auth-card">
        <div class="stack tight">
          <span class="eyebrow" style="color:var(--accent);font-weight:800;font-size:13px;letter-spacing:.06em;text-transform:uppercase">Welcome back</span>
          <h1>Log in to CampusBite</h1>
          <p class="soft">Skip the canteen queue. Order now, pick up later.</p>
        </div>
        <form class="card pad-lg stack" id="f">
          <label class="field">Email<input class="input" name="email" type="email" autocomplete="username" required placeholder="you@college.edu"></label>
          <label class="field">Password<input class="input" name="password" type="password" autocomplete="current-password" required></label>
          <button class="btn primary block">Log in</button>
          <p class="small muted center">New here? <a href="#/register" style="color:var(--accent);font-weight:800">Create an account</a></p>
        </form>
        <div class="stack tight">
          <div class="small muted">Try a demo account</div>
          <div class="demo-grid">
            <button data-e="siddharth@student.in"><b>🎓 Student</b><span>Order & pay</span></button>
            <button data-e="foodcourt@campusbite.in"><b>👨‍🍳 Food Court</b><span>Vendor board</span></button>
            <button data-e="night@campusbite.in"><b>🌙 Night Canteen</b><span>Vendor board</span></button>
            <button data-e="admin@campusbite.in"><b>🛡️ Admin</b><span>Campus overview</span></button>
          </div>
        </div>
      </div>
    </div>`;
  const f = $('#f');
  $$('.demo-grid button').forEach((b) => b.onclick = () => { f.email.value = b.dataset.e; f.password.value = 'Campus@123'; f.requestSubmit(); });
  f.onsubmit = async (e) => {
    e.preventDefault();
    const ok = await attempt(() => api('/auth/login', { body: { email: f.email.value, password: f.password.value } }), f.querySelector('button'));
    if (ok) { await refreshMe(); location.hash = homeFor(state.me.role); }
  };
}

function viewRegister() {
  view.innerHTML = `
    <div class="auth-card" style="margin-top:10px">
      <div><a class="back" href="#/login">${icon('back').replace('<svg', '<svg width="18" height="18"')} Back to login</a><h1>Create your account</h1>
      <p class="soft" style="margin-top:4px">Takes 30 seconds. Top up your wallet and start ordering.</p></div>
      <form class="card pad-lg stack" id="f">
        <label class="field">Full name<input class="input" name="full_name" required maxlength="80"></label>
        <label class="field">College email<input class="input" name="email" type="email" required></label>
        <div class="row top">
          <label class="field grow">Registration no.<input class="input" name="reg_no" maxlength="20" placeholder="23BCE1234"></label>
          <label class="field grow">Phone<input class="input" name="phone" inputmode="numeric" pattern="[0-9]{10}" placeholder="10 digits"></label>
        </div>
        <label class="field">Password<input class="input" name="password" type="password" minlength="8" required autocomplete="new-password" placeholder="At least 8 characters"></label>
        <button class="btn primary block">Create account</button>
      </form>
    </div>`;
  const f = $('#f');
  f.onsubmit = async (e) => {
    e.preventDefault();
    const body = Object.fromEntries(new FormData(f));
    const ok = await attempt(() => api('/auth/register', { body }), f.querySelector('button'));
    if (ok) { await refreshMe(); toast('Welcome to CampusBite! Add money to get started.'); location.hash = '#/wallet'; }
  };
}

// =============================================================== STUDENT
function outletCard(o) {
  const open = o.open_now === 'Y';
  return `
    <a class="outlet-card ${open ? '' : 'closed'}" href="#/outlet/${o.outlet_id}">
      <img class="cover" src="${img(o.cover_url, 900, 520)}" alt="" loading="lazy">
      <div class="top-badges">
        ${open ? '<span class="badge green"><span class="dot"></span>Open now</span>'
          : o.is_open === 'N' ? '<span class="badge bad">Paused</span>' : `<span class="badge glass">Opens ${esc(o.open_time)} · pre-order</span>`}
        ${o.rating ? `<span class="badge glass"><span class="star">★</span> ${o.rating}</span>` : ''}
      </div>
      <div class="info">
        <h2 style="color:#fff">${esc(o.name)}</h2>
        <p class="small" style="opacity:.85">${esc(o.tagline || '')}</p>
        <div class="facts">
          <span>${icon('clock').replace('<svg', '<svg width="15" height="15"')} ${o.next_slot ? 'Pickup ' + esc(o.next_slot) : 'No slots'}</span>
          <span>${icon('pin').replace('<svg', '<svg width="15" height="15"')} ${esc(o.location)}</span>
          ${o.queue ? `<span>${o.queue} in queue</span>` : ''}
        </div>
      </div>
    </a>`;
}

function dishCard(i) {
  return `
    <div class="dish-card" data-dish="${i.item_id}">
      <div class="ph"><img src="${img(i.image_url, 400, 300)}" alt="" loading="lazy">${isBest(i) ? '<span class="badge warn">★ Bestseller</span>' : ''}</div>
      <div class="body">
        <div class="row" style="gap:6px">${vegMark(i.is_veg)}<span class="name clamp2">${esc(i.name)}</span></div>
        <div class="tiny muted">${esc(i.outlet_name)}${i.times ? ` · ordered ${i.times}×` : ''}</div>
        <div class="foot"><b class="num">${inr(i.price)}</b>${addControl(i, { outlet_id: i.outlet_id }, i.is_available !== 'Y')}</div>
      </div>
    </div>`;
}

async function viewHome() {
  const [home, orders] = await Promise.all([api('/home'), api('/orders/mine'), refreshMe()]);
  state.home = home;
  const active = orders.filter((o) => ACTIVE.includes(o.status));
  const hour = new Date().getHours();
  const greet = hour < 5 ? 'Late-night cravings?' : hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  const first = esc(state.me.full_name.split(' ')[0]);
  const outletOf = (i) => ({ outlet_id: i.outlet_id, name: i.outlet_name });
  const all = [...home.popular, ...home.again];

  const draw = () => {
    view.innerHTML = `
      <div class="greet">
        <div><div class="eyebrow">${greet}</div><h1>Hey ${first}, what's for ${hour < 11 ? 'breakfast' : hour < 16 ? 'lunch' : hour < 19 ? 'snacks' : 'dinner'}?</h1></div>
        <a class="avatar" href="#/profile">${esc(state.me.full_name.split(' ').map((w) => w[0]).join('').slice(0, 2))}</a>
      </div>
      <div class="search" style="margin-bottom:16px">${icon('search')}<input class="input" id="q" type="search" placeholder="Search dosa, biryani, cold coffee…" autocomplete="off"></div>
      <div id="results"></div>
      <div id="feed">
        ${active.map((o) => {
          const at = FLOW.indexOf(o.status);
          return `<a class="live-order" href="#/order/${o.order_id}">
            <div class="t"><small>TOKEN</small><b>${o.token_no}</b></div>
            <div class="grow"><div class="row between"><b>${esc(o.outlet_name)}</b><span class="small" style="opacity:.8">${o.pickup_slot ? 'Pickup ' + time(o.pickup_slot) : ''}</span></div>
              <div class="small" style="opacity:.8">${o.status === 'READY' ? '✅ Ready - show your QR at the counter' : STATUS[o.status][0] + ' · ' + esc(o.items_text)}</div>
              <div class="bar"><i style="width:${((at + 1) / 4) * 100}%"></i></div></div>
          </a>`;
        }).join('')}

        ${home.offers.length ? `<div class="section" style="margin-top:${active.length ? 22 : 4}px">
          <div class="hscroll">${home.offers.map((c, k) => `
            <div class="offer o${k % 3}" data-coupon="${esc(c.code)}">
              <div><div class="big">${Number(c.discount_pct)}% OFF</div><div class="small" style="opacity:.9;margin-top:4px">up to ${inr(c.max_discount)}${c.min_order > 0 ? ` on orders above ${inr(c.min_order)}` : ' on any order'}</div></div>
              <div class="row between"><span class="code">${esc(c.code)}</span><span class="tiny" style="opacity:.85">Tap to apply</span></div>
            </div>`).join('')}</div></div>` : ''}

        ${home.again.length ? `<div class="section">
          <div class="section-head"><div><h2>Order again</h2><p>Your usual, one tap away</p></div></div>
          <div class="hscroll">${home.again.map(dishCard).join('')}</div></div>` : ''}

        <div class="section">
          <div class="section-head"><div><h2>Popular on campus</h2><p>Most ordered this week</p></div></div>
          <div class="hscroll">${home.popular.map(dishCard).join('')}</div>
        </div>

        <div class="section">
          <div class="section-head"><div><h2>Outlets</h2><p>${home.outlets.filter((o) => o.open_now === 'Y').length} open now · pre-order from the rest</p></div></div>
          <div class="grid">${home.outlets.map(outletCard).join('')}</div>
        </div>
      </div>
      <a class="cartbar ${cart.count() ? '' : 'hidden'}" href="#/cart"><span>${cart.count()} item${cart.count() > 1 ? 's' : ''} · ${inr(cart.subtotal())}<small>from ${esc(cart.load().outlet_name || '')}</small></span><span>View cart →</span></a>`;

    bindAddControls($('#feed'), all, outletOf, draw);
    $$('#feed [data-dish]').forEach((c) => c.onclick = () => {
      const i = all.find((x) => x.item_id === Number(c.dataset.dish));
      dishSheet(i, outletOf(i), draw);
    });
    $$('[data-coupon]').forEach((c) => c.onclick = () => {
      store.set('cb_coupon', c.dataset.coupon);
      toast(`${c.dataset.coupon} will be applied at checkout`);
    });
    let t;
    $('#q').oninput = (e) => {
      clearTimeout(t);
      const q = e.target.value.trim();
      t = setTimeout(() => search(q), 250);
    };
  };

  const search = async (q) => {
    const box = $('#results');
    $('#feed').classList.toggle('hidden', q.length >= 2);
    if (q.length < 2) { box.innerHTML = ''; return; }
    const rows = await api('/search?q=' + encodeURIComponent(q));
    box.innerHTML = rows.length ? `<div class="card" style="padding:0 16px">${rows.map((i) => `
      <div class="dish ${i.is_available === 'Y' ? '' : 'off'}" data-dish="${i.item_id}">
        <div class="txt"><div class="row" style="gap:8px">${vegMark(i.is_veg)}<span class="name">${esc(i.name)}</span></div>
          <span class="small muted">${esc(i.outlet_name)} · ${esc(i.category)}</span><span class="price">${inr(i.price)}</span></div>
        <div class="pic"><img src="${img(i.image_url, 260, 240)}" alt="" loading="lazy"></div>
      </div>`).join('')}</div>` : `<div class="empty"><div class="big">🔍</div>Nothing matches “${esc(q)}”</div>`;
    $$('[data-dish]', box).forEach((d) => d.onclick = () => {
      const i = rows.find((x) => x.item_id === Number(d.dataset.dish));
      dishSheet(i, outletOf(i), () => {});
    });
  };
  draw();
}

async function viewOutlet(id) {
  const { outlet, items } = await api(`/outlets/${id}/menu`);
  const cats = [...new Set(items.map((i) => i.category))];
  const ui = { veg: false, q: '' };
  const open = outlet.open_now === 'Y';

  view.innerHTML = `
    <div class="hero">
      <img src="${img(outlet.cover_url, 1400, 600)}" alt="">
      <a class="icon-btn glass back-btn" href="#/" aria-label="Back">${icon('back')}</a>
      <div class="inner">
        <div class="row wrap">${open ? '<span class="badge green"><span class="dot"></span>Open now</span>' : outlet.is_open === 'N' ? '<span class="badge bad">Paused</span>' : `<span class="badge glass">Closed · opens ${esc(outlet.open_time)}</span>`}
          ${outlet.rating ? `<span class="badge glass"><span class="star">★</span> ${outlet.rating}</span>` : ''}</div>
        <h1 style="color:#fff;font-size:30px">${esc(outlet.name)}</h1>
        <p style="opacity:.9">${esc(outlet.tagline || '')}</p>
        <p class="small" style="opacity:.8">${esc(outlet.location)} · ${esc(outlet.open_time)}–${esc(outlet.close_time)}</p>
      </div>
    </div>
    <div class="info-strip">
      <div><b>${outlet.next_slot ? esc(outlet.next_slot) : '—'}</b><span>Next pickup</span></div>
      <div><b>~${outlet.wait_minutes} min</b><span>Kitchen time</span></div>
      <div><b>${outlet.queue}</b><span>In queue</span></div>
    </div>
    ${!open && outlet.is_open !== 'N' ? `<div class="card" style="margin-top:14px;background:var(--info-soft);border-color:transparent;color:var(--info)"><b>Pre-order now</b> - your food will be ready for the first pickup slot after opening.</div>` : ''}
    <div class="cat-bar">
      <div class="search" style="margin-bottom:10px">${icon('search')}<input class="input" id="q" placeholder="Search in ${esc(outlet.name)}" type="search"></div>
      <div class="chips" id="cats">
        <button class="chip" data-veg>${vegMark('Y')} Veg only</button>
        ${cats.map((c) => `<button class="chip" data-cat="${esc(c)}">${esc(c)}</button>`).join('')}
      </div>
    </div>
    <div id="menu"></div>
    <a class="cartbar hidden" id="cartbar" href="#/cart"></a>`;

  const draw = () => {
    const list = items.filter((i) => (!ui.veg || i.is_veg === 'Y')
      && (!ui.q || (i.name + ' ' + (i.description || '')).toLowerCase().includes(ui.q)));
    const groups = cats.map((cat) => [cat, list.filter((i) => i.category === cat)]).filter(([, l]) => l.length);
    $('#menu').innerHTML = groups.length ? groups.map(([cat, l]) => `
      <div class="cat-head" id="cat-${esc(cat)}"><h3>${esc(cat)}</h3><span class="small muted">${l.length} item${l.length > 1 ? 's' : ''}</span></div>
      <div class="card" style="padding:0 16px">${l.map((i) => {
        const off = i.is_available !== 'Y' || outlet.is_open === 'N';
        return `
        <div class="dish ${i.is_available !== 'Y' ? 'off' : ''}" data-dish="${i.item_id}">
          <div class="txt">
            <div class="row" style="gap:8px">${vegMark(i.is_veg)}${isBest(i) ? '<span class="tag-best">★ Bestseller</span>' : ''}</div>
            <span class="name">${esc(i.name)}</span>
            <span class="price num">${inr(i.price)}</span>
            <div class="row wrap" style="gap:10px">${rating(i)}${i.is_available === 'Y' && i.stock_qty <= 5 ? `<span class="badge warn">Only ${i.stock_qty} left</span>` : ''}</div>
            <span class="desc clamp2">${esc(i.description || '')}</span>
          </div>
          <div class="pic"><img src="${img(i.image_url, 260, 240)}" alt="" loading="lazy"><div class="act">${addControl(i, outlet, off)}</div></div>
        </div>`;
      }).join('')}</div>`).join('') : '<div class="empty">No dishes match your filters.</div>';

    bindAddControls($('#menu'), items, () => outlet, draw);
    $$('#menu [data-dish]').forEach((d) => d.onclick = () => dishSheet(items.find((i) => i.item_id === Number(d.dataset.dish)), outlet, draw));

    const n = cart.count();
    const bar = $('#cartbar');
    bar.classList.toggle('hidden', !n || cart.load().outlet_id !== outlet.outlet_id);
    bar.innerHTML = `<span>${n} item${n > 1 ? 's' : ''} · ${inr(cart.subtotal())}<small>Pickup from ${esc(outlet.next_slot || 'next slot')}</small></span><span>View cart →</span>`;
  };

  $('#q').oninput = (e) => { ui.q = e.target.value.trim().toLowerCase(); draw(); };
  $$('#cats [data-cat]').forEach((b) => b.onclick = () => {
    const target = document.getElementById('cat-' + b.dataset.cat);
    if (target) window.scrollTo({ top: target.getBoundingClientRect().top + scrollY - 190, behavior: 'smooth' });
  });
  $('#cats [data-veg]').onclick = (e) => { ui.veg = !ui.veg; e.currentTarget.classList.toggle('on', ui.veg); draw(); };
  draw();
}

async function viewCart() {
  const c = cart.load();
  if (!Object.keys(c.items).length) {
    view.innerHTML = `<div class="empty"><div class="big">🛒</div><h2>Your cart is empty</h2><p>Pick an outlet and add something tasty.</p><a class="btn primary" href="#/">Browse outlets</a></div>`;
    return;
  }
  const [slots, home] = await Promise.all([api(`/outlets/${c.outlet_id}/slots`), api('/home'), refreshMe()]);
  const ui = { coupon: null, discount: 0, slot: null };
  const firstFree = slots.find((s) => s.available > 0);

  const applyCoupon = async (code, quiet) => {
    const r = await attempt(() => api('/coupons/check', { body: { code, subtotal: cart.subtotal() } }));
    if (r) {
      ui.coupon = r.code; ui.discount = r.discount;
      if (!quiet) toast(`${r.code} applied - you save ${inr(r.discount)}`);
    } else {
      ui.coupon = null; ui.discount = 0;
    }
    store.set('cb_coupon', null);
    draw();
  };

  const draw = () => {
    const cc = cart.load();
    const ls = Object.values(cc.items);
    if (!ls.length) return viewCart();
    const sub = cart.subtotal();
    const disc = Math.min(ui.discount, sub);
    const tax = round2((sub - disc) * GST);
    const total = round2(sub - disc + tax);
    const short = total - state.me.wallet_balance;

    view.innerHTML = `
      <a class="back" href="#/outlet/${cc.outlet_id}">${icon('back').replace('<svg', '<svg width="18" height="18"')} Add more from ${esc(cc.outlet_name)}</a>
      <h1 style="margin-bottom:16px">Checkout</h1>
      <div class="cols">
        <div class="stack">
          <div class="card">
            <div class="row between" style="margin-bottom:4px"><h3>${esc(cc.outlet_name)}</h3><span class="small muted">${ls.length} dish${ls.length > 1 ? 'es' : ''}</span></div>
            ${ls.map((i) => `
              <div class="line-item">
                <img src="${img(i.image_url, 120, 120)}" alt="">
                <div class="grow"><div class="row" style="gap:6px">${vegMark(i.is_veg)}<b class="small">${esc(i.name)}</b></div><span class="small muted">${inr(i.price)} each</span></div>
                <div class="stepper" data-step="${i.item_id}"><button data-d="-1">−</button><span>${i.qty}</span><button data-d="1">+</button></div>
                <b class="num" style="width:64px;text-align:right">${inr(i.qty * i.price)}</b>
              </div>`).join('')}
          </div>
          <div class="card stack">
            <div><h3>Pickup slot</h3><p class="small muted">Each slot takes a limited number of orders so nobody waits at the counter.</p></div>
            <div class="chips" id="slots">
              <button class="slot ${!ui.slot ? 'on' : ''}" data-slot=""><b>⚡ ASAP</b><span>${firstFree ? '≈ ' + esc(firstFree.label) : 'No slots'}</span></button>
              ${slots.map((s) => `<button class="slot ${ui.slot === s.slot ? 'on' : ''} ${s.available <= 2 ? 'low' : ''}" data-slot="${s.slot}" ${s.available ? '' : 'disabled'}>
                <b>${esc(s.label)}</b><span>${s.available ? `${s.available} left` : 'Full'}</span></button>`).join('')}
            </div>
            <label class="field">Note for the kitchen<textarea class="input" id="notes" maxlength="200" placeholder="Less spicy, no onion, extra chutney…">${esc(ui.notes || '')}</textarea></label>
          </div>
        </div>
        <div class="stack">
          <div class="card stack">
            <h3>Offers</h3>
            ${home.offers.map((o) => `<button class="coupon-pick ${ui.coupon === o.code ? 'on' : ''}" data-code="${esc(o.code)}">
              <span class="grow"><b>${esc(o.code)}</b><br><span class="small soft">${Number(o.discount_pct)}% off up to ${inr(o.max_discount)}${o.min_order > 0 ? ` · min ${inr(o.min_order)}` : ''}</span></span>
              <span class="small bold" style="color:${ui.coupon === o.code ? 'var(--green)' : 'var(--accent)'}">${ui.coupon === o.code ? '✓ Applied' : 'Apply'}</span></button>`).join('')}
            <div class="row"><input class="input grow" id="coupon" placeholder="Have a code?" style="text-transform:uppercase"><button class="btn" id="apply">Apply</button></div>
          </div>
          <div class="card bill">
            <h3 style="margin-bottom:4px">Bill</h3>
            <div class="line"><span>Item total</span><span>${inr(sub)}</span></div>
            ${disc ? `<div class="line" style="color:var(--green)"><span>Coupon ${esc(ui.coupon)}</span><span>−${inr(disc)}</span></div>` : ''}
            <div class="line"><span>GST (5%)</span><span>${inr(tax)}</span></div>
            <div class="line total"><span>To pay</span><span>${inr(total)}</span></div>
            <div class="line small"><span>Wallet balance</span><span class="${short > 0 ? '' : ''}" style="color:${short > 0 ? 'var(--bad)' : 'var(--green)'}">${inr(state.me.wallet_balance)}</span></div>
          </div>
          <div class="pay-bar"><button class="btn primary block" id="place">${short > 0 ? `Add ${inr(Math.ceil(short))} to wallet` : `Pay ${inr(total)} · Place order`}</button></div>
          <p class="tiny muted center">Paid from your CampusBite wallet. Free cancellation until the outlet accepts.</p>
        </div>
      </div>`;

    $$('[data-step]').forEach((s) => $$('button', s).forEach((b) => b.onclick = () => {
      const it = cc.items[s.dataset.step];
      const next = it.qty + Number(b.dataset.d);
      if (next > it.stock_qty) return toast(`Only ${it.stock_qty} left today`, true);
      cart.set({ outlet_id: cc.outlet_id, name: cc.outlet_name }, it, next);
      if (ui.coupon) applyCoupon(ui.coupon, true); else draw();
    }));
    $$('#slots [data-slot]').forEach((b) => b.onclick = () => { ui.notes = $('#notes').value; ui.slot = b.dataset.slot || null; draw(); });
    $('#notes').oninput = (e) => { ui.notes = e.target.value; };
    $$('[data-code]').forEach((b) => b.onclick = () => {
      ui.notes = $('#notes').value;
      if (ui.coupon === b.dataset.code) { ui.coupon = null; ui.discount = 0; draw(); } else applyCoupon(b.dataset.code);
    });
    $('#apply').onclick = () => { const code = $('#coupon').value.trim(); if (code) { ui.notes = $('#notes').value; applyCoupon(code); } };
    $('#place').onclick = short > 0 ? () => { location.hash = '#/wallet'; } : placeOrder;
  };

  const placeOrder = async () => {
    const cc = cart.load();
    const res = await attempt(() => api('/orders', {
      body: {
        outlet_id: cc.outlet_id,
        items: Object.values(cc.items).map((i) => ({ item_id: i.item_id, qty: i.qty })),
        coupon: ui.coupon, pickup_slot: ui.slot, notes: (ui.notes || '').trim() || null,
      },
    }), $('#place'));
    if (res) {
      cart.clear();
      refreshMe();
      toast(`Order placed! Token #${res.token_no}`);
      location.hash = `#/order/${res.order_id}`;
    } else {
      // a slot may have filled up meanwhile
      const fresh = await api(`/outlets/${c.outlet_id}/slots`).catch(() => null);
      if (fresh) { slots.splice(0, slots.length, ...fresh); draw(); }
    }
  };

  draw();
  const saved = store.get('cb_coupon');
  if (saved) applyCoupon(saved);
}

async function viewOrders() {
  const orders = await api('/orders/mine');
  let tab = orders.some((o) => ACTIVE.includes(o.status)) ? 'active' : 'past';
  const draw = () => {
    const list = orders.filter((o) => (tab === 'active') === ACTIVE.includes(o.status));
    $('#list').innerHTML = list.length ? list.map((o) => `
      <a class="card row top" href="#/order/${o.order_id}" style="gap:14px">
        <img src="${img(o.cover_url, 160, 160)}" alt="" style="width:64px;height:64px;border-radius:14px;object-fit:cover;flex:none">
        <div class="grow stack tight">
          <div class="row between"><b>${esc(o.outlet_name)}</b><b class="num">${inr(o.total_amount)}</b></div>
          <div class="small soft clamp2">${esc(o.items_text)}</div>
          <div class="row between">${statusBadge(o.status)}<span class="tiny muted">Token ${o.token_no} · ${when(o.placed_at)}</span></div>
        </div>
      </a>`).join('') : `<div class="empty"><div class="big">🍽️</div>${tab === 'active' ? 'No active orders. Hungry?' : 'No past orders yet.'}${tab === 'active' ? '<a class="btn primary" href="#/">Order something</a>' : ''}</div>`;
  };
  view.innerHTML = `
    <h1 style="margin-bottom:14px">My orders</h1>
    <div class="tabs" id="tabs" style="max-width:360px"><button data-t="active">Active</button><button data-t="past">Past</button></div>
    <div class="stack" id="list" style="margin-top:14px"></div>`;
  const setTab = (t) => { tab = t; $$('#tabs button').forEach((x) => x.classList.toggle('on', x.dataset.t === t)); draw(); };
  $$('#tabs button').forEach((b) => b.onclick = () => setTab(b.dataset.t));
  setTab(tab);
}

async function viewOrder(id) {
  let lastStatus = null;
  const draw = async () => {
    const { order: o, items, log, wait_minutes } = await api(`/orders/${id}`);
    const at = FLOW.indexOf(o.status);
    const mine = state.me.user_id === o.user_id;
    if (lastStatus && lastStatus !== o.status && o.status === 'READY' && mine) {
      beep();
      if ('vibrate' in navigator) navigator.vibrate([200, 100, 200]);
      toast('Your order is ready! 🎉');
    }
    lastStatus = o.status;
    const headline = {
      PLACED: 'Waiting for the outlet to accept',
      ACCEPTED: 'Order accepted',
      PREPARING: 'Your food is being prepared',
      READY: 'Ready for pickup!',
      PICKED_UP: 'Enjoy your meal 😋',
      CANCELLED: 'Order cancelled & refunded',
    }[o.status];
    const showQr = mine && ACTIVE.includes(o.status);

    view.innerHTML = `
      <a class="back" href="${mine ? '#/orders' : '#/v/board'}">${icon('back').replace('<svg', '<svg width="18" height="18"')} ${mine ? 'My orders' : 'Live orders'}</a>
      <div class="cols">
        <div class="ticket">
          <div class="head ${o.status === 'PICKED_UP' || o.status === 'READY' ? 'done' : o.status === 'CANCELLED' ? 'cancel' : ''}">
            <img src="${img(o.cover_url, 900, 500)}" alt="">
            <div class="row between top">
              <div><div class="small" style="opacity:.85;font-weight:700;letter-spacing:.08em">TOKEN</div><div class="tok">${o.token_no}</div></div>
              <div style="text-align:right"><div class="small" style="opacity:.85">${esc(o.outlet_name)}</div>
                <div style="font-size:20px;font-weight:800">${o.pickup_slot ? time(o.pickup_slot) : ''}</div><div class="tiny" style="opacity:.8">pickup slot</div></div>
            </div>
            <h2 style="color:#fff;margin-top:10px">${headline}</h2>
            ${wait_minutes && o.status !== 'READY' ? `<div class="small" style="opacity:.85">Kitchen estimate about ${wait_minutes} min</div>` : ''}
            ${o.status !== 'CANCELLED' ? `<div class="steps">${FLOW.map((s, k) => `<div class="s ${k < at || o.status === 'PICKED_UP' ? 'done' : k === at ? 'now' : ''}"><i></i>${STATUS[s][0]}</div>`).join('')}</div>` : ''}
          </div>
          ${showQr ? `<div class="perf"></div>
          <div class="qr-zone">
            <div class="qr-box" id="qr"></div>
            <div class="pickup-code">${esc(o.pickup_code)}</div>
            <p class="small soft" style="max-width:280px">Show this QR at the counter. The outlet scans it to hand over your food - no one else can collect your order.</p>
          </div>` : ''}
          ${o.status === 'PICKED_UP' ? `<div class="qr-zone"><span class="badge green">${icon('check').replace('<svg', '<svg width="14" height="14"')} Collected ${o.picked_up_at ? time(o.picked_up_at) : ''}</span></div>` : ''}
        </div>
        <div class="stack">
          <div class="card stack">
            <h3>Items</h3>
            ${items.map((i) => `
              <div class="stack tight">
                <div class="line-item" style="padding:2px 0">
                  <img src="${img(i.image_url, 120, 120)}" alt="">
                  <div class="grow"><div class="row" style="gap:6px">${vegMark(i.is_veg)}<b class="small">${esc(i.name)}</b></div><span class="small muted">× ${i.qty}</span></div>
                  <b class="num">${inr(i.line_total)}</b>
                </div>
                ${mine && o.status === 'PICKED_UP' ? (i.my_rating
                  ? `<div class="small muted">You rated <span class="star">${'★'.repeat(i.my_rating)}</span></div>`
                  : `<div class="row small"><span class="muted">How was it?</span><span class="stars" data-item="${i.item_id}">${[1, 2, 3, 4, 5].map((n) => `<button data-r="${n}" aria-label="${n} stars">★</button>`).join('')}</span></div>`) : ''}
              </div>`).join('')}
            <hr style="margin:2px 0">
            <div class="bill">
              <div class="line"><span>Item total</span><span>${inr(o.subtotal)}</span></div>
              ${o.discount > 0 ? `<div class="line" style="color:var(--green)"><span>Coupon ${esc(o.coupon_code)}</span><span>−${inr(o.discount)}</span></div>` : ''}
              <div class="line"><span>GST</span><span>${inr(o.tax)}</span></div>
              <div class="line total"><span>Paid</span><span>${inr(o.total_amount)}</span></div>
            </div>
            ${o.notes ? `<div class="small"><b>Note:</b> ${esc(o.notes)}</div>` : ''}
          </div>
          <div class="card stack">
            <h3>Timeline</h3>
            <div class="timeline">${log.map((l) => `<div class="ev"><i style="${l.new_status === 'CANCELLED' ? 'background:var(--bad);box-shadow:0 0 0 4px var(--bad-soft)' : ''}"></i><span>${STATUS[l.new_status][0]}</span><span class="small muted">${time(l.changed_at)}</span></div>`).join('')}</div>
            ${mine && o.status === 'PLACED' ? '<button class="btn danger block" id="cancel">Cancel order & refund</button>' : ''}
          </div>
        </div>
      </div>`;

    if (showQr && window.QRCode) {
      // eslint-disable-next-line no-new
      new QRCode($('#qr'), { text: `CAMPUSBITE:${o.order_id}:${o.pickup_code}`, width: 360, height: 360, correctLevel: QRCode.CorrectLevel.M });
    }
    const cancel = $('#cancel');
    if (cancel) cancel.onclick = async () => {
      if (!confirm('Cancel this order? The full amount goes back to your wallet.')) return;
      if (await attempt(() => api(`/orders/${id}/cancel`, { body: {} }), cancel)) { toast('Order cancelled and refunded'); refreshMe(); draw(); }
    };
    $$('.stars').forEach((s) => {
      $$('button', s).forEach((b) => {
        b.onmouseenter = () => $$('button', s).forEach((x) => x.classList.toggle('on', Number(x.dataset.r) <= Number(b.dataset.r)));
        b.onclick = async () => {
          if (await attempt(() => api(`/orders/${id}/review`, { body: { item_id: Number(s.dataset.item), rating: Number(b.dataset.r) } }))) {
            toast('Thanks for the rating!'); draw();
          }
        };
      });
    });
    if (!ACTIVE.includes(o.status)) clearInterval(state.timer);
  };
  await draw();
  poll(() => draw().catch(() => {}));
}

async function viewWallet() {
  const w = await api('/wallet');
  await refreshMe();
  const kind = {
    TOPUP: ['Added money', 'var(--green-soft)', 'var(--green)', 'up', '+'],
    DEBIT: ['Order payment', 'var(--surface-2)', 'var(--text-2)', 'down', '−'],
    REFUND: ['Refund', 'var(--info-soft)', 'var(--info)', 'refund', '+'],
  };
  view.innerHTML = `
    <h1 style="margin-bottom:16px">Wallet</h1>
    <div class="cols">
      <div class="stack">
        <div class="wallet-hero">
          <div class="small" style="opacity:.85;font-weight:700">CampusBite balance</div>
          <div class="amt">${inr(w.balance)}</div>
          <div class="row" style="margin-top:12px"><span class="badge glass">⭐ ${w.loyalty_points} points</span><span class="small" style="opacity:.8">1 point for every ₹10 spent</span></div>
        </div>
        <div class="card stack">
          <h3>Add money</h3>
          <div class="chips">${[100, 200, 500, 1000].map((a) => `<button class="chip" data-a="${a}">+ ${inr(a)}</button>`).join('')}</div>
          <div class="row"><input class="input grow" id="amt" type="number" min="1" max="5000" placeholder="Amount (max ₹5,000)"><button class="btn primary" id="add">Add</button></div>
          <div class="tiny muted">Demo build: UPI payment is simulated and the amount is credited instantly.</div>
        </div>
      </div>
      <div class="card">
        <h3 style="margin-bottom:4px">Transactions</h3>
        ${w.txns.length ? w.txns.map((t) => `
          <div class="txn">
            <div class="ic" style="background:${kind[t.txn_type][1]};color:${kind[t.txn_type][2]}">${icon(kind[t.txn_type][3])}</div>
            <div class="grow"><div class="bold small">${kind[t.txn_type][0]} ${t.order_id ? `<a style="color:var(--accent)" href="#/order/${t.order_id}">#${t.order_id}</a>` : ''}</div>
              <div class="tiny muted">${when(t.created_at)}</div></div>
            <div style="text-align:right"><div class="num bold" style="color:${t.txn_type === 'DEBIT' ? 'var(--text)' : 'var(--green)'}">${kind[t.txn_type][4]}${inr(t.amount)}</div>
              <div class="tiny muted num">Bal ${inr(t.balance_after)}</div></div>
          </div>`).join('') : '<div class="empty">No transactions yet</div>'}
      </div>
    </div>`;

  const add = async (amount, btn) => {
    const r = await attempt(() => api('/wallet/topup', { body: { amount } }), btn);
    if (r) { toast(`${inr(amount)} added to your wallet`); viewWallet(); }
  };
  $$('[data-a]').forEach((b) => b.onclick = () => add(Number(b.dataset.a), b));
  $('#add').onclick = (e) => add(Number($('#amt').value), e.target);
}

async function viewProfile() {
  const me = await refreshMe();
  view.innerHTML = `
    <div style="max-width:560px;margin:0 auto" class="stack">
      <div class="card pad-lg row" style="gap:16px">
        <div class="avatar" style="width:64px;height:64px;font-size:22px">${esc(me.full_name.split(' ').map((w) => w[0]).join('').slice(0, 2))}</div>
        <div class="grow"><h2>${esc(me.full_name)}</h2><div class="muted small">${esc(me.email)}</div>
          <span class="badge accent" style="margin-top:6px">${me.role[0] + me.role.slice(1).toLowerCase()}</span></div>
      </div>
      <div class="card bill">
        ${me.reg_no ? `<div class="line"><span>Registration no.</span><b>${esc(me.reg_no)}</b></div>` : ''}
        ${me.phone ? `<div class="line"><span>Phone</span><b>${esc(me.phone)}</b></div>` : ''}
        ${me.role === 'STUDENT' ? `<div class="line"><span>Loyalty points</span><b>⭐ ${me.loyalty_points}</b></div>` : ''}
        <div class="line"><span>Member since</span><b>${day(me.created_at)} ${D(me.created_at).getFullYear()}</b></div>
      </div>
      <button class="btn block danger" id="logout">Log out</button>
      <p class="tiny muted center">CampusBite · Oracle PL/SQL + Node.js · BCSE302P</p>
    </div>`;
  $('#logout').onclick = async () => {
    await api('/auth/logout', { body: {} });
    state.me = null;
    location.hash = '#/login';
  };
}

// ================================================================ VENDOR
function outletPicker(outlets, current) {
  if (outlets.length < 2) return '';
  return `<select class="input" id="outletSel" style="max-width:240px;min-height:42px">${outlets.map((o) => `<option value="${o.outlet_id}" ${o.outlet_id === current ? 'selected' : ''}>${esc(o.name)}</option>`).join('')}</select>`;
}
const currentOutlet = () => Number(store.get('cb_outlet')) || '';
function bindOutletPicker(redraw) {
  const sel = $('#outletSel');
  if (sel) sel.onchange = () => { store.set('cb_outlet', sel.value); redraw(); };
}

// QR / code hand-over dialog. expected = order the vendor clicked (optional).
function pickupDialog(outlet, expected, done) {
  let scanner = null;
  const stop = () => { if (scanner) { scanner.stop().catch(() => {}); scanner = null; } };

  const verify = async (code, orderId, btn) => {
    const r = await attempt(() => api('/vendor/pickup', { body: { outlet_id: outlet.outlet_id, code, order_id: orderId || null } }), btn);
    if (!r) return;
    stop();
    beep();
    $('.sheet .sheet-body').innerHTML = `
      <div class="success-burst">
        <div class="check">${icon('check')}</div>
        <h2>Token ${r.token_no} handed over</h2>
        <p class="soft">${esc(r.customer)}${r.reg_no ? ' · ' + esc(r.reg_no) : ''}</p>
        <p class="small">${esc(r.items_text)}</p>
        <button class="btn primary block" id="doneBtn">Done</button>
      </div>`;
    $('#doneBtn').onclick = closeSheet;
    done();
  };

  openSheet(`
    <div class="grab"></div>
    <div class="sheet-body">
      <div class="row between"><h2>${expected ? `Hand over token ${expected.token_no}` : 'Verify pickup'}</h2><button class="icon-btn" data-close aria-label="Close">${icon('close')}</button></div>
      <p class="small soft">${expected ? `Scan ${esc(expected.customer)}'s QR or type the 6-digit code from their phone.` : 'Scan the student\'s QR code or type their 6-digit pickup code.'}</p>
      <div class="scanner" id="reader">Starting camera…</div>
      <div class="row"><input class="input code-input grow" id="code" inputmode="numeric" maxlength="6" placeholder="••••••" autocomplete="off"><button class="btn primary" id="verifyBtn">Verify</button></div>
    </div>`, (sh) => {
    sh.parentElement._cleanup = stop;
    $('[data-close]', sh).onclick = closeSheet;
    const input = $('#code', sh);
    input.oninput = () => { input.value = input.value.replace(/\D/g, ''); if (input.value.length === 6) verify(input.value, expected?.order_id, $('#verifyBtn')); };
    $('#verifyBtn', sh).onclick = (e) => verify(input.value, expected?.order_id, e.target);

    const startCam = () => {
      if (!window.Html5Qrcode) return;
      if (!window.isSecureContext) { $('#reader').textContent = 'Camera needs HTTPS - type the code below.'; return; }
      scanner = new Html5Qrcode('reader');
      let busy = false;
      scanner.start({ facingMode: 'environment' }, { fps: 10, qrbox: 220 }, (text) => {
        const m = /^CAMPUSBITE:(\d+):(\d{6})$/.exec(text);
        if (!m || busy) return;
        busy = true;
        verify(m[2], Number(m[1])).finally(() => { busy = false; });
      }).catch(() => { $('#reader').textContent = 'Camera not available - type the code below.'; scanner = null; });
    };
    if (window.Html5Qrcode) startCam();
    else {
      const s = document.createElement('script');
      s.src = 'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js';
      s.onload = startCam;
      s.onerror = () => { $('#reader').textContent = 'Scanner unavailable offline - type the code below.'; };
      document.head.appendChild(s);
    }
  });
}

async function viewBoard() {
  const outlets = await api('/vendor/outlets');
  const lanes = [
    ['PLACED', 'New orders', [['ACCEPTED', 'Accept', 'primary'], ['CANCELLED', 'Reject', 'danger']]],
    ['ACCEPTED', 'Accepted', [['PREPARING', 'Start cooking', 'primary'], ['CANCELLED', 'Cancel', 'danger']]],
    ['PREPARING', 'Cooking', [['READY', 'Mark ready', 'green']]],
    ['READY', 'Ready · awaiting pickup', [['SCAN', 'Verify pickup', 'dark']]],
  ];
  let seen = null;
  let data = null;

  const draw = async () => {
    data = await api(`/vendor/orders?outlet_id=${currentOutlet()}`);
    const { outlet, orders, wait_minutes, slots } = data;
    const fresh = orders.filter((o) => o.status === 'PLACED').map((o) => o.order_id);
    if (seen && fresh.some((idn) => !seen.includes(idn))) { beep(); toast('🔔 New order received'); }
    seen = fresh;
    const done = orders.filter((o) => !ACTIVE.includes(o.status)).reverse();
    const late = (o) => o.pickup_slot && D(o.pickup_slot) < new Date() && ['PLACED', 'ACCEPTED', 'PREPARING'].includes(o.status);

    view.innerHTML = `
      <div class="vhead">
        <div><h1>${esc(outlet.name)}</h1><div class="muted small">Live · refreshes every 5 s · kitchen time ~${wait_minutes} min</div></div>
        <div class="row wrap">
          ${outletPicker(outlets, outlet.outlet_id)}
          <label class="row small bold">${outlet.is_open === 'Y' ? 'Taking orders' : 'Paused'}
            <span class="switch"><input type="checkbox" id="openSw" ${outlet.is_open === 'Y' ? 'checked' : ''}><span></span></span></label>
          <button class="btn primary" id="scanBtn">${icon('qr')} Scan pickup QR</button>
        </div>
      </div>
      <div class="card" style="padding:12px 14px">
        <div class="row between" style="margin-bottom:8px"><b class="small">Upcoming pickup slots</b><span class="tiny muted">${outlet.slot_capacity} orders per 15 min</span></div>
        <div class="slot-strip">${slots.map((s) => {
          const pct = Math.round((s.booked / s.capacity) * 100);
          return `<div class="sl ${s.available === 0 ? 'full' : pct >= 60 ? 'busy' : ''}"><b>${esc(s.label)}</b><div class="meter"><i style="width:${Math.max(pct, 3)}%"></i></div><span class="tiny muted">${s.booked}/${s.capacity}</span></div>`;
        }).join('')}</div>
      </div>
      <div class="board">${lanes.map(([st, title, acts]) => {
        const list = orders.filter((o) => o.status === st);
        return `<div class="lane"><div class="lane-head"><span>${title}</span><span class="count">${list.length}</span></div>
          ${list.map((o) => `
            <div class="vticket ${late(o) ? 'late' : ''}">
              <div class="row between top">
                <div class="row"><div class="tk">${o.token_no}</div>
                  <div><b class="small">${esc(o.customer)}</b><div class="tiny muted">${esc(o.reg_no || '')} · ${ago(o.placed_at)}</div></div></div>
                <div style="text-align:right"><b class="num small">${inr(o.total_amount)}</b><div class="tiny ${late(o) ? '' : 'muted'}" style="${late(o) ? 'color:var(--bad);font-weight:800' : ''}">⏰ ${esc(o.slot_label || '')}</div></div>
              </div>
              <div class="items">${esc(o.items_text)}</div>
              ${o.notes ? `<div class="note">📝 ${esc(o.notes)}</div>` : ''}
              <div class="row">${acts.map(([to, l, cls]) => `<button class="btn sm ${cls} ${cls !== 'danger' ? 'grow' : ''}" data-o="${o.order_id}" data-to="${to}">${l}</button>`).join('')}</div>
            </div>`).join('') || '<div class="tiny muted" style="padding:8px">Nothing here</div>'}
        </div>`;
      }).join('')}</div>
      <div class="section">
        <div class="section-head"><h2>Completed in the last 3 hours</h2></div>
        <div class="card table-wrap">${done.length ? `<table><tr><th>Token</th><th>Customer</th><th>Items</th><th>Status</th><th class="r">Amount</th></tr>
          ${done.map((o) => `<tr><td><b>#${o.token_no}</b></td><td>${esc(o.customer)}</td><td class="small">${esc(o.items_text)}</td><td>${statusBadge(o.status)}</td><td class="r">${inr(o.total_amount)}</td></tr>`).join('')}</table>`
          : '<div class="empty" style="padding:16px">No completed orders yet</div>'}</div>
      </div>`;

    bindOutletPicker(draw);
    $('#openSw').onchange = async (e) => {
      await attempt(() => api(`/vendor/outlets/${outlet.outlet_id}`, { method: 'PATCH', body: { is_open: e.target.checked ? 'Y' : 'N' } }));
      draw();
    };
    $('#scanBtn').onclick = () => pickupDialog(outlet, null, draw);
    $$('[data-to]').forEach((b) => b.onclick = async () => {
      const o = orders.find((x) => x.order_id === Number(b.dataset.o));
      if (b.dataset.to === 'SCAN') return pickupDialog(outlet, o, draw);
      if (b.dataset.to === 'CANCELLED' && !confirm(`Cancel token ${o.token_no}? ${o.customer} is refunded in full.`)) return;
      if (await attempt(() => api(`/vendor/orders/${b.dataset.o}/status`, { body: { status: b.dataset.to } }), b)) draw();
    });
  };
  await draw();
  poll(() => { if (!$('.sheet-bg')) draw().catch(() => {}); });
}

async function viewVendorMenu() {
  const outlets = await api('/vendor/outlets');
  const draw = async () => {
    const { outlet, items, categories } = await api(`/vendor/menu?outlet_id=${currentOutlet()}`);
    view.innerHTML = `
      <div class="vhead">
        <div><h1>Menu & stock</h1><div class="muted small">${esc(outlet.name)} · stock 0 hides a dish automatically (trigger)</div></div>
        <div class="row wrap">${outletPicker(outlets, outlet.outlet_id)}<button class="btn primary" id="newBtn">${icon('plus')} New dish</button></div>
      </div>
      <div class="card row wrap" style="margin-bottom:14px;gap:14px">
        <div class="grow"><b>Pickup slot capacity</b><div class="small muted">Maximum orders you accept per 15-minute pickup slot (applies to new slots).</div></div>
        <div class="row"><input class="input num" id="cap" type="number" min="1" max="200" value="${outlet.slot_capacity}" style="width:90px"><button class="btn" id="capSave">Save</button></div>
      </div>
      <form class="card stack hidden" id="newForm" style="margin-bottom:14px">
        <h3>Add a dish</h3>
        <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(170px,1fr))">
          <label class="field">Name<input class="input" name="name" required maxlength="80"></label>
          <label class="field">Category<select class="input" name="category_id">${categories.map((c) => `<option value="${c.category_id}">${esc(c.name)}</option>`).join('')}</select></label>
          <label class="field">Price (₹)<input class="input" name="price" type="number" min="1" step="0.5" required></label>
          <label class="field">Opening stock<input class="input" name="stock_qty" type="number" min="0" value="20"></label>
          <label class="field">Prep time (min)<input class="input" name="prep_minutes" type="number" min="1" max="120" value="10"></label>
          <label class="field">Type<select class="input" name="is_veg"><option value="Y">Veg</option><option value="N">Non-veg</option></select></label>
        </div>
        <label class="field">Description<input class="input" name="description" maxlength="300"></label>
        <label class="field">Photo URL (optional)<input class="input" name="image_url" type="url" placeholder="https://images.unsplash.com/photo-…"></label>
        <div class="row"><button class="btn primary">Save dish</button><button type="button" class="btn" id="cancelNew">Cancel</button></div>
      </form>
      <div class="card table-wrap">
        <table>
          <tr><th></th><th>Dish</th><th class="r">Price ₹</th><th class="r">Stock</th><th>On menu</th><th class="r">Rating</th><th></th></tr>
          ${items.map((i) => `
            <tr data-id="${i.item_id}">
              <td style="width:56px"><img class="thumb" src="${img(i.image_url, 100, 100)}" alt=""></td>
              <td><div class="row" style="gap:8px">${vegMark(i.is_veg)}<b>${esc(i.name)}</b></div><div class="tiny muted">${esc(i.category)}</div></td>
              <td class="r"><input class="input num" name="price" type="number" min="1" step="0.5" value="${i.price}"></td>
              <td class="r"><input class="input num" name="stock_qty" type="number" min="0" value="${i.stock_qty}" style="${i.stock_qty <= 5 ? 'border-color:var(--warn);color:var(--warn);font-weight:800' : ''}"></td>
              <td><span class="switch"><input type="checkbox" name="avail" ${i.is_available === 'Y' ? 'checked' : ''}><span></span></span></td>
              <td class="r small">${i.rating_count ? `<span class="star">★</span> ${Number(i.rating_avg).toFixed(1)} <span class="muted">(${i.rating_count})</span>` : '<span class="muted">-</span>'}</td>
              <td><button class="btn sm" data-save>Save</button></td>
            </tr>`).join('')}
        </table>
      </div>`;

    bindOutletPicker(draw);
    const form = $('#newForm');
    $('#newBtn').onclick = () => form.classList.remove('hidden');
    $('#cancelNew').onclick = () => form.classList.add('hidden');
    $('#capSave').onclick = async (e) => {
      if (await attempt(() => api(`/vendor/outlets/${outlet.outlet_id}`, { method: 'PATCH', body: { slot_capacity: $('#cap').value } }), e.target)) toast('Slot capacity saved');
    };
    form.onsubmit = async (e) => {
      e.preventDefault();
      const body = { ...Object.fromEntries(new FormData(form)), outlet_id: outlet.outlet_id };
      if (await attempt(() => api('/vendor/menu', { body }), form.querySelector('button'))) { toast('Dish added'); draw(); }
    };
    $$('tr[data-id]').forEach((tr) => {
      const save = async (btn) => {
        const body = {
          price: $('[name=price]', tr).value,
          stock_qty: $('[name=stock_qty]', tr).value,
          is_available: $('[name=avail]', tr).checked ? 'Y' : 'N',
        };
        if (await attempt(() => api(`/vendor/menu/${tr.dataset.id}`, { method: 'PATCH', body }), btn)) { toast('Saved'); draw(); }
      };
      $('[data-save]', tr).onclick = (e) => save(e.target);
      $('[name=avail]', tr).onchange = () => save();
    });
  };
  await draw();
}

function barChart(rows, key, labelKey) {
  if (!rows.length) return '<div class="empty" style="padding:16px">No sales in this period</div>';
  const W = 640, H = 220, padL = 44, padB = 26, padT = 10;
  const max = Math.max(...rows.map((r) => r[key])) || 1;
  const step = Math.pow(10, Math.floor(Math.log10(max)));
  const top = Math.ceil(max / step) * step;
  const bw = (W - padL) / rows.length;
  const y = (v) => padT + (H - padT - padB) * (1 - v / top);
  const ticks = [0, top / 2, top];
  return `<div class="chart" id="chart">
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Revenue by day">
      ${ticks.map((t) => `<line class="gridline" x1="${padL}" x2="${W}" y1="${y(t)}" y2="${y(t)}"/><text class="axis-label" x="${padL - 8}" y="${y(t) + 4}" text-anchor="end">${t >= 1000 ? (t / 1000) + 'k' : t}</text>`).join('')}
      ${rows.map((r, k) => {
        const x = padL + k * bw + 2;
        const w = Math.max(4, Math.min(bw - 4, 46));
        const cx = x + (bw - 4) / 2;
        const h = Math.max(2, H - padB - y(r[key]));
        const yy = H - padB - h;
        return `<g>
          <rect class="bar-hit" x="${padL + k * bw}" y="${padT}" width="${bw}" height="${H - padT - padB}" data-k="${k}"/>
          <path class="bar" d="M${cx - w / 2},${H - padB} V${yy + 4} q0,-4 4,-4 h${w - 8} q4,0 4,4 V${H - padB} Z"/>
          <text class="axis-label" x="${cx}" y="${H - 8}" text-anchor="middle">${day(r[labelKey])}</text>
        </g>`;
      }).join('')}
    </svg>
    <div class="tooltip hidden" id="tip"></div>
  </div>`;
}

function bindChart(rows) {
  const chart = $('#chart');
  if (!chart) return;
  const tip = $('#tip');
  $$('.bar-hit', chart).forEach((h) => {
    h.onmouseenter = h.onclick = () => {
      const r = rows[h.dataset.k];
      const box = h.getBoundingClientRect();
      const cb = chart.getBoundingClientRect();
      tip.innerHTML = `<b>${day(r.sale_date)}</b> · ${inr(r.revenue)} · ${r.orders} orders`;
      tip.style.left = (box.left - cb.left + box.width / 2) + 'px';
      tip.style.top = (h.nextElementSibling.getBoundingClientRect().top - cb.top) + 'px';
      tip.classList.remove('hidden');
    };
    h.onmouseleave = () => tip.classList.add('hidden');
  });
}

async function viewReports() {
  const outlets = await api('/vendor/outlets');
  let days = 7;
  const draw = async () => {
    const d = await api(`/vendor/reports?outlet_id=${currentOutlet()}&days=${days}`);
    const total = d.sales.reduce((a, r) => a + r.revenue, 0);
    view.innerHTML = `
      <div class="vhead">
        <div><h1>Reports</h1><div class="muted small">${esc(d.outlet.name)}</div></div>
        <div class="row wrap">${outletPicker(outlets, d.outlet.outlet_id)}
          <div class="tabs" id="days">${[7, 14, 30].map((n) => `<button data-d="${n}" class="${n === days ? 'on' : ''}">${n} days</button>`).join('')}</div></div>
      </div>
      <div class="tiles">
        <div class="tile accent"><div class="label">Revenue today</div><div class="value">${inr(d.today.revenue)}</div></div>
        <div class="tile"><div class="label">Orders today</div><div class="value">${d.today.orders}</div></div>
        <div class="tile"><div class="label">Avg order</div><div class="value">${inr(d.today.avg_order)}</div></div>
        <div class="tile"><div class="label">${days}-day revenue</div><div class="value">${inr(round2(total))}</div></div>
      </div>
      <div class="card" style="margin-top:14px">
        <div class="row between" style="margin-bottom:8px"><h3>Revenue by day</h3><span class="tiny muted">canteen_pkg.get_sales_report</span></div>
        ${barChart(d.sales, 'revenue', 'sale_date')}
      </div>
      <div class="cols even" style="margin-top:14px">
        <div class="card table-wrap">
          <div class="row between"><h3>Best sellers</h3><span class="tiny muted">get_top_items</span></div>
          <table><tr><th>#</th><th>Dish</th><th class="r">Sold</th><th class="r">Revenue</th></tr>
          ${d.top.map((t, k) => `<tr><td>${k + 1}</td><td>${esc(t.name)}</td><td class="r">${t.qty_sold}</td><td class="r">${inr(t.revenue)}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">No sales</td></tr>'}</table>
        </div>
        <div class="card table-wrap">
          <div class="row between"><h3>Low stock (≤ 10)</h3><span class="tiny muted">get_low_stock</span></div>
          <table><tr><th>Dish</th><th class="r">Stock</th><th>Status</th></tr>
          ${d.low.map((t) => `<tr><td>${esc(t.name)}</td><td class="r">${t.stock_qty}</td><td>${t.is_available === 'Y' ? '<span class="badge warn">⚠ Low</span>' : '<span class="badge bad">✕ Hidden</span>'}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">All items well stocked</td></tr>'}</table>
          ${d.alerts.length ? `<div class="small" style="margin-top:10px"><b>${d.alerts.length} open stock alert(s)</b> raised by trigger: ${d.alerts.map((a) => esc(a.name)).join(', ')}</div>` : ''}
        </div>
      </div>
      <div class="card table-wrap" style="margin-top:14px">
        <div class="row between wrap"><h3>Daily sales summary</h3><button class="btn sm" id="gen">Generate today's summary</button></div>
        <div class="tiny muted" style="margin:4px 0 8px">Built by canteen_pkg.generate_daily_summary - an explicit cursor over all outlets.</div>
        <table><tr><th>Date</th><th class="r">Orders</th><th class="r">Cancelled</th><th class="r">Items</th><th class="r">Revenue</th><th>Top dish</th></tr>
        ${d.summary.map((s) => `<tr><td>${day(s.summary_date)}</td><td class="r">${s.total_orders}</td><td class="r">${s.cancelled_orders}</td><td class="r">${s.items_sold}</td><td class="r">${inr(s.gross_revenue)}</td><td>${esc(s.top_item || '-')}</td></tr>`).join('')}</table>
      </div>
      ${d.prices.length ? `<div class="card table-wrap" style="margin-top:14px"><h3>Price changes</h3>
        <table><tr><th>Dish</th><th class="r">Old</th><th class="r">New</th><th>When</th></tr>
        ${d.prices.map((p) => `<tr><td>${esc(p.name)}</td><td class="r">${inr(p.old_price)}</td><td class="r">${inr(p.new_price)}</td><td class="small muted">${when(p.changed_at)}</td></tr>`).join('')}</table></div>` : ''}`;

    bindChart(d.sales);
    bindOutletPicker(draw);
    $$('#days button').forEach((b) => b.onclick = () => { days = Number(b.dataset.d); draw(); });
    $('#gen').onclick = async (e) => {
      const r = await attempt(() => api('/vendor/summary', { body: {} }), e.target);
      if (r) { toast(`Summary generated for ${r.outlets} outlets`); draw(); }
    };
  };
  await draw();
}

async function viewAdmin() {
  const { stats, outlets, users } = await api('/vendor/admin/overview');
  view.innerHTML = `
    <h1 style="margin-bottom:16px">Campus overview</h1>
    <div class="tiles">
      <div class="tile accent"><div class="label">All-time revenue</div><div class="value">${inr(stats.revenue)}</div></div>
      <div class="tile"><div class="label">Orders today</div><div class="value">${stats.orders_today}</div></div>
      <div class="tile"><div class="label">All-time orders</div><div class="value">${stats.orders}</div></div>
      <div class="tile"><div class="label">Students</div><div class="value">${stats.students}</div></div>
      <div class="tile"><div class="label">Wallet float</div><div class="value">${inr(stats.wallet_float)}</div></div>
    </div>
    <div class="section"><div class="section-head"><h2>Outlets</h2></div>
    <div class="card table-wrap"><table><tr><th>Outlet</th><th>Vendor</th><th class="r">Orders</th><th class="r">Revenue</th></tr>
      ${outlets.map((o) => `<tr><td><b>${esc(o.name)}</b></td><td>${esc(o.owner)}</td><td class="r">${o.orders}</td><td class="r">${inr(o.revenue)}</td></tr>`).join('')}</table></div></div>
    <div class="section"><div class="section-head"><h2>Users</h2></div>
    <div class="card table-wrap"><table><tr><th>Name</th><th>Email</th><th>Reg. no.</th><th>Role</th><th class="r">Wallet</th><th class="r">Points</th></tr>
      ${users.map((u) => `<tr><td>${esc(u.full_name)}</td><td class="small">${esc(u.email)}</td><td>${esc(u.reg_no || '-')}</td><td><span class="badge">${u.role}</span></td><td class="r">${inr(u.wallet_balance)}</td><td class="r">${u.loyalty_points}</td></tr>`).join('')}</table></div></div>`;
}

// ------------------------------------------------------------------ boot
window.addEventListener('hashchange', router);
(async () => {
  view.innerHTML = skeleton();
  try { await refreshMe(); } catch { state.me = null; }
  router();
})();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
