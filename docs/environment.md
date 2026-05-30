# Environment (repo AML_API)

## Database — live (tegas)

- Konfigurasi di `.env` **bisa menunjuk ke database production/live**.
- **Jangan** menjalankan dari mesin dev / agent / CI:
  - `node scripts/deploy-sp-*.js`
  - `mysql` / HeidiSQL otomatis lewat script agent
  - migration, seed, atau DDL apa pun ke DB yang di `.env`
- **Perubahan SP / skema:** hanya **serahkan file** di `sql/`; **kamu** yang review dan eksekusi manual di editor DB / prosedur tim.

## Deploy stored procedure (manual)

1. Buka HeidiSQL (atau tool DB) → database yang benar (staging/live sesuai prosedur tim).
2. Set delimiter `//` untuk file yang memakai `END//`.
3. Execute **hanya** file SQL yang sudah direview — mis. `sql/sp_driver_delivery_list_json.sql`.
4. Verifikasi: `SHOW CREATE PROCEDURE nama_sp;` lalu `CALL nama_sp(...);`

## Test API

- Aman: jalankan **AML_API** (`npm start`) dan hit endpoint (Bruno/Postman) — itu hanya `CALL` SP yang **sudah ada** di server.
- Jika SP belum di-deploy di server, endpoint akan error sampai SP di-update manual.

Lihat juga: `webapp/docs/environment.md`, `api/docs/environment.md`.
