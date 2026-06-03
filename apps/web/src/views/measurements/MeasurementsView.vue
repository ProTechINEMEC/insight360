<template>
  <div class="measurements-view">
    <div class="page-header">
      <h3>Mediciones</h3>
    </div>

    <!-- Asset selector -->
    <div class="card filter-bar">
      <div class="filter-row">
        <select v-model="selectedPlantaId" @change="onPlantaChange">
          <option value="">Todas las plantas</option>
          <option v-for="p in plantas" :key="p.id" :value="p.id">{{ p.nombre }}</option>
        </select>
        <select v-model="selectedSistemaId" @change="onSistemaChange" :disabled="!selectedPlantaId">
          <option value="">Todos los sistemas</option>
          <option v-for="s in filteredSistemas" :key="s.id" :value="s.id">{{ s.nombre }}</option>
        </select>
        <select v-model="selectedActivoId" @change="loadPuntos" :disabled="!selectedSistemaId">
          <option value="">Seleccionar activo</option>
          <option v-for="a in filteredActivos" :key="a.id" :value="a.id">{{ a.tag }} — {{ a.nombre }}</option>
        </select>
      </div>
    </div>

    <!-- No activo selected -->
    <div v-if="!selectedActivoId" class="card empty-state">
      Selecciona una planta, sistema y activo para ver sus puntos de medición.
    </div>

    <!-- Measurement points -->
    <template v-else>
      <!-- Health banner -->
      <div v-if="health" :class="`health-banner health-${health.estado}`">
        <div class="health-left">
          <span class="health-label">Salud del Activo</span>
          <span class="health-estado">{{ ESTADO_LABELS[health.estado] }}</span>
        </div>
        <div class="health-score" v-if="health.score !== null">
          <span class="score-num">{{ health.score }}</span>
          <span class="score-unit">/100</span>
        </div>
      </div>

      <!-- Punto cards -->
      <div class="puntos-grid">
        <div
          v-for="punto in puntos"
          :key="punto.id"
          :class="['punto-card', 'card', `estado-${getPuntoEstado(punto)}`]"
          @click="openChart(punto)"
        >
          <div class="punto-top">
            <div>
              <div class="punto-code">{{ punto.codigo }}</div>
              <div class="punto-name">{{ punto.nombre }}</div>
              <div class="punto-type">{{ punto.tipo }} · {{ punto.unidad }}</div>
            </div>
            <div class="punto-value-block">
              <div v-if="punto.ultimo_valor !== null" class="punto-value">
                {{ formatVal(punto.ultimo_valor) }}
                <span class="punto-unit">{{ punto.unidad }}</span>
              </div>
              <div v-else class="punto-no-data">Sin datos</div>
              <span :class="`estado-badge estado-${getPuntoEstado(punto)}`">
                {{ ESTADO_LABELS[getPuntoEstado(punto)] || '—' }}
              </span>
            </div>
          </div>

          <div class="punto-limits" v-if="punto.limite_alarma || punto.limite_alerta">
            <span v-if="punto.limite_alerta" class="limit alerta">
              Alerta: {{ punto.limite_alerta }} {{ punto.unidad }}
            </span>
            <span v-if="punto.limite_alarma" class="limit alarma">
              Alarma: {{ punto.limite_alarma }} {{ punto.unidad }}
            </span>
          </div>

          <div class="punto-time" v-if="punto.ultimo_tiempo">
            Última: {{ formatTime(punto.ultimo_tiempo) }}
          </div>

          <button class="btn-add-reading" @click.stop="openAddReading(punto)">
            + Registrar Lectura
          </button>
        </div>

        <!-- Add new punto card -->
        <div
          v-if="canWrite"
          class="punto-card card add-punto-card"
          @click="showAddPunto = true"
        >
          <div class="add-icon">+</div>
          <div class="add-label">Agregar Punto de Medición</div>
        </div>
      </div>
    </template>

    <!-- Trend chart modal -->
    <Teleport to="body">
      <div v-if="chartPunto" class="modal-overlay" @click.self="chartPunto = null">
        <div class="modal modal-xl">
          <div class="modal-header">
            <div>
              <h4>{{ chartPunto.nombre }}</h4>
              <span class="modal-sub">{{ chartPunto.codigo }} · {{ chartPunto.tipo }} · {{ chartPunto.unidad }}</span>
            </div>
            <button class="modal-close" @click="chartPunto = null">✕</button>
          </div>
          <div class="modal-body">
            <TrendChart :punto="chartPunto" />
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Add reading modal -->
    <Teleport to="body">
      <div v-if="addReadingPunto" class="modal-overlay" @click.self="addReadingPunto = null">
        <div class="modal">
          <div class="modal-header">
            <h4>Registrar Lectura — {{ addReadingPunto.nombre }}</h4>
            <button class="modal-close" @click="addReadingPunto = null">✕</button>
          </div>
          <form @submit.prevent="submitReading" class="modal-body">
            <div class="field">
              <label>Valor ({{ addReadingPunto.unidad }}) *</label>
              <input
                v-model.number="newReading.valor"
                type="number"
                step="any"
                :placeholder="`en ${addReadingPunto.unidad}`"
                required
                autofocus
              />
              <div v-if="newReading.valor !== null && addReadingPunto.limite_alarma" class="reading-preview">
                <span :class="`estado-badge estado-${calcEstado(newReading.valor, addReadingPunto)}`">
                  {{ ESTADO_LABELS[calcEstado(newReading.valor, addReadingPunto)] }}
                </span>
              </div>
            </div>
            <div class="field">
              <label>Fecha y hora</label>
              <input v-model="newReading.time" type="datetime-local" />
            </div>
            <div class="field">
              <label>Notas</label>
              <textarea v-model="newReading.notas" rows="2" placeholder="Observaciones opcionales"></textarea>
            </div>
            <div v-if="readingError" class="error-alert">{{ readingError }}</div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" @click="addReadingPunto = null">Cancelar</button>
              <button type="submit" class="btn btn-primary" :disabled="submittingReading">
                {{ submittingReading ? 'Guardando...' : 'Guardar Lectura' }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>

    <!-- Add punto modal -->
    <Teleport to="body">
      <div v-if="showAddPunto" class="modal-overlay" @click.self="showAddPunto = false">
        <div class="modal">
          <div class="modal-header">
            <h4>Nuevo Punto de Medición</h4>
            <button class="modal-close" @click="showAddPunto = false">✕</button>
          </div>
          <form @submit.prevent="submitAddPunto" class="modal-body">
            <div class="form-grid">
              <div class="field">
                <label>Código *</label>
                <input v-model="newPunto.codigo" type="text" placeholder="VIB-001" required />
              </div>
              <div class="field">
                <label>Tipo *</label>
                <select v-model="newPunto.tipo" required>
                  <option v-for="t in TIPOS" :key="t" :value="t">{{ t }}</option>
                </select>
              </div>
              <div class="field field-full">
                <label>Nombre *</label>
                <input v-model="newPunto.nombre" type="text" placeholder="Vibración Rodamiento DE" required />
              </div>
              <div class="field">
                <label>Unidad *</label>
                <input v-model="newPunto.unidad" type="text" placeholder="mm/s" required />
              </div>
              <div class="field">
                <label>Límite Alerta</label>
                <input v-model.number="newPunto.limite_alerta" type="number" step="any" placeholder="Ej: 4.5" />
              </div>
              <div class="field">
                <label>Límite Alarma</label>
                <input v-model.number="newPunto.limite_alarma" type="number" step="any" placeholder="Ej: 7.1" />
              </div>
              <div class="field field-full">
                <label>Descripción</label>
                <textarea v-model="newPunto.descripcion" rows="2"></textarea>
              </div>
            </div>
            <div v-if="puntoError" class="error-alert">{{ puntoError }}</div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" @click="showAddPunto = false">Cancelar</button>
              <button type="submit" class="btn btn-primary" :disabled="submittingPunto">
                {{ submittingPunto ? 'Guardando...' : 'Crear Punto' }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, computed, reactive, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/services/api'
import TrendChart from '@/components/TrendChart.vue'

const auth = useAuthStore()

const ESTADO_LABELS = { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: 'Sin datos' }
const TIPOS = ['vibracion', 'temperatura', 'presion', 'caudal', 'corriente', 'voltaje', 'rpm', 'nivel', 'otro']

const plantas = ref([])
const sistemas = ref([])
const activos = ref([])
const puntos = ref([])
const health = ref(null)

const selectedPlantaId = ref('')
const selectedSistemaId = ref('')
const selectedActivoId = ref('')

const chartPunto = ref(null)
const addReadingPunto = ref(null)
const showAddPunto = ref(false)

const newReading = reactive({ valor: null, time: '', notas: '' })
const submittingReading = ref(false)
const readingError = ref('')

const newPunto = reactive({ codigo: '', nombre: '', tipo: 'vibracion', unidad: '', limite_alerta: null, limite_alarma: null, descripcion: '' })
const submittingPunto = ref(false)
const puntoError = ref('')

const canWrite = computed(() => ['admin', 'ingeniero_confiabilidad', 'supervisor'].includes(auth.user?.role))

const filteredSistemas = computed(() =>
  sistemas.value.filter((s) => !selectedPlantaId.value || s.planta_id === selectedPlantaId.value)
)
const filteredActivos = computed(() =>
  activos.value.filter((a) => !selectedSistemaId.value || a.sistema_id === selectedSistemaId.value)
)

function getPuntoEstado(punto) {
  if (punto.ultimo_valor === null) return 'desconocido'
  return calcEstado(punto.ultimo_valor, punto)
}

function calcEstado(valor, punto) {
  if (valor === null || valor === undefined) return 'desconocido'
  if (punto.limite_alarma !== null && Number(valor) >= Number(punto.limite_alarma)) return 'critico'
  if (punto.limite_alerta !== null && Number(valor) >= Number(punto.limite_alerta)) return 'alerta'
  return 'bueno'
}

function formatVal(v) {
  if (v === null || v === undefined) return '—'
  return Number(v) % 1 === 0 ? v : Number(v).toFixed(3)
}

function formatTime(t) {
  if (!t) return ''
  return new Date(t).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })
}

