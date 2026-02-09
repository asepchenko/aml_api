import { Router } from 'express';
import { body, query, param, validationResult } from 'express-validator';
import { authRequired } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, created, bad, notFound, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';
import { sendPushNotification } from '../utils/pushNotifications.js';
import { getPool } from '../db.js';

const router = Router();
const MOD = MODULE.CUSTOMER;

/**
 * GET /api/customer/dashboard
 * Mendapatkan statistik dan data dashboard customer
 * SP: sp_customer_dashboard_json(p_user_id)
 */
router.get(
  '/dashboard',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const data = await callJsonSP('sp_customer_dashboard_json', [userId]);
    if (!data) return notFound(res, 'Data dashboard tidak ditemukan', MOD);
    return ok(res, data, 'Data dashboard berhasil diambil', MOD);
  })
);

/**
 * GET /api/customer/orders
 * Mendapatkan daftar order customer dengan tracking location
 * SP: sp_customer_orders_json(p_user_id, p_status, p_start_date, p_end_date, p_page, p_limit)
 */
router.get(
  '/orders',
  authRequired,
  [
    query('status').optional().isIn(['Processing','On Delivery', 'Delivered']),
    query('start_date').optional().isString(),
    query('end_date').optional().isString(),
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
    const startDate = req.query.start_date || null;
    const endDate = req.query.end_date || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_customer_orders_json', [userId, status, startDate, endDate, page, limit]);
    if (!data) return notFound(res, 'Data orders tidak ditemukan', MOD);
    return ok(res, data, 'Daftar order berhasil diambil', MOD);
  })
);

/**
 * GET /api/customer/orders/:sttNumber/tracking
 * Mendapatkan detail tracking untuk sttNumber tertentu
 * SP: sp_customer_order_tracking_json(p_user_id, p_sttnumber)
 */
router.get(
  '/orders/:sttNumber/tracking',
  authRequired,
  [param('sttNumber').isString().notEmpty()],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { sttNumber } = req.params;

    const data = await callJsonSP('sp_customer_order_tracking_json', [userId, sttNumber]);
    if (!data) return notFound(res, 'Data tracking tidak ditemukan', MOD);
    return ok(res, data, 'Detail tracking berhasil diambil', MOD);
  })
);



/**
 * POST /api/customer/pickup
 * Membuat request pickup baru
 * SP: sp_customer_pickup_create_json(p_user_id, p_data_json)
 * test update
 */
router.post(
  '/pickup',
  authRequired,
  [
    body('customer_name').isString().notEmpty().withMessage('customer_name wajib diisi'),
    body('pickup_address').isString().notEmpty().withMessage('pickup_address wajib diisi'),
    body('item').isObject().withMessage('item wajib berupa object'),
    body('item.koli').isInt({ min: 1 }).withMessage('item.koli wajib berupa angka'),
    body('item.weight_kg').isFloat({ min: 0 }).withMessage('item.weight_kg wajib berupa angka'),
    body('schedule').isObject().withMessage('schedule wajib berupa object'),
    body('schedule.date').isString().notEmpty().withMessage('schedule.date wajib diisi'),
    body('schedule.time_range').isString().notEmpty().withMessage('schedule.time_range wajib diisi'),
    body('pic').isObject().withMessage('pic wajib berupa object'),
    body('pic.name').isString().notEmpty().withMessage('pic.name wajib diisi'),
    body('pic.phone').isString().notEmpty().withMessage('pic.phone wajib diisi'),
    body('destination').isObject().withMessage('destination wajib berupa object'),
    body('destination.city').isString().notEmpty().withMessage('destination.city wajib diisi'),
    body('destination.address').isString().notEmpty().withMessage('destination.address wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const pickupData = JSON.stringify(req.body);

    const data = await callJsonSP('sp_customer_pickup_create_json', [userId, pickupData]);
    if (!data) return bad(res, 'Gagal membuat pickup request', 400, MOD, SPECIFIC.INVALID);

    // Notify all drivers about the new pickup request
    try {
      const pool = getPool();
      const [drivers] = await pool.query("SELECT email FROM users WHERE role = 'driver'");
      for (const driver of drivers) {
        await sendPushNotification(
          driver.email,
          'Pickup Baru',
          `Ada request pickup baru dari ${req.body.customer_name}`,
          {
            type: 'pickup_new',
            pickupId: data.id || data.pickup_id, // Adjust based on SP return
            customerName: req.body.customer_name,
            address: req.body.pickup_address
          }
        );
      }
    } catch (pushError) {
      console.error('[PUSH] Error notifying drivers:', pushError);
    }

    return created(res, data, 'Pickup request berhasil dibuat', MOD);
  })
);

