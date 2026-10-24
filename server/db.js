// Oracle connection pool and small helpers around node-oracledb (thin mode).
const oracledb = require('oracledb');

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
// Dates travel as the database's wall-clock time ("2026-10-22T13:45:00"),
// so the app shows campus time no matter where the Node server runs.
oracledb.fetchAsString = [oracledb.CLOB, oracledb.DATE];

let poolPromise;

function sessionSetup(conn, requested, cb) {
  conn.execute(
    `ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD"T"HH24:MI:SS'
                       NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD"T"HH24:MI:SS'
                       NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD"T"HH24:MI:SS'`,
    (err) => cb(err));
}

// Created on first use, which suits both a long-running server and
// short-lived serverless functions.
function getPool() {
  if (!poolPromise) {
    poolPromise = oracledb.createPool({
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      connectString: process.env.DB_CONNECT,
      poolMin: 0,
      poolMax: Number(process.env.DB_POOL_MAX) || 6,
      poolIncrement: 1,
      sessionCallback: sessionSetup,
    }).catch((err) => {
      poolPromise = null;
      throw err;
    });
  }
  return poolPromise;
}

// Oracle returns upper-case column names; the API uses lower case.
function lowerKeys(row) {
  const out = {};
  for (const k of Object.keys(row)) out[k.toLowerCase()] = row[k];
  return out;
}

async function withConn(fn) {
  const conn = await (await getPool()).getConnection();
  try {
    return await fn(conn);
  } finally {
    await conn.close();
  }
}

// SELECT helper: returns an array of lower-cased row objects.
async function query(sql, binds = {}) {
  return withConn(async (conn) => {
    const r = await conn.execute(sql, binds, { fetchTypeHandler: tsAsString });
    return (r.rows || []).map(lowerKeys);
  });
}

// TIMESTAMP columns are fetched as strings too (see fetchAsString above).
function tsAsString(meta) {
  if (meta.dbType === oracledb.DB_TYPE_TIMESTAMP || meta.dbType === oracledb.DB_TYPE_TIMESTAMP_TZ
      || meta.dbType === oracledb.DB_TYPE_TIMESTAMP_LTZ) {
    return { type: oracledb.STRING };
  }
  return undefined;
}

async function one(sql, binds = {}) {
  const rows = await query(sql, binds);
  return rows[0] || null;
}

// DML helper with autocommit.
async function exec(sql, binds = {}) {
  return withConn((conn) => conn.execute(sql, binds, { autoCommit: true }));
}

// Calls a PL/SQL block; OUT REF CURSORs are read fully and closed.
async function plsql(sql, binds = {}) {
  return withConn(async (conn) => {
    const r = await conn.execute(sql, binds, { fetchTypeHandler: tsAsString });
    const out = {};
    for (const [k, v] of Object.entries(r.outBinds || {})) {
      if (v && typeof v.getRows === 'function') {
        const rows = await v.getRows();
        await v.close();
        out[k] = rows.map(lowerKeys);
      } else {
        out[k] = v;
      }
    }
    return out;
  });
}

// Business-rule errors from the package (ORA-20000..20999) become 400s
// carrying just the human-readable message.
function toHttpError(err) {
  if (err && err.errorNum >= 20000 && err.errorNum <= 20999) {
    const first = String(err.message).split('\n')[0];
    return { status: 400, message: first.replace(/^ORA-\d+:\s*/, '') };
  }
  if (err && err.errorNum === 1) {
    return { status: 409, message: 'A record with these details already exists' };
  }
  if (err && err.errorNum === 2290) {
    return { status: 400, message: 'Some values are not valid' };
  }
  return null;
}

const OUT_NUM = { dir: oracledb.BIND_OUT, type: oracledb.NUMBER };
const OUT_CURSOR = { dir: oracledb.BIND_OUT, type: oracledb.CURSOR };

module.exports = { getPool, query, one, exec, plsql, toHttpError, OUT_NUM, OUT_CURSOR, oracledb };
