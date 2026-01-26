import { Router } from 'express';
import { body, query, param, validationResult } from 'express-validator';
import { authRequired } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, bad, notFound, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';

const router = Router();
const MOD = MODULE.AGENT;

/**
 * GET /api/agent/dashboard
 * Mendapatkan statistik dan data dashboard agent
 * SP: sp_agent_dashboard_json(p_user_id)
 */
router.get(
  '/dashboard',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const data = await callJsonSP('sp_agent_dashboard_json', [userId]);
    if (!data) return notFound(res, 'Data dashboard tidak ditemukan', MOD);
    return ok(res, data, 'Data dashboard agent berhasil diambil', MOD);
  })
);

/**
 * GET /api/agent/orders
 * Mendapatkan daftar tasks untuk agent
 * SP: sp_agent_tasks_json(p_user_id, p_type, p_status, p_priority, p_page, p_limit)
 */
router.get(
  '/orders',
  authRequired,
  [
    // query('type').optional().isIn(['pickup', 'delivery', 'all']),
    query('status').optional().isIn(['Open', 'On Process Delivery', 'Delivered']),
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

    const data = await callJsonSP('sp_agent_order_json', [userId, status, page, limit]);
    if (!data) return notFound(res, 'Data Order tidak ditemukan', MOD);
    return ok(res, data, 'Daftar Order berhasil diambil', MOD);
  })
);

/**
 * PUT /api/agent/tasks/:id/start
 * Mulai task
 * SP: sp_agent_task_start_json(p_user_id, p_task_id)
 */
router.put(
  '/tasks/:id/start',
  authRequired,
  [param('id').isString().notEmpty()],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { id } = req.params;

    const data = await callJsonSP('sp_agent_task_start_json', [userId, id]);
    if (!data) return bad(res, 'Gagal memulai task', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, 'Task berhasil dimulai', MOD);
  })
);

/**
 * PUT /api/agent/tasks/:id/complete
 * Selesaikan task
 * SP: sp_agent_task_complete_json(p_user_id, p_task_id)
 */
router.put(
  '/tasks/:id/complete',
  authRequired,
  [param('id').isString().notEmpty()],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { id } = req.params;

    const data = await callJsonSP('sp_agent_task_complete_json', [userId, id]);
    if (!data) return bad(res, 'Gagal menyelesaikan task', 400, MOD, SPECIFIC.INVALID);
    return ok(res, data, 'Task berhasil diselesaikan', MOD);
  })
);

/**
 * GET /api/agent/stts/:sttNumber/kolis
 * Mendapatkan daftar koli dari STT tertentu (Versi Driver)
 * SP: sp_driver_stt_kolis_json(p_stt_number, p_trip_id, p_manifest_id)
 */
router.get(
  '/stts/:sttNumber/kolis',
  authRequired,
  [
    param('sttNumber').notEmpty().withMessage('sttNumber wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const { sttNumber } = req.params;

    try {
      const data = await callJsonSP('sp_agent_stt_kolis_json', [sttNumber]);
      
      if (!data) {
        return notFound(res, 'STT tidak ditemukan', MOD);
      }

      if (data.error === 'stt_not_found') {
        return notFound(res, 'STT tidak ditemukan', MOD);
      }

      return ok(res, data, 'Daftar koli berhasil diambil', MOD);
    } catch (err) {
      console.error('[AGENT STT KOLIS ERROR]', err);
      return bad(res, 'Gagal mengambil data koli', 500, MOD, SPECIFIC.ERROR);
    }
  })
);

/**
 * POST /api/driver/scan/koli
 * Scan koli barcode (auto-detect STT dari koli ID)
 * SP: sp_agent_scan_koli_json(p_user_id, p_stt_number, p_koli_id, p_city_name, p_last_location)
 */
router.post(
  '/scan/koli',
  authRequired,
  [
    body('sttNumber').isString().notEmpty().withMessage('sttNumber wajib diisi'),
    body('koliId').isString().notEmpty().withMessage('koliId wajib diisi')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { sttNumber, koliId } = req.body;

    try {
      const data = await callJsonSP('sp_agent_scan_koli_json', [userId, sttNumber, koliId]);
      
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
      console.error('[DELIVERY SCAN ERROR]', err);
      return bad(res, 'Gagal scan koli', 500, MOD, SPECIFIC.ERROR);
    }
  })
);
/**
 * POST /api/agent/delivery/:id/confirm
 * Driver konfirmasi dengan koli dan foto
 * SP: sp_agent_delivery_confirm_json(p_user_id, p_stt_number, p_confirmed_koli, p_photo_url, p_recipient_name, p_driver_name)
 * p_driver_name : Manual input nama driver
*/
router.post(
  '/delivery/:sttnumber/confirm',
  authRequired,
  [
    param('sttnumber').isString().notEmpty(),    
    body('address').isString().notEmpty().withMessage('address wajib diisi'),
    body('city').isString().notEmpty().withMessage('city wajib diisi'),

  ],
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const { sttnumber } = req.params;
    const confirmedKoli = parseInt(req.body.confirmed_koli) || 0;    
    const recipientName = req.body.recipient_name || null;
    const driverName = req.body.driver_name || null;
    const address = req.body.address || null;
    const city = req.body.city || null;
    const photoBase64 = req.body.photo; // Base64 string from body

    const data = await callJsonSP('sp_agent_delivery_confirm_json', [userId, sttnumber, confirmedKoli, photoBase64, recipientName, driverName, address, city]);
    
    if (!data) {
      return bad(res, 'Gagal konfirmasi pickup', 400, MOD, SPECIFIC.INVALID);
    }

    // Handle error responses from SP
    if (data.error === 'not_found') {
      return notFound(res, 'Stt Number tidak ditemukan', MOD);
    }

    if (data.error === 'already_delivered') {
      return bad(res, 'Stt Number sudah dikonfirmasi sebelumnya', 400, MOD, SPECIFIC.INVALID);
    }

    if (data.error === 'not_ready') {
      return bad(res, 'Stt tidak ada dalam task anda', 400, MOD, SPECIFIC.INVALID);
    }

    return ok(res, data, 'Delivery berhasil dikonfirmasi', MOD);
  })
);

/**
 * GET /api/agent/monitoring
 * Mendapatkan data monitoring agent
 * SP: sp_agent_monitoring_json(p_user_id, p_period, p_date)
 */
router.get(
  '/monitoring',
  authRequired,
  [
    query('period').optional().isIn(['today', 'week', 'month']),
    query('date').optional().isString()
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const period = req.query.period || 'today';
    const date = req.query.date || null;

    const data = await callJsonSP('sp_agent_monitoring_json', [userId, period, date]);
    if (!data) return notFound(res, 'Data monitoring tidak ditemukan', MOD);
    return ok(res, data, 'Data monitoring berhasil diambil', MOD);
  })
);

/**
 * GET /api/agent/profile
 * Mendapatkan profil agent
 * SP: sp_agent_profile_get_json(p_user_id)
 */
router.get(
  '/profile',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const data = await callJsonSP('sp_agent_profile_get_json', [userId]);
    if (!data) return notFound(res, 'Profil tidak ditemukan', MOD);
    return ok(res, data, 'Profil agent berhasil diambil', MOD);
  })
);

export default router;

