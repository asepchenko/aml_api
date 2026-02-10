import { Router } from 'express';
import { body, query, param, validationResult } from 'express-validator';
import multer from 'multer';
import { authRequired } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, bad, notFound, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';
import { sendPushNotification } from '../utils/pushNotifications.js';

// Reverse geocoding using OpenStreetMap Nominatim API
const reverseGeocode = async (latitude, longitude) => {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&zoom=10&addressdetails=1`;
    
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'AML-API/1.0' // Required by Nominatim
      }
    });

    if (!response.ok) {
      throw new Error('Geocoding request failed');
    }

    const data = await response.json();
    
    // Extract city and address
    const address = data.address || {};
    const cityName = address.city || address.town || address.municipality || address.county || address.state || '-';
    const lastLocation = data.display_name || '-';

    return {
      cityName,
      lastLocation,
      region: address.state || address.region || '-'
    };
  } catch (error) {
    console.error('[GEOCODE ERROR]', error.message);
    return {
      cityName: '-',
      lastLocation: '-',
      region: '-'
    };
  }
};

const router = Router();
const MOD = MODULE.DRIVER;

// Multer configuration for file uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/pickup-photos');
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, `pickup-${uniqueSuffix}-${file.originalname}`);
  }
});
const upload = multer({ storage });

/**
 * GET /api/driver/dashboard
 * Mendapatkan statistik dan data dashboard driver
 * SP: sp_driver_dashboard_json(p_user_id)
 */
router.get(
  '/dashboard',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const data = await callJsonSP('sp_driver_dashboard_json', [userId]);
    if (!data) return notFound(res, 'Data dashboard tidak ditemukan', MOD);
    return ok(res, data, 'Data dashboard driver berhasil diambil', MOD);
  })
);

/**
 * GET /api/driver/pickup
 * Mendapatkan daftar pickup request untuk driver
 * SP: sp_driver_pickup_list_json(p_user_id, p_status, p_page, p_limit)
 */
router.get(
  '/pickup',
  authRequired,
  [
    query('status').optional().isIn(['pending', 'accept', 'done']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const status = req.query.status || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_driver_pickup_list_json', [userId, status, page, limit]);
    if (!data) return notFound(res, 'Data pickup tidak ditemukan', MOD);
    return ok(res, data, 'Daftar pickup request berhasil diambil', MOD);
  })
);

/**
 * GET /api/driver/pickup/:id
 * Mendapatkan detail pickup berdasarkan ID
 * SP: sp_driver_pickup_detail_json(p_user_id, p_pickup_id)
 */
router.get(
  '/pickup/:id',
  authRequired,
  [param('id').isString().notEmpty()],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { id } = req.params;

    const data = await callJsonSP('sp_driver_pickup_detail_json', [userId, id]);
    if (!data) return notFound(res, 'Data pickup tidak ditemukan', MOD);
    return ok(res, data, 'Detail pickup berhasil diambil', MOD);
  })
);

/**
 * PUT /api/driver/pickup/:id/accept
 * Driver menerima pickup request
 * SP: sp_driver_pickup_accept_json(p_user_id, p_pickup_id, p_email_id)
 */
router.put(
  '/pickup/:id/accept',
  authRequired,
  [param('id').isString().notEmpty()],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const email = req.user.email;
    const { id } = req.params;

    const data = await callJsonSP('sp_driver_pickup_accept_json', [userId, id, email]);
    
    if (!data) {
      return bad(res, 'Gagal menerima pickup request', 400, MOD, SPECIFIC.INVALID);
    }

    // Handle error responses from SP
    if (data.error === 'not_found') {
      return notFound(res, 'Pickup request tidak ditemukan', MOD);
    }

    if (data.error === 'already_accepted') {
      return bad(res, 'Pickup sudah diambil driver lain', 400, MOD, SPECIFIC.INVALID);
    }

    // Notify driver about successful assignment
    await sendPushNotification(
      email,
      'Pickup Diterima',
      `Anda telah berhasil menerima pickup request #${id}`,
      {
        type: 'pickup_assigned',
        pickupId: id
      }
    );

    return ok(res, data, 'Pickup request berhasil diterima', MOD);
  })
);

