<template>
  <div class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal">
      <div class="modal-header">
        <h2>{{ isEdit ? 'Editar Equipo' : 'Nuevo Equipo' }}</h2>
        <button class="modal-close" @click="$emit('close')">✕</button>
      </div>

      <div class="modal-body">
        <!-- ── UBICACIÓN ──────────────────────────────────────── -->
        <section class="form-section">
          <div class="section-title">Ubicación</div>

          <!-- Contrato -->
          <div class="field">
            <label class="field-label">Contrato <span class="req">*</span></label>
            <select v-model="loc.contrato_id" class="input" @change="onContratoChange">
              <option value="">Seleccionar contrato...</option>
              <option v-for="c in catalogs.contratos" :key="c.id" :value="c.id">{{ c.nombre }}</option>
            </select>
            <div v-if="errors.contrato_id" class="field-error">{{ errors.contrato_id }}</div>
          </div>

          <!-- Planta -->
          <div class="field" v-if="loc.contrato_id">
            <label class="field-label">Planta <span class="req">*</span></label>
            <div class="select-with-action">
              <select v-model="loc.planta_id" class="input" :disabled="newPlanta.open" @change="onPlantaChange">
                <option value="">Seleccionar planta...</option>
                <option v-for="p in plantasFiltradas" :key="p.id" :value="p.id">{{ p.nombre }}</option>
              </select>
              <button v-if="!newPlanta.open" type="button" class="btn-inline" @click="newPlanta.open = true">+ Nueva</button>
              <button v-else type="button" class="btn-inline btn-cancel" @click="newPlanta.open = false; newPlanta.codigo=''; newPlanta.nombre=''; newPlanta.ubicacion=''">Cancelar</button>
            </div>
            <!-- Inline new planta form -->
            <div v-if="newPlanta.open" class="inline-create">
              <div class="inline-row">
                <div class="field">
                  <label class="field-label">Código <span class="req">*</span></label>
                  <input v-model="newPlanta.codigo" class="input" placeholder="Ej: PLT-001" maxlength="20" />
                </div>
                <div class="field field-wide">
                  <label class="field-label">Nombre <span class="req">*</span></label>
                  <input v-model="newPlanta.nombre" class="input" placeholder="Nombre de la planta" maxlength="200" />
                </div>
              </div>
              <div class="field">
                <label class="field-label">Ubicación</label>
                <input v-model="newPlanta.ubicacion" class="input" placeholder="Departamento, municipio..." />
              </div>
              <button type="button" class="btn btn-secondary btn-sm" :disabled="saving" @click="createPlanta">
                {{ saving ? 'Creando...' : 'Crear Planta' }}
              </button>
              <div v-if="errors.newPlanta" class="field-error">{{ errors.newPlanta }}</div>
            </div>
            <div v-if="errors.planta_id" class="field-error">{{ errors.planta_id }}</div>
          </div>

          <!-- Sistema -->
          <div class="field" v-if="loc.planta_id">
            <label class="field-label">Sistema <span class="req">*</span></label>
            <div class="select-with-action">
              <select v-model="loc.sistema_id" class="input" :disabled="newSistema.open" @change="onSistemaChange">
                <option value="">Seleccionar sistema...</option>
                <option v-for="s in sistemasFiltrados" :key="s.id" :value="s.id">{{ s.nombre }}</option>
              </select>
              <button v-if="!newSistema.open" type="button" class="btn-inline" @click="newSistema.open = true">+ Nuevo</button>
              <button v-else type="button" class="btn-inline btn-cancel" @click="newSistema.open = false; newSistema.codigo=''; newSistema.nombre=''; newSistema.descripcion=''">Cancelar</button>
            </div>
            <div v-if="newSistema.open" class="inline-create">
              <div class="inline-row">
                <div class="field">
                  <label class="field-label">Código <span class="req">*</span></label>
                  <input v-model="newSistema.codigo" class="input" placeholder="Ej: SIS-01" maxlength="30" />
                </div>
                <div class="field field-wide">
                  <label class="field-label">Nombre <span class="req">*</span></label>
                  <input v-model="newSistema.nombre" class="input" placeholder="Nombre del sistema" maxlength="200" />
                </div>
              </div>
              <div class="field">
                <label class="field-label">Descripción</label>
                <input v-model="newSistema.descripcion" class="input" placeholder="Descripción breve..." />
              </div>
              <button type="button" class="btn btn-secondary btn-sm" :disabled="saving" @click="createSistema">
                {{ saving ? 'Creando...' : 'Crear Sistema' }}
              </button>
              <div v-if="errors.newSistema" class="field-error">{{ errors.newSistema }}</div>
            </div>
            <div v-if="errors.sistema_id" class="field-error">{{ errors.sistema_id }}</div>
          </div>

          <!-- Area (optional) -->
          <div class="field" v-if="loc.sistema_id">
            <label class="field-label">Área <span class="opt">(opcional)</span></label>
            <div class="select-with-action">
              <select v-model="form.area_id" class="input" :disabled="newArea.open">
                <option value="">Sin área específica</option>
                <option v-for="a in areasFiltradas" :key="a.id" :value="a.id">{{ a.nombre }}</option>
              </select>
              <button v-if="!newArea.open" type="button" class="btn-inline" @click="newArea.open = true">+ Nueva</button>
              <button v-else type="button" class="btn-inline btn-cancel" @click="newArea.open = false; newArea.codigo=''; newArea.nombre=''">Cancelar</button>
            </div>
            <div v-if="newArea.open" class="inline-create">
              <div class="inline-row">
                <div class="field">
                  <label class="field-label">Código <span class="req">*</span></label>
                  <input v-model="newArea.codigo" class="input" placeholder="Ej: AREA-01" maxlength="30" />
                </div>
                <div class="field field-wide">
                  <label class="field-label">Nombre <span class="req">*</span></label>
                  <input v-model="newArea.nombre" class="input" placeholder="Nombre del área" maxlength="200" />
                </div>
              </div>
              <button type="button" class="btn btn-secondary btn-sm" :disabled="saving" @click="createArea">
                {{ saving ? 'Creando...' : 'Crear Área' }}
              </button>
              <div v-if="errors.newArea" class="field-error">{{ errors.newArea }}</div>
            </div>
          </div>

          <!-- Equipo superior (optional) -->
          <div class="field" v-if="loc.sistema_id && equiposSistema.length">
            <label class="field-label">Equipo Superior <span class="opt">(opcional)</span></label>
            <select v-model="form.equipo_superior_id" class="input">
              <option value="">Ninguno (equipo independiente)</option>
              <option v-for="e in equiposSistema" :key="e.id" :value="e.id">{{ e.tag }} — {{ e.nombre }}</option>
            </select>
            <div class="field-hint">Seleccionar si este equipo es sub-componente de otro activo del mismo sistema</div>
          </div>
        </section>

        <!-- ── DATOS DEL EQUIPO ──────────────────────────────── -->
        <section class="form-section">
          <div class="section-title">Datos del Equipo</div>

          <div class="field-row">
            <div class="field">
              <label class="field-label">TAG <span class="req">*</span></label>
              <input v-model="form.tag" class="input mono" placeholder="Ej: K-101A" maxlength="100" />
              <div v-if="errors.tag" class="field-error">{{ errors.tag }}</div>
            </div>
            <div class="field field-wide">
              <label class="field-label">Nombre <span class="req">*</span></label>
              <input v-model="form.nombre" class="input" placeholder="Nombre descriptivo del equipo" maxlength="200" />
              <div v-if="errors.nombre" class="field-error">{{ errors.nombre }}</div>
            </div>
          </div>

          <div class="field-row">
            <div class="field">
              <label class="field-label">Criticidad <span class="req">*</span></label>
              <div class="crit-group">
                <label v-for="c in CRITICIDADES" :key="c.value" :class="['crit-option', `crit-${c.value}`, { active: form.criticidad === c.value }]">
                  <input type="radio" v-model="form.criticidad" :value="c.value" class="sr-only" />
                  {{ c.label }}
                </label>
              </div>
            </div>
            <div class="field field-wide">
              <label class="field-label">Estado Operacional</label>
              <select v-model="form.estado_operacional" class="input">
                <option v-for="e in ESTADOS_OP" :key="e.value" :value="e.value">{{ e.label }}</option>
              </select>
            </div>
          </div>
        </section>

        <!-- ── DATOS TÉCNICOS ────────────────────────────────── -->
        <section class="form-section">
          <div class="section-title">
            Datos Técnicos
            <button type="button" class="toggle-btn" @click="showTechnical = !showTechnical">
              {{ showTechnical ? 'Ocultar' : 'Mostrar' }}
            </button>
          </div>

          <template v-if="showTechnical">
            <div class="field-row">
              <div class="field">
                <label class="field-label">Código SAP</label>
                <input v-model="form.codigo_sap" class="input mono" placeholder="Ej: 10005432" maxlength="50" />
              </div>
              <div class="field">
                <label class="field-label">Fabricante</label>
                <input v-model="form.fabricante" class="input" placeholder="Ej: Siemens" maxlength="100" />
              </div>
              <div class="field">
                <label class="field-label">Modelo</label>
                <input v-model="form.modelo" class="input" placeholder="Modelo / referencia" maxlength="100" />
              </div>
            </div>
            <div class="field-row">
              <div class="field">
                <label class="field-label">Número de Serie</label>
                <input v-model="form.numero_serie" class="input mono" placeholder="S/N" maxlength="100" />
              </div>
              <div class="field">
                <label class="field-label">Fecha de Instalación</label>
                <input v-model="form.fecha_instalacion" type="date" class="input" />
              </div>
            </div>
            <div class="field">
              <label class="field-label">Descripción</label>
              <textarea v-model="form.descripcion" class="input textarea" placeholder="Descripción técnica, función, especificaciones relevantes..." rows="3" />
            </div>
          </template>
        </section>

        <div v-if="errors.general" class="error-banner">{{ errors.general }}</div>
      </div>

      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" @click="$emit('close')">Cancelar</button>
        <button type="button" class="btn btn-primary" :disabled="saving" @click="submit">
          {{ saving ? 'Guardando...' : (isEdit ? 'Guardar Cambios' : 'Crear Equipo') }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue'
import { api } from '@/services/api'

const props = defineProps({
  // Pre-fill context (from tree clicks)
  preContrato: String,
  prePlanta: String,
  preSistema: String,
  // Edit mode
  asset: Object,
})
const emit = defineEmits(['close', 'saved'])

const isEdit = computed(() => !!props.asset)
const saving = ref(false)
const showTechnical = ref(!!props.asset)

const CRITICIDADES = [
  { value: 'critico',  label: 'Crítico' },
  { value: 'esencial', label: 'Esencial' },
  { value: 'general',  label: 'General' },
]
const ESTADOS_OP = [
  { value: 'operativo',           label: 'Operativo' },
  { value: 'operativo_limitado',  label: 'Operativo Limitado' },
  { value: 'stand_by',            label: 'Stand By' },
  { value: 'fuera_de_servicio',   label: 'Fuera de Servicio' },
  { value: 'dado_de_baja',        label: 'Dado de Baja' },
]

// Catalogs
const catalogs = reactive({ contratos: [], plantas: [], sistemas: [], areas: [] })

// Location selection (drives cascading loads)
const loc = reactive({
  contrato_id: props.preContrato || '',
  planta_id: props.prePlanta || '',
  sistema_id: props.preSistema || '',
})

// Main form
const form = reactive({
  tag: '',
  nombre: '',
  criticidad: 'general',
  estado_operacional: 'operativo',
  area_id: '',
  equipo_superior_id: '',
  codigo_sap: '',
  fabricante: '',
  modelo: '',
  numero_serie: '',
  fecha_instalacion: '',
  descripcion: '',
})

const errors = reactive({})

// Inline create forms
const newPlanta  = reactive({ open: false, codigo: '', nombre: '', ubicacion: '' })
const newSistema = reactive({ open: false, codigo: '', nombre: '', descripcion: '' })
const newArea    = reactive({ open: false, codigo: '', nombre: '' })

// Equipos in same sistema (for equipo_superior)
const equiposSistema = ref([])

// Computed filter lists
const plantasFiltradas = computed(() =>
  catalogs.plantas.filter((p) => p.contrato_id === loc.contrato_id)
)
const sistemasFiltrados = computed(() =>
  catalogs.sistemas.filter((s) => s.planta_id === loc.planta_id)
)
const areasFiltradas = computed(() =>
  catalogs.areas.filter((a) => a.sistema_id === loc.sistema_id)
)

// ── Watchers ───────────────────────────────────────────────

watch(() => loc.sistema_id, async (id) => {
  form.area_id = ''
  form.equipo_superior_id = ''
  equiposSistema.value = []
  if (!id) return
  try {
    const [areasRes, activosRes] = await Promise.all([
      api.get('/assets/areas', { params: { sistema_id: id } }),
      api.get('/assets', { params: { sistema_id: id } }),
    ])
    catalogs.areas = areasRes.data.areas
    equiposSistema.value = activosRes.data.activos.filter((a) => !props.asset || a.id !== props.asset.id)
  } catch { /* ignore */ }
})

// ── Loaders ────────────────────────────────────────────────

async function loadCatalogs() {
  const [contrRes, plantRes, sisRes] = await Promise.all([
    api.get('/assets/contratos'),
    api.get('/assets/plantas'),
    api.get('/assets/sistemas'),
  ])
  catalogs.contratos = contrRes.data.contratos
  catalogs.plantas   = plantRes.data.plantas
  catalogs.sistemas  = sisRes.data.sistemas

  if (loc.sistema_id) {
    const [areasRes, activosRes] = await Promise.all([
      api.get('/assets/areas', { params: { sistema_id: loc.sistema_id } }),
      api.get('/assets', { params: { sistema_id: loc.sistema_id } }),
    ])
    catalogs.areas = areasRes.data.areas
    equiposSistema.value = activosRes.data.activos.filter((a) => !props.asset || a.id !== props.asset.id)
  }
}

// ── Pre-fill in edit mode ───────────────────────────────────

async function initEdit() {
  const a = props.asset
  form.tag                = a.tag || ''
  form.nombre             = a.nombre || ''
  form.criticidad         = a.criticidad || 'general'
  form.estado_operacional = a.estado_operacional || 'operativo'
  form.area_id            = a.area_id || ''
  form.equipo_superior_id = a.equipo_superior_id || ''
  form.codigo_sap         = a.codigo_sap || ''
  form.fabricante         = a.fabricante || ''
  form.modelo             = a.modelo || ''
  form.numero_serie       = a.numero_serie || ''
  form.fecha_instalacion  = a.fecha_instalacion ? a.fecha_instalacion.slice(0, 10) : ''
  form.descripcion        = a.descripcion || ''

  // Derive location from asset's sistema
  loc.sistema_id = a.sistema_id || ''
  const sistema = catalogs.sistemas.find((s) => s.id === a.sistema_id)
  if (sistema) {
    loc.planta_id = sistema.planta_id
    const planta = catalogs.plantas.find((p) => p.id === sistema.planta_id)
    if (planta) loc.contrato_id = planta.contrato_id || ''
  }
}

onMounted(async () => {
  await loadCatalogs()
  if (isEdit.value) await initEdit()
})

// ── Cascade handlers ────────────────────────────────────────

function onContratoChange() {
  loc.planta_id = ''
  loc.sistema_id = ''
  form.area_id = ''
}
function onPlantaChange() {
  loc.sistema_id = ''
  form.area_id = ''
}
function onSistemaChange() {
  form.area_id = ''
}

// ── Inline creates ──────────────────────────────────────────

async function createPlanta() {
  if (!newPlanta.codigo || !newPlanta.nombre) {
    errors.newPlanta = 'Código y nombre son requeridos'
    return
  }
  saving.value = true
  errors.newPlanta = ''
  try {
    const { data } = await api.post('/assets/plantas', {
      contrato_id: loc.contrato_id || null,
      codigo: newPlanta.codigo,
      nombre: newPlanta.nombre,
      ubicacion: newPlanta.ubicacion || null,
    })
    catalogs.plantas.push(data.planta)
    loc.planta_id = data.planta.id
    newPlanta.open = false
    newPlanta.codigo = ''; newPlanta.nombre = ''; newPlanta.ubicacion = ''
  } catch (err) {
    errors.newPlanta = err.response?.data?.error || 'Error al crear planta'
  } finally {
    saving.value = false
  }
}

async function createSistema() {
  if (!newSistema.codigo || !newSistema.nombre) {
    errors.newSistema = 'Código y nombre son requeridos'
    return
  }
  saving.value = true
  errors.newSistema = ''
  try {
    const { data } = await api.post('/assets/sistemas', {
      planta_id: loc.planta_id,
      codigo: newSistema.codigo,
      nombre: newSistema.nombre,
      descripcion: newSistema.descripcion || null,
    })
    catalogs.sistemas.push(data.sistema)
    loc.sistema_id = data.sistema.id
    newSistema.open = false
    newSistema.codigo = ''; newSistema.nombre = ''; newSistema.descripcion = ''
  } catch (err) {
    errors.newSistema = err.response?.data?.error || 'Error al crear sistema'
  } finally {
    saving.value = false
  }
}

async function createArea() {
  if (!newArea.codigo || !newArea.nombre) {
    errors.newArea = 'Código y nombre son requeridos'
    return
  }
  saving.value = true
  errors.newArea = ''
  try {
    const { data } = await api.post('/assets/areas', {
      sistema_id: loc.sistema_id,
      codigo: newArea.codigo,
      nombre: newArea.nombre,
    })
    catalogs.areas.push(data.area)
    form.area_id = data.area.id
    newArea.open = false
    newArea.codigo = ''; newArea.nombre = ''
  } catch (err) {
    errors.newArea = err.response?.data?.error || 'Error al crear área'
  } finally {
    saving.value = false
  }
}

// ── Submit ──────────────────────────────────────────────────

function validate() {
  Object.keys(errors).forEach((k) => delete errors[k])
  let ok = true
  if (!loc.contrato_id) { errors.contrato_id = 'Seleccionar contrato'; ok = false }
  if (!loc.planta_id)   { errors.planta_id = 'Seleccionar planta'; ok = false }
  if (!loc.sistema_id)  { errors.sistema_id = 'Seleccionar sistema'; ok = false }
  if (!form.tag.trim()) { errors.tag = 'TAG es requerido'; ok = false }
  if (!form.nombre.trim()) { errors.nombre = 'Nombre es requerido'; ok = false }
  return ok
}

async function submit() {
  if (!validate()) return
  saving.value = true
  errors.general = ''
  try {
    const payload = {
      sistema_id: loc.sistema_id,
      area_id: form.area_id || null,
      equipo_superior_id: form.equipo_superior_id || null,
      tag: form.tag.trim(),
      nombre: form.nombre.trim(),
      criticidad: form.criticidad,
      codigo_sap: form.codigo_sap || null,
      fabricante: form.fabricante || null,
      modelo: form.modelo || null,
      numero_serie: form.numero_serie || null,
      fecha_instalacion: form.fecha_instalacion || null,
      descripcion: form.descripcion || null,
    }

    let data
    if (isEdit.value) {
      const res = await api.put(`/assets/${props.asset.id}`, payload)
      data = res.data
    } else {
      const res = await api.post('/assets', payload)
      data = res.data
    }
    emit('saved', data.activo)
  } catch (err) {
    errors.general = err.response?.data?.error || 'Error al guardar equipo'
  } finally {
    saving.value = false
  }
}
</script>

<style scoped>
.modal-backdrop {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.4);
  z-index: 1000;
  display: flex; align-items: flex-start; justify-content: center;
  padding: 2rem 1rem;
  overflow-y: auto;
}

