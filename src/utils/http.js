/**
 * Response Code Format:
 * - 2 digit pertama: HTTP Status (20=200, 40=400, 41=401, 50=500)
 * - 3 digit berikutnya: Module Code (001=Auth, 002=Customer, 003=Driver, 004=Loading, 005=Agent, 006=Tracking)
 * - 2 digit terakhir: Specific Code (00=Success, 01=Created, 02=Not Found, 03=Invalid, 04=Unauthorized, 05=Forbidden)
 */

// Module codes
export const MODULE = {
  AUTH: '001',
  CUSTOMER: '002',
  DRIVER: '003',
  LOADING: '004',
  AGENT: '005',
  TRACKING: '006'
};

// Specific codes
export const SPECIFIC = {
  SUCCESS: '00',
  CREATED: '01',
  NOT_FOUND: '02',
  INVALID: '03',
  UNAUTHORIZED: '04',
  FORBIDDEN: '05',
  ERROR: '06'
};

/**
 * Generate response code
 * @param {number} httpStatus - HTTP status code
 * @param {string} module - Module code from MODULE constant
 * @param {string} specific - Specific code from SPECIFIC constant
 * @returns {string} - Response code string
 */
export const generateResponseCode = (httpStatus, module, specific) => {
  const statusPrefix = httpStatus.toString().substring(0, 2) + '0';
  return `${statusPrefix}${module}${specific}`;
};

/**
 * Success response (200 OK)
 */
export const ok = (res, data, message = 'Success', module = MODULE.AUTH) => {
  const responseCode = generateResponseCode(200, module, SPECIFIC.SUCCESS);
  return res.json({
    success: true,
    responseCode,
    responseMessage: message,
    data
  });
};

/**
 * Created response (201 Created)
 */
export const created = (res, data, message = 'Created successfully', module = MODULE.AUTH) => {
  const responseCode = generateResponseCode(201, module, SPECIFIC.CREATED);
  return res.status(201).json({
    success: true,
    responseCode,
    responseMessage: message,
    data
  });
};

/**
 * Error response with custom code
 */
export const bad = (res, message, httpCode = 400, module = MODULE.AUTH, specific = SPECIFIC.INVALID) => {
  const responseCode = generateResponseCode(httpCode, module, specific);
  return res.status(httpCode).json({
    success: false,
    responseCode,
    responseMessage: message
  });
};

/**
 * Not Found response (404)
 */
export const notFound = (res, message = 'Resource not found', module = MODULE.AUTH) => {
  const responseCode = generateResponseCode(404, module, SPECIFIC.NOT_FOUND);
  return res.status(404).json({
    success: false,
    responseCode,
    responseMessage: message
  });
};

/**
 * Unauthorized response (401)
 */
export const unauthorized = (res, message = 'Unauthorized', module = MODULE.AUTH) => {
  const responseCode = generateResponseCode(401, module, SPECIFIC.UNAUTHORIZED);
  return res.status(401).json({
    success: false,
    responseCode,
    responseMessage: message
  });
};

/**
 * Forbidden response (403)
 */
export const forbidden = (res, message = 'Forbidden', module = MODULE.AUTH) => {
  const responseCode = generateResponseCode(403, module, SPECIFIC.FORBIDDEN);
  return res.status(403).json({
    success: false,
    responseCode,
    responseMessage: message
  });
};

/**
 * Internal Server Error response (500)
 */
export const serverError = (res, message = 'Internal server error', module = MODULE.AUTH) => {
  const responseCode = generateResponseCode(500, module, SPECIFIC.ERROR);
  return res.status(500).json({
    success: false,
    responseCode,
    responseMessage: message
  });
};

/** Wrap async route handler to bubble errors to Express error middleware */
export const asyncRoute = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};
