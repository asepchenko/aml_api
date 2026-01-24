import { Router } from 'express';
import { body, query, param, validationResult } from 'express-validator';
import { authRequired } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, bad, notFound, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';

const router = Router();
const MOD = MODULE.LOADING;

/**
 * GET /api/loading/dashboard
 * Mendapatkan statistik dan data dashboard loading
 * SP: sp_loading_dashboard_json(p_user_id)
 */
router.get(
  '/dashboard',
  authRequired,
  asyncRoute(async (req, res) => {
    const userId = req.user.sub;
    const data = await callJsonSP('sp_loading_dashboard_json', [userId]);
    if (!data) return notFound(res, 'Data dashboard tidak ditemukan', MOD);
    return ok(res, data, 'Data dashboard loading berhasil diambil', MOD);
  })
);

/**
 * GET /api/loading/orders
 * Mendapatkan daftar trips/orders untuk loading
 * SP: sp_loading_orders_json(p_user_id, p_status, p_page, p_limit)
 */
router.get(
  '/orders',
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
    const status = req.query.status || 'Open';
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_loading_orders_json', [userId, status, page, limit]);
    if (!data) return notFound(res, 'Data orders tidak ditemukan', MOD);
    return ok(res, data, 'Daftar trips/orders berhasil diambil', MOD);
  })
);

/**
 * GET /api/loading/manifests/:manifestId/stts
 * Mendapatkan daftar STT berdasarkan manifest ID
 * SP: sp_loading_manifest_stts_json(p_user_id, p_manifest_id, p_trip_id, p_search, p_page, p_limit)
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
      // SP expects 4 params: p_manifest_id, p_search, p_page, p_limit (tanpa user_id)
      const data = await callJsonSP('sp_loading_manifest_stts_json', [manifestId, search, page, limit]);
      
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
      console.error('[LOADING MANIFEST STTS ERROR]', err);
      return bad(res, 'Gagal mengambil data STT', 500, MOD, SPECIFIC.ERROR);
    }
  })
);

/**
 * GET /api/loading/stts/:sttNumber/kolis
 * Mendapatkan daftar koli dari STT tertentu
 * SP: sp_loading_stt_kolis_json(p_stt_number, p_trip_id, p_manifest_id)
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
      const data = await callJsonSP('sp_loading_stt_kolis_json', [sttNumber, tripId, manifestId]);
      
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
      console.error('[LOADING STT KOLIS ERROR]', err);
      return bad(res, 'Gagal mengambil data koli', 500, MOD, SPECIFIC.ERROR);
    }
  })
);

/**
 * GET /api/loading/history
 * Mendapatkan history trips yang sudah selesai
 * SP: sp_loading_history_json(p_user_id, p_date_from, p_date_to, p_page, p_limit)
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

    const data = await callJsonSP('sp_loading_history_json', [userId, dateFrom, dateTo, page, limit]);
    if (!data) return notFound(res, 'Data history tidak ditemukan', MOD);
    return ok(res, data, 'History trips berhasil diambil', MOD);
  })
);

/**
 * POST /api/loading/scan/koli
 * Scan koli barcode untuk update status scanned di loading department
 * SP: sp_loading_scan_koli_json(p_user_id, p_trip_id, p_manifest_id, p_stt_number, p_koli_id)
 */
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
      const data = await callJsonSP('sp_loading_scan_koli_json', [userId, tripId, manifestId, sttNumber, koliId]);
      
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
 * GET /api/loading/profile
 * Mendapatkan profil loading staff
 * SP: sp_loading_profile_get_json(p_user_id)
 */
router.get(
  '/profile',
  authRequired,
  asyncRoute(async (req, res) => {
    // const userId = req.user.sub;
    const email = req.user.email;
    const data = await callJsonSP('sp_loading_profile_get_json', [email]);
    if (!data) return notFound(res, 'Profil tidak ditemukan', MOD);
    return ok(res, data, 'Profil loading staff berhasil diambil', MOD);
  })
);

export default router;