/**
 * PUT /api/driver/pickup/:id/status
 * Update status pickup
 * SP: sp_driver_pickup_status_update_json(p_user_id, p_pickup_id, p_status, p_eta)
 */
router.put(
  '/pickup/:id/status',
  authRequired,
  [
    param('id').isString().notEmpty(),
    body('status').isString().notEmpty().withMessage('status wajib diisi'),
    body('eta').optional().isString()
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const email = req.user.email;
    const { id } = req.params;
    const { status, eta } = req.body;

    const data = await callJsonSP('sp_driver_pickup_status_update_json', [userId, id, status, eta || null]);
    if (!data) return bad(res, 'Gagal update status pickup', 400, MOD, SPECIFIC.INVALID);

    // Notify user/customer about status update if needed
    // For now, let's notify the driver themselves as a confirmation
    await sendPushNotification(
      email,
      'Status Pickup Diperbarui',
      `Status pickup #${id} sekarang: ${status}`,
      {
        type: 'order_update',
        pickupId: id,
        status: status
      }
    );

    return ok(res, data, 'Status pickup berhasil diupdate', MOD);
  })
);

/**
 * POST /api/driver/pickup/:id/confirm
 * Driver konfirmasi pickup dengan koli dan foto
 * SP: sp_driver_pickup_confirm_json(p_user_id, p_pickup_id, p_confirmed_koli, p_photo_url, p_driver_name)
 */
router.post(
  '/pickup/:id/confirm',
  authRequired,
  [
    param('id').isString().notEmpty()
  ],
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const { id } = req.params;
    const confirmedKoli = parseInt(req.body.confirmed_koli) || 0;
    const driverName = req.body.driver_name || null;
    const photoBase64 = req.body.photo; // Base64 string from body

    const data = await callJsonSP('sp_driver_pickup_confirm_json', [userId, id, confirmedKoli, photoBase64, driverName]);
    
    if (!data) {
      return bad(res, 'Gagal konfirmasi pickup', 400, MOD, SPECIFIC.INVALID);
    }

    // Handle error responses from SP
    if (data.error === 'not_found') {
      return notFound(res, 'Pickup request tidak ditemukan', MOD);
    }

    if (data.error === 'already_confirmed') {
      return bad(res, 'Pickup sudah dikonfirmasi sebelumnya', 400, MOD, SPECIFIC.INVALID);
    }

    if (data.error === 'not_accepted') {
      return bad(res, 'Pickup belum di-accept, tidak bisa dikonfirmasi', 400, MOD, SPECIFIC.INVALID);
    }

    return ok(res, data, 'Pickup berhasil dikonfirmasi', MOD);
  })
);

/**
 * GET /api/driver/packages
 * Mendapatkan daftar packages/trips untuk driver dengan tracking data
 * SP: sp_driver_packages_json(p_user_id, p_status, p_page, p_limit)
 */
router.get(
  '/packages',
  authRequired,
  [
    query('status').optional().isIn(['pending', 'in_progress', 'completed']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const status = req.query.status || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_driver_packages_json', [userId, status, page, limit]);
    if (!data) return notFound(res, 'Data packages tidak ditemukan', MOD);
    return ok(res, data, 'Daftar packages/trips berhasil diambil', MOD);
  })
);

/**
 * GET /api/driver/orders
 * Mendapatkan daftar trips/orders untuk driver
 * SP: sp_driver_orders_json(p_user_id, p_status, p_page, p_limit)
 */
