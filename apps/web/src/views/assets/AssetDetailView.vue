<template>
  <div class="asset-detail" v-if="asset">
    <!-- Header -->
    <div class="detail-header">
      <div>
        <div class="breadcrumb">
          <RouterLink to="/activos/arbol">Árbol de Equipos</RouterLink>
          <span>/</span>
          <span>{{ asset.tag }}</span>
        </div>
        <div class="detail-title-row">
          <h3>{{ asset.nombre }}</h3>
          <span :class="`badge badge-${asset.criticidad}`">{{ asset.criticidad }}</span>
        </div>
        <p class="asset-meta">{{ asset.planta_nombre }} &rsaquo; {{ asset.sistema_nombre }}</p>
      </div>
      <button v-if="canWrite" class="btn btn-secondary btn-sm" @click="editOpen = true">Editar</button>
    </div>

    <!-- Tabs -->
    <div class="tabs">
      <button v-for="t in tabs" :key="t.key" :class="['tab', { active: activeTab === t.key }]" @click="activeTab = t.key">
        {{ t.label }}
        <span v-if="t.key === 'mediciones' && puntos.length" class="tab-count">{{ puntos.length }}</span>
        <span v-if="t.key === 'componentes' && componentes.length" class="tab-count">{{ componentes.length }}</span>
      </button>
    </div>

    <!-- Info tab -->
    <div v-if="activeTab === 'info'" class="card">
      <div class="info-grid">
        <div class="info-item"><div class="info-label">Tag</div><div class="info-value">{{ asset.tag }}</div></div>
        <div class="info-item"><div class="info-label">Código SAP</div><div class="info-value">{{ asset.codigo_sap || '—' }}</div></div>
        <div class="info-item"><div class="info-label">Fabricante</div><div class="info-value">{{ asset.fabricante || '—' }}</div></div>
        <div class="info-item"><div class="info-label">Modelo</div><div class="info-value">{{ asset.modelo || '—' }}</div></div>
        <div class="info-item"><div class="info-label">N° Serie</div><div class="info-value">{{ asset.numero_serie || '—' }}</div></div>
        <div class="info-item"><div class="info-label">Fecha Instalación</div><div class="info-value">{{ formatDate(asset.fecha_instalacion) }}</div></div>
        <div class="info-item field-full"><div class="info-label">Descripción</div><div class="info-value">{{ asset.descripcion || '—' }}</div></div>
      </div>
    </div>

    <!-- Measurements tab -->
    <div v-if="activeTab === 'mediciones'" class="mediciones-tab">
      <!-- Selected punto chart -->
      <div v-if="selectedPunto" class="card">
        <div class="chart-header">
          <div>
            <span class="punto-code">{{ selectedPunto.codigo }}</span>
            <span class="punto-name">{{ selectedPunto.nombre }}</span>
          </div>
          <button class="btn btn-secondary btn-sm" @click="selectedPunto = null">← Todos</button>
        </div>
        <TrendChart :punto="selectedPunto" />
      </div>

      <!-- Punto cards grid -->
      <div v-else>
        <div v-if="!puntos.length" class="card empty-state">
          Este activo no tiene puntos de medición configurados.
          <RouterLink to="/mediciones">Ir a Mediciones</RouterLink> para agregarlos.
        </div>
        <div v-else class="puntos-mini-grid">
          <div
            v-for="p in puntosWithHealth"
            :key="p.id"
            :class="['mini-punto', `estado-${p.estado}`]"
            @click="selectedPunto = p"
          >
            <div class="mini-top">
              <span class="mini-code">{{ p.codigo }}</span>
              <span :class="`estado-badge estado-${p.estado}`">{{ ESTADO_LABELS[p.estado] }}</span>
            </div>
            <div class="mini-name">{{ p.nombre }}</div>
            <div class="mini-value" v-if="p.ultimo_valor !== null">
              {{ fmtVal(p.ultimo_valor) }} <span class="mini-unit">{{ p.unidad }}</span>
            </div>
            <div class="mini-value mini-nodata" v-else>Sin datos</div>
            <div class="mini-time" v-if="p.ultimo_tiempo">{{ formatTime(p.ultimo_tiempo) }}</div>
          </div>
        </div>
      </div>
    </div>
    <!-- Componentes tab -->
    <div v-if="activeTab === 'componentes'" class="componentes-tab">
      <div class="comp-toolbar">
        <button v-if="canWrite" class="btn btn-primary btn-sm" @click="compFormOpen = true">+ Agregar Componente</button>
      </div>

      <div v-if="!componentes.length" class="card empty-state">Sin componentes registrados para este activo.</div>

      <div v-else class="comp-list card">
        <div v-for="c in componentes" :key="c.id" class="comp-row">
          <div class="comp-left">
            <span class="comp-tag">{{ c.tag || c.codigo_cmms || '—' }}</span>
            <span class="comp-name">{{ c.nombre }}</span>
            <span class="comp-tipo">{{ c.tipo_nombre }}</span>
          </div>
          <div class="comp-right">
            <span :class="`op-badge op-${c.estado_operacional}`">{{ ESTADO_OP_LABELS[c.estado_operacional] || c.estado_operacional }}</span>
          </div>
        </div>
      </div>

      <!-- Add componente inline form -->
      <div v-if="compFormOpen" class="card comp-form">
        <div class="comp-form-title">Nuevo Componente</div>
        <div class="field-row">
          <div class="field">
            <label class="field-label">Tipo <span class="req">*</span></label>
            <select v-model="compForm.tipo_componente_id" class="input">
              <option value="">Seleccionar tipo...</option>
              <option v-for="t in tiposComponente" :key="t.id" :value="t.id">{{ t.nombre }}</option>
            </select>
          </div>
          <div class="field field-wide">
            <label class="field-label">Nombre <span class="req">*</span></label>
            <input v-model="compForm.nombre" class="input" placeholder="Ej: Motor de la Bomba P-401A" />
          </div>
        </div>
        <div class="field-row">
          <div class="field">
            <label class="field-label">Código CMMS / SAP PM</label>
            <input v-model="compForm.cmms_id" class="input mono" placeholder="Ubicación funcional SAP" />
          </div>
        </div>
        <div class="field">
          <label class="field-label">Descripción</label>
          <input v-model="compForm.descripcion" class="input" placeholder="Descripción breve..." />
        </div>
        <div v-if="compError" class="field-error">{{ compError }}</div>
        <div class="comp-form-actions">
          <button class="btn btn-secondary btn-sm" @click="compFormOpen = false; compError = ''">Cancelar</button>
          <button class="btn btn-primary btn-sm" :disabled="compSaving" @click="submitComponente">
            {{ compSaving ? 'Guardando...' : 'Agregar' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Archivos tab -->
    <div v-if="activeTab === 'archivos'" class="archivos-tab">
      <div class="archivos-toolbar">
        <div class="upload-group" v-if="canWrite">
          <label class="upload-label">
            <input type="file" multiple data-tipo="manual" @change="handleArchivoUpload" :disabled="uploadingFile" />
            <span>{{ uploadingFile ? 'Subiendo…' : '+ Manual / Plano' }}</span>
          </label>
          <label class="upload-label">
            <input type="file" accept="image/*" multiple data-tipo="foto" @change="handleArchivoUpload" :disabled="uploadingFile" />
            <span>+ Foto</span>
          </label>
          <label class="upload-label">
            <input type="file" multiple data-tipo="otro" @change="handleArchivoUpload" :disabled="uploadingFile" />
            <span>+ Otro</span>
          </label>
        </div>
      </div>

      <div v-if="!archivos.length" class="card empty-state">No hay archivos adjuntos para este activo.</div>
      <div v-else class="card">
        <div v-for="a in archivos" :key="a.id" class="archivo-row">
          <div class="archivo-icon">
            <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M4 3h8l4 4v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M12 3v4h4"/></svg>
          </div>
          <div class="archivo-info">
            <span class="archivo-nombre">{{ a.nombre_original }}</span>
            <span class="archivo-meta">{{ a.tipo }} · {{ formatBytes(a.size_bytes) }} · {{ formatDate(a.created_at) }}</span>
            <span class="archivo-desc" v-if="a.descripcion">{{ a.descripcion }}</span>
          </div>
          <button class="btn btn-secondary btn-sm" @click="downloadArchivo(a)">Descargar</button>
          <button v-if="canWrite" class="btn-del" @click="deleteArchivo(a)" title="Eliminar">✕</button>
        </div>
      </div>
    </div>

    <!-- Campos adicionales tab -->
    <div v-if="activeTab === 'campos'" class="campos-tab">
      <div class="campos-toolbar">
        <button v-if="!camposEditing && canWrite" class="btn btn-secondary btn-sm" @click="camposEditing = true">Editar</button>
        <template v-if="camposEditing">
          <button class="btn btn-primary btn-sm" :disabled="camposSaving" @click="saveCampos">{{ camposSaving ? 'Guardando…' : 'Guardar' }}</button>
          <button class="btn btn-secondary btn-sm" @click="camposEditing = false; loadCampos()">Cancelar</button>
        </template>
      </div>

      <div v-if="!campos.length" class="card empty-state">
        No hay campos adicionales definidos. Un administrador puede crearlos en la configuración del sistema.
      </div>
      <div v-else class="card campos-grid">
        <div v-for="c in campos" :key="c.id" class="campo-item">
          <div class="campo-label">{{ c.nombre }}</div>
          <template v-if="camposEditing">
            <input v-if="c.tipo === 'texto'" v-model="camposFormValues[c.id]" class="input campo-input" />
            <input v-else-if="c.tipo === 'numero'" type="number" v-model="camposFormValues[c.id]" class="input campo-input" step="any" />
            <input v-else-if="c.tipo === 'fecha'" type="date" v-model="camposFormValues[c.id]" class="input campo-input" />
            <select v-else-if="c.tipo === 'dropdown'" v-model="camposFormValues[c.id]" class="input campo-input">
              <option value="">— Seleccionar —</option>
              <option v-for="op in (c.opciones || [])" :key="op" :value="op">{{ op }}</option>
            </select>
          </template>
          <div v-else class="campo-valor">{{ c.valor || '—' }}</div>
        </div>
      </div>
    </div>
  </div>

  <div v-else-if="loading" class="loading-box"><div class="spinner"></div></div>
  <div v-else class="card empty-state">
    Activo no encontrado. <RouterLink to="/activos/arbol">Volver</RouterLink>
  </div>

  <!-- Edit modal -->
  <Teleport to="body">
    <AssetFormModal
      v-if="editOpen && asset"
      :asset="asset"
      @close="editOpen = false"
      @saved="onEditSaved"
    />
  </Teleport>
</template>

<script setup>
import { ref, computed, reactive, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/services/api'
import TrendChart from '@/components/TrendChart.vue'
import AssetFormModal from '@/components/AssetFormModal.vue'

const route = useRoute()
const auth = useAuthStore()

const asset = ref(null)
const puntos = ref([])
const loading = ref(true)
const activeTab = ref('info')
const selectedPunto = ref(null)
const editOpen = ref(false)

// Componentes
const componentes = ref([])
const tiposComponente = ref([])
const compFormOpen = ref(false)
const compSaving = ref(false)
const compError = ref('')
const compForm = reactive({
  tipo_componente_id: '',
  nombre: '',
  cmms_id: '',
  descripcion: '',
})

// Archivos
const archivos = ref([])
const uploadingFile = ref(false)

// Campos extra
const campos = ref([])
const camposSaving = ref(false)
const camposEditing = ref(false)
const camposFormValues = ref({})

const canWrite = computed(() => ['admin', 'ingeniero_confiabilidad', 'supervisor'].includes(auth.user?.role))

const ESTADO_LABELS = { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: 'Sin datos' }
const ESTADO_OP_LABELS = {
  operativo: 'Operativo',
  operativo_limitado: 'Op. Limitado',
  stand_by: 'Stand By',
  fuera_de_servicio: 'Fuera de Servicio',
  dado_de_baja: 'Dado de Baja',
}

const tabs = [
  { key: 'info', label: 'Información General' },
  { key: 'mediciones', label: 'Mediciones' },
  { key: 'componentes', label: 'Componentes' },
  { key: 'archivos', label: 'Archivos' },
  { key: 'campos', label: 'Campos Adicionales' },
]

const puntosWithHealth = computed(() =>
  puntos.value.map((p) => ({ ...p, estado: 'desconocido' }))
)

function formatDate(d) { return d ? new Date(d).toLocaleDateString('es-CO') : '—' }
function formatTime(t) { return t ? new Date(t).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' }) : '' }
function fmtVal(v) {
  if (v === null) return '—'
  const n = Number(v)
  return n % 1 === 0 ? n : n.toFixed(3)
}

async function loadComponentes() {
  try {
    const { data } = await api.get('/inspections/componentes', { params: { activo_id: route.params.id } })
    componentes.value = data.componentes
  } catch { /* ignore */ }
}

async function submitComponente() {
  if (!compForm.tipo_componente_id || !compForm.nombre.trim()) {
    compError.value = 'Tipo y nombre son requeridos'
    return
  }
  compSaving.value = true
  compError.value = ''
  try {
    await api.post('/inspections/componentes', {
      activo_id: route.params.id,
      tipo_componente_id: compForm.tipo_componente_id || null,
      cmms_id: compForm.cmms_id || null,
      nombre: compForm.nombre.trim(),
      descripcion: compForm.descripcion || null,
    })
    compFormOpen.value = false
    compForm.tipo_componente_id = ''
    compForm.nombre = ''
    compForm.cmms_id = ''
    compForm.descripcion = ''
    await loadComponentes()
  } catch (err) {
    compError.value = err.response?.data?.error || 'Error al agregar componente'
  } finally {
    compSaving.value = false
  }
}

async function onEditSaved(updated) {
  editOpen.value = false
  try {
    const { data } = await api.get(`/assets/${route.params.id}`)
    asset.value = data.activo
  } catch { /* ignore */ }
}

async function loadArchivos() {
  try {
    const { data } = await api.get(`/assets/${route.params.id}/archivos`)
    archivos.value = data.archivos
  } catch { /* ignore */ }
}

async function handleArchivoUpload(e) {
  const files = Array.from(e.target.files)
  if (!files.length) return
  uploadingFile.value = true
  try {
    for (const file of files) {
      const fd = new FormData()
      fd.append('archivo', file)
      fd.append('tipo', e.target.dataset.tipo || 'otro')
      const { data } = await api.post(`/assets/${route.params.id}/archivos`, fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
      })
      archivos.value.unshift(data.archivo)
    }
  } finally {
    uploadingFile.value = false
    e.target.value = ''
  }
}

async function downloadArchivo(archivo) {
  try {
    const { data } = await api.get(`/assets/${route.params.id}/archivos/${archivo.id}/download`)
    window.open(data.url, '_blank')
  } catch { alert('Error al generar el enlace de descarga') }
}

async function deleteArchivo(archivo) {
  if (!confirm(`¿Eliminar "${archivo.nombre_original}"?`)) return
  try {
    await api.delete(`/assets/${route.params.id}/archivos/${archivo.id}`)
    archivos.value = archivos.value.filter((a) => a.id !== archivo.id)
  } catch { alert('Error al eliminar el archivo') }
}

async function loadCampos() {
  try {
    const { data } = await api.get(`/assets/${route.params.id}/campos-extra`)
    campos.value = data.campos
    camposFormValues.value = {}
    for (const c of data.campos) camposFormValues.value[c.id] = c.valor || ''
  } catch { /* ignore */ }
}

async function saveCampos() {
  camposSaving.value = true
  try {
    const valores = Object.entries(camposFormValues.value).map(([campo_id, valor]) => ({ campo_id, valor: valor || null }))
    await api.put(`/assets/${route.params.id}/campos-extra`, { valores })
    await loadCampos()
    camposEditing.value = false
  } catch { alert('Error al guardar los campos') }
  finally { camposSaving.value = false }
}

function formatBytes(b) {
  if (!b) return ''
  if (b < 1024) return b + ' B'
  if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB'
  return (b / (1024 * 1024)).toFixed(1) + ' MB'
}

onMounted(async () => {
  try {
    const [assetRes, puntosRes, tiposRes] = await Promise.allSettled([
      api.get(`/assets/${route.params.id}`),
      api.get('/measurements/latest', { params: { activo_id: route.params.id } }),
      api.get('/inspections/tipos-componente'),
    ])
    if (assetRes.status === 'fulfilled') asset.value = assetRes.value.data.activo
    if (puntosRes.status === 'fulfilled') puntos.value = puntosRes.value.data.puntos
    if (tiposRes.status === 'fulfilled') tiposComponente.value = tiposRes.value.data.tipos
    await Promise.allSettled([loadComponentes(), loadArchivos(), loadCampos()])
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
.asset-detail { display: flex; flex-direction: column; gap: 1rem; }

.breadcrumb { font-size: 0.8125rem; color: var(--color-text-muted); display: flex; gap: 0.5rem; align-items: center; margin-bottom: 0.25rem; }
.breadcrumb a { color: var(--color-brand); }

.detail-title-row { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; margin-bottom: 0.25rem; }
.detail-title-row h3 { margin: 0; }
.asset-meta { color: var(--color-text-muted); font-size: 0.875rem; }

.health-chip {
  padding: 3px 10px; border-radius: 999px; font-size: 0.75rem; font-weight: 600;
}
.health-chip.health-bueno { background: #f0fdf4; color: #16a34a; }
.health-chip.health-alerta { background: #fffbeb; color: #d97706; }
.health-chip.health-critico { background: #fef2f2; color: #dc2626; }
.health-chip.health-desconocido { background: var(--color-bg); color: var(--color-text-muted); }

.tabs { display: flex; gap: 0; border-bottom: 2px solid var(--color-border); }
.tab { padding: 0.625rem 1.25rem; background: none; border: none; border-bottom: 2px solid transparent; font-size: 0.875rem; font-weight: 500; cursor: pointer; color: var(--color-text-muted); margin-bottom: -2px; display: flex; align-items: center; gap: 0.5rem; }
.tab.active { color: var(--color-brand); border-bottom-color: var(--color-brand); }
.tab-count { background: var(--color-bg); border-radius: 999px; padding: 0 6px; font-size: 0.7rem; }

.info-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1.25rem; }
.field-full { grid-column: 1 / -1; }
.info-label { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 0.25rem; }
.info-value { font-size: 0.9375rem; font-weight: 500; }

.mediciones-tab { display: flex; flex-direction: column; gap: 1rem; }

.chart-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 1rem; }
.punto-code { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.06em; margin-right: 0.5rem; }
.punto-name { font-weight: 600; }

.puntos-mini-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 0.875rem; }

.mini-punto {
  background: #fff; border-radius: 10px; padding: 1rem; cursor: pointer;
  border: 1px solid var(--color-border); border-left: 4px solid var(--color-border);
  transition: box-shadow 0.15s, transform 0.1s;
}
.mini-punto:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.08); transform: translateY(-1px); }
.mini-punto.estado-bueno { border-left-color: #16a34a; }
.mini-punto.estado-alerta { border-left-color: #d97706; }
.mini-punto.estado-critico { border-left-color: #dc2626; }

.mini-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.25rem; }
.mini-code { font-size: 0.7rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.05em; }
.mini-name { font-size: 0.875rem; font-weight: 500; margin-bottom: 0.5rem; }
.mini-value { font-size: 1.5rem; font-weight: 700; line-height: 1; }
.mini-unit { font-size: 0.75rem; font-weight: 400; color: var(--color-text-muted); }
.mini-nodata { font-size: 0.875rem; color: var(--color-text-muted); font-weight: 400; }
.mini-time { font-size: 0.7rem; color: var(--color-text-muted); margin-top: 0.375rem; }

.estado-badge { display: inline-block; padding: 1px 6px; border-radius: 999px; font-size: 0.68rem; font-weight: 600; text-transform: uppercase; }
.estado-badge.estado-bueno { background: #f0fdf4; color: #16a34a; }
.estado-badge.estado-alerta { background: #fffbeb; color: #d97706; }
.estado-badge.estado-critico { background: #fef2f2; color: #dc2626; }
.estado-badge.estado-desconocido { background: var(--color-bg); color: var(--color-text-muted); }

.btn-sm { padding: 0.25rem 0.75rem; font-size: 0.8125rem; }
.loading-box { display: flex; justify-content: center; align-items: center; padding: 4rem; }
.empty-state { text-align: center; color: var(--color-text-muted); padding: 3rem; }

/* Detail header edit button */
.detail-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; }

/* Componentes tab */
.componentes-tab { display: flex; flex-direction: column; gap: 1rem; }
.comp-toolbar { display: flex; justify-content: flex-end; }
.comp-list { padding: 0; overflow: hidden; }
.comp-row {
  display: flex; align-items: center; justify-content: space-between;
  padding: 0.75rem 1.25rem; border-bottom: 1px solid var(--color-border);
  gap: 1rem;
}
.comp-row:last-child { border-bottom: none; }
.comp-left { display: flex; flex-direction: column; gap: 0.15rem; flex: 1; min-width: 0; }
.comp-tag { font-family: monospace; font-size: 0.75rem; color: var(--color-text-muted); font-weight: 700; }
.comp-name { font-size: 0.9rem; font-weight: 600; }
.comp-tipo { font-size: 0.75rem; color: var(--color-text-secondary); }
.comp-right { flex-shrink: 0; }

.op-badge {
  display: inline-block; padding: 2px 8px; border-radius: 999px;
  font-size: 0.68rem; font-weight: 700; text-transform: uppercase;
}
.op-operativo            { background: #dcfce7; color: #15803d; }
.op-operativo_limitado   { background: #fef3c7; color: #b45309; }
.op-stand_by             { background: #dbeafe; color: #1d4ed8; }
.op-fuera_de_servicio    { background: #fee2e2; color: #b91c1c; }
.op-dado_de_baja         { background: #f3f4f6; color: #6b7280; }

/* Componente form */
.comp-form { display: flex; flex-direction: column; gap: 0.75rem; padding: 1.25rem; }
.comp-form-title { font-size: 0.8125rem; font-weight: 700; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
.field-row { display: flex; gap: 0.75rem; flex-wrap: wrap; }
.field { display: flex; flex-direction: column; gap: 0.25rem; flex: 1; min-width: 0; }
.field-wide { flex: 2; }
.field-label { font-size: 0.75rem; font-weight: 600; color: var(--color-text-secondary); }
.field-error { font-size: 0.75rem; color: #dc2626; }
.req { color: #dc2626; }
.input {
  padding: 0.4rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px;
  font-size: 0.8125rem; font-family: inherit; background: #fff; width: 100%; box-sizing: border-box;
}
.input:focus { outline: none; border-color: var(--color-brand); }
.mono { font-family: monospace; }
.comp-form-actions { display: flex; gap: 0.5rem; justify-content: flex-end; }

/* Archivos tab */
.archivos-tab { display: flex; flex-direction: column; gap: 1rem; }
.archivos-toolbar { display: flex; align-items: center; gap: 0.5rem; }
.upload-group { display: flex; gap: 0.5rem; flex-wrap: wrap; }
.upload-label {
  display: inline-block; padding: 5px 12px;
  background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 6px;
  font-size: 0.8125rem; color: #374151; cursor: pointer;
}
.upload-label:hover { background: #f3f4f6; }
.upload-label input[type="file"] { display: none; }
.archivo-row { display: flex; align-items: center; gap: 12px; padding: 12px 0; border-bottom: 1px solid var(--color-border); }
.archivo-row:last-child { border-bottom: none; }
.archivo-icon { color: #9ca3af; flex-shrink: 0; }
.archivo-info { flex: 1; }
.archivo-nombre { display: block; font-size: 13px; font-weight: 500; color: #111827; }
.archivo-meta { display: block; font-size: 11px; color: #9ca3af; text-transform: capitalize; }
.archivo-desc { display: block; font-size: 11px; color: #6b7280; }
.btn-del { background: none; border: none; color: #9ca3af; cursor: pointer; font-size: 16px; padding: 4px 8px; }
.btn-del:hover { color: #dc2626; }

/* Campos tab */
.campos-tab { display: flex; flex-direction: column; gap: 1rem; }
.campos-toolbar { display: flex; gap: 0.5rem; }
.campos-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 1rem; padding: 1.25rem; }
.campo-item { display: flex; flex-direction: column; gap: 0.4rem; }
.campo-label { font-size: 0.75rem; font-weight: 600; color: var(--color-text-secondary); }
.campo-valor { font-size: 0.875rem; color: #111827; }
.campo-input { padding: 0.4rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.8125rem; font-family: inherit; }
</style>
