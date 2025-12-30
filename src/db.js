import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

dotenv.config();

let pool;

/**
 * Initialize MySQL/MariaDB Pool (Direct Connection via Public IP)
 */
export async function initDb() {
  pool = mysql.createPool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
    connectTimeout: 30000,
    acquireTimeout: 30000,
    timeout: 60000,
    timezone: 'Z',
    dateStrings: true,
    charset: 'utf8mb4'
  });

  // Test connection
  try {
    const connection = await pool.getConnection();
    console.log('[DB] MariaDB connected to', process.env.DB_HOST);
    connection.release();
  } catch (err) {
    console.error('[DB] Connection failed:', err.message);
    throw err;
  }

  return pool;
}

export const getPool = () => pool;

/** CALL stored procedure yang return kolom JSON */
export async function callJsonSP(spName, params = []) {
  try {
    const currentPool = getPool();
    if (!currentPool) {
      throw new Error('Database pool not initialized. Call initDb() first.');
    }

    const placeholders = params.map(() => '?').join(', ');
    const sql = `CALL ${spName}(${placeholders});`;
    console.log('[SP CALL]', sql, params);

    const [rows] = await currentPool.query(sql, params);
    const firstSet = Array.isArray(rows) ? rows[0] : rows;
    const firstRow = Array.isArray(firstSet) ? firstSet[0] : firstSet;

    if (!firstRow) {
      console.warn('[SP EMPTY RESULT]', spName);
      return null;
    }

    console.log('[SP RAW RESULT]', firstRow);

    // ✅ 1️⃣ kalau hasil SP-nya punya kolom json
    if (firstRow.json) {
      return typeof firstRow.json === 'string' ? JSON.parse(firstRow.json) : firstRow.json;
    }

    // ✅ 2️⃣ kalau hasil SP-nya langsung JSON string
    const jsonKey = Object.keys(firstRow).find(k => typeof firstRow[k] === 'string' && firstRow[k].trim().startsWith('{'));
    if (jsonKey) return JSON.parse(firstRow[jsonKey]);

    // ✅ 3️⃣ fallback: kalau hasilnya object biasa
    return firstRow;
  } catch (err) {
    console.error('[SP ERROR]', err);
    throw err;
  }
}