router.get(
  '/orders',
  authRequired,
  [
    query('status').optional().isIn(['all','In_Progress', 'Closing']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const status = req.query.status || 'all';
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_driver_orders_json', [userId, status, page, limit]);
    if (!data) return notFound(res, 'Data orders tidak ditemukan', MOD);
    return ok(res, data, 'Daftar trips/orders berhasil diambil', MOD);
  })
);

/**
 * GET /api/driver/manifests/:manifestId/stts
 * Mendapatkan daftar STT berdasarkan manifest ID (Versi Driver)
 * SP: sp_driver_manifest_stts_json(p_user_id, p_manifest_id, p_trip_id, p_search, p_page, p_limit)
 */
router.get(
  '/manifests/:manifestId/stts',
  authRequired,
  asyncRoute(async (req, res) => {
    const { manifestId } = req.params;
    
    if (!manifestId) {
      return bad(res, 'manifestId wajib diisi', 400, MOD, SPECIFIC.INVALID);
    }

    const search = req.query.search || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;

    try {
      const data = await callJsonSP('sp_driver_manifest_stts_json', [manifestId, search, page, limit]);
      
      if (!data) {
        return notFound(res, 'Manifest tidak ditemukan', MOD);
      }

      if (data.error === 'manifest_not_found') {
        return notFound(res, 'Manifest tidak ditemukan', MOD);
      }

      if (data.error === 'invalid_trip') {
        return bad(res, 'TripId tidak valid atau manifest tidak termasuk dalam trip tersebut', 400, MOD, SPECIFIC.INVALID);
      }

      return ok(res, data, 'Daftar STT berhasil diambil', MOD);
    } catch (err) {
      console.error('[DRIVER MANIFEST STTS ERROR]', err);
      return bad(res, 'Gagal mengambil data STT', 500, MOD, SPECIFIC.ERROR);
    }
  })
);

/**
 * GET /api/driver/stts/:sttNumber/kolis
 * Mendapatkan daftar koli dari STT tertentu (Versi Driver)
 * SP: sp_driver_stt_kolis_json(p_stt_number, p_trip_id, p_manifest_id)
 */
router.get(
  '/stts/:sttNumber/kolis',
  authRequired,
  [
    param('sttNumber').notEmpty().withMessage('sttNumber wajib diisi'),
    query('tripId').notEmpty().withMessage('tripId wajib diisi'),
    query('manifestId').notEmpty().withMessage('manifestId wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const { sttNumber } = req.params;
    const { tripId, manifestId } = req.query;

    try {
      const data = await callJsonSP('sp_driver_stt_kolis_json', [sttNumber, tripId, manifestId]);
      
      if (!data) {
        return notFound(res, 'STT tidak ditemukan', MOD);
      }

      if (data.error === 'stt_not_found') {
        return notFound(res, 'STT tidak ditemukan', MOD);
      }

      if (data.error === 'invalid_params') {
        return bad(res, 'TripId atau ManifestId tidak valid', 400, MOD, SPECIFIC.INVALID);
      }

      return ok(res, data, 'Daftar koli berhasil diambil', MOD);
    } catch (err) {
      console.error('[DRIVER STT KOLIS ERROR]', err);
      return bad(res, 'Gagal mengambil data koli', 500, MOD, SPECIFIC.ERROR);
    }
  })
);

/**
 * POST /api/driver/scan/koli
 * Scan koli barcode (auto-detect STT dari koli ID)
 * SP: sp_driver_scan_koli_json(p_user_id, p_koli_id, p_city_name, p_last_location)
 */
// router.post(
//   '/scan/koli',
//   authRequired,
//   [
//     body('koli_id').isString().notEmpty().withMessage('koli_id wajib diisi'),
//     body('latitude').isFloat().withMessage('latitude wajib berupa angka'),
//     body('longitude').isFloat().withMessage('longitude wajib berupa angka')
//   ],
//   asyncRoute(async (req, res) => {
//     const errors = validationResult(req);
//     if (!errors.isEmpty()) {
//       return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
//     }

