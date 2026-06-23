const router = require('express').Router()
const Joi = require('joi')
const { db, withRLS } = require('../db/knex')
const { authenticate, authorize } = require('../middleware/auth')
const { validate } = require('../middleware/validate')

router.use(authenticate)

const CRITICIDADES = ['critico', 'esencial', 'general']
const WRITE_ROLES = ['admin', 'ingeniero_confiabilidad', 'supervisor']

// ─── Contracts ─────────────────────────────────────────────────────────────

// GET /api/v1/assets/contratos
router.get('/contratos', async (req, res) => {
  try {
    const contratos = await db('core.contratos').where({ activo: true }).orderBy('nombre')
    res.json({ contratos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Plants ────────────────────────────────────────────────────────────────

// GET /api/v1/assets/plantas
router.get('/plantas', async (req, res) => {
  try {
    const plantas = await db('core.plantas').where({ activo: true }).orderBy('nombre')
    res.json({ plantas })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/assets/plantas
router.post('/plantas', authorize(...WRITE_ROLES), validate(Joi.object({
  codigo: Joi.string().max(20).required(),
  nombre: Joi.string().max(200).required(),
  ubicacion: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const [planta] = await db('core.plantas').insert(req.body).returning('*')
    res.status(201).json({ planta })
  } catch (err) {
    if (err.constraint) return res.status(409).json({ error: 'Código de planta ya existe' })
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Areas ─────────────────────────────────────────────────────────────────

// GET /api/v1/assets/areas?sistema_id=
router.get('/areas', async (req, res) => {
  try {
    const query = db('core.areas').where({ activo: true }).orderBy('nombre')
    if (req.query.sistema_id) query.where({ sistema_id: req.query.sistema_id })
    const areas = await query
    res.json({ areas })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Systems ───────────────────────────────────────────────────────────────

// GET /api/v1/assets/sistemas?planta_id=
router.get('/sistemas', async (req, res) => {
  try {
    const query = db('core.sistemas').where({ activo: true }).orderBy('nombre')
    if (req.query.planta_id) query.where({ planta_id: req.query.planta_id })
    const sistemas = await query
    res.json({ sistemas })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/assets/sistemas
router.post('/sistemas', authorize(...WRITE_ROLES), validate(Joi.object({
  planta_id: Joi.string().uuid().required(),
  codigo: Joi.string().max(30).required(),
  nombre: Joi.string().max(200).required(),
  descripcion: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const [sistema] = await db('core.sistemas').insert(req.body).returning('*')
    res.status(201).json({ sistema })
  } catch (err) {
    if (err.constraint) return res.status(409).json({ error: 'Código de sistema ya existe en esta planta' })
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Assets (Activos) ──────────────────────────────────────────────────────

// GET /api/v1/assets — with optional filters
router.get('/', async (req, res) => {
  try {
    const query = db('core.activos as a')
      .join('core.sistemas as s', 'a.sistema_id', 's.id')
      .join('core.plantas as p', 's.planta_id', 'p.id')
      .where({ 'a.activo': true })
      .select(
        'a.id', 'a.codigo_sap', 'a.tag', 'a.nombre', 'a.criticidad',
        'a.fabricante', 'a.modelo', 'a.fecha_instalacion', 'a.created_at',
        's.id as sistema_id', 's.nombre as sistema_nombre',
        'p.id as planta_id', 'p.nombre as planta_nombre'
      )
      .orderBy('a.nombre')

    if (req.query.planta_id) query.where({ 's.planta_id': req.query.planta_id })
    if (req.query.sistema_id) query.where({ 'a.sistema_id': req.query.sistema_id })
    if (req.query.criticidad) query.where({ 'a.criticidad': req.query.criticidad })
    if (req.query.search) {
      const s = `%${req.query.search}%`
      query.where((b) => b.whereLike('a.nombre', s).orWhereLike('a.tag', s).orWhereLike('a.codigo_sap', s))
    }

    const activos = await query
    res.json({ activos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/assets/:id
router.get('/:id', async (req, res) => {
  try {
    const activo = await db('core.activos as a')
      .join('core.sistemas as s', 'a.sistema_id', 's.id')
      .join('core.plantas as p', 's.planta_id', 'p.id')
      .where({ 'a.id': req.params.id })
      .select(
        'a.*',
        's.nombre as sistema_nombre', 's.codigo as sistema_codigo',
        'p.id as planta_id', 'p.nombre as planta_nombre', 'p.codigo as planta_codigo'
      )
      .first()

    if (!activo) return res.status(404).json({ error: 'Activo no encontrado' })
    res.json({ activo })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/assets
router.post('/', authorize(...WRITE_ROLES), validate(Joi.object({
  sistema_id: Joi.string().uuid().required(),
  codigo_sap: Joi.string().max(50).allow('', null),
  tag: Joi.string().max(100).required(),
  nombre: Joi.string().max(200).required(),
  descripcion: Joi.string().allow('', null),
  fabricante: Joi.string().max(100).allow('', null),
  modelo: Joi.string().max(100).allow('', null),
  numero_serie: Joi.string().max(100).allow('', null),
  fecha_instalacion: Joi.date().iso().allow(null),
  criticidad: Joi.string().valid(...CRITICIDADES).default('general'),
  metadata: Joi.object().allow(null),
})), async (req, res) => {
  try {
    const payload = { ...req.body, created_by: req.user.id }
    const [activo] = await db('core.activos').insert(payload).returning('*')
    res.status(201).json({ activo })
  } catch (err) {
    if (err.constraint?.includes('codigo_sap')) return res.status(409).json({ error: 'Código SAP ya existe' })
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/assets/:id
router.put('/:id', authorize(...WRITE_ROLES), validate(Joi.object({
  sistema_id: Joi.string().uuid(),
  codigo_sap: Joi.string().max(50).allow('', null),
  tag: Joi.string().max(100),
  nombre: Joi.string().max(200),
  descripcion: Joi.string().allow('', null),
  fabricante: Joi.string().max(100).allow('', null),
  modelo: Joi.string().max(100).allow('', null),
  numero_serie: Joi.string().max(100).allow('', null),
  fecha_instalacion: Joi.date().iso().allow(null),
  criticidad: Joi.string().valid(...CRITICIDADES),
  activo: Joi.boolean(),
  metadata: Joi.object().allow(null),
})), async (req, res) => {
  try {
    const [updated] = await db('core.activos')
      .where({ id: req.params.id })
      .update(req.body)
      .returning('*')

    if (!updated) return res.status(404).json({ error: 'Activo no encontrado' })
    res.json({ activo: updated })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/assets/tree — hierarchical structure (contrato → planta → sistema → activo)
router.get('/tree/hierarchy', async (req, res) => {
  try {
    const contratos = await db('core.contratos').where({ activo: true }).orderBy('nombre')
    const plantas = await db('core.plantas').where({ activo: true }).orderBy('nombre')
    const sistemas = await db('core.sistemas').where({ activo: true }).orderBy('nombre')
    const activos = await db('core.activos')
      .where({ activo: true })
      .select('id', 'sistema_id', 'tag', 'nombre', 'criticidad', 'codigo_sap', 'area_id')
      .orderBy('tag')

    // Plantas without a contrato (legacy) get grouped under a virtual "Sin contrato" entry
    const tree = contratos.map((ct) => ({
      ...ct,
      plantas: plantas
        .filter((p) => p.contrato_id === ct.id)
        .map((p) => ({
          ...p,
          sistemas: sistemas
            .filter((s) => s.planta_id === p.id)
            .map((s) => ({
              ...s,
              activos: activos.filter((a) => a.sistema_id === s.id),
            })),
        })),
    }))

    // Include plantas with no contrato (shouldn't happen after migration, but defensive)
    const sinContrato = plantas.filter((p) => !p.contrato_id)
    if (sinContrato.length) {
      tree.push({
        id: null,
        nombre: 'Sin Contrato',
        plantas: sinContrato.map((p) => ({
          ...p,
          sistemas: sistemas
            .filter((s) => s.planta_id === p.id)
            .map((s) => ({
              ...s,
              activos: activos.filter((a) => a.sistema_id === s.id),
            })),
        })),
      })
    }

    res.json({ tree })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
