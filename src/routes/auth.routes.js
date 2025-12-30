import { Router } from 'express';
import { body, validationResult } from 'express-validator';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import rateLimit from 'express-rate-limit';
import { callJsonSP } from '../db.js';
import { ok, bad, unauthorized, MODULE, SPECIFIC, asyncRoute } from '../utils/http.js';

const router = Router();
const MOD = MODULE.AUTH;

// Basic rate limiters for auth endpoints
const loginLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 minutes
  max: 30,
  standardHeaders: true,
  legacyHeaders: false
});

const forgotLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false
});

/**
 * POST /api/auth/login
 * body: { username, password }
 * SP: sp_user_login_json(p_username) -> { id, username, email, name, password_hash, role, avatar }
 */
router.post(
  '/login',
  loginLimiter,
  [
    body('username').isString().notEmpty().withMessage('username wajib diisi'),
    body('password').isString().isLength({ min: 4 }).withMessage('password minimal 4 karakter')
  ],
   asyncRoute(async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    console.warn('[LOGIN] ❌ Validation error:', errors.array());
      return bad(res, errors.array()[0].msg, 422, MOD, SPECIFIC.INVALID);
  }

    const { username, password } = req.body;
    console.log(`[LOGIN] 🔹 Incoming login attempt: ${username}`);

  try {
      console.log(`[LOGIN] 🌀 Calling SP: sp_user_login_json('${username}')`);
      const result = await callJsonSP('sp_user_login_json', [username]);
    console.log('[LOGIN] 🧩 SP raw result:', result);

      const user = result?.user;
    if (!user) {
        console.warn(`[LOGIN] ⚠️ No user found for username: ${username}`);
        return unauthorized(res, 'Username atau password salah', MOD);
    }

    const match = await bcrypt.compare(password, user.password_hash || '');
    console.log(`[LOGIN] 🔍 Password match result: ${match}`);

    if (!match) {
        console.warn(`[LOGIN] ❌ Invalid password for: ${username}`);
        return unauthorized(res, 'Username atau password salah', MOD);
    }

    const token = jwt.sign(
        { sub: user.id, username: user.username, email: user.email, name: user.name || '', role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES || '1d' }
    );

    const { password_hash, ...safeUser } = user;
      console.log(`[LOGIN] ✅ Login success for: ${username}`);
      
      return ok(res, { token, user: safeUser }, 'Login berhasil', MOD);
  } catch (err) {
    console.error('[LOGIN] 💥 Unexpected error:', err);
      return bad(res, 'Internal server error during login', 500, MOD, SPECIFIC.ERROR);
  }
})
);

/**
 * POST /api/auth/forgot-password
 * body: { email }
 * SP: sp_password_reset_request_json(p_email) -> { user_id, reset_token, expired_at }
 */
router.post(
  '/forgot-password',
  forgotLimiter,
  [body('email').isEmail().withMessage('email tidak valid')],
  asyncRoute(async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return bad(res, errors.array()[0].msg, 422, MOD, SPECIFIC.INVALID);
    }

    const { email } = req.body;
    const result = await callJsonSP('sp_password_reset_request_json', [email]);
    if (!result) {
      return bad(res, 'Email tidak ditemukan', 404, MOD, SPECIFIC.NOT_FOUND);
    }
    // TODO: Send email with reset token link
    return ok(res, { message: 'Reset token generated', reset: result }, 'Reset password berhasil dikirim', MOD);
  })
);

export default router;
