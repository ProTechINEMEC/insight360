<template>
  <div class="salud-view">
    <!-- Filters bar -->
    <div class="filters-bar card">
      <div class="filters-row">
        <!-- Row 1: cascading location + search -->
        <div class="filters-group">
          <select v-model="filtroContrato" class="filter-select" @change="filtroPlanta = ''; filtroSistema = ''">
            <option value="">Todos los contratos</option>
            <option v-for="ct in contratos" :key="ct.id" :value="ct.id">{{ ct.nombre }}</option>
          </select>
          <select v-model="filtroPlanta" class="filter-select" :disabled="!filtroContrato" @change="filtroSistema = ''">
            <option value="">Todas las plantas</option>
            <option v-for="p in plantasFiltradas" :key="p.id" :value="p.id">{{ p.nombre }}</option>
          </select>
          <select v-model="filtroSistema" class="filter-select" :disabled="!filtroPlanta">
            <option value="">Todos los sistemas</option>
            <option v-for="s in sistemasFiltrados" :key="s.id" :value="s.id">{{ s.nombre }}</option>
          </select>
          <div class="search-wrap">
            <input v-model="searchTag" type="text" placeholder="Buscar TAG o nombre..." class="filter-input" />
            <button v-if="searchTag" class="search-clear" @click="searchTag = ''">✕</button>
          </div>
        </div>

        <!-- Row 2: criticidad chips + estado op + legend + refresh -->
        <div class="filters-group filters-group-bottom">
          <div class="filter-label-group">
            <span class="filter-label">Criticidad:</span>
            <div class="chip-group">
              <button
                v-for="c in CRITICIDADES"
                :key="c.value"
                :class="['chip', `chip-${c.value}`, { active: filtroCrit.includes(c.value) }]"
                @click="toggleCrit(c.value)"
              >{{ c.label }}</button>
            </div>
          </div>
          <select v-model="filtroEstado" class="filter-select">
            <option value="">Todos los estados</option>
            <option v-for="e in ESTADOS_OP" :key="e.value" :value="e.value">{{ e.label }}</option>
          </select>
          <div class="legend">
            <span class="legend-item"><span class="cond-dot cond-normal"></span>Normal</span>
            <span class="legend-item"><span class="cond-dot cond-observacion"></span>Observación</span>
            <span class="legend-item"><span class="cond-dot cond-alerta"></span>Alerta</span>
            <span class="legend-item"><span class="cond-dot cond-urgencia"></span>Urgencia</span>
          </div>
          <button class="btn btn-primary btn-sm" @click="loadMatrix">Actualizar</button>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="loading-box card"><div class="spinner"></div> Cargando matriz...</div>

    <!-- Empty -->
    <div v-else-if="!filteredRows.length" class="empty-box card">
      Sin equipos para los filtros seleccionados
    </div>

    <!-- Matrix table -->
    <div v-else class="matrix-wrap card">
      <div class="matrix-scroll">
        <table class="matrix-table">
          <thead>
            <tr>
              <th class="col-contrato">Contrato</th>
              <th class="col-planta">Planta</th>
              <th class="col-sistema">Sistema</th>
              <th class="col-tag">TAG</th>
              <th class="col-nombre">Equipo</th>
              <th class="col-crit">Crit.</th>
              <th class="col-estado">Estado</th>
              <th
                v-for="t in tecnicas"
                :key="t.codigo"
                class="col-tecnica"
                :title="t.nombre + (t.norma_referencia ? ' — ' + t.norma_referencia : '')"
              >{{ t.codigo }}</th>
              <th class="col-peor">Peor</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in filteredRows"
              :key="row.activo_id"
              class="matrix-row"
              @click="goToActivo(row.activo_id)"
            >
              <td class="col-contrato">{{ row.contrato_nombre }}</td>
              <td class="col-planta">{{ row.planta_nombre }}</td>
              <td class="col-sistema">{{ row.sistema_nombre }}</td>
              <td class="col-tag"><span class="tag-mono">{{ row.tag }}</span></td>
              <td class="col-nombre">{{ row.nombre }}</td>
              <td class="col-crit">
                <span class="crit-plain">{{ row.criticidad[0].toUpperCase() }}</span>
              </td>
              <td class="col-estado">
                <span v-if="row.estado_op_actual" :class="`estado-op estado-op-${row.estado_op_actual}`">{{ ESTADO_OP_SHORT[row.estado_op_actual] }}</span>
                <span v-else class="no-data">—</span>
              </td>
              <td
                v-for="t in tecnicas"
                :key="t.codigo"
                class="col-tecnica"
                :title="cellTitle(row, t)"
              >
                <span
                  v-if="row.condiciones[t.codigo]"
                  :class="`cond-cell cond-${row.condiciones[t.codigo]}`"
                >{{ COND_SHORT[row.condiciones[t.codigo]] }}</span>
                <span v-else-if="row.aplica && row.aplica[t.codigo] === false" class="cond-cell cond-na" title="">N/A</span>
                <span v-else class="cond-cell cond-empty">—</span>
              </td>
              <td class="col-peor">
                <span
                  v-if="worstCondicion(row)"
                  :class="`cond-badge cond-badge-${worstCondicion(row)}`"
                >{{ COND_LABELS[worstCondicion(row)] }}</span>
                <span v-else class="no-data">Sin datos</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="matrix-footer">
        {{ filteredRows.length }} equipo{{ filteredRows.length !== 1 ? 's' : '' }}
        · {{ tecnicas.length }} técnicas
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/services/api'

