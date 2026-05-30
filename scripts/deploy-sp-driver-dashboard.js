/**
 * Deploy sp_driver_dashboard_json ke DB sesuai .env AML_API
 * Usage: node scripts/deploy-sp-driver-dashboard.js
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const sqlPath = path.join(__dirname, '..', 'sql', 'sp_driver_dashboard_json.sql');
const raw = fs.readFileSync(sqlPath, 'utf8');

// Strip DELIMITER lines and // terminators (HeidiSQL style)
const body = raw
  .replace(/^DELIMITER.*$/gm, '')
  .replace(/\/\/\s*$/gm, ';')
  .trim();

async function main() {
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    multipleStatements: true,
  });

  console.log('[deploy] target:', process.env.DB_HOST, '/', process.env.DB_NAME);

  await conn.query(body);
  console.log('[deploy] sp_driver_dashboard_json OK');

  const [rows] = await conn.query('SHOW CREATE PROCEDURE sp_driver_dashboard_json');
  const def = rows[0]['Create Procedure'] || '';
  console.log('[verify] recentDeliverys:', def.includes('recentDeliverys'));
  console.log('[verify] recentPickupReturs:', def.includes('recentPickupReturs'));
  console.log('[verify] _schemaVersion:', def.includes('_schemaVersion'));

  const [callRows] = await conn.query('CALL sp_driver_dashboard_json(?)', ['0']);
  const row = callRows[0][0];
  const key = Object.keys(row).find(
    (k) => typeof row[k] === 'string' && row[k].trim().startsWith('{')
  );
  const json = JSON.parse(row[key]);
  console.log('[verify] response keys:', Object.keys(json));

  await conn.end();
}

main().catch((err) => {
  console.error('[deploy] FAILED:', err.message);
  process.exit(1);
});