.modal {
  background: #fff;
  border-radius: 12px;
  width: 100%;
  max-width: 680px;
  box-shadow: 0 20px 60px rgba(0,0,0,0.2);
  display: flex; flex-direction: column;
  min-height: 0;
}

.modal-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 1.25rem 1.5rem;
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;
}
.modal-header h2 { margin: 0; font-size: 1.125rem; }
.modal-close {
  background: none; border: none; cursor: pointer;
  font-size: 1rem; color: var(--color-text-muted);
  padding: 0.25rem; border-radius: 4px;
}
.modal-close:hover { background: var(--color-bg); }

.modal-body { padding: 1.5rem; overflow-y: auto; display: flex; flex-direction: column; gap: 1.5rem; }

.modal-footer {
  display: flex; justify-content: flex-end; gap: 0.75rem;
  padding: 1rem 1.5rem;
  border-top: 1px solid var(--color-border);
  flex-shrink: 0;
}

/* Sections */
.form-section { display: flex; flex-direction: column; gap: 0.875rem; }
.section-title {
  font-size: 0.75rem; font-weight: 700; text-transform: uppercase;
  letter-spacing: 0.06em; color: var(--color-text-muted);
  display: flex; align-items: center; gap: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid var(--color-border);
}
.toggle-btn {
  background: none; border: none; cursor: pointer;
  font-size: 0.75rem; color: var(--color-brand);
  text-transform: none; letter-spacing: 0; font-weight: 500;
}