//     const userId = req.user.sub;
//     const { koli_id, latitude, longitude } = req.body;

//     // Reverse geocode lat/long to city_name and last_location
//     const geoData = await reverseGeocode(latitude, longitude);
//     const cityName = geoData.cityName;
//     const lastLocation = geoData.lastLocation;

//     const data = await callJsonSP('sp_driver_scan_koli_json', [userId, koli_id, cityName, lastLocation]);
    
//     if (!data) {
//       return bad(res, `Koli ${koli_id} tidak ditemukan.`, 400, MOD, SPECIFIC.NOT_FOUND);
//     }

//     // Handle error responses from SP
//     if (data.error === 'not_found') {
//       return bad(res, `Koli ${koli_id} tidak ditemukan.`, 400, MOD, SPECIFIC.NOT_FOUND);
//     }
    
//     const message = `Koli ${koli_id} berhasil di-scan. (${data.scanned_count}/${data.total_count} koli)`;
//     return ok(res, data, message, MOD);
//   })
// );

router.post(
  '/scan/koli',
  authRequired,
  [
    body('tripId').isString().notEmpty().withMessage('tripId wajib diisi'),
    body('manifestId').isString().notEmpty().withMessage('manifestId wajib diisi'),
    body('sttNumber').isString().notEmpty().withMessage('sttNumber wajib diisi'),
    body('koliId').isString().notEmpty().withMessage('koliId wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { tripId, manifestId, sttNumber, koliId } = req.body;

    try {
      const data = await callJsonSP('sp_driver_scan_koli_json', [userId, tripId, manifestId, sttNumber, koliId]);
      
      if (!data) {
        return notFound(res, 'STT tidak ditemukan', MOD);
      }

      if (data.error === 'not_found') {
        return bad(res, `Koli ${koliId} tidak ditemukan di STT ${sttNumber}`, 400, MOD, SPECIFIC.NOT_FOUND);
      }

      if (data.error === 'already_scanned') {
        return bad(res, `Koli ${koliId} sudah pernah di-scan sebelumnya`, 400, MOD, SPECIFIC.INVALID);
      }

      const message = `Koli ${koliId} berhasil di-scan. (${data.scannedCount}/${data.totalCount} koli)`;
      return ok(res, data, message, MOD);
    } catch (err) {
      console.error('[LOADING SCAN ERROR]', err);
      return bad(res, 'Gagal scan koli', 500, MOD, SPECIFIC.ERROR);
    }
  })
);


/**
 * POST /api/driver/scan/stt/hold
 * Hold STT aktif dengan alasan
 * SP: sp_driver_stt_hold_json(p_user_id, p_trip_id, p_stt_number, p_reason)
 */
router.post(
  '/scan/stt/hold',
  authRequired,
  [
    body('trip_id').isString().notEmpty().withMessage('trip_id wajib diisi'),
    body('stt_number').isString().notEmpty().withMessage('stt_number wajib diisi'),
    body('reason').isString().notEmpty().withMessage('reason wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { trip_id, stt_number, reason } = req.body;
    try {
      const data = await callJsonSP('sp_driver_stt_hold_json', [userId, trip_id, stt_number, reason]);
    

    if (data.error === 'not_found') {
      return bad(res, `STT ${stt_number} tidak ditemukan`, 400, MOD, SPECIFIC.NOT_FOUND);
    }

    if (data.error === 'already_hold') {
      return bad(res, `STT ${stt_number} sudah pernah di-hold sebelumnya`, 400, MOD, SPECIFIC.INVALID);
    }
    // if (!data) return bad(res, 'Gagal hold STT', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, `STT ${stt_number} telah di-hold.`, MOD);
  } catch (err) {
    console.error('[HOLD STT ERROR]', err);
    return bad(res, 'Gagal hold STT', 500, MOD, SPECIFIC.ERROR);
  }
  })
);

