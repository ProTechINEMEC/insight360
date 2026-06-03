const { db } = require('../db/knex')

// Calculate health state for a single measurement point given its latest value
function calcPuntoState(valor, punto) {
  if (valor === null || valor === undefined) return 'desconocido'
  if (punto.limite_alarma !== null && Number(valor) >= Number(punto.limite_alarma)) return 'critico'
  if (punto.limite_alerta !== null && Number(valor) >= Number(punto.limite_alerta)) return 'alerta'
  return 'bueno'
}

// Score mapping: bueno=100, alerta=50, critico=0, desconocido=null (excluded)
const STATE_SCORE = { bueno: 100, alerta: 50, critico: 0 }

/**
 * Calculate current health for an activo from latest readings.
 * Returns { estado, score, detalle } without writing to DB.
 */
async function calcActivoHealth(activoId) {
  const puntos = await db('cbm.puntos_medicion')
    .where({ activo_id: activoId, activo: true })

  if (!puntos.length) {
    return { estado: 'desconocido', score: null, detalle: {} }
  }

  // Get latest reading per punto via TimescaleDB last() or subquery
  const puntosIds = puntos.map((p) => p.id)
  const latestReadings = await db('cbm.measurement_entries')
    .whereIn('punto_id', puntosIds)
    .select(
      'punto_id',
      db.raw('last(valor, time) as valor'),
      db.raw('max(time) as last_time')
    )
    .groupBy('punto_id')

  const readingMap = {}
  latestReadings.forEach((r) => { readingMap[r.punto_id] = r })

  const detalle = {}
  const scoredStates = []

  for (const punto of puntos) {
    const reading = readingMap[punto.id]
    const valor = reading ? reading.valor : null
    const estado = calcPuntoState(valor, punto)
    const lastTime = reading ? reading.last_time : null

    detalle[punto.id] = {
      codigo: punto.codigo,
      nombre: punto.nombre,
      unidad: punto.unidad,
      valor: valor !== null ? Number(valor) : null,
      last_time: lastTime,
      estado,
    }

    if (estado !== 'desconocido') {
      scoredStates.push(STATE_SCORE[estado])
    }
  }

  if (!scoredStates.length) {
    return { estado: 'desconocido', score: null, detalle }
  }

  const score = Math.round(scoredStates.reduce((a, b) => a + b, 0) / scoredStates.length)
  const estado = score >= 70 ? 'bueno' : score >= 40 ? 'alerta' : 'critico'

  return { estado, score, detalle }
}

/**
 * Calculate and persist a health snapshot for an activo.
 */
async function snapshotActivoHealth(activoId) {
  const { estado, score, detalle } = await calcActivoHealth(activoId)
  await db('cbm.health_snapshots').insert({
    time: db.fn.now(),
    activo_id: activoId,
    estado,
    score,
    detalle: JSON.stringify(detalle),
  })
  return { estado, score, detalle }
}

module.exports = { calcActivoHealth, snapshotActivoHealth, calcPuntoState }
