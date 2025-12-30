import { Router } from 'express';
import { param, validationResult } from 'express-validator';
import { authRequired } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, bad, notFound, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';

const router = Router();
const MOD = MODULE.TRACKING;

/**
 * GET /api/tracking/:sttNumber
 * Mendapatkan detail tracking untuk STT tertentu
 * SP: sp_tracking_detail_json(p_stt_number)
 */
router.get(
  '/:sttNumber',
  authRequired,
  [param('sttNumber').isString().notEmpty().withMessage('sttNumber wajib diisi')],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const { sttNumber } = req.params;

    const data = await callJsonSP('sp_tracking_detail_json', [sttNumber]);
    if (!data) return notFound(res, 'Data tracking tidak ditemukan', MOD);
    return ok(res, data, 'Detail tracking berhasil diambil', MOD);
  })
);

export default router;