function onPlantaChange() {
  selectedSistemaId.value = ''
  selectedActivoId.value = ''
  puntos.value = []
  health.value = null
}

function onSistemaChange() {
  selectedActivoId.value = ''
  puntos.value = []
  health.value = null
}

async function loadPuntos() {
  if (!selectedActivoId.value) return
  puntos.value = []
  health.value = null
  const [pRes, hRes] = await Promise.allSettled([
    api.get('/measurements/latest', { params: { activo_id: selectedActivoId.value } }),
    api.get(`/health/asset/${selectedActivoId.value}`),
  ])
  if (pRes.status === 'fulfilled') puntos.value = pRes.value.data.puntos
  if (hRes.status === 'fulfilled') health.value = hRes.value.data
}

function openChart(punto) { chartPunto.value = punto }

function openAddReading(punto) {
  addReadingPunto.value = punto
  newReading.valor = null
  newReading.time = ''
  newReading.notas = ''
  readingError.value = ''
}

async function submitReading() {
  submittingReading.value = true
  readingError.value = ''
  try {
    const payload = { punto_id: addReadingPunto.value.id, valor: newReading.valor }
    if (newReading.time) payload.time = new Date(newReading.time).toISOString()
    if (newReading.notas) payload.notas = newReading.notas
    await api.post('/measurements/readings', payload)
    addReadingPunto.value = null
    await loadPuntos()
  } catch (err) {
    readingError.value = err.response?.data?.error || 'Error al guardar'
  } finally {
    submittingReading.value = false
  }
}

