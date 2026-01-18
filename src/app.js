import express from 'express';
import dotenv from 'dotenv';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import path from 'path';
import { fileURLToPath } from 'url';

import { initDb, getPool } from './db.js';
import authRoutes from './routes/auth.routes.js';
import customerRoutes from './routes/customer.routes.js';
import driverRoutes from './routes/driver.routes.js';
import loadingRoutes from './routes/loading.routes.js';
import agentRoutes from './routes/agent.routes.js';
import trackingRoutes from './routes/tracking.routes.js';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',') : true,
  credentials: true
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));
app.use(morgan('dev'));

// Serve static files for uploads
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

/**
 * Health check with DB connectivity test.
 */
app.get('/health', async (_req, res) => {
  const env = process.env.NODE_ENV || 'dev';
  const started = Date.now();
  try {
    const pool = getPool();
    if (!pool || typeof pool.query !== 'function') {
      throw new Error('DB pool is not available');
    }

    const [rows] = await pool.query('SELECT 1 as health_check');
    const latency = Date.now() - started;
    
    return res.json({
      success: true,
      responseCode: '2000000',
      responseMessage: 'Health check passed',
      data: {
        ok: true,
        env,
        db: { ok: true, latency_ms: latency }
      }
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      responseCode: '5000006',
      responseMessage: 'Health check failed',
      data: {
        ok: false,
        env,
        db: { ok: false, error: err?.message || 'DB connection error' }
      }
    });
  }
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/customer', customerRoutes);
app.use('/api/driver', driverRoutes);
app.use('/api/loading', loadingRoutes);
app.use('/api/agent', agentRoutes);
app.use('/api/tracking', trackingRoutes);

// 404 handler
app.use((req, res, next) => {
  if (res.headersSent) return next();
  return res.status(404).json({
    success: false,
    responseCode: '4040002',
    responseMessage: 'Resource not found'
  });
});

// Centralized error handler
app.use((err, _req, res, _next) => {
  console.error('Unhandled error:', err);
  return res.status(500).json({
    success: false,
    responseCode: '5000006',
    responseMessage: 'Internal Server Error'
  });
});

/**
 * Start server after DB connection established
 */
const port = Number(process.env.PORT || 4000);

async function startServer() {
  try {
    console.log('🔌 Connecting to database...');
    await initDb();
    console.log('✅ Database connected successfully!');
    
    app.listen(port, () => {
      console.log(`🚀 AML API running at http://localhost:${port}`);
      console.log(`📚 Available routes:`);
      console.log(`   - POST /api/auth/login`);
      console.log(`   - GET  /api/customer/*`);
      console.log(`   - GET  /api/driver/*`);
      console.log(`   - GET  /api/loading/*`);
      console.log(`   - GET  /api/agent/*`);
      console.log(`   - GET  /api/tracking/:sttNumber`);
    });
  } catch (err) {
    console.error('❌ Failed to start server:', err.message);
    process.exit(1);
  }
}

startServer();
