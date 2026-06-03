const { verifyAccessToken } = require('../services/jwt')
const { db } = require('../db/knex')

// Extract and verify JWT from Authorization: Bearer <token>
async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token requerido' })
  }

  const token = authHeader.slice(7)

  try {
    const payload = verifyAccessToken(token)
    // Verify user still exists and is active
    const user = await db('auth.users')
      .where({ id: payload.sub, activo: true })
      .select('id', 'cedula', 'nombre', 'apellido', 'email', 'role')
      .first()

    if (!user) {
      return res.status(401).json({ error: 'Usuario no encontrado o inactivo' })
    }

    req.user = user
    next()
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expirado', code: 'TOKEN_EXPIRED' })
    }
    return res.status(401).json({ error: 'Token inválido' })
  }
}

// Role-based authorization
function authorize(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'No autenticado' })
    }
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Sin permisos suficientes' })
    }
    next()
  }
}

module.exports = { authenticate, authorize }
