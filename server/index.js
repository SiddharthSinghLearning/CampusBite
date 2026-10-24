// Local server: node server/index.js
const app = require('./app');
const db = require('./db');

const port = Number(process.env.PORT) || 3000;
db.getPool()
  .then(() => app.listen(port, '0.0.0.0', () => console.log(`CampusBite running on http://localhost:${port}`)))
  .catch((err) => {
    console.error('Could not connect to Oracle:', err.message);
    process.exit(1);
  });
