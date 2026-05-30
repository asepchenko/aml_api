/**
 * Deploy SP driver: delivery DPL + pickup retur
 *
 * PERINGATAN: .env AML_API sering mengarah ke DB LIVE.
 * Jangan jalankan script ini dari agent/CI otomatis.
 * Hanya operator yang mengetahui target DB boleh menjalankan secara manual.
 *
 * Manual usage (jika memang DB staging/lokal yang terisolasi):
 *   node scripts/deploy-sp-driver-dpl-pickup-retur.js
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const FILES = [
  'sp_driver_delivery_list_json.sql',
  'sp_driver_delivery_detail_json.sql',
  'sp_driver_delivery_start_process_json.sql',
  'sp_driver_delivery_deliver_item_json.sql',
  'sp_driver_pickup_retur_list_json.sql',
  'sp_driver_pickup_retur_detail_json.sql',
  'sp_driver_pickup_retur_status_json.sql',
];

function parseSqlFile(raw) {
  return raw
    .replace(/^DELIMITER.*$/gm, '')
    .replace(/\/\/\s*$/gm, ';')
    .trim();
}

async function main() {
  if (process.env.ALLOW_SP_DEPLOY !== 'yes') {
    console.error('[deploy] DITOLAK: set ALLOW_SP_DEPLOY=yes di .env hanya jika target DB bukan live.');
    console.error('[deploy] Untuk live: deploy manual lewat HeidiSQL — lihat docs/environment.md');
    process.exit(1);
  }

  const conn = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    multipleStatements: true,
  });

  console.log('[deploy] target:', process.env.DB_HOST, '/', process.env.DB_NAME);

  for (const file of FILES) {
    const sqlPath = path.join(__dirname, '..', 'sql', file);
    const body = parseSqlFile(fs.readFileSync(sqlPath, 'utf8'));
    await conn.query(body);
    console.log('[deploy] OK', file);
  }

  await conn.end();
  console.log('[deploy] selesai —', FILES.length, 'procedures');
}

main().catch((err) => {
  console.error('[deploy] FAILED', err.message);
  process.exit(1);
});