const router = useRouter()

const COND_ORDER = ['urgencia', 'alerta', 'observacion', 'normal']
const COND_LABELS = { normal: 'Normal', observacion: 'Observación', alerta: 'Alerta', urgencia: 'Urgencia' }
const COND_SHORT  = { normal: 'N', observacion: 'O', alerta: 'A', urgencia: 'U' }

const CRITICIDADES = [
  { value: 'critico', label: 'C' },
  { value: 'esencial', label: 'E' },
  { value: 'general', label: 'G' },
]
const ESTADOS_OP = [
  { value: 'operativo',          label: 'Operativo' },
  { value: 'operativo_limitado', label: 'Op. Limitado' },
  { value: 'stand_by',           label: 'Stand By' },
  { value: 'fuera_de_servicio',  label: 'Fuera de Servicio' },
  { value: 'dado_de_baja',       label: 'Dado de Baja' },
]
const ESTADO_OP_SHORT = {
  operativo:          'OPER',
  operativo_limitado: 'LIM',
  stand_by:           'SB',
  fuera_de_servicio:  'FDS',
  dado_de_baja:       'BAJA',
}

const loading = ref(false)
const contratos = ref([])
const tecnicas = ref([])
const rows = ref([])
const filtroContrato = ref('')
const filtroPlanta = ref('')
const filtroSistema = ref('')
const filtroCrit = ref([])
const filtroEstado = ref('')
const searchTag = ref('')

const plantasFiltradas = computed(() => {
  if (!filtroContrato.value) return []
  const seen = new Set()
  return rows.value
    .filter((r) => r.contrato_id === filtroContrato.value)
    .reduce((acc, r) => {
      if (!seen.has(r.planta_id)) { seen.add(r.planta_id); acc.push({ id: r.planta_id, nombre: r.planta_nombre }) }
      return acc
    }, [])
})

const sistemasFiltrados = computed(() => {
  if (!filtroPlanta.value) return []
  const seen = new Set()
  return rows.value
    .filter((r) => r.planta_id === filtroPlanta.value)
    .reduce((acc, r) => {
      if (!seen.has(r.sistema_id)) { seen.add(r.sistema_id); acc.push({ id: r.sistema_id, nombre: r.sistema_nombre }) }
      return acc
    }, [])
})

function toggleCrit(val) {
  const idx = filtroCrit.value.indexOf(val)
  if (idx === -1) filtroCrit.value.push(val)
  else filtroCrit.value.splice(idx, 1)
}

const filteredRows = computed(() => {
  return rows.value.filter((r) => {
    if (filtroContrato.value && r.contrato_id !== filtroContrato.value) return false
    if (filtroPlanta.value && r.planta_id !== filtroPlanta.value) return false
    if (filtroSistema.value && r.sistema_id !== filtroSistema.value) return false
    if (filtroCrit.value.length && !filtroCrit.value.includes(r.criticidad)) return false
    if (filtroEstado.value && r.estado_op_actual !== filtroEstado.value) return false
    if (searchTag.value) {
      const q = searchTag.value.toLowerCase()
      return r.tag.toLowerCase().includes(q) || r.nombre.toLowerCase().includes(q)
    }
    return true
  })
})

