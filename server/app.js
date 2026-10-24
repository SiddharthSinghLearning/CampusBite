// CampusBite Express app: JSON API + static front-end.
// Used by server/index.js locally and by api/index.js on Vercel.
const path = require('path');
const express = require('express');
const cookieSession = require('cookie-session');
const db = require('./db');

try {
  process.loadEnvFile(path.join(__dirname, '..', '.env'));
} catch {
  // variables come from the real environment (e.g. Vercel project settings)
}

const app = express();
app.set('trust proxy', 1);
app.use(express.json({ limit: '100kb' }));
// Signed cookie sessions: no server-side store, so they also work on serverless.
app.use(cookieSession({
  name: 'cb_session',
  keys: [process.env.SESSION_SECRET || 'dev-only-secret'],
  httpOnly: true,
  sameSite: 'lax',
  secure: process.env.NODE_ENV === 'production',
  maxAge: 7 * 24 * 3600 * 1000,
}));

app.use('/api', require('./routes/student'));
app.use('/api/vendor', require('./routes/vendor'));
app.use('/api', (req, res) => res.status(404).json({ error: 'Not found' }));

app.use(express.static(path.join(__dirname, '..', 'public')));

app.use((err, req, res, next) => {
  const known = db.toHttpError(err);
  if (known) return res.status(known.status).json({ error: known.message });
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server' });
});

module.exports = app;