/**
 * POST /api/driver/scan/stt/unhold
 * Unhold STT aktif dengan alasan
 * SP: sp_driver_stt_unhold_json(p_user_id, p_trip_id, p_stt_number, p_reason)
 */
router.post(
  '/scan/stt/unhold',
  authRequired,
  [
    body('trip_id').isString().notEmpty().withMessage('trip_id wajib diisi'),
    body('stt_number').isString().notEmpty().withMessage('stt_number wajib diisi'),
    body('reason').isString().notEmpty().withMessage('reason wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { trip_id, stt_number, reason } = req.body;
    try {
      const data = await callJsonSP('sp_driver_stt_unhold_json', [userId, trip_id, stt_number, reason]);
    

    if (data.error === 'not_found') {
      return bad(res, `STT ${stt_number} tidak ditemukan`, 400, MOD, SPECIFIC.NOT_FOUND);
    }

    if (data.error === 'already_unhold') {
      return bad(res, `STT ${stt_number} sudah pernah di-unhold sebelumnya`, 400, MOD, SPECIFIC.INVALID);
    }
    // if (!data) return bad(res, 'Gagal hold STT', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, `STT ${stt_number} telah di-unhold.`, MOD);
  } catch (err) {
    console.error('[UNHOLD STT ERROR]', err);
    return bad(res, 'Gagal unhold STT', 500, MOD, SPECIFIC.ERROR);
  }
  })
);

/**
 * POST /api/driver/location/update
 * Update location untuk trip
 * SP: sp_driver_location_update_json(p_user_id, sttNumber, p_latitude, p_longitude)
 */
router.post(
  '/location/update',
  authRequired,
  [
    body('sttNumber').isString().notEmpty().withMessage('Stt Number wajib diisi'),
    body('latitude').isFloat().withMessage('latitude wajib berupa angka'),
    body('longitude').isFloat().withMessage('longitude wajib berupa angka'),
    body('address').isString().notEmpty().withMessage('address wajib diisi'),
    body('city').isString().notEmpty().withMessage('city wajib diisi'),
    body('region').isString().notEmpty().withMessage('region wajib diisi'),
    body('timestamp').isString().notEmpty().withMessage('timestamp wajib diisi'),
    body('action_type').isString().notEmpty().withMessage('action_type wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { sttNumber, latitude, longitude, address, city, region, timestamp, action_type } = req.body;
    try{
      const data = await callJsonSP('sp_driver_location_update_json', [
        userId, 
        sttNumber, 
        latitude, 
        longitude,
        address,
        city,
        region,
        timestamp,
        action_type
      ]);
      if (data.error === 'not_found') {
        return bad(res, `Data Trip ${trip_id} tidak ditemukan`, 400, MOD, SPECIFIC.NOT_FOUND);
      }
  
      // if (data.error === 'already_hold') {
      //   return bad(res, `STT ${stt_number} sudah pernah di-hold sebelumnya`, 400, MOD, SPECIFIC.INVALID);
      // }
       // if (!data) return bad(res, 'Gagal update location', 400, MOD, SPECIFIC.INVALID);
      return ok(res, data, 'Location berhasil diupdate', MOD);
    } catch (err) {
      console.error('[UPDATE LOCATION ERROR]', err);
      return bad(res, 'Gagal update location', 500, MOD, SPECIFIC.ERROR);
    }    
  })
);

/**
 * POST /api/driver/manifest/closed
 * Untuk closed salah satu manifest di trip, dan update status pengiriman last location ke semua stt pada trip yg manifestnya belum closed.
 * SP: sp_driver_manifest_closed_json(p_user_id, p_trip_id, p_manifest, p_last_location,p_city)
 */