function worstCondicion(row) {
  const found = COND_ORDER.find((c) => Object.values(row.condiciones).includes(c))
  return found || null
}

function cellTitle(row, t) {
  if (row.condiciones[t.codigo]) return `${t.nombre}: ${COND_LABELS[row.condiciones[t.codigo]]}`
  if (row.aplica && row.aplica[t.codigo] === false) return `${t.nombre}: No aplica a este equipo`
  if (row.aplica && row.aplica[t.codigo] === true) return `${t.nombre}: Sin datos`
  return `${t.nombre}: Sin componentes registrados`
}

function goToActivo(id) {
  router.push(`/activos/${id}`)
}

async function loadContratos() {
  try {
    const { data } = await api.get('/assets/contratos')
    contratos.value = data.contratos
  } catch (err) {
    console.error(err)
  }
}

async function loadMatrix() {
  loading.value = true
  try {
    const params = {}
    // Always load full matrix (filter client-side) — no server param
    const { data } = await api.get('/inspections/salud-matriz', { params })
    tecnicas.value = data.tecnicas
    rows.value = data.rows
  } catch (err) {
    console.error(err)
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await Promise.all([loadContratos(), loadMatrix()])
})
</script>

<style scoped>
.salud-view { display: flex; flex-direction: column; gap: 1rem; }

/* Filters bar */
.filters-bar { padding: 0.875rem 1.25rem; flex-shrink: 0; }
.filters-row { display: flex; flex-direction: column; gap: 0.625rem; }
.filters-group { display: flex; align-items: center; gap: 0.625rem; flex-wrap: wrap; }
.filters-group-bottom { padding-top: 0.5rem; border-top: 1px solid var(--color-border); }

.filter-select, .filter-input {
  padding: 0.4rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px;
  font-size: 0.8125rem; background: #fff; font-family: inherit;
}
.filter-select:focus, .filter-input:focus { outline: none; border-color: var(--color-brand); }
.filter-select:disabled { background: var(--color-bg); color: var(--color-text-muted); }
.filter-select { min-width: 150px; }
.filter-input { min-width: 190px; }
.search-wrap { position: relative; display: flex; align-items: center; }
.search-clear { position: absolute; right: 0.4rem; background: none; border: none; cursor: pointer; color: var(--color-text-muted); font-size: 0.8rem; }

