const router = require('express').Router()
const Joi = require('joi')
const { db } = require('../db/knex')
const { authenticate, authorize } = require('../middleware/auth')
const { validate } = require('../middleware/validate')

router.use(authenticate)

const WRITE_ROLES = ['admin', 'ingeniero_confiabilidad', 'supervisor', 'tecnico_campo']

// ─── Catalog Endpoints ──────────────────────────────────────────────────────

// GET /api/v1/inspections/tecnicas
router.get('/tecnicas', async (req, res) => {
  try {
    const tecnicas = await db('cbm.tecnicas').where({ activo: true }).orderBy('nombre')
    res.json({ tecnicas })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/inspections/tipos-componente
router.get('/tipos-componente', async (req, res) => {
  try {
    const tipos = await db('cbm.tipos_componente').orderBy('nombre')
    res.json({ tipos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/inspections/modos-falla?tecnica_id=&tipo_componente_id=
router.get('/modos-falla', async (req, res) => {
  try {
    const query = db('cbm.catalogo_modos_falla as m')
      .join('cbm.tecnicas as t', 'm.tecnica_id', 't.id')
      .join('cbm.tipos_componente as tc', 'm.tipo_componente_id', 'tc.id')
      .select('m.id', 'm.modo_falla', 't.nombre as tecnica', 'tc.nombre as tipo_componente')
      .orderBy('m.modo_falla')

    if (req.query.tecnica_id) query.where({ 'm.tecnica_id': req.query.tecnica_id })
    if (req.query.tipo_componente_id) query.where({ 'm.tipo_componente_id': req.query.tipo_componente_id })

    const modos = await query
    res.json({ modos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Componentes ────────────────────────────────────────────────────────────

// GET /api/v1/inspections/componentes?activo_id=
router.get('/componentes', async (req, res) => {
  try {
    const query = db('cbm.componentes as c')
      .leftJoin('cbm.tipos_componente as tc', 'c.tipo_componente_id', 'tc.id')
      .where({ 'c.activo': true })
      .select('c.*', 'tc.nombre as tipo_nombre', 'tc.codigo as tipo_codigo')
      .orderBy('c.nombre')

    if (req.query.activo_id) query.where({ 'c.activo_id': req.query.activo_id })

    const componentes = await query
    res.json({ componentes })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/inspections/componentes
router.post('/componentes', authorize(...WRITE_ROLES), validate(Joi.object({
  activo_id: Joi.string().uuid().required(),
  tipo_componente_id: Joi.string().uuid().allow(null),
  cmms_id: Joi.string().max(100).allow('', null),
  nombre: Joi.string().max(300).required(),
  descripcion: Joi.string().allow('', null),
})), async (req, res) => {
  // Strip any extra fields the client may send (tag, estado_operacional, codigo_cmms)
  req.body = {
    activo_id: req.body.activo_id,
    tipo_componente_id: req.body.tipo_componente_id || null,
    cmms_id: req.body.cmms_id || req.body.codigo_cmms || null,
    nombre: req.body.nombre,
    descripcion: req.body.descripcion || null,
  }
  try {
    const [componente] = await db('cbm.componentes').insert(req.body).returning('*')
    res.status(201).json({ componente })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Findings ───────────────────────────────────────────────────────────────

// GET /api/v1/inspections/findings?componente_id=&activo_id=&contrato_id=&tecnica_id=&limit=50&offset=0
router.get('/findings', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 50, 500)
  const offset = parseInt(req.query.offset) || 0
  try {
    const query = db('cbm.inspection_findings as f')
      .join('cbm.componentes as c', 'f.componente_id', 'c.id')
      .join('core.activos as a', 'c.activo_id', 'a.id')
      .join('core.sistemas as s', 'a.sistema_id', 's.id')
      .join('core.plantas as p', 's.planta_id', 'p.id')
      .leftJoin('cbm.tecnicas as t', 'f.tecnica_id', 't.id')
      .leftJoin('cbm.catalogo_modos_falla as mf', 'f.modo_falla_id', 'mf.id')
      .leftJoin('cbm.tipos_componente as tc', 'c.tipo_componente_id', 'tc.id')
      .select(
        'f.time', 'f.condicion', 'f.estado_operacional', 'f.analista', 'f.observaciones',
        'c.id as componente_id', 'c.nombre as componente_nombre', 'c.cmms_id',
        'tc.nombre as tipo_componente',
        'a.id as activo_id', 'a.tag', 'a.nombre as activo_nombre',
        's.nombre as sistema_nombre',
        'p.id as planta_id', 'p.nombre as planta_nombre',
        't.id as tecnica_id', 't.codigo as tecnica_codigo', 't.nombre as tecnica_nombre',
        'mf.modo_falla'
      )
      .orderBy('f.time', 'desc')
      .limit(limit)
      .offset(offset)

    if (req.query.componente_id) query.where({ 'f.componente_id': req.query.componente_id })
    if (req.query.activo_id) query.where({ 'c.activo_id': req.query.activo_id })
    if (req.query.tecnica_id) query.where({ 'f.tecnica_id': req.query.tecnica_id })
    if (req.query.contrato_id) query.where({ 'p.contrato_id': req.query.contrato_id })
    if (req.query.planta_id) query.where({ 'p.id': req.query.planta_id })

    const findings = await query
    res.json({ findings })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/inspections/findings
router.post('/findings', authorize(...WRITE_ROLES), validate(Joi.object({
  time: Joi.date().iso().default(() => new Date()),
  componente_id: Joi.string().uuid().required(),
  tecnica_id: Joi.string().uuid().required(),
  analista: Joi.string().max(200).allow('', null),
  estado_operacional: Joi.string().valid('operativo', 'operativo_limitado', 'stand_by', 'fuera_de_servicio', 'dado_de_baja').required(),
  condicion: Joi.string().valid('normal', 'observacion', 'alerta', 'urgencia').required(),
  modo_falla_id: Joi.string().uuid().allow(null),
  observaciones: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const payload = { ...req.body, creado_por: req.user.id }
    const [finding] = await db('cbm.inspection_findings').insert(payload).returning('*')
    res.status(201).json({ finding })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Salud Matrix ───────────────────────────────────────────────────────────

// GET /api/v1/inspections/salud-matriz?contrato_id=&planta_id=
// Returns per-activo, per-tecnica last condition for the health matrix page
router.get('/salud-matriz', async (req, res) => {
  try {
    // Fetch all active tecnicas
    const tecnicas = await db('cbm.tecnicas').where({ activo: true }).orderBy('nombre').select('id', 'codigo', 'nombre')

    // Build base activos query filtered by contrato/planta
    const activosQuery = db('core.activos as a')
      .join('core.sistemas as s', 'a.sistema_id', 's.id')
      .join('core.plantas as p', 's.planta_id', 'p.id')
      .leftJoin('core.contratos as ct', 'p.contrato_id', 'ct.id')
      .leftJoin('core.areas as ar', 'a.area_id', 'ar.id')
      .where({ 'a.activo': true })
      .select(
        'a.id', 'a.tag', 'a.nombre', 'a.criticidad',
        's.id as sistema_id', 's.nombre as sistema_nombre',
        'p.id as planta_id', 'p.nombre as planta_nombre',
        'ct.id as contrato_id', 'ct.nombre as contrato_nombre',
        'ar.nombre as area_nombre'
      )
      .orderBy(['ct.nombre', 'p.nombre', 's.nombre', 'a.tag'])

    if (req.query.contrato_id) activosQuery.where({ 'p.contrato_id': req.query.contrato_id })
    if (req.query.planta_id) activosQuery.where({ 'p.id': req.query.planta_id })

    const activos = await activosQuery

    if (!activos.length) {
      return res.json({ tecnicas, rows: [] })
    }

    const activoIds = activos.map((a) => a.id)

    // For each (activo, tecnica): get the most recent finding condition
    // using DISTINCT ON to get latest per (activo_id, tecnica_id)
    const findings = await db.raw(`
      SELECT DISTINCT ON (c.activo_id, f.tecnica_id)
        c.activo_id,
        f.tecnica_id,
        f.condicion,
        f.time
      FROM cbm.inspection_findings f
      JOIN cbm.componentes c ON f.componente_id = c.id
      WHERE c.activo_id = ANY(?)
      ORDER BY c.activo_id, f.tecnica_id, f.time DESC
    `, [activoIds])

    // Build condition lookup: activo_id -> tecnica_id -> condicion
    const condMap = {}
    for (const row of findings.rows) {
      if (!condMap[row.activo_id]) condMap[row.activo_id] = {}
      condMap[row.activo_id][row.tecnica_id] = row.condicion
    }

    // Determine which techniques apply to each activo via componentes × catalogo_modos_falla
    const [aplicableRows, compCounts] = await Promise.all([
      db.raw(`
        SELECT DISTINCT c.activo_id, mf.tecnica_id
        FROM cbm.componentes c
        JOIN cbm.catalogo_modos_falla mf ON mf.tipo_componente_id = c.tipo_componente_id
        WHERE c.activo_id = ANY(?)
      `, [activoIds]),
      db('cbm.componentes')
        .whereIn('activo_id', activoIds)
        .groupBy('activo_id')
        .select('activo_id', db.raw('count(*) as cnt')),
    ])

    const compCountMap = {}
    for (const row of compCounts) compCountMap[row.activo_id] = Number(row.cnt)

    const aplicaMap = {}
    for (const row of aplicableRows.rows) {
      if (!aplicaMap[row.activo_id]) aplicaMap[row.activo_id] = new Set()
      aplicaMap[row.activo_id].add(row.tecnica_id)
    }

    // Build result rows
    const rows = activos.map((a) => {
      const hasComps = (compCountMap[a.id] || 0) > 0
      return {
        activo_id: a.id,
        tag: a.tag,
        nombre: a.nombre,
        criticidad: a.criticidad,
        contrato_id: a.contrato_id,
        contrato_nombre: a.contrato_nombre,
        planta_id: a.planta_id,
        planta_nombre: a.planta_nombre,
        sistema_nombre: a.sistema_nombre,
        area_nombre: a.area_nombre,
        condiciones: Object.fromEntries(
          tecnicas.map((t) => [t.codigo, (condMap[a.id] || {})[t.id] || null])
        ),
        // aplica: true = applies, false = does not apply (grey cell), null = no componentes (unknown)
        aplica: Object.fromEntries(
          tecnicas.map((t) => [
            t.codigo,
            hasComps ? (aplicaMap[a.id]?.has(t.id) ?? false) : null,
          ])
        ),
      }
    })

    res.json({ tecnicas, rows })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
