const router = require('express').Router()
const { db } = require('../db/knex')
const { authenticate } = require('../middleware/auth')
const { calcActivoHealth, snapshotActivoHealth } = require('../services/health')

router.use(authenticate)

// GET /api/v1/health/asset/:id — live health (no DB write)
router.get('/asset/:id', async (req, res) => {
  try {
    const activo = await db('core.activos').where({ id: req.params.id }).first()
    if (!activo) return res.status(404).json({ error: 'Activo no encontrado' })

    const health = await calcActivoHealth(req.params.id)
    res.json({ activo_id: req.params.id, ...health })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// POST /api/v1/health/asset/:id/snapshot — calculate and persist
router.post('/asset/:id/snapshot', async (req, res) => {
  try {
    const result = await snapshotActivoHealth(req.params.id)
    res.json({ activo_id: req.params.id, ...result })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/health/asset/:id/history?limit=50
router.get('/asset/:id/history', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 50, 500)
  try {
    const rows = await db('cbm.health_snapshots')
      .where({ activo_id: req.params.id })
      .orderBy('time', 'desc')
      .limit(limit)
      .select('time', 'estado', 'score')
    res.json({ history: rows.reverse() })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

// GET /api/v1/health/plant/:id — health for all assets in a plant
router.get('/plant/:id', async (req, res) => {
  try {
    const activos = await db('core.activos as a')
      .join('core.sistemas as s', 'a.sistema_id', 's.id')
      .where({ 's.planta_id': req.params.id, 'a.activo': true })
      .select('a.id', 'a.tag', 'a.nombre', 'a.criticidad', 's.nombre as sistema_nombre')

    const results = await Promise.all(
      activos.map(async (a) => {
        const health = await calcActivoHealth(a.id)
        return { ...a, health }
      })
    )
    res.json({ activos: results })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: 'Error interno' })
  }
})

module.exports = router