/**
 * GET /api/customer/pickup/history
 * Mendapatkan history pickup customer
 * SP: sp_customer_pickup_history_json(p_user_id, p_status, p_page, p_limit)
 */
router.get(
  '/pickup/history',
  authRequired,
  [
    query('status').optional().isIn(['waiting', 'accept', 'done', 'canceled']),
    query('start_date').optional().isString(),
    query('end_date').optional().isString(),
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
    const startDate = req.query.start_date || null;
    const endDate = req.query.end_date || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_customer_pickup_history_json', [
      userId,
      status,
      startDate,
      endDate,
      page,
      limit
    ]);
    if (!data) return notFound(res, 'Data pickup history tidak ditemukan', MOD);
    return ok(res, data, 'History pickup berhasil diambil', MOD);
  })
);

/**
 * GET /api/customer/reports
 * Mendapatkan data laporan customer termasuk statistik dan grafik
 * SP: sp_customer_reports_json(p_user_id)
 */
router.get(
  '/reports',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;

    const data = await callJsonSP('sp_customer_reports_json', [userId]);
    if (!data) return notFound(res, 'Data laporan tidak ditemukan', MOD);
    return ok(res, data, 'Success', MOD);
  })
);

/**
 * GET /api/customer/pickup/:id
 * Mendapatkan detail pickup berdasarkan ID
 * SP: sp_customer_pickup_detail_json(p_user_id, p_pickup_id)
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

    const data = await callJsonSP('sp_customer_pickup_detail_json', [userId, id]);
    if (!data) return notFound(res, 'Data pickup tidak ditemukan', MOD);
    return ok(res, data, 'Detail pickup berhasil diambil', MOD);
  })
);

/**
 * GET /api/customer/invoice
 * Mendapatkan daftar invoice customer
 * SP: sp_customer_invoice_list_json(p_user_id, p_month, p_year, p_status, p_page, p_limit)
 */
router.get(
  '/invoice',
  authRequired,
  [
    query('month').optional().isInt({ min: 1, max: 12 }),
    query('year').optional().isInt({ min: 2000 }),
    query('status').optional().isIn(['paid', 'pending', 'overdue']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const month = req.query.month ? parseInt(req.query.month) : null;
    const year = req.query.year ? parseInt(req.query.year) : null;
    const status = req.query.status || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_customer_invoice_list_json', [userId, month, year, status, page, limit]);
    if (!data) return notFound(res, 'Data invoice tidak ditemukan', MOD);
    return ok(res, data, 'Daftar invoice berhasil diambil', MOD);
  })
);

/**
 * GET /api/customer/history
 * Mendapatkan history orders yang sudah selesai
 * SP: sp_customer_order_history_json(p_user_id, p_date_from, p_date_to, p_page, p_limit)
 */
router.get(
  '/history',
  authRequired,
  [
    query('dateFrom').optional().isString(),
    query('dateTo').optional().isString(),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const dateFrom = req.query.dateFrom || null;
    const dateTo = req.query.dateTo || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_customer_order_history_json', [userId, dateFrom, dateTo, page, limit]);
    if (!data) return notFound(res, 'Data history tidak ditemukan', MOD);
    return ok(res, data, 'History orders berhasil diambil', MOD);
  })
);

/**
 * GET /api/customer/profile
 * Mendapatkan profil customer
 * SP: sp_customer_profile_get_json(p_user_id)
 */
router.get(
  '/profile',
  authRequired,
  asyncRoute(async (req, res) => {
    // const userId = req.user.sub;
    // const data = await callJsonSP('sp_customer_profile_get_json', [userId]);
    const email = req.user.email;
    const data = await callJsonSP('sp_customer_profile_get_json', [email]);
    if (!data) return notFound(res, 'Profil tidak ditemukan', MOD);
    return ok(res, data, 'Profil customer berhasil diambil', MOD);
  })
);

/**
 * PUT /api/customer/profile
 * Update profil customer
 * SP: sp_customer_profile_update_json(p_user_id, p_data_json)
 */
router.put(
  '/profile',
  authRequired,
  [
    body('name').optional({ nullable: true }).isString(),
    body('email').optional({ nullable: true }).custom((value) => {
      // Allow null or valid email
      if (value === null || value === undefined || value === '') return true;
      // Validate email format
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(value)) {
        throw new Error('Format email tidak valid');
      }
      return true;
    }),
    body('phone').optional({ nullable: true }).isString(),
    body('address').optional({ nullable: true }).isString(),
    body('company').optional({ nullable: true }).isString()
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    // const userId = req.user.sub;
    const email = req.user.email;
    const profileData = JSON.stringify(req.body);

    const data = await callJsonSP('sp_customer_profile_update_json', [email, profileData]);
    if (!data) return bad(res, 'Gagal update profil', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, 'Profil berhasil diupdate', MOD);
  })
);

export default router;

