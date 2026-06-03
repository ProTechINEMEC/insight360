const router = require('express').Router()
const Joi = require('joi')
const { db } = require('../db/knex')
const { authenticate, authorize } = require('../middleware/auth')
const { validate } = require('../middleware/validate')
const { snapshotActivoHealth } = require('../services/health')

router.use(authenticate)

const WRITE_ROLES = ['admin', 'ingeniero_confiabilidad', 'tecnico_campo', 'supervisor']

// ─── Measurement Points ────────────────────────────────────────────────────

// GET /api/v1/measurements/puntos?activo_id=
router.get('/puntos', async (req, res) => {
  try {
    const query = db('cbm.puntos_medicion').where({ activo: true }).orderBy('nombre')
    if (req.query.activo_id) query.where({ activo_id: req.query.activo_id })
    const puntos = await query
    res.json({ puntos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/measurements/puntos
router.post('/puntos', authorize('admin', 'ingeniero_confiabilidad'), validate(Joi.object({
  activo_id: Joi.string().uuid().required(),
  codigo: Joi.string().max(50).required(),
  nombre: Joi.string().max(200).required(),
  tipo: Joi.string().valid('vibracion', 'temperatura', 'presion', 'caudal', 'corriente', 'voltaje', 'rpm', 'nivel', 'otro').required(),
  unidad: Joi.string().max(30).required(),
  limite_alerta: Joi.number().allow(null),
  limite_alarma: Joi.number().allow(null),
  descripcion: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const [punto] = await db('cbm.puntos_medicion').insert(req.body).returning('*')
    res.status(201).json({ punto })
  } catch (err) {
    if (err.constraint) return res.status(409).json({ error: 'Código de punto ya existe en este activo' })
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/measurements/puntos/:id
router.put('/puntos/:id', authorize('admin', 'ingeniero_confiabilidad'), validate(Joi.object({
  nombre: Joi.string().max(200),
  unidad: Joi.string().max(30),
  limite_alerta: Joi.number().allow(null),
  limite_alarma: Joi.number().allow(null),
  descripcion: Joi.string().allow('', null),
  activo: Joi.boolean(),
})), async (req, res) => {
  try {
    const [punto] = await db('cbm.puntos_medicion')
      .where({ id: req.params.id })
      .update(req.body)
      .returning('*')
    if (!punto) return res.status(404).json({ error: 'Punto no encontrado' })
    res.json({ punto })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/measurements/latest?activo_id= — latest reading per punto (for dashboard cards)
router.get('/latest', async (req, res) => {
  if (!req.query.activo_id) return res.status(422).json({ error: 'activo_id requerido' })
  try {
    const puntos = await db('cbm.puntos_medicion')
      .where({ activo_id: req.query.activo_id, activo: true })

    if (!puntos.length) return res.json({ puntos: [] })

    const ids = puntos.map((p) => p.id)
    const latest = await db('cbm.measurement_entries')
      .whereIn('punto_id', ids)
      .select('punto_id', db.raw('last(valor, time) as valor'), db.raw('max(time) as last_time'))
      .groupBy('punto_id')

    const latestMap = {}
    latest.forEach((r) => { latestMap[r.punto_id] = r })

    const result = puntos.map((p) => ({
      ...p,
      ultimo_valor: latestMap[p.id]?.valor ?? null,
      ultimo_tiempo: latestMap[p.id]?.last_time ?? null,
    }))
    res.json({ puntos: result })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Readings (Time Series) ────────────────────────────────────────────────

// GET /api/v1/measurements/readings?punto_id=&from=&to=&limit=
router.get('/readings', async (req, res) => {
  const schema = Joi.object({
    punto_id: Joi.string().uuid().required(),
    from: Joi.date().iso(),
    to: Joi.date().iso(),
    limit: Joi.number().integer().min(1).max(10000).default(500),
  })
  const { error, value } = schema.validate(req.query)
  if (error) return res.status(422).json({ error: 'Parámetros inválidos' })

  try {
    const query = db('cbm.measurement_entries')
      .where({ punto_id: value.punto_id })
      .orderBy('time', 'desc')
      .limit(value.limit)
      .select('time', 'valor', 'fuente', 'notas')

    if (value.from) query.where('time', '>=', value.from)
    if (value.to) query.where('time', '<=', value.to)

    const readings = await query
    res.json({ readings: readings.reverse() }) // return chronological
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/measurements/readings — single reading
router.post('/readings', authorize(...WRITE_ROLES), validate(Joi.object({
  punto_id: Joi.string().uuid().required(),
  valor: Joi.number().required(),
  time: Joi.date().iso().default(() => new Date()),
  fuente: Joi.string().valid('manual', 'sensor', 'import').default('manual'),
  notas: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const { punto_id, valor, time, fuente, notas } = req.body
    await db('cbm.measurement_entries').insert({
      time, punto_id, valor, fuente, notas, registrado_by: req.user.id,
    })

    // Async health snapshot — fire-and-forget, don't block response
    db('cbm.puntos_medicion').where({ id: punto_id }).select('activo_id').first()
      .then((p) => p && snapshotActivoHealth(p.activo_id))
      .catch((e) => console.error('Health snapshot error:', e))

    res.status(201).json({ message: 'Lectura registrada' })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/measurements/readings/batch — bulk import
router.post('/readings/batch', authorize('admin', 'ingeniero_confiabilidad'), validate(Joi.object({
  punto_id: Joi.string().uuid().required(),
  readings: Joi.array().items(Joi.object({
    time: Joi.date().iso().required(),
    valor: Joi.number().required(),
    notas: Joi.string().allow('', null),
  })).min(1).max(5000).required(),
  fuente: Joi.string().valid('manual', 'sensor', 'import').default('import'),
})), async (req, res) => {
  const { punto_id, readings, fuente } = req.body

  try {
    const rows = readings.map((r) => ({
      time: r.time,
      punto_id,
      valor: r.valor,
      fuente,
      notas: r.notas || null,
      registrado_by: req.user.id,
    }))

    // Insert in chunks of 500
    for (let i = 0; i < rows.length; i += 500) {
      await db('cbm.measurement_entries').insert(rows.slice(i, i + 500))
    }

    res.status(201).json({ message: `${rows.length} lecturas importadas` })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/measurements/stats?punto_id=&from=&to=
router.get('/stats', async (req, res) => {
  const schema = Joi.object({
    punto_id: Joi.string().uuid().required(),
    from: Joi.date().iso(),
    to: Joi.date().iso(),
  })
  const { error, value } = schema.validate(req.query)
  if (error) return res.status(422).json({ error: 'Parámetros inválidos' })

  try {
    const query = db('cbm.measurement_entries')
      .where({ punto_id: value.punto_id })
      .select(
        db.raw('MIN(valor) as min'),
        db.raw('MAX(valor) as max'),
        db.raw('AVG(valor) as avg'),
        db.raw('STDDEV(valor) as stddev'),
        db.raw('COUNT(*) as count'),
        db.raw('MIN(time) as from_time'),
        db.raw('MAX(time) as to_time')
      )
      .first()

    if (value.from) query.where('time', '>=', value.from)
    if (value.to) query.where('time', '<=', value.to)

    const stats = await query
    res.json({ stats })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
