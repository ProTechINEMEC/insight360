const router = require('express').Router()
const Joi = require('joi')
const bcrypt = require('bcryptjs')
const { db } = require('../db/knex')
const {
  signAccessToken,
  signRefreshToken,
  storeRefreshToken,
  revokeRefreshToken,
  validateRefreshToken,
  revokeAllUserTokens,
} = require('../services/jwt')
const { authenticate } = require('../middleware/auth')
const { validate } = require('../middleware/validate')

const REFRESH_COOKIE = 'insight360_rt'
const COOKIE_OPTS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict',
  maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days in ms
  path: '/api/v1/auth',
}

async function logAudit(userId, action, req, metadata = null) {
  await db('auth.audit_log').insert({
    user_id: userId,
    action,
    ip_address: req.ip || null,
    user_agent: req.get('user-agent') || null,
    metadata: metadata ? JSON.stringify(metadata) : null,
  }).catch(() => {}) // audit failures must not break auth flow
}

// POST /api/v1/auth/login
router.post('/login', validate(Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().min(6).required(),
})), async (req, res) => {
  const { email, password } = req.body

  try {
    const user = await db('auth.users')
      .where({ email })
      .select('id', 'cedula', 'nombre', 'apellido', 'email', 'role', 'password_hash', 'activo')
      .first()

    if (!user || !user.activo) {
      await logAudit(user?.id || null, 'LOGIN_FAILED', req, { email, reason: 'user_not_found' })
      return res.status(401).json({ error: 'Credenciales incorrectas' })
    }

    const valid = await bcrypt.compare(password, user.password_hash)
    if (!valid) {
      await logAudit(user.id, 'LOGIN_FAILED', req, { reason: 'bad_password' })
      return res.status(401).json({ error: 'Credenciales incorrectas' })
    }

    const tokenPayload = { sub: user.id, role: user.role }
    const accessToken = signAccessToken(tokenPayload)
    const refreshToken = signRefreshToken(tokenPayload)

    await storeRefreshToken(user.id, refreshToken, req.ip, req.get('user-agent'))
    await db('auth.users').where({ id: user.id }).update({ ultimo_acceso: db.fn.now() })
    await logAudit(user.id, 'LOGIN', req)

    res.cookie(REFRESH_COOKIE, refreshToken, COOKIE_OPTS)

    res.json({
      accessToken,
      user: {
        id: user.id,
        cedula: user.cedula,
        nombre: user.nombre,
        apellido: user.apellido,
        email: user.email,
        role: user.role,
      },
    })
  } catch (err) {
    console.error('Login error:', err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/auth/refresh
router.post('/refresh', async (req, res) => {
  const token = req.cookies?.[REFRESH_COOKIE]
  if (!token) {
    return res.status(401).json({ error: 'Refresh token requerido', code: 'NO_REFRESH_TOKEN' })
  }

  try {
    const stored = await validateRefreshToken(token)
    if (!stored) {
      res.clearCookie(REFRESH_COOKIE, { path: '/api/v1/auth' })
      return res.status(401).json({ error: 'Refresh token inválido o expirado', code: 'INVALID_REFRESH_TOKEN' })
    }

    const user = await db('auth.users')
      .where({ id: stored.user_id, activo: true })
      .select('id', 'cedula', 'nombre', 'apellido', 'email', 'role')
      .first()

    if (!user) {
      return res.status(401).json({ error: 'Usuario inactivo' })
    }

    // Rotate refresh token
    await revokeRefreshToken(token)
    const tokenPayload = { sub: user.id, role: user.role }
    const newAccessToken = signAccessToken(tokenPayload)
    const newRefreshToken = signRefreshToken(tokenPayload)

    await storeRefreshToken(user.id, newRefreshToken, req.ip, req.get('user-agent'))
    await logAudit(user.id, 'TOKEN_REFRESH', req)

    res.cookie(REFRESH_COOKIE, newRefreshToken, COOKIE_OPTS)
    res.json({
      accessToken: newAccessToken,
      user: {
        id: user.id,
        cedula: user.cedula,
        nombre: user.nombre,
        apellido: user.apellido,
        email: user.email,
        role: user.role,
      },
    })
  } catch (err) {
    console.error('Refresh error:', err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/auth/logout
router.post('/logout', authenticate, async (req, res) => {
  const token = req.cookies?.[REFRESH_COOKIE]

  if (token) {
    await revokeRefreshToken(token).catch(() => {})
  }

  await logAudit(req.user.id, 'LOGOUT', req)
  res.clearCookie(REFRESH_COOKIE, { path: '/api/v1/auth' })
  res.json({ message: 'Sesión cerrada' })
})

// POST /api/v1/auth/logout-all (revoke all sessions)
router.post('/logout-all', authenticate, async (req, res) => {
  await revokeAllUserTokens(req.user.id)
  await logAudit(req.user.id, 'LOGOUT_ALL', req)
  res.clearCookie(REFRESH_COOKIE, { path: '/api/v1/auth' })
  res.json({ message: 'Todas las sesiones cerradas' })
})

// GET /api/v1/auth/me
router.get('/me', authenticate, (req, res) => {
  res.json({ user: req.user })
})

// POST /api/v1/auth/change-password
router.post('/change-password', authenticate, validate(Joi.object({
  current_password: Joi.string().required(),
  new_password: Joi.string().min(8).required(),
})), async (req, res) => {
  const { current_password, new_password } = req.body

  try {
    const user = await db('auth.users')
      .where({ id: req.user.id })
      .select('password_hash')
      .first()

    const valid = await bcrypt.compare(current_password, user.password_hash)
    if (!valid) {
      return res.status(400).json({ error: 'Contraseña actual incorrecta' })
    }

    const newHash = await bcrypt.hash(new_password, 12)
    await db('auth.users').where({ id: req.user.id }).update({ password_hash: newHash })
    await revokeAllUserTokens(req.user.id)
    await logAudit(req.user.id, 'PASSWORD_CHANGE', req)

    res.clearCookie(REFRESH_COOKIE, { path: '/api/v1/auth' })
    res.json({ message: 'Contraseña actualizada. Por favor inicie sesión nuevamente.' })
  } catch (err) {
    console.error('Change password error:', err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
