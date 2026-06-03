const router = require('express').Router()
const Joi = require('joi')
const bcrypt = require('bcryptjs')
const { db } = require('../db/knex')
const { authenticate, authorize } = require('../middleware/auth')
const { validate } = require('../middleware/validate')

const ROLES = ['admin', 'ingeniero_confiabilidad', 'tecnico_campo', 'supervisor', 'visualizador']

// All routes require authentication
router.use(authenticate)

// GET /api/v1/users — admin only
router.get('/', authorize('admin'), async (req, res) => {
  try {
    const users = await db('auth.users')
      .select('id', 'cedula', 'nombre', 'apellido', 'email', 'role', 'activo', 'ultimo_acceso', 'created_at')
      .orderBy('nombre')
    res.json({ users })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/users — admin only
router.post('/', authorize('admin'), validate(Joi.object({
  cedula: Joi.string().max(20).required(),
  nombre: Joi.string().max(100).required(),
  apellido: Joi.string().max(100).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(8).required(),
  role: Joi.string().valid(...ROLES).required(),
})), async (req, res) => {
  const { cedula, nombre, apellido, email, password, role } = req.body

  try {
    const existing = await db('auth.users').where({ email }).orWhere({ cedula }).first()
    if (existing) {
      return res.status(409).json({ error: 'Ya existe un usuario con ese email o cédula' })
    }

    const password_hash = await bcrypt.hash(password, 12)
    const [user] = await db('auth.users')
      .insert({ cedula, nombre, apellido, email, password_hash, role })
      .returning(['id', 'cedula', 'nombre', 'apellido', 'email', 'role', 'activo', 'created_at'])

    res.status(201).json({ user })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/users/:id — admin only
router.put('/:id', authorize('admin'), validate(Joi.object({
  nombre: Joi.string().max(100),
  apellido: Joi.string().max(100),
  email: Joi.string().email(),
  role: Joi.string().valid(...ROLES),
  activo: Joi.boolean(),
})), async (req, res) => {
  try {
    const [user] = await db('auth.users')
      .where({ id: req.params.id })
      .update(req.body)
      .returning(['id', 'cedula', 'nombre', 'apellido', 'email', 'role', 'activo'])

    if (!user) return res.status(404).json({ error: 'Usuario no encontrado' })
    res.json({ user })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/users/:id/reset-password — admin only
router.post('/:id/reset-password', authorize('admin'), validate(Joi.object({
  new_password: Joi.string().min(8).required(),
})), async (req, res) => {
  try {
    const password_hash = await bcrypt.hash(req.body.new_password, 12)
    const updated = await db('auth.users').where({ id: req.params.id }).update({ password_hash })
    if (!updated) return res.status(404).json({ error: 'Usuario no encontrado' })
    res.json({ message: 'Contraseña restablecida' })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
