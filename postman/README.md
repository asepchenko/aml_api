# AML API — Koleksi HTTP (Bruno / Postman)

Folder ini berisi **Postman Collection v2.1** yang bisa di-import ke **Bruno** atau Postman.

## Import ke Bruno

1. Buka Bruno → workspace AML_API
2. **Import Collection** → pilih file `*.postman_collection.json`
3. Atur environment variable `base_url` dan kredensial login

## File

| File | Isi |
|------|-----|
| `AML_API_Pickup.postman_collection.json` | Customer pickup |
| `AML_API_Driver.postman_collection.json` | Driver: dashboard, pickup request, **delivery DPL**, **pickup retur**, manifest |

## Driver — urutan uji disarankan

1. **0. Auth → Login Driver** (simpan `token` otomatis)
2. **1. Dashboard**
3. **3. Delivery DPL**: List → Detail → Start Process → Deliver Item
4. **4. Pickup Retur**: List → Detail → Start Trip → Arrived

## Variable collection (Driver)

| Variable | Default | Keterangan |
|----------|---------|------------|
| `base_url` | `http://localhost:4000/api` | Root API AML |
| `token` | *(kosong)* | Diisi setelah login |
| `driver_username` | `driver1` | Sesuaikan DB |
| `driver_password` | `password123` | Sesuaikan DB |
| `dpl_id` | *(auto dari list)* | Id atau `packing_list_number` |
| `pickup_retur_id` | *(auto dari list)* | Id atau `retur_number` |
| `order_number` | *(auto dari detail DPL)* | STT untuk deliver item |

## Deploy SP (manual — DB sering live)

**Jangan** jalankan script deploy otomatis dari agent/CI. File SQL ada di `sql/` — deploy manual di HeidiSQL setelah review.

- Delivery (fix collation 1267): `sql/sp_driver_delivery_*.sql`
- Pickup retur: `sql/sp_driver_pickup_retur_*.sql`

Lihat [`docs/environment.md`](../docs/environment.md).
