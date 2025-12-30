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
 * GET /api/agent/tasks
 * Mendapatkan daftar tasks untuk agent
 * SP: sp_agent_tasks_json(p_user_id, p_type, p_status, p_priority, p_page, p_limit)
 */
router.get(
  '/tasks',
  authRequired,
  [
    query('type').optional().isIn(['pickup', 'delivery', 'all']),
    query('status').optional().isIn(['pending', 'in_progress', 'completed']),
    query('priority').optional().isIn(['low', 'medium', 'high']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const type = req.query.type || null;
    const status = req.query.status || null;
    const priority = req.query.priority || null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;

    const data = await callJsonSP('sp_agent_tasks_json', [userId, type, status, priority, page, limit]);
    if (!data) return notFound(res, 'Data tasks tidak ditemukan', MOD);
    return ok(res, data, 'Daftar tasks berhasil diambil', MOD);
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
 * POST /api/agent/scan
 * Scan barcode untuk penerimaan atau pengiriman
 * SP: sp_agent_scan_json(p_user_id, p_barcode, p_scan_type, p_latitude, p_longitude)
 */
router.post(
  '/scan',
  authRequired,
  [
    body('barcode').isString().notEmpty().withMessage('barcode wajib diisi'),
    body('scan_type').isIn(['receive', 'send']).withMessage('scan_type harus receive atau send'),
    body('latitude').isFloat().withMessage('latitude wajib berupa angka'),
    body('longitude').isFloat().withMessage('longitude wajib berupa angka')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const userId = req.user.sub;
    const { barcode, scan_type, latitude, longitude } = req.body;

    const data = await callJsonSP('sp_agent_scan_json', [userId, barcode, scan_type, latitude, longitude]);
    if (!data) return bad(res, 'Gagal scan barcode', 400, MOD, SPECIFIC.INVALID);
    
    const message = scan_type === 'receive' ? 'Paket berhasil diterima' : 'Paket berhasil dikirim';
    return ok(res, data, message, MOD);
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

