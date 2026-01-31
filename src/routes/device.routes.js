import { Router } from 'express';
import { body, validationResult } from 'express-validator';
import { authRequired } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, bad, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';

const router = Router();
const MOD = MODULE.AUTH; // Using AUTH module for device registration

/**
 * POST /api/device/register
 * Register device token for push notifications
 */
router.post(
  '/register',
  authRequired,
  [
    body('token').isString().notEmpty().withMessage('token wajib diisi'),
    body('platform').isIn(['ios', 'android']).withMessage('platform harus ios atau android')
  ],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 400, MOD, SPECIFIC.INVALID);
    }

    const email = req.user.email;
    const { token, platform } = req.body;

    try {
      const data = await callJsonSP('sp_device_register_json', [email, token, platform]);
      
      if (!data) {
        return bad(res, 'Gagal mendaftarkan device token', 400, MOD, SPECIFIC.ERROR);
      }

      return res.json({
        success: true,
        responseCode: '2000300',
        responseMessage: 'Device token berhasil didaftarkan',
        data
      });
    } catch (error) {
      console.error('[DEVICE] Registration error:', error);
      return bad(res, 'Gagal mendaftarkan device token', 500, MOD, SPECIFIC.ERROR);
    }
  })
);

export default router;