async function submitAddPunto() {
  submittingPunto.value = true
  puntoError.value = ''
  try {
    await api.post('/measurements/puntos', { ...newPunto, activo_id: selectedActivoId.value })
    showAddPunto.value = false
    Object.assign(newPunto, { codigo: '', nombre: '', tipo: 'vibracion', unidad: '', limite_alerta: null, limite_alarma: null, descripcion: '' })
    await loadPuntos()
  } catch (err) {
    puntoError.value = err.response?.data?.error || 'Error al crear punto'
  } finally {
    submittingPunto.value = false
  }
}

onMounted(async () => {
  const [pRes, sRes, aRes] = await Promise.all([
    api.get('/assets/plantas'),
    api.get('/assets/sistemas'),
    api.get('/assets'),
  ])
  plantas.value = pRes.data.plantas
  sistemas.value = sRes.data.sistemas
  activos.value = aRes.data.activos
})
</script>

<style scoped>
.measurements-view { display: flex; flex-direction: column; gap: 1rem; }

.filter-bar { padding: 0.875rem 1.5rem; }
.filter-row { display: flex; gap: 0.75rem; flex-wrap: wrap; }
.filter-row select { padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.875rem; background: #fff; min-width: 200px; }

.empty-state { text-align: center; color: var(--color-text-muted); padding: 3rem; }

/* Health banner */
.health-banner {
  display: flex; align-items: center; justify-content: space-between;
  padding: 1rem 1.5rem; border-radius: 12px; border-left: 4px solid;
}
.health-bueno { background: #f0fdf4; border-color: #16a34a; }
.health-alerta { background: #fffbeb; border-color: #d97706; }
.health-critico { background: #fef2f2; border-color: #dc2626; }
.health-desconocido { background: var(--color-bg); border-color: var(--color-border); }

.health-label { font-size: 0.75rem; color: var(--color-text-muted); display: block; }
.health-estado { font-size: 1rem; font-weight: 700; }
.health-score { text-align: right; }
.score-num { font-size: 2.5rem; font-weight: 800; line-height: 1; }
.score-unit { font-size: 0.875rem; color: var(--color-text-muted); }

/* Puntos grid */
.puntos-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1rem;
}

.punto-card {
  cursor: pointer;
  transition: box-shadow 0.15s, transform 0.1s;
  border-left: 4px solid var(--color-border);
}
.punto-card:hover { box-shadow: 0 4px 16px rgba(0,0,0,0.1); transform: translateY(-1px); }

.estado-bueno { border-left-color: #16a34a; }
.estado-alerta { border-left-color: #d97706; }
.estado-critico { border-left-color: #dc2626; }
.estado-desconocido { border-left-color: var(--color-border); }

.punto-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.75rem; }
.punto-code { font-size: 0.7rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.06em; }
.punto-name { font-weight: 600; font-size: 0.9375rem; }
.punto-type { font-size: 0.75rem; color: var(--color-text-muted); margin-top: 0.125rem; }

.punto-value-block { text-align: right; }
.punto-value { font-size: 1.5rem; font-weight: 700; line-height: 1; }
.punto-unit { font-size: 0.75rem; color: var(--color-text-muted); font-weight: 400; }
.punto-no-data { font-size: 0.875rem; color: var(--color-text-muted); }

.estado-badge {
  display: inline-block; padding: 2px 8px; border-radius: 999px;
  font-size: 0.7rem; font-weight: 600; text-transform: uppercase; margin-top: 0.25rem;
}
.estado-badge.estado-bueno { background: #f0fdf4; color: #16a34a; }
.estado-badge.estado-alerta { background: #fffbeb; color: #d97706; }
.estado-badge.estado-critico { background: #fef2f2; color: #dc2626; }
.estado-badge.estado-desconocido { background: var(--color-bg); color: var(--color-text-muted); }

.punto-limits { display: flex; gap: 0.5rem; margin-bottom: 0.5rem; flex-wrap: wrap; }
.limit { font-size: 0.7rem; padding: 2px 6px; border-radius: 4px; }
.limit.alerta { background: #fffbeb; color: #d97706; }
.limit.alarma { background: #fef2f2; color: #dc2626; }

.punto-time { font-size: 0.75rem; color: var(--color-text-muted); margin-bottom: 0.75rem; }

.btn-add-reading {
  width: 100%; padding: 0.5rem; background: none;
  border: 1px dashed var(--color-border); border-radius: 6px;
  font-size: 0.8125rem; color: var(--color-text-muted); cursor: pointer;
  transition: all 0.15s;
}
.btn-add-reading:hover { border-color: var(--color-brand); color: var(--color-brand); background: var(--color-brand-light); }

/* Add punto card */
.add-punto-card {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  min-height: 160px; border: 2px dashed var(--color-border); background: transparent;
}
.add-icon { font-size: 2rem; color: var(--color-text-muted); line-height: 1; }
.add-label { font-size: 0.875rem; color: var(--color-text-muted); margin-top: 0.5rem; }
.add-punto-card:hover { border-color: var(--color-brand); }
.add-punto-card:hover .add-icon, .add-punto-card:hover .add-label { color: var(--color-brand); }

/* Modals */
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 1000; padding: 1rem; }
.modal { background: #fff; border-radius: 12px; width: 100%; max-width: 520px; max-height: 90vh; overflow-y: auto; box-shadow: 0 20px 60px rgba(0,0,0,0.2); }
.modal-xl { max-width: 860px; }
.modal-header { display: flex; align-items: flex-start; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-border); }
.modal-header h4 { font-size: 1rem; font-weight: 700; margin: 0; }
.modal-sub { font-size: 0.75rem; color: var(--color-text-muted); }
.modal-close { background: none; border: none; cursor: pointer; font-size: 1rem; color: var(--color-text-muted); margin-left: 1rem; flex-shrink: 0; }
.modal-body { padding: 1.5rem; }
.modal-footer { display: flex; gap: 0.75rem; justify-content: flex-end; margin-top: 1.25rem; }

.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.field-full { grid-column: 1 / -1; }
.field label { display: block; font-size: 0.8rem; font-weight: 500; color: var(--color-text-secondary); margin-bottom: 0.25rem; }
.field input, .field select, .field textarea { width: 100%; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.875rem; font-family: inherit; }
.reading-preview { margin-top: 0.5rem; }
.error-alert { background: #fef2f2; border: 1px solid #fecaca; color: #dc2626; padding: 0.5rem 0.75rem; border-radius: 6px; font-size: 0.8125rem; margin-top: 0.75rem; }
</style>
