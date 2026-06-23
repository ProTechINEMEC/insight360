const router = require('express').Router()
const Joi = require('joi')
const multer = require('multer')
const { db, withRLS } = require('../db/knex')
const { authenticate, authorize } = require('../middleware/auth')
const { validate } = require('../middleware/validate')
const { uploadFile, getPresignedUrl, deleteFile } = require('../services/minio')

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } })

router.use(authenticate)

const CRITICIDADES = ['critico', 'esencial', 'general']
const ESTADOS_OP = ['operativo', 'operativo_limitado', 'stand_by', 'fuera_de_servicio', 'dado_de_baja']
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

// POST /api/v1/assets/contratos
router.post('/contratos', authorize('admin'), validate(Joi.object({
  nombre: Joi.string().max(200).required(),
  numero_contrato: Joi.string().max(100).allow('', null),
  empresa_cliente: Joi.string().max(200).allow('', null),
  fecha_inicio: Joi.date().iso().allow(null),
  fecha_fin: Joi.date().iso().allow(null),
})), async (req, res) => {
  try {
    const [contrato] = await db('core.contratos').insert(req.body).returning('*')
    res.status(201).json({ contrato })
  } catch (err) {
    if (err.constraint) return res.status(409).json({ error: 'Número de contrato ya existe' })
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
  contrato_id: Joi.string().uuid().allow(null),
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

// POST /api/v1/assets/areas
router.post('/areas', authorize(...WRITE_ROLES), validate(Joi.object({
  sistema_id: Joi.string().uuid().required(),
  codigo: Joi.string().max(30).required(),
  nombre: Joi.string().max(200).required(),
  descripcion: Joi.string().allow('', null),
})), async (req, res) => {
  try {
    const [area] = await db('core.areas').insert(req.body).returning('*')
    res.status(201).json({ area })
  } catch (err) {
    if (err.constraint) return res.status(409).json({ error: 'Código de área ya existe en este sistema' })
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
  area_id: Joi.string().uuid().allow(null),
  equipo_superior_id: Joi.string().uuid().allow(null),
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
  area_id: Joi.string().uuid().allow(null),
  equipo_superior_id: Joi.string().uuid().allow(null),
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

// ─── Asset Attachments ──────────────────────────────────────────────────────

const ADMIN_ROLES = ['admin', 'ingeniero_confiabilidad']

// GET /api/v1/assets/:id/archivos
router.get('/:id/archivos', async (req, res) => {
  try {
    const archivos = await db('cbm.activo_archivos')
      .where({ activo_id: req.params.id })
      .orderBy('created_at', 'desc')
    res.json({ archivos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/assets/:id/archivos — upload file
router.post('/:id/archivos', authorize(...WRITE_ROLES), upload.single('archivo'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Archivo requerido' })

  const tipo = req.body.tipo || 'otro'
  const objectKey = `activos/${req.params.id}/${Date.now()}_${req.file.originalname}`

  try {
    const activo = await db('core.activos').where({ id: req.params.id }).first()
    if (!activo) return res.status(404).json({ error: 'Activo no encontrado' })

    await uploadFile(objectKey, req.file.buffer, req.file.mimetype)

    const [archivo] = await db('cbm.activo_archivos').insert({
      activo_id: req.params.id,
      nombre_original: req.file.originalname,
      object_key: objectKey,
      content_type: req.file.mimetype,
      size_bytes: req.file.size,
      tipo,
      descripcion: req.body.descripcion || null,
      uploaded_by: req.user.id,
    }).returning('*')

    res.status(201).json({ archivo })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/assets/:id/archivos/:archivoId/download — presigned URL
router.get('/:id/archivos/:archivoId/download', async (req, res) => {
  try {
    const archivo = await db('cbm.activo_archivos')
      .where({ id: req.params.archivoId, activo_id: req.params.id })
      .first()
    if (!archivo) return res.status(404).json({ error: 'Archivo no encontrado' })

    const url = await getPresignedUrl(archivo.object_key)
    res.json({ url })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// DELETE /api/v1/assets/:id/archivos/:archivoId
router.delete('/:id/archivos/:archivoId', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const archivo = await db('cbm.activo_archivos')
      .where({ id: req.params.archivoId, activo_id: req.params.id })
      .first()
    if (!archivo) return res.status(404).json({ error: 'Archivo no encontrado' })

    await deleteFile(archivo.object_key)
    await db('cbm.activo_archivos').where({ id: req.params.archivoId }).del()
    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// ─── Custom Fields ──────────────────────────────────────────────────────────

// GET /api/v1/assets/campos-extra/definiciones
router.get('/campos-extra/definiciones', async (req, res) => {
  try {
    const definiciones = await db('cbm.campos_extra_definicion')
      .where({ activo: true })
      .orderBy('orden')
    res.json({ definiciones })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/assets/campos-extra/definiciones (admin)
router.post('/campos-extra/definiciones', authorize(...ADMIN_ROLES), validate(Joi.object({
  nombre: Joi.string().max(200).required(),
  tipo: Joi.string().valid('texto', 'numero', 'fecha', 'dropdown').required(),
  opciones: Joi.array().items(Joi.string()).when('tipo', {
    is: 'dropdown', then: Joi.required(), otherwise: Joi.forbidden(),
  }),
  orden: Joi.number().integer().default(0),
})), async (req, res) => {
  try {
    const payload = {
      nombre: req.body.nombre,
      tipo: req.body.tipo,
      opciones: req.body.opciones ? JSON.stringify(req.body.opciones) : null,
      orden: req.body.orden ?? 0,
    }
    const [definicion] = await db('cbm.campos_extra_definicion').insert(payload).returning('*')
    res.status(201).json({ definicion })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/assets/campos-extra/definiciones/:id (admin)
router.put('/campos-extra/definiciones/:id', authorize(...ADMIN_ROLES), validate(Joi.object({
  nombre: Joi.string().max(200),
  tipo: Joi.string().valid('texto', 'numero', 'fecha', 'dropdown'),
  opciones: Joi.array().items(Joi.string()).allow(null),
  orden: Joi.number().integer(),
  activo: Joi.boolean(),
})), async (req, res) => {
  try {
    const payload = { ...req.body }
    if (payload.opciones !== undefined) {
      payload.opciones = payload.opciones ? JSON.stringify(payload.opciones) : null
    }
    const [definicion] = await db('cbm.campos_extra_definicion')
      .where({ id: req.params.id })
      .update(payload)
      .returning('*')
    if (!definicion) return res.status(404).json({ error: 'Campo no encontrado' })
    res.json({ definicion })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// DELETE /api/v1/assets/campos-extra/definiciones/:id (admin)
router.delete('/campos-extra/definiciones/:id', authorize(...ADMIN_ROLES), async (req, res) => {
  try {
    const [updated] = await db('cbm.campos_extra_definicion')
      .where({ id: req.params.id })
      .update({ activo: false })
      .returning('id')
    if (!updated) return res.status(404).json({ error: 'Campo no encontrado' })
    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/assets/:id/campos-extra — values for a specific machine
router.get('/:id/campos-extra', async (req, res) => {
  try {
    const definiciones = await db('cbm.campos_extra_definicion')
      .where({ activo: true })
      .orderBy('orden')

    const valores = await db('cbm.activo_campos_extra')
      .where({ activo_id: req.params.id })

    const valorMap = {}
    for (const v of valores) valorMap[v.campo_id] = v.valor

    const campos = definiciones.map((d) => ({
      ...d,
      valor: valorMap[d.id] ?? null,
    }))

    res.json({ campos })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// PUT /api/v1/assets/:id/campos-extra — upsert values for a machine
router.put('/:id/campos-extra', authorize(...WRITE_ROLES), validate(Joi.object({
  valores: Joi.array().items(Joi.object({
    campo_id: Joi.string().uuid().required(),
    valor: Joi.string().allow('', null),
  })).required(),
})), async (req, res) => {
  const { valores } = req.body
  try {
    const activo = await db('core.activos').where({ id: req.params.id }).first()
    if (!activo) return res.status(404).json({ error: 'Activo no encontrado' })

    const rows = valores.map((v) => ({
      activo_id: req.params.id,
      campo_id: v.campo_id,
      valor: v.valor ?? null,
      updated_at: new Date(),
    }))

    await db('cbm.activo_campos_extra')
      .insert(rows)
      .onConflict(['activo_id', 'campo_id'])
      .merge()

    res.json({ ok: true })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
