const router = require('express').Router()
const Joi = require('joi')
const multer = require('multer')
const { db } = require('../db/knex')
const { authenticate, authorize } = require('../middleware/auth')
const { validate } = require('../middleware/validate')
const { uploadFile, getPresignedUrl, deleteFile } = require('../services/minio')

router.use(authenticate)

const WRITE_ROLES = ['admin', 'ingeniero_confiabilidad', 'supervisor', 'tecnico_campo']
const ADMIN_ROLES = ['admin', 'ingeniero_confiabilidad']

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50 MB
})

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
      .select('m.id', 'm.modo_falla', 'm.tecnica_id', 'm.tipo_componente_id', 'tc.nombre as tipo_componente', 'tc.codigo as tipo_codigo')
      .orderBy(['tc.nombre', 'm.modo_falla'])

    if (req.query.tecnica_id) query.where({ 'm.tecnica_id': req.query.tecnica_id })
    if (req.query.tipo_componente_id) query.where({ 'm.tipo_componente_id': req.query.tipo_componente_id })

    const modos = await query
    res.json({ modos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/inspections/modos-falla
router.post('/modos-falla', authorize(...ADMIN_ROLES), validate(Joi.object({
  tecnica_id: Joi.string().uuid().required(),
  tipo_componente_id: Joi.string().uuid().required(),
  modo_falla: Joi.string().max(300).required(),
})), async (req, res) => {
  try {
    const [modo] = await db('cbm.catalogo_modos_falla')
      .insert({ tecnica_id: req.body.tecnica_id, tipo_componente_id: req.body.tipo_componente_id, modo_falla: req.body.modo_falla })
      .returning('*')
    res.status(201).json({ modo })
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Este modo de falla ya existe para esta técnica y tipo de componente' })
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/inspections/modos-falla/:id
router.put('/modos-falla/:id', authorize(...ADMIN_ROLES), validate(Joi.object({
  modo_falla: Joi.string().max(300).required(),
})), async (req, res) => {
  try {
    const [modo] = await db('cbm.catalogo_modos_falla')
      .where({ id: req.params.id })
      .update({ modo_falla: req.body.modo_falla })
      .returning('*')
    if (!modo) return res.status(404).json({ error: 'No encontrado' })
    res.json({ modo })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// DELETE /api/v1/inspections/modos-falla/:id
router.delete('/modos-falla/:id', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    await db('cbm.catalogo_modos_falla').where({ id: req.params.id }).delete()
    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Puntos de Medición por Técnica ─────────────────────────────────────────

// GET /api/v1/inspections/puntos-tecnica?tecnica_id=
router.get('/puntos-tecnica', async (req, res) => {
  try {
    const query = db('cbm.puntos_medicion_tecnica as p')
      .leftJoin('cbm.tecnicas as t', 'p.tecnica_id', 't.id')
      .where({ 'p.activo': true })
      .select('p.*', 't.codigo as tecnica_codigo', 't.nombre as tecnica_nombre')
      .orderBy(['p.tecnica_id', 'p.orden'])

    if (req.query.tecnica_id) query.where({ 'p.tecnica_id': req.query.tecnica_id })

    const puntos = await query
    res.json({ puntos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/inspections/puntos-tecnica (admin)
router.post('/puntos-tecnica', authorize(...ADMIN_ROLES), validate(Joi.object({
  tecnica_id: Joi.string().uuid().required(),
  nombre: Joi.string().max(200).required(),
  unidad: Joi.string().max(50).allow('', null),
  descripcion: Joi.string().allow('', null),
  orden: Joi.number().integer().default(0),
})), async (req, res) => {
  try {
    const [punto] = await db('cbm.puntos_medicion_tecnica').insert(req.body).returning('*')
    res.status(201).json({ punto })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/inspections/puntos-tecnica/:id (admin)
router.put('/puntos-tecnica/:id', authorize(...ADMIN_ROLES), validate(Joi.object({
  nombre: Joi.string().max(200),
  unidad: Joi.string().max(50).allow('', null),
  descripcion: Joi.string().allow('', null),
  orden: Joi.number().integer(),
  activo: Joi.boolean(),
})), async (req, res) => {
  try {
    const [punto] = await db('cbm.puntos_medicion_tecnica')
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

// DELETE /api/v1/inspections/puntos-tecnica/:id (admin)
router.delete('/puntos-tecnica/:id', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const deleted = await db('cbm.puntos_medicion_tecnica').where({ id: req.params.id }).del()
    if (!deleted) return res.status(404).json({ error: 'Punto no encontrado' })
    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Técnicas Admin ──────────────────────────────────────────────────────────

// GET /api/v1/inspections/tecnicas-admin (all, including inactive)
router.get('/tecnicas-admin', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const tecnicas = await db('cbm.tecnicas').orderBy('nombre').select('*')
    res.json({ tecnicas })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/inspections/tecnicas-admin (admin)
router.post('/tecnicas-admin', authorize(...ADMIN_ROLES), validate(Joi.object({
  codigo: Joi.string().max(50).required(),
  nombre: Joi.string().max(200).required(),
  norma_referencia: Joi.string().allow('', null),
  aplica_a: Joi.string().max(200).allow('', null),
  activo: Joi.boolean().default(true),
})), async (req, res) => {
  try {
    const [tecnica] = await db('cbm.tecnicas').insert(req.body).returning('*')
    res.status(201).json({ tecnica })
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Código de técnica ya existe' })
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/inspections/tecnicas-admin/:id (admin)
router.put('/tecnicas-admin/:id', authorize(...ADMIN_ROLES), validate(Joi.object({
  nombre: Joi.string().max(200),
  norma_referencia: Joi.string().allow('', null),
  aplica_a: Joi.string().max(200).allow('', null),
  activo: Joi.boolean(),
})), async (req, res) => {
  try {
    const [tecnica] = await db('cbm.tecnicas')
      .where({ id: req.params.id })
      .update(req.body)
      .returning('*')
    if (!tecnica) return res.status(404).json({ error: 'Técnica no encontrada' })
    res.json({ tecnica })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/inspections/tecnicas-admin/:id/tipos-componente — tipos linked via catalogo_modos_falla
router.get('/tecnicas-admin/:id/tipos-componente', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const tipos = await db('cbm.tipos_componente as tc')
      .join('cbm.catalogo_modos_falla as mf', 'mf.tipo_componente_id', 'tc.id')
      .where({ 'mf.tecnica_id': req.params.id })
      .distinct('tc.id', 'tc.codigo', 'tc.nombre')
      .orderBy('tc.nombre')
    res.json({ tipos })
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

// ─── Inspecciones ────────────────────────────────────────────────────────────

// GET /api/v1/inspections/inspecciones?componente_id=&activo_id=&tecnica_id=&limit=&offset=
router.get('/inspecciones', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 50, 500)
  const offset = parseInt(req.query.offset) || 0
  try {
    const query = db('cbm.inspecciones as i')
      .join('cbm.componentes as c', 'i.componente_id', 'c.id')
      .join('core.activos as a', 'c.activo_id', 'a.id')
      .join('cbm.tecnicas as t', 'i.tecnica_id', 't.id')
      .leftJoin('cbm.catalogo_modos_falla as mf', 'i.modo_falla_id', 'mf.id')
      .leftJoin('cbm.tipos_componente as tc', 'c.tipo_componente_id', 'tc.id')
      .select(
        'i.id', 'i.fecha', 'i.condicion', 'i.estado_operacional',
        'i.analista', 'i.observaciones', 'i.created_at',
        'c.id as componente_id', 'c.nombre as componente_nombre', 'c.cmms_id',
        'tc.nombre as tipo_componente',
        'a.id as activo_id', 'a.tag', 'a.nombre as activo_nombre',
        't.id as tecnica_id', 't.codigo as tecnica_codigo', 't.nombre as tecnica_nombre',
        'mf.modo_falla'
      )
      .orderBy('i.fecha', 'desc')
      .limit(limit)
      .offset(offset)

    if (req.query.componente_id) query.where({ 'i.componente_id': req.query.componente_id })
    if (req.query.activo_id) query.where({ 'c.activo_id': req.query.activo_id })
    if (req.query.tecnica_id) query.where({ 'i.tecnica_id': req.query.tecnica_id })

    const inspecciones = await query
    res.json({ inspecciones })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/inspections/inspecciones/:id — full detail with measurements and files
router.get('/inspecciones/:id', async (req, res) => {
  try {
    const inspeccion = await db('cbm.inspecciones as i')
      .join('cbm.componentes as c', 'i.componente_id', 'c.id')
      .join('core.activos as a', 'c.activo_id', 'a.id')
      .join('core.sistemas as s', 'a.sistema_id', 's.id')
      .join('core.plantas as p', 's.planta_id', 'p.id')
      .join('cbm.tecnicas as t', 'i.tecnica_id', 't.id')
      .leftJoin('cbm.catalogo_modos_falla as mf', 'i.modo_falla_id', 'mf.id')
      .leftJoin('cbm.tipos_componente as tc', 'c.tipo_componente_id', 'tc.id')
      .where({ 'i.id': req.params.id })
      .select(
        'i.*',
        'c.nombre as componente_nombre', 'c.cmms_id',
        'tc.nombre as tipo_componente',
        'a.id as activo_id', 'a.tag', 'a.nombre as activo_nombre',
        's.nombre as sistema_nombre',
        'p.nombre as planta_nombre',
        't.codigo as tecnica_codigo', 't.nombre as tecnica_nombre', 't.norma_referencia',
        'mf.modo_falla'
      )
      .first()

    if (!inspeccion) return res.status(404).json({ error: 'Inspección no encontrada' })

    const [mediciones, archivos] = await Promise.all([
      db('cbm.inspeccion_mediciones as m')
        .join('cbm.puntos_medicion_tecnica as p', 'm.punto_id', 'p.id')
        .where({ 'm.inspeccion_id': req.params.id })
        .select('m.*', 'p.nombre as punto_nombre', 'p.unidad', 'p.orden')
        .orderBy('p.orden'),
      db('cbm.inspeccion_archivos')
        .where({ inspeccion_id: req.params.id })
        .orderBy('created_at'),
    ])

    res.json({ inspeccion, mediciones, archivos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/inspections/inspecciones
router.post('/inspecciones', authorize(...WRITE_ROLES), validate(Joi.object({
  componente_id: Joi.string().uuid().required(),
  tecnica_id: Joi.string().uuid().required(),
  fecha: Joi.date().iso().default(() => new Date()),
  analista: Joi.string().max(200).allow('', null),
  estado_operacional: Joi.string()
    .valid('operativo', 'operativo_limitado', 'stand_by', 'fuera_de_servicio', 'dado_de_baja')
    .required(),
  condicion: Joi.string().valid('normal', 'observacion', 'alerta', 'urgencia').required(),
  modo_falla_id: Joi.string().uuid().allow(null),
  observaciones: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const payload = { ...req.body, creado_por: req.user.id }
    const [inspeccion] = await db('cbm.inspecciones').insert(payload).returning('*')
    res.status(201).json({ inspeccion })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/inspections/inspecciones/:id
router.put('/inspecciones/:id', authorize(...WRITE_ROLES), validate(Joi.object({
  fecha: Joi.date().iso(),
  analista: Joi.string().max(200).allow('', null),
  estado_operacional: Joi.string()
    .valid('operativo', 'operativo_limitado', 'stand_by', 'fuera_de_servicio', 'dado_de_baja'),
  condicion: Joi.string().valid('normal', 'observacion', 'alerta', 'urgencia'),
  modo_falla_id: Joi.string().uuid().allow(null),
  observaciones: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const [inspeccion] = await db('cbm.inspecciones')
      .where({ id: req.params.id })
      .update(req.body)
      .returning('*')
    if (!inspeccion) return res.status(404).json({ error: 'Inspección no encontrada' })
    res.json({ inspeccion })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// DELETE /api/v1/inspections/inspecciones/:id
router.delete('/inspecciones/:id', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const deleted = await db('cbm.inspecciones').where({ id: req.params.id }).del()
    if (!deleted) return res.status(404).json({ error: 'Inspección no encontrada' })
    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Mediciones por Inspección ───────────────────────────────────────────────

// PUT /api/v1/inspections/inspecciones/:id/mediciones — bulk upsert measurement values
router.put('/inspecciones/:id/mediciones', authorize(...WRITE_ROLES), validate(Joi.object({
  mediciones: Joi.array().items(Joi.object({
    punto_id: Joi.string().uuid().required(),
    valor: Joi.number().allow(null),
    valor_texto: Joi.string().allow('', null),
    condicion: Joi.string().valid('normal', 'observacion', 'alerta', 'urgencia').allow(null),
    observaciones: Joi.string().allow('', null),
  })).required(),
})), async (req, res) => {
  const { mediciones } = req.body
  try {
    // Verify inspection exists
    const exists = await db('cbm.inspecciones').where({ id: req.params.id }).first()
    if (!exists) return res.status(404).json({ error: 'Inspección no encontrada' })

    // Upsert each measurement
    const rows = mediciones.map((m) => ({
      inspeccion_id: req.params.id,
      punto_id: m.punto_id,
      valor: m.valor ?? null,
      valor_texto: m.valor_texto || null,
      condicion: m.condicion || null,
      observaciones: m.observaciones || null,
    }))

    await db('cbm.inspeccion_mediciones')
      .insert(rows)
      .onConflict(['inspeccion_id', 'punto_id'])
      .merge()

    const saved = await db('cbm.inspeccion_mediciones as m')
      .join('cbm.puntos_medicion_tecnica as p', 'm.punto_id', 'p.id')
      .where({ 'm.inspeccion_id': req.params.id })
      .select('m.*', 'p.nombre as punto_nombre', 'p.unidad', 'p.orden')
      .orderBy('p.orden')

    res.json({ mediciones: saved })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Archivos por Inspección ────────────────────────────────────────────────

// POST /api/v1/inspections/inspecciones/:id/archivos — upload file
router.post('/inspecciones/:id/archivos', authorize(...WRITE_ROLES),
  upload.single('archivo'),
  async (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'Archivo requerido' })

    const tipo = req.body.tipo || 'reporte'
    const objectKey = `inspecciones/${req.params.id}/${Date.now()}_${req.file.originalname}`

    try {
      const exists = await db('cbm.inspecciones').where({ id: req.params.id }).first()
      if (!exists) return res.status(404).json({ error: 'Inspección no encontrada' })

      await uploadFile(objectKey, req.file.buffer, req.file.mimetype)

      const [archivo] = await db('cbm.inspeccion_archivos').insert({
        inspeccion_id: req.params.id,
        nombre_original: req.file.originalname,
        object_key: objectKey,
        content_type: req.file.mimetype,
        size_bytes: req.file.size,
        tipo,
        uploaded_by: req.user.id,
      }).returning('*')

      res.status(201).json({ archivo })
    } catch (err) {
      console.error(err)
      res.status(500).json({ error: 'Error interno' })
    }
  }
)

// GET /api/v1/inspections/inspecciones/:id/archivos/:archivoId/download — presigned URL
router.get('/inspecciones/:id/archivos/:archivoId/download', async (req, res) => {
  try {
    const archivo = await db('cbm.inspeccion_archivos')
      .where({ id: req.params.archivoId, inspeccion_id: req.params.id })
      .first()
    if (!archivo) return res.status(404).json({ error: 'Archivo no encontrado' })

    const url = await getPresignedUrl(archivo.object_key)
    res.json({ url })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// DELETE /api/v1/inspections/inspecciones/:id/archivos/:archivoId
router.delete('/inspecciones/:id/archivos/:archivoId', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const archivo = await db('cbm.inspeccion_archivos')
      .where({ id: req.params.archivoId, inspeccion_id: req.params.id })
      .first()
    if (!archivo) return res.status(404).json({ error: 'Archivo no encontrado' })

    await deleteFile(archivo.object_key)
    await db('cbm.inspeccion_archivos').where({ id: req.params.archivoId }).del()
    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Resumen Activo (for tree-view detail panel) ─────────────────────────────

// GET /api/v1/inspections/resumen-activo?activo_id=
// Returns per-technique last inspection + list of components (for new inspection modal)
router.get('/resumen-activo', async (req, res) => {
  const { activo_id } = req.query
  if (!activo_id) return res.status(400).json({ error: 'activo_id requerido' })

  try {
    // All applicable techniques for this activo (via componentes × catalogo_modos_falla)
    const tecnicasAplicables = await db.raw(`
      SELECT DISTINCT t.id, t.codigo, t.nombre, t.norma_referencia
      FROM cbm.componentes c
      JOIN cbm.catalogo_modos_falla mf ON mf.tipo_componente_id = c.tipo_componente_id
      JOIN cbm.tecnicas t ON t.id = mf.tecnica_id
      WHERE c.activo_id = ? AND t.activo = TRUE
      ORDER BY t.nombre
    `, [activo_id])

    // Latest inspection per technique
    const latestInspecciones = await db.raw(`
      SELECT DISTINCT ON (i.tecnica_id)
        i.id AS inspeccion_id,
        i.tecnica_id,
        i.fecha,
        i.condicion,
        i.estado_operacional,
        i.analista,
        c.nombre AS componente_nombre
      FROM cbm.inspecciones i
      JOIN cbm.componentes c ON i.componente_id = c.id
      WHERE c.activo_id = ?
      ORDER BY i.tecnica_id, i.fecha DESC
    `, [activo_id])

    const latestMap = {}
    for (const row of latestInspecciones.rows) {
      latestMap[row.tecnica_id] = row
    }

    // Components for the modal
    const componentes = await db('cbm.componentes as c')
      .leftJoin('cbm.tipos_componente as tc', 'c.tipo_componente_id', 'tc.id')
      .where({ 'c.activo_id': activo_id, 'c.activo': true })
      .select('c.id', 'c.nombre', 'c.cmms_id', 'c.tipo_componente_id', 'tc.codigo as tipo_codigo', 'tc.nombre as tipo_nombre')
      .orderBy('c.nombre')

    const tecnicas = tecnicasAplicables.rows.map((t) => ({
      ...t,
      ultima_inspeccion: latestMap[t.id] || null,
    }))

    res.json({ tecnicas, componentes })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Salud Matrix ───────────────────────────────────────────────────────────

// GET /api/v1/inspections/salud-matriz?contrato_id=&planta_id=
router.get('/salud-matriz', async (req, res) => {
  try {
    const tecnicas = await db('cbm.tecnicas')
      .where({ activo: true })
      .orderBy('nombre')
      .select('id', 'codigo', 'nombre', 'norma_referencia')

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

    // Latest inspection per (activo, tecnica) — from inspecciones table
    const findings = await db.raw(`
      SELECT DISTINCT ON (c.activo_id, i.tecnica_id)
        c.activo_id,
        i.tecnica_id,
        i.condicion,
        i.fecha,
        i.id AS inspeccion_id
      FROM cbm.inspecciones i
      JOIN cbm.componentes c ON i.componente_id = c.id
      WHERE c.activo_id = ANY(?)
      ORDER BY c.activo_id, i.tecnica_id, i.fecha DESC
    `, [activoIds])

    const condMap = {}
    const inspMap = {}
    for (const row of findings.rows) {
      if (!condMap[row.activo_id]) condMap[row.activo_id] = {}
      if (!inspMap[row.activo_id]) inspMap[row.activo_id] = {}
      condMap[row.activo_id][row.tecnica_id] = row.condicion
      inspMap[row.activo_id][row.tecnica_id] = row.inspeccion_id
    }

    // Most recent estado_operacional per activo
    const estadoRows = await db.raw(`
      SELECT DISTINCT ON (c.activo_id)
        c.activo_id,
        i.estado_operacional
      FROM cbm.inspecciones i
      JOIN cbm.componentes c ON i.componente_id = c.id
      WHERE c.activo_id = ANY(?)
      ORDER BY c.activo_id, i.fecha DESC
    `, [activoIds])

    const estadoMap = {}
    for (const row of estadoRows.rows) estadoMap[row.activo_id] = row.estado_operacional

    // Applicable techniques per activo via componentes × catalogo_modos_falla
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
        sistema_id: a.sistema_id,
        sistema_nombre: a.sistema_nombre,
        area_nombre: a.area_nombre,
        estado_op_actual: estadoMap[a.id] || null,
        condiciones: Object.fromEntries(
          tecnicas.map((t) => [t.codigo, (condMap[a.id] || {})[t.id] || null])
        ),
        inspeccion_ids: Object.fromEntries(
          tecnicas.map((t) => [t.codigo, (inspMap[a.id] || {})[t.id] || null])
        ),
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

// ─── Legacy: inspection_findings (kept for backwards compatibility) ──────────

// GET /api/v1/inspections/findings
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

module.exports = router