/* Fields */
.field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 0; }
.field-wide { flex: 2; }
.field-row { display: flex; gap: 0.75rem; flex-wrap: wrap; }
.field-label { font-size: 0.75rem; font-weight: 600; color: var(--color-text-secondary); }
.req { color: #dc2626; }
.opt { color: var(--color-text-muted); font-weight: 400; }
.field-hint { font-size: 0.7rem; color: var(--color-text-muted); }
.field-error { font-size: 0.75rem; color: #dc2626; }

.input {
  padding: 0.45rem 0.75rem;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 0.8125rem;
  font-family: inherit;
  background: #fff;
  width: 100%;
  box-sizing: border-box;
}
.input:focus { outline: none; border-color: var(--color-brand); box-shadow: 0 0 0 2px rgba(37,99,235,0.1); }
.input:disabled { background: var(--color-bg); color: var(--color-text-muted); }
.mono { font-family: monospace; }
.textarea { resize: vertical; min-height: 72px; }

/* Criticidad radio group */
.crit-group { display: flex; gap: 0.5rem; }
.crit-option {
  flex: 1; text-align: center; padding: 0.35rem 0.5rem;
  border: 1.5px solid var(--color-border); border-radius: 6px;
  font-size: 0.8rem; font-weight: 500; cursor: pointer;
  transition: all 0.15s;
}
.crit-option.active.crit-critico  { background: #fee2e2; border-color: #dc2626; color: #b91c1c; }
.crit-option.active.crit-esencial { background: #fef3c7; border-color: #d97706; color: #b45309; }
.crit-option.active.crit-general  { background: #dcfce7; border-color: #16a34a; color: #15803d; }
.crit-option:not(.active):hover   { background: var(--color-bg); }
.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); }

/* Select with inline action */
.select-with-action { display: flex; gap: 0.5rem; align-items: center; }
.select-with-action .input { flex: 1; }
.btn-inline {
  white-space: nowrap; flex-shrink: 0;
  padding: 0.4rem 0.75rem; border-radius: 6px; border: 1px solid var(--color-brand);
  background: none; color: var(--color-brand); font-size: 0.75rem; font-weight: 600;
  cursor: pointer; transition: background 0.15s;
}
.btn-inline:hover { background: rgba(37,99,235,0.06); }
.btn-inline.btn-cancel { border-color: var(--color-border); color: var(--color-text-muted); }
.btn-inline.btn-cancel:hover { background: var(--color-bg); }

/* Inline create sub-form */
.inline-create {
  background: var(--color-bg);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  padding: 0.875rem;
  display: flex; flex-direction: column; gap: 0.625rem;
  margin-top: 0.25rem;
}
.inline-row { display: flex; gap: 0.625rem; }

.btn-sm { padding: 0.35rem 0.875rem; font-size: 0.8rem; align-self: flex-start; }

/* Error banner */
.error-banner {
  background: #fef2f2; border: 1px solid #fca5a5;
  border-radius: 6px; padding: 0.625rem 0.875rem;
  font-size: 0.8125rem; color: #b91c1c;
}
</style>