router.post(
  '/manifest/closed',
  authRequired,
  [
    body('trip_id').isString().notEmpty().withMessage('trip_id wajib diisi'),
    body('manifest').isString().notEmpty().withMessage('manifest wajib diisi'),
    body('address').isString().notEmpty().withMessage('address wajib diisi'),
    body('city').isString().notEmpty().withMessage('city wajib diisi'),
    body('region').isString().notEmpty().withMessage('Region wajib diisi'),
    body('timestamp').isString().notEmpty().withMessage('timestamp wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { trip_id, manifest, address, city, region, latitude, longitude, timestamp } = req.body;
    try{
      const data = await callJsonSP('sp_driver_manifest_closed_json', [
        userId, 
        trip_id,
        manifest,
        address,
        city,
        region,
        timestamp
      ]);
      if (data.error === 'not_found') {
        return bad(res, `Data Trip ${manifest} tidak ditemukan`, 400, MOD, SPECIFIC.NOT_FOUND);
      }
  
      // if (data.error === 'already_hold') {
      //   return bad(res, `STT ${stt_number} sudah pernah di-hold sebelumnya`, 400, MOD, SPECIFIC.INVALID);
      // }
       // if (!data) return bad(res, 'Gagal update location', 400, MOD, SPECIFIC.INVALID);
      return ok(res, data, 'Closed Manifest Success, Location berhasil diupdate', MOD);
    } catch (err) {
      console.error('[CLOSED MANIFEST ERROR]', err);
      return bad(res, 'Gagal update location', 500, MOD, SPECIFIC.ERROR);
    }    
  })
);

/**
 * GET /api/driver/notifications
 * Mendapatkan daftar notifikasi driver
 * SP: sp_driver_notifications_json(p_user_id, p_is_read, p_type, p_page, p_limit)
 */
router.get(
  '/notifications',
  authRequired,
  [
    query('is_read').optional().isBoolean(),
    query('type').optional().isIn(['pickup_new', 'pickup_assigned', 'pickup_reminder', 'order_update', 'system']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const isRead = req.query.is_read !== undefined ? req.query.is_read === 'true' : null;
    const type = req.query.type || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_driver_notifications_json', [userId, isRead, type, page, limit]);
    if (!data) return notFound(res, 'Data notifikasi tidak ditemukan', MOD);
    return ok(res, data, 'Daftar notifikasi berhasil diambil', MOD);
  })
);

/**
 * PUT /api/driver/notifications/:id/read
 * Tandai notifikasi sebagai sudah dibaca
 * SP: sp_driver_notification_read_json(p_user_id, p_notification_id)
 */
router.put(
  '/notifications/:id/read',
  authRequired,
  [param('id').isString().notEmpty()],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { id } = req.params;

    const data = await callJsonSP('sp_driver_notification_read_json', [userId, id]);
    if (!data) return bad(res, 'Gagal update notifikasi', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, 'Notifikasi berhasil ditandai sebagai sudah dibaca', MOD);
  })
);

/**
 * PUT /api/driver/notifications/read-all
 * Tandai semua notifikasi sebagai sudah dibaca
 * SP: sp_driver_notification_read_all_json(p_user_id)
 */
router.put(
  '/notifications/read-all',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;

    const data = await callJsonSP('sp_driver_notification_read_all_json', [userId]);
    if (!data) return bad(res, 'Gagal update notifikasi', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, 'Semua notifikasi berhasil ditandai sebagai sudah dibaca', MOD);
  })
);

/**
 * GET /api/driver/profile
 * Mendapatkan profil driver
 * SP: sp_driver_profile_get_json(p_user_id)
 */
router.get(
  '/profile',
  authRequired,
  asyncRoute(async (req, res) => {
    // const userId = req.user.sub;
    const email = req.user.email;
    const data = await callJsonSP('sp_driver_profile_get_json', [email]);
    if (!data) return notFound(res, 'Profil tidak ditemukan', MOD);
    return ok(res, data, 'Profil driver berhasil diambil', MOD);
  })
);

export default router;

