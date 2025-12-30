import jwt from 'jsonwebtoken';

/** Require Bearer JWT; attaches decoded payload to req.user */
export function authRequired(req, res, next) {
  const auth = req.headers.authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return res.status(401).json({ ok:false, message: 'Missing bearer token' });
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded; // { sub, email, name, roles }
    return next();
  } catch (err) {
    return res.status(401).json({ ok:false, message: 'Invalid or expired token' });
  }
}

/** Ensure ?user_id & ?role_id exist and are numeric */
export function requireUserAndRoleQuery(req, res, next) {
  const userId = Number(req.query.user_id);
  const roleId = Number(req.query.role_id);
  if (!userId || !roleId) {
    return res.status(422).json({ ok:false, message: 'Query params user_id and role_id are required (number)' });
  }
  req.query.user_id = userId;
  req.query.role_id = roleId;
  return next();
}
