<template>
  <div class="asset-tree-view">
    <!-- Top controls -->
    <div class="tree-controls card">
      <div class="controls-left">
        <div class="search-wrap">
          <span class="search-icon">🔍</span>
          <input
            v-model="search"
            type="text"
            placeholder="Buscar tag, nombre o código SAP..."
            class="search-input"
          />
          <button v-if="search" class="search-clear" @click="search = ''">✕</button>
        </div>
      </div>
      <div class="controls-right">
        <div class="filter-chips">
          <span class="filter-label">Criticidad:</span>
          <button
            v-for="c in CRITICIDADES"
            :key="c.key"
            :class="['chip', `chip-${c.key}`, { active: filters.criticidad.includes(c.key) }]"
            @click="toggleFilter('criticidad', c.key)"
          >{{ c.label }}</button>
        </div>
        <div class="view-toggles">
          <button class="toggle-btn" @click="expandAll(true)" title="Expandir todo">⊞</button>
          <button class="toggle-btn" @click="expandAll(false)" title="Colapsar todo">⊟</button>
        </div>
        <button v-if="canWrite" class="btn btn-primary btn-sm" @click="openAssetForm()">+ Nuevo Equipo</button>
      </div>
    </div>

    <!-- Main panels -->
    <div class="panels">
      <!-- Tree panel -->
      <div class="tree-panel card">
        <div v-if="loadingTree" class="tree-loading"><div class="spinner"></div> Cargando jerarquía...</div>
        <div v-else-if="!filteredTree.length" class="tree-empty">
          <div>Sin resultados</div>
          <button v-if="hasActiveFilters" class="btn btn-secondary btn-sm" @click="clearFilters" style="margin-top:0.5rem">Limpiar filtros</button>
        </div>

        <template v-else>
          <div v-for="contrato in filteredTree" :key="contrato.id || 'sin-contrato'" class="tree-contrato">
            <!-- Contrato row -->
            <div class="tree-row tree-row-contrato" @click="toggleNode('contrato', contrato.id)">
              <span class="expand-icon">{{ expandedNodes.contratos.has(contrato.id) ? '▼' : '▶' }}</span>
              <svg class="node-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="2.5" y="1.5" width="11" height="13" rx="1"/>
                <line x1="5" y1="5.5" x2="11" y2="5.5"/>
                <line x1="5" y1="8" x2="11" y2="8"/>
                <line x1="5" y1="10.5" x2="8.5" y2="10.5"/>
              </svg>
              <span class="node-label">{{ contrato.nombre }}</span>
              <div class="node-badges">
                <span class="count-badge">{{ contrato._activoCount }} activos</span>
                <button v-if="canWrite" class="quick-add-btn" title="Nuevo equipo en este contrato" @click.stop="openAssetForm(contrato.id)">+</button>
              </div>
            </div>

            <!-- Plantas -->
            <div v-if="expandedNodes.contratos.has(contrato.id)">
              <div v-for="planta in contrato.plantas" :key="planta.id" class="tree-planta">
                <div class="tree-row tree-row-planta" @click="toggleNode('planta', planta.id)">
                  <span class="indent-1"></span>
                  <span class="expand-icon">{{ expandedNodes.plantas.has(planta.id) ? '▼' : '▶' }}</span>
                  <svg class="node-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <rect x="1.5" y="7.5" width="13" height="7" rx="0.5"/>
                    <polyline points="1.5,7.5 4.5,3.5 8,6 11.5,2.5 14.5,7.5"/>
                  </svg>
                  <span class="node-label">{{ planta.nombre }}</span>
                  <span class="node-code">{{ planta.codigo }}</span>
                  <div class="node-badges">
                    <span class="count-badge">{{ planta._activoCount }} activos</span>
                    <button v-if="canWrite" class="quick-add-btn" title="Nuevo equipo en esta planta" @click.stop="openAssetForm(contrato.id, planta.id)">+</button>
                  </div>
                </div>

                <!-- Sistemas -->
                <div v-if="expandedNodes.plantas.has(planta.id)">
                  <div v-for="sistema in planta.sistemas" :key="sistema.id" class="tree-sistema">
                    <div class="tree-row tree-row-sistema" @click="toggleNode('sistema', sistema.id)">
                      <span class="indent-2"></span>
                      <span class="expand-icon">{{ expandedNodes.sistemas.has(sistema.id) ? '▼' : '▶' }}</span>
                      <svg class="node-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                        <circle cx="8" cy="3" r="1.5"/>
                        <circle cx="3" cy="13" r="1.5"/>
                        <circle cx="13" cy="13" r="1.5"/>
                        <line x1="8" y1="4.5" x2="3.8" y2="11.6"/>
                        <line x1="8" y1="4.5" x2="12.2" y2="11.6"/>
                        <line x1="4.5" y1="13" x2="11.5" y2="13"/>
                      </svg>
                      <span class="node-label">{{ sistema.nombre }}</span>
                      <span class="node-code">{{ sistema.codigo }}</span>
                      <div class="node-badges">
                        <span class="count-badge">{{ sistema.activos.length }}</span>
                        <button v-if="canWrite" class="quick-add-btn" title="Nuevo equipo en este sistema" @click.stop="openAssetForm(contrato.id, planta.id, sistema.id)">+</button>
                      </div>
                    </div>

                    <!-- Activos -->
                    <div v-if="expandedNodes.sistemas.has(sistema.id)">
                      <div
                        v-for="activo in sistema.activos"
                        :key="activo.id"
                        :class="['tree-row', 'tree-row-activo', `crit-${activo.criticidad}`, { selected: selectedActivoId === activo.id, match: !!search && isMatch(activo) }]"
                        @click="selectActivo(activo)"
                      >
                        <span class="indent-3"></span>
                        <span class="crit-bar"></span>
                        <svg class="node-icon-svg activo-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                          <rect x="3" y="3" width="10" height="10" rx="1.5"/>
                          <circle cx="8" cy="8" r="2.5"/>
                        </svg>
                        <div class="activo-info">
                          <span class="activo-tag">{{ activo.tag }}</span>
                          <span class="activo-name">{{ activo.nombre }}</span>
                        </div>
                        <div class="activo-right">
                          <button
                            v-if="canWrite"
                            class="quick-add-btn"
                            :title="`Registrar lectura en ${activo.tag}`"
                            @click.stop="openQuickReading(activo)"
                          >+</button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- Detail panel -->
      <div class="detail-panel card">
        <template v-if="selectedActivo">
          <div class="detail-header">
            <div :class="`detail-crit-bar crit-bar-${selectedActivo.criticidad}`"></div>
            <div class="detail-title-block">
              <div class="detail-tag">{{ selectedActivo.tag }}</div>
              <div class="detail-name">{{ selectedActivo.nombre }}</div>
              <div class="detail-meta">
                {{ selectedActivo.planta_nombre }} › {{ selectedActivo.sistema_nombre }}
              </div>
            </div>
            <div class="detail-badges">
              <span :class="`badge badge-${selectedActivo.criticidad}`">{{ selectedActivo.criticidad }}</span>
            </div>
          </div>

          <!-- Puntos de medición -->
          <div class="detail-section">
            <div class="detail-section-title">Puntos de Medición</div>
            <div v-if="loadingDetail" class="detail-loading"><div class="spinner" style="width:16px;height:16px;border-width:2px"></div></div>
            <div v-else-if="!detailPuntos.length" class="detail-empty">Sin puntos configurados</div>
            <div v-else class="detail-puntos">
              <div
                v-for="p in detailPuntos"
                :key="p.id"
                :class="['detail-punto', `estado-left-${getPuntoEstado(p)}`]"
                @click="openChart(p)"
              >
                <div class="dpunto-left">
                  <div class="dpunto-code">{{ p.codigo }}</div>
                  <div class="dpunto-name">{{ p.nombre }}</div>
                  <div class="dpunto-type">{{ p.tipo }}</div>
                </div>
                <div class="dpunto-right">
                  <div v-if="p.ultimo_valor !== null" class="dpunto-val">
                    {{ fmtVal(p.ultimo_valor) }}<span class="dpunto-unit"> {{ p.unidad }}</span>
                  </div>
                  <div v-else class="dpunto-nodata">—</div>
                  <span :class="`estado-badge estado-${getPuntoEstado(p)}`">
                    {{ ESTADO_LABELS[getPuntoEstado(p)] }}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Actions -->
          <div class="detail-actions">
            <button class="btn btn-primary" @click="openQuickReading(selectedActivo)">
              + Registrar Lectura
            </button>
            <RouterLink :to="`/activos/${selectedActivo.id}`" class="btn btn-secondary">
              Ver detalle completo →
            </RouterLink>
          </div>
        </template>

        <div v-else class="detail-placeholder">
          <svg class="placeholder-icon-svg" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="8" y="6" width="32" height="36" rx="2"/><line x1="14" y1="16" x2="34" y2="16"/><line x1="14" y1="22" x2="34" y2="22"/><line x1="14" y1="28" x2="24" y2="28"/></svg>
          <div>Selecciona un activo en el árbol para ver su detalle</div>
        </div>
      </div>
    </div>

    <!-- Quick reading modal -->
    <Teleport to="body">
      <div v-if="quickReadingActivo" class="modal-overlay" @click.self="quickReadingActivo = null">
        <div class="modal">
          <div class="modal-header">
            <div>
              <h4>Registrar Lectura</h4>
              <div class="modal-sub">{{ quickReadingActivo.tag }} — {{ quickReadingActivo.nombre }}</div>
            </div>
            <button class="modal-close" @click="quickReadingActivo = null">✕</button>
          </div>
          <div class="modal-body">
            <div v-if="loadingQRPuntos" class="detail-loading"><div class="spinner"></div></div>
            <div v-else-if="!quickPuntos.length" class="detail-empty">
              Este activo no tiene puntos de medición.
              <RouterLink to="/mediciones">Configurar en Mediciones</RouterLink>
            </div>
            <template v-else>
              <div class="field">
                <label>Punto de Medición *</label>
                <select v-model="qrPuntoId">
                  <option value="">Seleccionar punto</option>
                  <option v-for="p in quickPuntos" :key="p.id" :value="p.id">
                    {{ p.codigo }} — {{ p.nombre }} ({{ p.unidad }})
                  </option>
                </select>
              </div>
              <template v-if="qrSelectedPunto">
                <div class="field">
                  <label>Valor ({{ qrSelectedPunto.unidad }}) *</label>
                  <input v-model.number="qrValor" type="number" step="any" autofocus required />
                  <div v-if="qrValor !== null && qrValor !== ''" class="reading-preview">
                    <span :class="`estado-badge estado-${calcEstado(qrValor, qrSelectedPunto)}`">
                      {{ ESTADO_LABELS[calcEstado(qrValor, qrSelectedPunto)] }}
                    </span>
                    <span v-if="qrSelectedPunto.limite_alarma" class="limit-hint">
                      Alerta ≥ {{ qrSelectedPunto.limite_alerta }} / Alarma ≥ {{ qrSelectedPunto.limite_alarma }}
                    </span>
                  </div>
                </div>
                <div class="field">
                  <label>Notas</label>
                  <textarea v-model="qrNotas" rows="2"></textarea>
                </div>
              </template>
              <div v-if="qrError" class="error-alert">{{ qrError }}</div>
              <div class="modal-footer">
                <button class="btn btn-secondary" @click="quickReadingActivo = null">Cancelar</button>
                <button class="btn btn-primary" :disabled="!qrPuntoId || qrValor === null || qrSubmitting" @click="submitQuickReading">
                  {{ qrSubmitting ? 'Guardando...' : 'Guardar' }}
                </button>
              </div>
            </template>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Trend chart modal -->
    <Teleport to="body">
      <div v-if="chartPunto" class="modal-overlay" @click.self="chartPunto = null">
        <div class="modal modal-xl">
          <div class="modal-header">
            <div>
              <h4>{{ chartPunto.nombre }}</h4>
              <span class="modal-sub">{{ chartPunto.codigo }} · {{ chartPunto.unidad }}</span>
            </div>
            <button class="modal-close" @click="chartPunto = null">✕</button>
          </div>
          <div class="modal-body">
            <TrendChart :punto="chartPunto" />
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Asset create modal -->
    <Teleport to="body">
      <AssetFormModal
        v-if="assetFormOpen"
        :pre-contrato="assetFormContext.contrato"
        :pre-planta="assetFormContext.planta"
        :pre-sistema="assetFormContext.sistema"
        @close="assetFormOpen = false"
        @saved="onAssetSaved"
      />
    </Teleport>
  </div>
