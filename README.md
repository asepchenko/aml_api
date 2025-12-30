# AML API

Express API for AMLC Application dengan MySQL stored procedures yang mengembalikan JSON.

## Tech Stack

- **Node.js** + **Express** (v4.19)
- **MySQL2** untuk koneksi database
- **JWT** untuk autentikasi
- **Multer** untuk upload file

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Setup environment variables:**
   ```bash
   cp .env.example .env
   # Edit .env dengan konfigurasi database dan JWT secret
   ```

3. **Setup database:**
   - Jalankan `sql/stored_procedures.sql` di MySQL untuk membuat semua stored procedures

4. **Run development server:**
   ```bash
   npm run dev
   ```

## Environment Variables

```env
PORT=4000
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=aml_db
JWT_SECRET=your_jwt_secret
JWT_EXPIRES=1d
CORS_ORIGIN=http://localhost:3000
```

## API Endpoints

### Base URL
```
http://localhost:4000/api
```

### Authentication
Semua endpoint (kecuali login) memerlukan header:
```
Authorization: Bearer {token}
```

---

### 1. Auth Module (`/api/auth`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/login` | Login user dan mendapatkan access token |
| POST | `/auth/forgot-password` | Request reset password |

---

### 2. Customer Module (`/api/customer`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/customer/dashboard` | Data dashboard customer |
| GET | `/customer/orders` | Daftar order dengan tracking |
| GET | `/customer/orders/:tripId/tracking` | Detail tracking trip |
| POST | `/customer/pickup` | Buat request pickup baru |
| GET | `/customer/pickup/history` | History pickup |
| GET | `/customer/pickup/:id` | Detail pickup |
| GET | `/customer/invoice` | Daftar invoice |
| GET | `/customer/history` | History orders selesai |
| GET | `/customer/profile` | Profil customer |
| PUT | `/customer/profile` | Update profil customer |

---

### 3. Driver Module (`/api/driver`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/driver/dashboard` | Data dashboard driver |
| GET | `/driver/pickup` | Daftar pickup request |
| PUT | `/driver/pickup/:id/accept` | Terima pickup request |
| PUT | `/driver/pickup/:id/status` | Update status pickup |
| POST | `/driver/pickup/:id/confirm` | Konfirmasi pickup dengan foto |
| GET | `/driver/packages` | Daftar packages/trips |
| POST | `/driver/scan/koli` | Scan koli barcode |
| POST | `/driver/scan/stt/hold` | Hold STT dengan alasan |
| POST | `/driver/location/update` | Update lokasi trip |
| GET | `/driver/notifications` | Daftar notifikasi |
| PUT | `/driver/notifications/:id/read` | Tandai notifikasi dibaca |
| PUT | `/driver/notifications/read-all` | Tandai semua dibaca |
| GET | `/driver/profile` | Profil driver |

---

### 4. Loading Module (`/api/loading`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/loading/dashboard` | Data dashboard loading |
| GET | `/loading/orders` | Daftar trips/orders |
| GET | `/loading/history` | History trips selesai |
| POST | `/loading/scan/koli` | Scan koli di loading |
| GET | `/loading/profile` | Profil loading staff |

---

### 5. Agent Module (`/api/agent`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/agent/dashboard` | Data dashboard agent |
| GET | `/agent/tasks` | Daftar tasks |
| PUT | `/agent/tasks/:id/start` | Mulai task |
| PUT | `/agent/tasks/:id/complete` | Selesaikan task |
| POST | `/agent/scan` | Scan barcode receive/send |
| GET | `/agent/monitoring` | Data monitoring |
| GET | `/agent/profile` | Profil agent |

---

### 6. Tracking Module (`/api/tracking`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/tracking/:sttNumber` | Detail tracking STT |

---

## Response Format

### Success Response
```json
{
  "success": true,
  "responseCode": "2000200",
  "responseMessage": "Data berhasil diambil",
  "data": { ... }
}
```

### Error Response
```json
{
  "success": false,
  "responseCode": "4010104",
  "responseMessage": "Username atau password salah"
}
```

### Response Code Format
- **2 digit pertama**: HTTP Status (20=200, 40=400, 41=401, 50=500)
- **3 digit berikutnya**: Module Code (001=Auth, 002=Customer, 003=Driver, 004=Loading, 005=Agent, 006=Tracking)
- **2 digit terakhir**: Specific Code (00=Success, 01=Created, 02=Not Found, 03=Invalid, 04=Unauthorized, 05=Forbidden)

---

## Project Structure

```
AML_API/
├── src/
│   ├── app.js                 # Express app entry point
│   ├── db.js                  # Database connection & SP caller
│   ├── middleware/
│   │   └── auth.js            # JWT authentication middleware
│   ├── routes/
│   │   ├── auth.routes.js     # Auth endpoints
│   │   ├── customer.routes.js # Customer endpoints
│   │   ├── driver.routes.js   # Driver endpoints
│   │   ├── loading.routes.js  # Loading endpoints
│   │   ├── agent.routes.js    # Agent endpoints
│   │   └── tracking.routes.js # Tracking endpoints
│   └── utils/
│       └── http.js            # Response helpers
├── sql/
│   └── stored_procedures.sql  # Dummy stored procedures
├── uploads/
│   └── pickup-photos/         # Upload directory for pickup photos
├── package.json
└── README.md
```

## Scripts

```bash
# Development dengan hot-reload
npm run dev

# Production
npm start
```

##problem solving run dev with terminal / powershell
##by pass priviledge for session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


## License

Private
