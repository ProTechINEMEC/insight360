require('dotenv').config()

const express = require('express')
const helmet = require('helmet')
const cors = require('cors')
const cookieParser = require('cookie-parser')
const morgan = require('morgan')
const compression = require('compression')
const rateLimit = require('express-rate-limit')

const { db } = require('./db/knex')
const { ensureBucket } = require('./services/minio')
const { cleanupExpiredTokens } = require('./services/jwt')

const app = express()
const PORT = process.env.API_PORT || 3000

// ─── Security & Middleware ─────────────────────────────────────────────────

app.set('trust proxy', 1)

app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' },
}))

app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:5173',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
}))

app.use(compression())
app.use(express.json({ limit: '10mb' }))
app.use(cookieParser())

if (process.env.NODE_ENV !== 'test') {
  app.use(morgan('combined'))
}

// Auth-specific rate limiter (stricter)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: { error: 'Demasiados intentos. Por favor espere 15 minutos.' },
  standardHeaders: true,
  legacyHeaders: false,
})

// General API limiter
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
})

app.use('/api/v1/auth', authLimiter)
app.use('/api/', apiLimiter)

// ─── Routes ────────────────────────────────────────────────────────────────

app.use('/api/v1/auth', require('./routes/auth'))
app.use('/api/v1/users', require('./routes/users'))
app.use('/api/v1/assets', require('./routes/assets'))
app.use('/api/v1/measurements', require('./routes/measurements'))
app.use('/api/v1/health', require('./routes/health'))
app.use('/api/v1/inspections', require('./routes/inspections'))

// ─── Health Check ──────────────────────────────────────────────────────────

app.get('/health', async (req, res) => {
  try {
    await db.raw('SELECT 1')
    res.json({ status: 'ok', timestamp: new Date().toISOString() })
  } catch {
    res.status(503).json({ status: 'error', timestamp: new Date().toISOString() })
  }
})

// ─── 404 & Error Handlers ──────────────────────────────────────────────────

app.use((req, res) => {
  res.status(404).json({ error: 'Ruta no encontrada' })
})

app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err)
  res.status(500).json({ error: 'Error interno del servidor' })
})

// ─── Startup ───────────────────────────────────────────────────────────────

async function start() {
  // Wait for DB
  let retries = 10
  while (retries > 0) {
    try {
      await db.raw('SELECT 1')
      console.log('Database connected')
      break
    } catch (err) {
      retries--
      if (retries === 0) { console.error('Cannot connect to database:', err); process.exit(1) }
      console.log(`DB not ready, retrying... (${retries} left)`)
      await new Promise((r) => setTimeout(r, 3000))
    }
  }

  // MinIO bucket setup
  try {
    await ensureBucket()
    console.log('MinIO ready')
  } catch (err) {
    console.error('MinIO setup failed:', err.message)
    // Non-fatal — API can work without file upload
  }

  // Periodic cleanup of expired tokens (every hour)
  setInterval(() => {
    cleanupExpiredTokens().catch((err) => console.error('Token cleanup error:', err))
  }, 60 * 60 * 1000)

  app.listen(PORT, () => {
    console.log(`Insight 360 API running on port ${PORT}`)
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`)
  })
}

start()

module.exports = app
