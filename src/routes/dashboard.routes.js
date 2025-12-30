import { Router } from 'express';
import { authRequired, requireUserAndRoleQuery } from '../middleware/auth.js';
import { callJsonSP } from '../db.js';
import { ok, bad, asyncRoute } from '../utils/http.js';

const router = Router();

// GET /api/dashboard/loading?user_id=..&role_id=..
router.get(
  '/dashboard/loading',
  authRequired,
  requireUserAndRoleQuery,
  asyncRoute(async (req, res) => {
    const { user_id, role_id } = req.query;
    const data = await callJsonSP('sp_dashboard_loading_json', [user_id, role_id]);
    if (!data) return bad(res, 'No dashboard loading data', 404);
    return ok(res, data);
  })
);

// GET /api/dashboard/customer?user_id=..&role_id=..&limit=20
router.get(
  '/dashboard/customer',
  authRequired,
  requireUserAndRoleQuery,
  asyncRoute(async (req, res) => {
    const { user_id, role_id } = req.query;
    const limit = Math.max(1, Math.min(100, Number(req.query.limit || 20)));
    const data = await callJsonSP('sp_dashboard_customer_json', [user_id, role_id, limit]);
    if (!data) return bad(res, 'No dashboard customer data', 404);
    return ok(res, data);
  })
);

export default router;