/* Criticidad chips */
.filter-label-group { display: flex; align-items: center; gap: 0.5rem; }
.filter-label { font-size: 0.75rem; color: var(--color-text-muted); white-space: nowrap; }
.chip-group { display: flex; gap: 0.25rem; }
.chip {
  padding: 2px 10px; border-radius: 999px; border: 1px solid var(--color-border);
  background: #fff; font-size: 0.75rem; font-weight: 600; cursor: pointer;
  color: var(--color-text-secondary); transition: all 0.12s;
}
.chip.active.chip-critico  { background: #fef2f2; border-color: #dc2626; color: #dc2626; }
.chip.active.chip-esencial { background: #fffbeb; border-color: #d97706; color: #d97706; }
.chip.active.chip-general  { background: #f0fdf4; border-color: #16a34a; color: #16a34a; }
.chip:not(.active):hover { background: var(--color-bg); }

/* Legend */
.legend { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; margin-left: auto; }
.legend-item { display: flex; align-items: center; gap: 0.35rem; font-size: 0.72rem; color: var(--color-text-secondary); }
.cond-dot { width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0; }
.cond-dot.cond-normal { background: #16a34a; }
.cond-dot.cond-observacion { background: #2563eb; }
.cond-dot.cond-alerta { background: #d97706; }
.cond-dot.cond-urgencia { background: #dc2626; }

.btn-sm { padding: 0.35rem 0.875rem; font-size: 0.8125rem; }

/* Loading / empty */
.loading-box { display: flex; align-items: center; justify-content: center; gap: 0.75rem; padding: 3rem; color: var(--color-text-muted); }
.empty-box { display: flex; align-items: center; justify-content: center; padding: 3rem; color: var(--color-text-muted); font-size: 0.9375rem; }

/* Matrix */
.matrix-wrap { padding: 0; overflow: hidden; }
.matrix-scroll { overflow-x: auto; max-height: calc(100vh - 290px); overflow-y: auto; }
.matrix-footer { padding: 0.5rem 1rem; font-size: 0.75rem; color: var(--color-text-muted); border-top: 1px solid var(--color-border); }

.matrix-table {
  border-collapse: collapse;
  width: 100%;
  font-size: 0.8rem;
  white-space: nowrap;
}
.matrix-table thead {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--color-sidebar);
}
.matrix-table th {
  padding: 0.5rem 0.625rem;
  text-align: left;
  font-size: 0.7rem;
  font-weight: 600;
  color: rgba(255,255,255,0.8);
  border-right: 1px solid rgba(255,255,255,0.08);
}
.matrix-table th.col-tecnica {
  text-align: center;
  min-width: 52px;
  max-width: 52px;
  font-size: 0.65rem;
  letter-spacing: 0.02em;
}
.matrix-table td {
  padding: 0.4rem 0.625rem;
  border-bottom: 1px solid var(--color-border);
  border-right: 1px solid var(--color-border);
  vertical-align: middle;
}
.matrix-row { cursor: pointer; transition: background 0.1s; }
.matrix-row:hover { background: var(--color-bg); }

.col-contrato { min-width: 80px; font-weight: 600; font-size: 0.75rem; }
.col-planta { min-width: 130px; font-size: 0.75rem; }
.col-sistema { min-width: 160px; font-size: 0.75rem; color: var(--color-text-secondary); }
.col-tag { min-width: 90px; }
.col-nombre { min-width: 200px; }
.col-crit { width: 40px; text-align: center; }
.col-estado { min-width: 80px; }
.col-tecnica { width: 52px; text-align: center; }
.col-peor { min-width: 100px; }

/* Estado operacional badge in matrix */
.estado-op {
  display: inline-block; padding: 1px 6px; border-radius: 4px;
  font-size: 0.65rem; font-weight: 700; letter-spacing: 0.03em;
}
.estado-op-operativo          { background: #dcfce7; color: #15803d; }
.estado-op-operativo_limitado { background: #fef3c7; color: #b45309; }
.estado-op-stand_by           { background: #dbeafe; color: #1d4ed8; }
.estado-op-fuera_de_servicio  { background: #fee2e2; color: #b91c1c; }
.estado-op-dado_de_baja       { background: #f3f4f6; color: #6b7280; }

.tag-mono { font-family: monospace; font-weight: 700; font-size: 0.8125rem; }

/* Criticidad — plain, no color */
.crit-plain { font-size: 0.7rem; font-weight: 700; color: var(--color-text-muted); }

/* Condition cells */
.cond-cell {
  display: inline-flex; align-items: center; justify-content: center;
  width: 28px; height: 22px; border-radius: 4px;
  font-size: 0.7rem; font-weight: 700;
}
.cond-cell.cond-normal { background: #dcfce7; color: #15803d; }
.cond-cell.cond-observacion { background: #dbeafe; color: #1d4ed8; }
.cond-cell.cond-alerta { background: #fef3c7; color: #b45309; }
.cond-cell.cond-urgencia { background: #fee2e2; color: #b91c1c; }
.cond-cell.cond-empty { background: none; color: var(--color-text-muted); }
.cond-cell.cond-na { background: #f3f4f6; color: #9ca3af; font-size: 0.6rem; letter-spacing: 0.02em; }

/* Overall condition badge */
.cond-badge {
  display: inline-block; padding: 2px 8px; border-radius: 999px;
  font-size: 0.68rem; font-weight: 700; text-transform: uppercase;
}
.cond-badge-normal { background: #dcfce7; color: #15803d; }
.cond-badge-observacion { background: #dbeafe; color: #1d4ed8; }
.cond-badge-alerta { background: #fef3c7; color: #b45309; }
.cond-badge-urgencia { background: #fee2e2; color: #b91c1c; }

.no-data { color: var(--color-text-muted); font-size: 0.75rem; }
</style>
