import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import rateLimit from 'express-rate-limit';
import orderRoutes from './routes/orders.js';
import { initDatabase } from './config/database.js';
import { metricsMiddleware, metricsEndpoint } from './middleware/metrics.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3003;
const SERVICE_NAME = 'order-service';
const VERSION = '3.3';

app.use(cors({ origin: true, credentials: true }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(metricsMiddleware);

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 100 });
app.use('/api/', limiter);

app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    const user = req.user?.email || req.body?.email || 'anonymous';
    const status = res.statusCode;
    const emoji = status < 400 ? '✅' : '❌';
    
    console.log(`${emoji} [${SERVICE_NAME}] ${req.method} ${req.path}
   User: ${user}
   Status: ${status}
   Duration: ${duration}ms`);
  });
  
  next();
});

// ============================================
// ROUTES DE SANTÉ (avec préfixe /api/orders)
// ============================================
app.get('/api/orders/health', async (req, res) => {
  const health = {
    status: 'ok',
    service: SERVICE_NAME,
    version: VERSION,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'production',
    database: 'disconnected'
  };

  try {
    const { getConnection } = await import('./config/database.js');
    const connection = await getConnection();
    await connection.query('SELECT 1');
    connection.release();
    health.database = 'connected';
  } catch (error) {
    health.database = 'error';
    health.status = 'degraded';
  }

  res.status(health.status === 'ok' ? 200 : 503).json(health);
});

app.get('/api/orders/ready', async (req, res) => {
  try {
    const { getConnection } = await import('./config/database.js');
    const connection = await getConnection();
    await connection.query('SELECT 1');
    connection.release();
    res.json({ status: 'ready' });
  } catch (error) {
    console.error('Readiness check failed:', error);
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

app.get('/api/orders/metrics', metricsEndpoint);

app.get('/api/orders/info', (req, res) => {
  res.json({
    service: SERVICE_NAME,
    version: VERSION,
    description: 'Service de gestion des commandes',
    endpoints: [
      'GET  /api/orders/health       - Health check',
      'GET  /api/orders/ready        - Readiness check',
      'GET  /api/orders/metrics      - Prometheus metrics',
      'GET  /api/orders/info         - Service info',
      'GET  /api/orders              - List orders (auth required)',
      'POST /api/orders              - Create order (auth required)',
      'GET  /api/orders/:id          - Order details (auth required)',
      'PUT  /api/orders/:id/status   - Update order status (auth required)'
    ]
  });
});

// ============================================
// ROUTES MÉTIER
// ============================================
app.use('/api/orders', orderRoutes);

// ============================================
// ERROR HANDLERS
// ============================================
app.use((req, res) => {
  res.status(404).json({ 
    error: 'Route non trouvée',
    path: req.path,
    method: req.method
  });
});

app.use((err, req, res, next) => {
  console.error(`[${SERVICE_NAME}] Error:`, err);
  res.status(err.status || 500).json({ 
    error: err.message || 'Erreur interne du serveur',
    service: SERVICE_NAME
  });
});

// ============================================
// SERVER START
// ============================================
const startServer = async () => {
  try {
    await initDatabase();
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`
╔═══════════════════════════════════════════════
║   📦 ${SERVICE_NAME.toUpperCase()} - v${VERSION}
║
║   Port: ${PORT}
║   Environment: ${process.env.NODE_ENV || 'development'}
║   Database: ${process.env.DB_HOST || 'localhost'}:${process.env.DB_PORT || 3306}
║
║   📚 Endpoints:
║   GET  /api/orders/health       - Health check
║   GET  /api/orders/ready        - Ready check
║   GET  /api/orders/metrics      - Prometheus
║   GET  /api/orders/info         - Service info
║   GET  /api/orders              - List orders
║   POST /api/orders              - Create order
║   GET  /api/orders/all          - List all orders
║   GET  /api/orders/:id          - Order details
║   PUT  /api/orders/:id/status   - Update status
║
╚═══════════════════════════════════════════════
      `);
    });
  } catch (error) {
    console.error(`❌ Failed to start ${SERVICE_NAME}:`, error);
    process.exit(1);
  }
};

startServer();