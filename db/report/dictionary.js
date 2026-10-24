// Dumps column and constraint metadata for every CANTEEN table to dictionary.json
// (used to build the relational-schema tables in the report).
const path = require('path');
process.loadEnvFile(path.join(__dirname, '..', '..', '.env'));
const oracledb = require('../../node_modules/oracledb');
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

(async () => {
  const conn = await oracledb.getConnection({
    user: process.env.DB_USER, password: process.env.DB_PASSWORD, connectString: process.env.DB_CONNECT,
  });
  const cols = (await conn.execute(
    `SELECT table_name, column_name, data_type, data_length, data_precision, data_scale, nullable,
            data_default, identity_column, column_id
       FROM user_tab_columns
      WHERE table_name IN (SELECT table_name FROM user_tables)
      ORDER BY table_name, column_id`, [], { fetchInfo: { DATA_DEFAULT: { type: oracledb.STRING } } })).rows;
  const cons = (await conn.execute(
    `SELECT c.table_name, c.constraint_name, c.constraint_type, c.search_condition_vc,
            cc.column_name, cc.position, r.table_name AS r_table, rc.column_name AS r_column
       FROM user_constraints c
       JOIN user_cons_columns cc ON cc.constraint_name = c.constraint_name
       LEFT JOIN user_constraints r ON r.constraint_name = c.r_constraint_name
       LEFT JOIN user_cons_columns rc ON rc.constraint_name = c.r_constraint_name AND rc.position = cc.position
      WHERE c.constraint_name NOT LIKE 'SYS%' AND c.table_name IN (SELECT table_name FROM user_tables)
      ORDER BY c.table_name, c.constraint_name, cc.position`)).rows;
  require('fs').writeFileSync(path.join(__dirname, 'dictionary.json'), JSON.stringify({ cols, cons }, null, 1));
  console.log(cols.length, 'columns,', cons.length, 'constraint columns');
  await conn.close();
})().catch((e) => { console.error(e); process.exit(1); });