</template>

<script setup>
import { ref, computed, reactive, onMounted, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/services/api'
import TrendChart from '@/components/TrendChart.vue'
import AssetFormModal from '@/components/AssetFormModal.vue'

const auth = useAuthStore()

const CRITICIDADES = [
  { key: 'critico', label: 'Crítico' },
  { key: 'esencial', label: 'Esencial' },
  { key: 'general', label: 'General' },
]
const ESTADO_LABELS = { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: 'Sin datos' }  // still used by puntos section

// State
const rawTree = ref([])   // full hierarchy from API (contratos → plantas → sistemas → activos)
const loadingTree = ref(true)
const search = ref('')
const selectedActivoId = ref(null)
const selectedActivo = ref(null)
const detailPuntos = ref([])
const loadingDetail = ref(false)
const chartPunto = ref(null)

const filters = reactive({ criticidad: [] })

const expandedNodes = reactive({
  contratos: new Set(),
  plantas: new Set(),
  sistemas: new Set(),
})

// Asset form modal
const assetFormOpen = ref(false)
const assetFormContext = reactive({ contrato: '', planta: '', sistema: '' })

function openAssetForm(contrato = '', planta = '', sistema = '') {
  assetFormContext.contrato = contrato
  assetFormContext.planta = planta
  assetFormContext.sistema = sistema
  assetFormOpen.value = true
}

function onAssetSaved(activo) {
  assetFormOpen.value = false
  loadTree()
}

// Quick reading modal
const quickReadingActivo = ref(null)
const quickPuntos = ref([])
const loadingQRPuntos = ref(false)
const qrPuntoId = ref('')
const qrValor = ref(null)
const qrNotas = ref('')
const qrSubmitting = ref(false)
const qrError = ref('')

const canWrite = computed(() => ['admin', 'ingeniero_confiabilidad', 'supervisor', 'tecnico_campo'].includes(auth.user?.role))
const hasActiveFilters = computed(() => search.value || filters.criticidad.length)

const qrSelectedPunto = computed(() => quickPuntos.value.find((p) => p.id === qrPuntoId.value) || null)

// Filter + search logic
const filteredTree = computed(() => {
  return rawTree.value
    .map((contrato) => {
      const plantas = contrato.plantas
        .map((planta) => {
          const sistemas = planta.sistemas
            .map((sistema) => {
              const activos = sistema.activos.filter((a) => {
                if (filters.criticidad.length && !filters.criticidad.includes(a.criticidad)) return false
                if (search.value) {
                  const q = search.value.toLowerCase()
                  return a.tag.toLowerCase().includes(q) ||
                    a.nombre.toLowerCase().includes(q) ||
                    (a.codigo_sap || '').toLowerCase().includes(q)
                }
                return true
              })
              return { ...sistema, activos }
            })
            .filter((s) => s.activos.length)

          const activoCount = sistemas.reduce((n, s) => n + s.activos.length, 0)
          return { ...planta, sistemas, _activoCount: activoCount }
        })
        .filter((p) => p._activoCount > 0)

      const activoCount = plantas.reduce((n, p) => n + p._activoCount, 0)
      return { ...contrato, plantas, _activoCount: activoCount }
    })
    .filter((ct) => ct._activoCount > 0)
})

function isMatch(activo) {
  if (!search.value) return false
  const q = search.value.toLowerCase()
  return activo.tag.toLowerCase().includes(q) ||
    activo.nombre.toLowerCase().includes(q) ||
    (activo.codigo_sap || '').toLowerCase().includes(q)
}

function toggleFilter(type, val) {
  const arr = filters[type]
  const idx = arr.indexOf(val)
  if (idx === -1) arr.push(val)
  else arr.splice(idx, 1)
}

function clearFilters() {
  filters.criticidad = []
  search.value = ''
}

function toggleNode(type, id) {
  const setMap = { contrato: 'contratos', planta: 'plantas', sistema: 'sistemas' }
  const set = expandedNodes[setMap[type]]
  if (set.has(id)) set.delete(id)
  else set.add(id)
}

function expandAll(open) {
  rawTree.value.forEach((ct) => {
    if (open) expandedNodes.contratos.add(ct.id)
    else expandedNodes.contratos.delete(ct.id)
    ct.plantas.forEach((p) => {
      if (open) expandedNodes.plantas.add(p.id)
      else expandedNodes.plantas.delete(p.id)
      p.sistemas.forEach((s) => {
        if (open) expandedNodes.sistemas.add(s.id)
        else expandedNodes.sistemas.delete(s.id)
      })
    })
  })
}

async function selectActivo(activo) {
  selectedActivoId.value = activo.id
  selectedActivo.value = activo
  detailPuntos.value = []
  loadingDetail.value = true
  try {
    const { data } = await api.get('/measurements/latest', { params: { activo_id: activo.id } })
    detailPuntos.value = data.puntos
  } finally {
    loadingDetail.value = false
  }
}

function getPuntoEstado(punto) {
  if (punto.ultimo_valor === null) return 'desconocido'
  return calcEstado(punto.ultimo_valor, punto)
}

function calcEstado(valor, punto) {
  if (valor === null) return 'desconocido'
  if (punto.limite_alarma !== null && Number(valor) >= Number(punto.limite_alarma)) return 'critico'
  if (punto.limite_alerta !== null && Number(valor) >= Number(punto.limite_alerta)) return 'alerta'
  return 'bueno'
}

function fmtVal(v) {
  if (v === null) return '—'
  const n = Number(v)
  return n % 1 === 0 ? String(n) : n.toFixed(3)
}

function openChart(punto) { chartPunto.value = punto }

async function openQuickReading(activo) {
  quickReadingActivo.value = activo
  qrPuntoId.value = ''
  qrValor.value = null
  qrNotas.value = ''
  qrError.value = ''
  quickPuntos.value = []
  loadingQRPuntos.value = true
  try {
    const { data } = await api.get('/measurements/puntos', { params: { activo_id: activo.id } })
    quickPuntos.value = data.puntos
  } finally {
    loadingQRPuntos.value = false
  }
}

async function submitQuickReading() {
  qrSubmitting.value = true
  qrError.value = ''
  try {
    await api.post('/measurements/readings', {
      punto_id: qrPuntoId.value,
      valor: qrValor.value,
      notas: qrNotas.value || undefined,
    })
    quickReadingActivo.value = null

    // Refresh detail puntos
    if (selectedActivoId.value) {
      const { data } = await api.get('/measurements/latest', { params: { activo_id: selectedActivoId.value } })
      detailPuntos.value = data.puntos
    }
  } catch (err) {
    qrError.value = err.response?.data?.error || 'Error al guardar'
  } finally {
    qrSubmitting.value = false
  }
}

async function loadTree() {
  loadingTree.value = true
  try {
    const { data } = await api.get('/assets/tree/hierarchy')
    rawTree.value = data.tree

    // Auto-expand first contrato + its first planta + all its sistemas
    if (data.tree.length) {
      const firstContrato = data.tree[0]
      expandedNodes.contratos.add(firstContrato.id)
      if (firstContrato.plantas?.length) {
        const firstPlanta = firstContrato.plantas[0]
        expandedNodes.plantas.add(firstPlanta.id)
        firstPlanta.sistemas?.forEach((s) => expandedNodes.sistemas.add(s.id))
      }
    }
  } finally {
    loadingTree.value = false
  }
}

// Auto-expand search matches
watch(search, (q) => {
  if (!q) return
  rawTree.value.forEach((ct) => {
    ct.plantas?.forEach((p) => {
      const plantaHasMatch = p.sistemas?.some((s) => s.activos?.some((a) => isMatch(a)))
      if (plantaHasMatch) {
        expandedNodes.contratos.add(ct.id)
        expandedNodes.plantas.add(p.id)
        p.sistemas.forEach((s) => {
          if (s.activos.some((a) => isMatch(a))) expandedNodes.sistemas.add(s.id)
        })
      }
    })
  })
})

onMounted(loadTree)
</script>

<style scoped>
.asset-tree-view { display: flex; flex-direction: column; gap: 1rem; height: calc(100vh - 56px - 3rem); }

/* Controls */
.tree-controls {
  display: flex; align-items: center; gap: 1rem; flex-wrap: wrap; padding: 0.875rem 1.25rem; flex-shrink: 0;
}
.controls-left { flex: 1; min-width: 200px; }
.search-wrap { position: relative; display: flex; align-items: center; }
.search-icon { position: absolute; left: 0.625rem; font-size: 0.875rem; pointer-events: none; }
.search-input { width: 100%; padding: 0.5rem 2rem 0.5rem 2rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.875rem; }
.search-input:focus { outline: none; border-color: var(--color-brand); }
.search-clear { position: absolute; right: 0.5rem; background: none; border: none; cursor: pointer; color: var(--color-text-muted); font-size: 0.875rem; }

.controls-right { display: flex; align-items: center; gap: 1rem; flex-wrap: wrap; }
.filter-chips { display: flex; align-items: center; gap: 0.375rem; }
.filter-label { font-size: 0.75rem; color: var(--color-text-muted); white-space: nowrap; }
.chip { padding: 3px 10px; border-radius: 999px; border: 1px solid var(--color-border); background: #fff; font-size: 0.75rem; cursor: pointer; transition: all 0.15s; color: var(--color-text-secondary); }
.chip.active.chip-critico { background: #fef2f2; border-color: #dc2626; color: #dc2626; }
.chip.active.chip-esencial { background: #fffbeb; border-color: #d97706; color: #d97706; }
.chip.active.chip-general { background: #f0fdf4; border-color: #16a34a; color: #16a34a; }
.chip.active.chip-health-critico { background: #fef2f2; border-color: #dc2626; color: #dc2626; }
.chip.active.chip-health-alerta { background: #fffbeb; border-color: #d97706; color: #d97706; }
.chip.active.chip-health-bueno { background: #f0fdf4; border-color: #16a34a; color: #16a34a; }
.chip.active.chip-health-desconocido { background: var(--color-bg); border-color: var(--color-border); color: var(--color-text-muted); }

.view-toggles { display: flex; gap: 0.375rem; }
.toggle-btn { padding: 4px 8px; border: 1px solid var(--color-border); border-radius: 4px; background: #fff; font-size: 0.75rem; cursor: pointer; color: var(--color-text-secondary); }
.toggle-btn:hover, .toggle-btn.active { background: var(--color-brand); border-color: var(--color-brand); color: #fff; }

/* Panels */
.panels { display: grid; grid-template-columns: 380px 1fr; gap: 1rem; flex: 1; min-height: 0; }
@media (max-width: 900px) { .panels { grid-template-columns: 1fr; } }

.tree-panel { overflow-y: auto; padding: 0.75rem 0; }
.detail-panel { overflow-y: auto; padding: 1.5rem; display: flex; flex-direction: column; gap: 1.25rem; }

.tree-loading, .tree-empty { display: flex; align-items: center; justify-content: center; flex-direction: column; gap: 0.5rem; padding: 3rem; color: var(--color-text-muted); }

/* Tree rows */
.tree-row {
  display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 1rem;
  cursor: pointer; user-select: none; transition: background 0.1s;
}
.tree-row:hover { background: var(--color-bg); }

.tree-row-contrato { font-weight: 800; font-size: 1rem; color: var(--color-text-primary); background: var(--color-bg); border-bottom: 1px solid var(--color-border); }
.tree-row-planta { font-weight: 700; font-size: 0.9375rem; }
.tree-row-sistema { font-weight: 600; font-size: 0.875rem; color: var(--color-text-secondary); }
.tree-row-activo { font-size: 0.8125rem; }

.expand-icon { width: 12px; font-size: 0.6rem; color: var(--color-text-muted); flex-shrink: 0; }
.node-icon-svg { width: 15px; height: 15px; flex-shrink: 0; color: var(--color-text-muted); }
.tree-row-contrato .node-icon-svg { color: rgba(255,255,255,0.6); }
.tree-row-planta .node-icon-svg { color: var(--color-brand); opacity: 0.8; }
.tree-row-sistema .node-icon-svg { color: var(--color-text-secondary); }
.activo-icon-svg { width: 12px; height: 12px; color: var(--color-text-muted); }
.node-label { flex: 1; }
.node-code { font-size: 0.7rem; color: var(--color-text-muted); font-family: monospace; }
.node-badges { display: flex; align-items: center; gap: 0.375rem; }

.indent-1 { width: 20px; flex-shrink: 0; }
.indent-2 { width: 40px; flex-shrink: 0; }
.indent-3 { width: 60px; flex-shrink: 0; }

/* Crit bar on activo rows */
.crit-bar { width: 3px; height: 28px; border-radius: 2px; flex-shrink: 0; background: var(--color-border); }
.crit-critico .crit-bar { background: #dc2626; }
.crit-esencial .crit-bar { background: #d97706; }
.crit-general .crit-bar { background: #16a34a; }

.activo-info { flex: 1; }
.activo-tag { font-weight: 700; display: block; font-family: monospace; }
.activo-name { font-size: 0.75rem; color: var(--color-text-muted); display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 140px; }

.activo-right { display: flex; align-items: center; gap: 0.5rem; flex-shrink: 0; }

.count-badge { font-size: 0.7rem; background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 999px; padding: 0 6px; color: var(--color-text-muted); }

.quick-add-btn {
  width: 22px; height: 22px; border-radius: 50%; border: 1px solid var(--color-border);
  background: #fff; font-size: 0.875rem; cursor: pointer; display: flex; align-items: center; justify-content: center;
  color: var(--color-text-muted); line-height: 1; flex-shrink: 0; transition: all 0.15s;
}
.quick-add-btn:hover { background: var(--color-brand); border-color: var(--color-brand); color: #fff; }

.tree-row-activo.selected { background: var(--color-brand-light) !important; }
.tree-row-activo.match { background: #fef9e7; }

/* Detail panel */
.detail-header { display: flex; gap: 0.75rem; align-items: flex-start; }
.detail-crit-bar { width: 4px; border-radius: 2px; align-self: stretch; flex-shrink: 0; min-height: 60px; }
.crit-bar-critico { background: #dc2626; }
.crit-bar-esencial { background: #d97706; }
.crit-bar-general { background: #16a34a; }
.detail-title-block { flex: 1; }
.detail-tag { font-size: 0.75rem; font-family: monospace; color: var(--color-text-muted); }
.detail-name { font-size: 1.125rem; font-weight: 700; }
.detail-meta { font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.125rem; }
.detail-badges { display: flex; flex-direction: column; gap: 0.375rem; align-items: flex-end; }


.detail-section-title { font-size: 0.75rem; font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 0.625rem; }
.detail-loading, .detail-empty { display: flex; align-items: center; justify-content: center; gap: 0.5rem; padding: 1.5rem; color: var(--color-text-muted); font-size: 0.875rem; }

.detail-puntos { display: flex; flex-direction: column; gap: 0.5rem; }
.detail-punto {
  display: flex; justify-content: space-between; align-items: center;
  padding: 0.625rem 0.75rem; border-radius: 8px; background: var(--color-bg);
  border-left: 3px solid var(--color-border); cursor: pointer; transition: background 0.1s;
}
.detail-punto:hover { background: #eef0f3; }
.estado-left-bueno { border-left-color: #16a34a; }
.estado-left-alerta { border-left-color: #d97706; }
.estado-left-critico { border-left-color: #dc2626; }
.dpunto-code { font-size: 0.7rem; color: var(--color-text-muted); font-family: monospace; }
.dpunto-name { font-weight: 500; font-size: 0.8125rem; }
.dpunto-type { font-size: 0.7rem; color: var(--color-text-muted); }
.dpunto-right { text-align: right; }
.dpunto-val { font-size: 1.125rem; font-weight: 700; line-height: 1.2; }
.dpunto-unit { font-size: 0.7rem; font-weight: 400; color: var(--color-text-muted); }
.dpunto-nodata { font-size: 0.875rem; color: var(--color-text-muted); }

.estado-badge { display: inline-block; padding: 1px 6px; border-radius: 999px; font-size: 0.65rem; font-weight: 600; text-transform: uppercase; margin-top: 0.125rem; }
.estado-badge.estado-bueno { background: #f0fdf4; color: #16a34a; }
.estado-badge.estado-alerta { background: #fffbeb; color: #d97706; }
.estado-badge.estado-critico { background: #fef2f2; color: #dc2626; }
.estado-badge.estado-desconocido { background: var(--color-bg); color: var(--color-text-muted); }

.detail-actions { display: flex; gap: 0.75rem; flex-wrap: wrap; margin-top: auto; }

.detail-placeholder { display: flex; flex-direction: column; align-items: center; justify-content: center; flex: 1; color: var(--color-text-muted); font-size: 0.9375rem; gap: 0.75rem; }
.placeholder-icon-svg { width: 48px; height: 48px; color: var(--color-border); }

/* Modals */
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 1000; padding: 1rem; }
.modal { background: #fff; border-radius: 12px; width: 100%; max-width: 480px; max-height: 90vh; overflow-y: auto; box-shadow: 0 20px 60px rgba(0,0,0,0.2); }
.modal-xl { max-width: 860px; }
.modal-header { display: flex; align-items: flex-start; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-border); }
.modal-header h4 { font-size: 1rem; font-weight: 700; margin: 0; }
.modal-sub { font-size: 0.75rem; color: var(--color-text-muted); }
.modal-close { background: none; border: none; cursor: pointer; font-size: 1rem; color: var(--color-text-muted); margin-left: 1rem; flex-shrink: 0; }
.modal-body { padding: 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
.modal-footer { display: flex; gap: 0.75rem; justify-content: flex-end; margin-top: 0.25rem; }

.field label { display: block; font-size: 0.8rem; font-weight: 500; color: var(--color-text-secondary); margin-bottom: 0.25rem; }
.field input, .field select, .field textarea { width: 100%; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.875rem; font-family: inherit; }
.field input:focus, .field select:focus { outline: none; border-color: var(--color-brand); }
.reading-preview { margin-top: 0.5rem; display: flex; align-items: center; gap: 0.75rem; }
.limit-hint { font-size: 0.75rem; color: var(--color-text-muted); }
.error-alert { background: #fef2f2; border: 1px solid #fecaca; color: #dc2626; padding: 0.5rem 0.75rem; border-radius: 6px; font-size: 0.8125rem; }

.btn-sm { padding: 0.25rem 0.75rem; font-size: 0.8125rem; }
</style>
