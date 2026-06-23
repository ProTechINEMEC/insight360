<template>
  <div class="tecnicas-view">
    <div class="page-header">
      <h1 class="page-title">Gestión de Técnicas CBM</h1>
      <button class="btn-primary" @click="openNewTecnica">+ Nueva Técnica</button>
    </div>

    <div class="tecnicas-layout">
      <!-- Techniques list -->
      <div class="tecnicas-list">
        <div
          v-for="t in tecnicas"
          :key="t.id"
          class="tecnica-card"
          :class="{ active: selectedId === t.id, inactive: !t.activo }"
          @click="select(t)"
        >
          <div class="tc-header">
            <span class="tc-codigo">{{ t.codigo }}</span>
            <span v-if="!t.activo" class="tc-inact">Inactiva</span>
          </div>
          <div class="tc-nombre">{{ t.nombre }}</div>
          <div class="tc-meta" v-if="t.norma_referencia">{{ t.norma_referencia }}</div>
        </div>
      </div>

      <!-- Technique detail panel -->
      <div class="detail-panel" v-if="selected">
        <div class="detail-header">
          <div>
            <div class="detail-codigo">{{ selected.codigo }}</div>
            <div class="detail-nombre">{{ selected.nombre }}</div>
            <div class="detail-meta" v-if="selected.norma_referencia">{{ selected.norma_referencia }}</div>
            <div class="detail-aplica" v-if="selected.aplica_a">Aplica a: {{ selected.aplica_a }}</div>
          </div>
          <button class="btn-outline" @click="editTecnica(selected)">Editar</button>
        </div>

        <!-- Measuring points -->
        <div class="puntos-section">
          <div class="puntos-header">
            <h3 class="puntos-title">Puntos de Medición ({{ puntos.length }})</h3>
            <button class="btn-sm" @click="openNewPunto">+ Agregar Punto</button>
          </div>

          <div v-if="!puntos.length" class="empty-puntos">
            No hay puntos de medición definidos para esta técnica.
            <span v-if="selected.codigo === 'VIS'"> (Inspección visual — sin puntos cuantitativos)</span>
          </div>

          <div class="puntos-list">
            <div v-for="(p, idx) in puntos" :key="p.id" class="punto-row">
              <span class="punto-orden">{{ idx + 1 }}</span>
              <div class="punto-info">
                <span class="punto-nombre">{{ p.nombre }}</span>
                <span class="punto-unidad" v-if="p.unidad">{{ p.unidad }}</span>
                <span class="punto-desc" v-if="p.descripcion">{{ p.descripcion }}</span>
              </div>
              <div class="punto-actions">
                <button class="act-btn" @click="editPunto(p)" title="Editar">
                  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M11.5 2.5l2 2L5 13H3v-2L11.5 2.5z"/></svg>
                </button>
                <button class="act-btn del" @click="deletePunto(p)" title="Eliminar">
                  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 5h10M8 5V3M6 5v7M10 5v7M4 5l.5 8h7L12 5"/></svg>
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Applicable component types -->
        <div class="tipos-section">
          <h3 class="puntos-title">Tipos de Componente Asociados</h3>
          <div class="tipos-list">
            <span v-for="tc in tiposLinked" :key="tc.id" class="tipo-chip">
              {{ tc.nombre }}
            </span>
            <span v-if="!tiposLinked.length" class="empty-puntos">
              Ningún tipo de componente asociado aún. Las asociaciones se crean vía catálogo de modos de falla.
            </span>
          </div>
        </div>
      </div>

      <div class="detail-panel empty-panel" v-else>
        <div class="empty-panel-inner">Selecciona una técnica para ver sus detalles</div>
      </div>
    </div>

    <!-- Tecnica modal -->
    <Teleport to="body">
      <div v-if="tecnicaModal.open" class="modal-backdrop" @click.self="tecnicaModal.open = false">
        <div class="modal">
          <div class="modal-header">
            <h2>{{ tecnicaModal.isEdit ? 'Editar Técnica' : 'Nueva Técnica' }}</h2>
            <button class="modal-close" @click="tecnicaModal.open = false">×</button>
          </div>
          <form @submit.prevent="saveTecnica" class="modal-form">
            <label v-if="!tecnicaModal.isEdit">
              Código *
              <input v-model="tecnicaModal.form.codigo" required maxlength="50" placeholder="VIB" />
            </label>
            <label>
              Nombre *
              <input v-model="tecnicaModal.form.nombre" required maxlength="200" placeholder="Análisis de Vibraciones" />
            </label>
            <label>
              Norma de Referencia
              <input v-model="tecnicaModal.form.norma_referencia" placeholder="ISO 10816-3" />
            </label>
            <label>
              Aplica a
              <input v-model="tecnicaModal.form.aplica_a" placeholder="Rotativo, Eléctrico, Todos..." />
            </label>
            <label class="checkbox-label" v-if="tecnicaModal.isEdit">
              <input type="checkbox" v-model="tecnicaModal.form.activo" />
              Técnica activa
            </label>
            <div class="modal-actions">
              <button type="button" class="btn-cancel" @click="tecnicaModal.open = false">Cancelar</button>
              <button type="submit" class="btn-primary" :disabled="savingT">
                {{ savingT ? 'Guardando…' : 'Guardar' }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>

    <!-- Punto modal -->
    <Teleport to="body">
      <div v-if="puntoModal.open" class="modal-backdrop" @click.self="puntoModal.open = false">
        <div class="modal">
          <div class="modal-header">
            <h2>{{ puntoModal.isEdit ? 'Editar Punto' : 'Nuevo Punto de Medición' }}</h2>
            <button class="modal-close" @click="puntoModal.open = false">×</button>
          </div>
          <form @submit.prevent="savePunto" class="modal-form">
            <label>
              Nombre *
              <input v-model="puntoModal.form.nombre" required maxlength="200" placeholder="Velocidad H" />
            </label>
            <label>
              Unidad
              <input v-model="puntoModal.form.unidad" maxlength="50" placeholder="mm/s" />
            </label>
            <label>
              Descripción
              <textarea v-model="puntoModal.form.descripcion" rows="2" placeholder="Descripción del punto de medición" />
            </label>
            <label>
              Orden
              <input type="number" v-model.number="puntoModal.form.orden" min="0" />
            </label>
            <div class="modal-actions">
              <button type="button" class="btn-cancel" @click="puntoModal.open = false">Cancelar</button>
              <button type="submit" class="btn-primary" :disabled="savingP">
                {{ savingP ? 'Guardando…' : 'Guardar' }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, watch } from 'vue'
import api from '@/services/api'

const tecnicas = ref([])
const selectedId = ref(null)
const selected = ref(null)
const puntos = ref([])
const tiposLinked = ref([])

const savingT = ref(false)
const savingP = ref(false)

const tecnicaModal = reactive({
  open: false,
  isEdit: false,
  form: {},
})

const puntoModal = reactive({
  open: false,
  isEdit: false,
  editId: null,
  form: {},
})

async function loadTecnicas() {
  const { data } = await api.get('/inspections/tecnicas-admin')
  tecnicas.value = data.tecnicas
}

function select(t) {
  selectedId.value = t.id
  selected.value = t
  loadPuntos(t.id)
  loadTipos(t.id)
}

async function loadPuntos(tecnicaId) {
  const { data } = await api.get(`/inspections/puntos-tecnica?tecnica_id=${tecnicaId}`)
  puntos.value = data.puntos
}

async function loadTipos(tecnicaId) {
  const { data } = await api.get(`/inspections/tecnicas-admin/${tecnicaId}/tipos-componente`)
  tiposLinked.value = data.tipos
}

function openNewTecnica() {
  tecnicaModal.isEdit = false
  tecnicaModal.form = { codigo: '', nombre: '', norma_referencia: '', aplica_a: '', activo: true }
  tecnicaModal.open = true
}

function editTecnica(t) {
  tecnicaModal.isEdit = true
  tecnicaModal.form = {
    nombre: t.nombre,
    norma_referencia: t.norma_referencia || '',
    aplica_a: t.aplica_a || '',
    activo: t.activo,
  }
  tecnicaModal.open = true
}

async function saveTecnica() {
  savingT.value = true
  try {
    if (tecnicaModal.isEdit) {
      const { data } = await api.put(`/inspections/tecnicas-admin/${selected.value.id}`, tecnicaModal.form)
      selected.value = data.tecnica
      const idx = tecnicas.value.findIndex((t) => t.id === data.tecnica.id)
      if (idx >= 0) tecnicas.value[idx] = data.tecnica
    } else {
      const { data } = await api.post('/inspections/tecnicas-admin', tecnicaModal.form)
      tecnicas.value.push(data.tecnica)
      select(data.tecnica)
    }
    tecnicaModal.open = false
  } catch (err) {
    alert(err.response?.data?.error || 'Error al guardar la técnica')
  } finally {
    savingT.value = false
  }
}

function openNewPunto() {
  puntoModal.isEdit = false
  puntoModal.editId = null
  puntoModal.form = { nombre: '', unidad: '', descripcion: '', orden: puntos.value.length + 1 }
  puntoModal.open = true
}

function editPunto(p) {
  puntoModal.isEdit = true
  puntoModal.editId = p.id
  puntoModal.form = { nombre: p.nombre, unidad: p.unidad || '', descripcion: p.descripcion || '', orden: p.orden }
  puntoModal.open = true
}

async function savePunto() {
  savingP.value = true
  try {
    if (puntoModal.isEdit) {
      await api.put(`/inspections/puntos-tecnica/${puntoModal.editId}`, puntoModal.form)
    } else {
      await api.post('/inspections/puntos-tecnica', { ...puntoModal.form, tecnica_id: selected.value.id })
    }
    await loadPuntos(selected.value.id)
    puntoModal.open = false
  } catch (err) {
    alert(err.response?.data?.error || 'Error al guardar el punto')
  } finally {
    savingP.value = false
  }
}

async function deletePunto(p) {
  if (!confirm(`¿Eliminar el punto "${p.nombre}"? Esta acción no se puede deshacer.`)) return
  try {
    await api.delete(`/inspections/puntos-tecnica/${p.id}`)
    puntos.value = puntos.value.filter((x) => x.id !== p.id)
  } catch (err) {
    alert(err.response?.data?.error || 'Error al eliminar el punto')
  }
}

onMounted(loadTecnicas)
</script>

<style scoped>
.tecnicas-view {
  padding: 24px;
  max-width: 1200px;
  margin: 0 auto;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}
.page-title { font-size: 20px; font-weight: 700; color: #111827; margin: 0; }

.tecnicas-layout {
  display: grid;
  grid-template-columns: 280px 1fr;
  gap: 20px;
  align-items: start;
}

/* Techniques list */
.tecnicas-list { display: flex; flex-direction: column; gap: 8px; }
.tecnica-card {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 12px 16px;
  cursor: pointer;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.tecnica-card:hover { border-color: #93c5fd; }
.tecnica-card.active { border-color: #2563eb; background: #eff6ff; }
.tecnica-card.inactive { opacity: 0.6; }

.tc-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
.tc-codigo { font-family: monospace; font-size: 13px; font-weight: 700; color: #1e40af; }
.tc-inact { font-size: 10px; color: #9ca3af; font-weight: 500; background: #f3f4f6; padding: 1px 6px; border-radius: 10px; }
.tc-nombre { font-size: 13px; font-weight: 500; color: #374151; }
.tc-meta { font-size: 11px; color: #9ca3af; margin-top: 2px; }

/* Detail panel */
.detail-panel {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 24px;
  min-height: 400px;
}
.empty-panel { display: flex; align-items: center; justify-content: center; }
.empty-panel-inner { color: #9ca3af; font-size: 14px; }

.detail-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 24px; }
.detail-codigo { font-family: monospace; font-size: 13px; font-weight: 700; color: #1e40af; }
.detail-nombre { font-size: 18px; font-weight: 600; color: #111827; margin: 4px 0; }
.detail-meta { font-size: 12px; color: #6b7280; }
.detail-aplica { font-size: 12px; color: #9ca3af; margin-top: 2px; }

/* Puntos */
.puntos-section, .tipos-section { margin-bottom: 24px; }
.puntos-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
.puntos-title { font-size: 13px; font-weight: 600; color: #374151; text-transform: uppercase; letter-spacing: 0.05em; margin: 0 0 12px; }
.puntos-header .puntos-title { margin: 0; }
.empty-puntos { font-size: 13px; color: #9ca3af; padding: 8px 0; }

.puntos-list { display: flex; flex-direction: column; gap: 6px; }
.punto-row {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 10px 14px;
  background: #f9fafb;
  border: 1px solid #f3f4f6;
  border-radius: 6px;
}
.punto-orden {
  width: 22px;
  height: 22px;
  background: #e5e7eb;
  color: #6b7280;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: 600;
  flex-shrink: 0;
  margin-top: 1px;
}
.punto-info { flex: 1; }
.punto-nombre { font-size: 13px; font-weight: 500; color: #111827; margin-right: 6px; }
.punto-unidad { font-size: 11px; font-family: monospace; color: #6b7280; background: #e5e7eb; padding: 1px 5px; border-radius: 3px; }
.punto-desc { display: block; font-size: 11px; color: #9ca3af; margin-top: 3px; }
.punto-actions { display: flex; gap: 4px; }
.act-btn {
  width: 28px; height: 28px;
  border: 1px solid #e5e7eb;
  border-radius: 5px;
  background: #fff;
  cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  color: #6b7280;
}
.act-btn:hover { background: #f3f4f6; color: #374151; }
.act-btn.del:hover { background: #fee2e2; border-color: #fca5a5; color: #dc2626; }

/* Tipos */
.tipos-list { display: flex; flex-wrap: wrap; gap: 8px; }
.tipo-chip {
  display: inline-block;
  padding: 4px 12px;
  background: #f0f9ff;
  border: 1px solid #bae6fd;
  border-radius: 20px;
  font-size: 12px;
  color: #0369a1;
}

/* Buttons */
.btn-primary {
  padding: 8px 16px;
  background: #2563eb;
  color: #fff;
  border: none;
  border-radius: 6px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
}
.btn-primary:hover { background: #1d4ed8; }
.btn-primary:disabled { opacity: 0.6; cursor: not-allowed; }
.btn-outline {
  padding: 6px 14px;
  background: #fff;
  color: #2563eb;
  border: 1px solid #bfdbfe;
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
}
.btn-outline:hover { background: #eff6ff; }
.btn-sm {
  padding: 5px 12px;
  background: #f9fafb;
  color: #374151;
  border: 1px solid #e5e7eb;
  border-radius: 5px;
  font-size: 12px;
  cursor: pointer;
}
.btn-sm:hover { background: #f3f4f6; }

/* Modal */
.modal-backdrop {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.4);
  display: flex; align-items: center; justify-content: center;
  z-index: 1000;
}
.modal {
  background: #fff;
  border-radius: 12px;
  padding: 24px;
  width: 480px;
  max-width: 95vw;
  box-shadow: 0 20px 60px rgba(0,0,0,0.2);
}
.modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.modal-header h2 { font-size: 16px; font-weight: 600; color: #111827; margin: 0; }
.modal-close { background: none; border: none; font-size: 22px; color: #6b7280; cursor: pointer; line-height: 1; }
.modal-form { display: flex; flex-direction: column; gap: 14px; }
.modal-form label { display: flex; flex-direction: column; gap: 5px; font-size: 13px; font-weight: 500; color: #374151; }
.modal-form input, .modal-form textarea {
  padding: 8px 12px;
  border: 1px solid #d1d5db;
  border-radius: 6px;
  font-size: 13px;
  font-family: inherit;
  outline: none;
}
.modal-form input:focus, .modal-form textarea:focus { border-color: #2563eb; box-shadow: 0 0 0 3px rgba(37,99,235,0.1); }
.checkbox-label { flex-direction: row !important; align-items: center; gap: 8px !important; }
.modal-actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 6px; }
.btn-cancel {
  padding: 8px 16px;
  background: #f3f4f6;
  color: #374151;
  border: none;
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
}
</style>
