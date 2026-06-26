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
                      <template v-for="activo in sistema.activos" :key="activo.id">
                        <!-- Activo row -->
                        <div
                          :class="['tree-row', 'tree-row-activo', `crit-${activo.criticidad}`, { expanded: expandedActivos.has(activo.id), match: !!search && isMatch(activo) }]"
                          @click="toggleActivo(activo)"
                        >
                          <span class="indent-3"></span>
                          <span class="expand-icon">{{ expandedActivos.has(activo.id) ? '▼' : '▶' }}</span>
                          <span class="crit-bar"></span>
                          <svg class="node-icon-svg activo-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                            <rect x="3" y="3" width="10" height="10" rx="1.5"/>
                            <circle cx="8" cy="8" r="2.5"/>
                          </svg>
                          <div class="activo-info">
                            <span class="activo-tag">{{ activo.tag }}</span>
                            <span class="activo-name">{{ activo.nombre }}</span>
                          </div>
                          <div class="activo-right"></div>
                        </div>

                        <!-- Component + technique expansion -->
                        <div v-if="expandedActivos.has(activo.id)" class="activo-children">
                          <div v-if="loadingActivoTree[activo.id]" class="tree-inline-loading">
                            <div class="spinner-xs"></div>
                          </div>
                          <template v-else-if="activoTreeData[activo.id]">
                            <!-- General node (union of all techniques) -->
                            <template v-if="activoTreeData[activo.id].generalTecnicas.length">
                              <div
                                :class="['tree-row', 'tree-row-comp', { expanded: expandedComps[activo.id]?.has('__general__') }]"
                                @click.stop="toggleComp(activo.id, '__general__')"
                              >
                                <span class="indent-4"></span>
                                <span class="expand-icon">{{ expandedComps[activo.id]?.has('__general__') ? '▼' : '▶' }}</span>
                                <svg class="node-icon-svg comp-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                                  <circle cx="8" cy="8" r="6"/>
                                  <line x1="8" y1="5" x2="8" y2="8"/>
                                  <line x1="8" y1="8" x2="10.5" y2="10.5"/>
                                </svg>
                                <span class="node-label">General</span>
                                <span class="count-badge">{{ activoTreeData[activo.id].generalTecnicas.length }}</span>
                              </div>
                              <template v-if="expandedComps[activo.id]?.has('__general__')">
                                <div
                                  v-for="tec in activoTreeData[activo.id].generalTecnicas"
                                  :key="tec.id"
                                  :class="['tree-row', 'tree-row-tecnica', { selected: selectedNode?.activoId === activo.id && selectedNode?.compKey === '__general__' && selectedNode?.tecnicaId === tec.id }]"
                                  @click.stop="selectTecnica(activo, null, tec)"
                                >
                                  <span class="indent-5"></span>
                                  <span class="tec-codigo">{{ tec.codigo }}</span>
                                  <span class="tec-nombre">{{ tec.nombre }}</span>
                                </div>
                              </template>
                            </template>

                            <!-- Per-component nodes -->
                            <template v-for="comp in activoTreeData[activo.id].componentes" :key="comp.id">
                              <div
                                :class="['tree-row', 'tree-row-comp', { expanded: expandedComps[activo.id]?.has(comp.id) }]"
                                @click.stop="toggleComp(activo.id, comp.id)"
                              >
                                <span class="indent-4"></span>
                                <span class="expand-icon">{{ expandedComps[activo.id]?.has(comp.id) ? '▼' : '▶' }}</span>
                                <svg class="node-icon-svg comp-icon-svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                                  <rect x="2" y="5" width="12" height="8" rx="1"/>
                                  <line x1="5" y1="5" x2="5" y2="3"/>
                                  <line x1="11" y1="5" x2="11" y2="3"/>
                                  <line x1="5" y1="3" x2="11" y2="3"/>
                                </svg>
                                <span class="node-label">{{ comp.nombre }}</span>
                                <span v-if="comp.tipo_nombre" class="node-code">{{ comp.tipo_nombre }}</span>
                                <span v-if="comp.tecnicas.length" class="count-badge">{{ comp.tecnicas.length }}</span>
                                <span v-else class="count-badge muted">Sin técnicas</span>
                              </div>
                              <template v-if="expandedComps[activo.id]?.has(comp.id)">
                                <div
                                  v-if="!comp.tecnicas.length"
                                  class="tree-row tree-row-tecnica no-tec"
                                >
                                  <span class="indent-5"></span>
                                  <span class="tec-nombre muted">Sin técnicas configuradas</span>
                                </div>
                                <div
                                  v-for="tec in comp.tecnicas"
                                  :key="tec.id"
                                  :class="['tree-row', 'tree-row-tecnica', { selected: selectedNode?.activoId === activo.id && selectedNode?.compKey === comp.id && selectedNode?.tecnicaId === tec.id }]"
                                  @click.stop="selectTecnica(activo, comp, tec)"
                                >
                                  <span class="indent-5"></span>
                                  <span class="tec-codigo">{{ tec.codigo }}</span>
                                  <span class="tec-nombre">{{ tec.nombre }}</span>
                                </div>
                              </template>
                            </template>

                            <div v-if="!activoTreeData[activo.id].componentes.length && !activoTreeData[activo.id].generalTecnicas.length" class="tree-row tree-row-tecnica no-tec">
                              <span class="indent-4"></span>
                              <span class="tec-nombre muted">Sin componentes configurados</span>
                            </div>
                          </template>
                        </div>
                      </template>
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

        <!-- State 1: Full inspection detail -->
        <template v-if="selectedNode && selectedInspeccion">
          <div class="detail-header">
            <button class="back-btn" @click="selectedInspeccion = null">← Volver</button>
            <div class="detail-title-block" style="margin-top:0.5rem">
              <div class="detail-tag">{{ selectedNode.activo.tag }}</div>
              <div class="detail-name">{{ selectedNode.activo.nombre }}</div>
              <div class="detail-meta">
                <span :class="`cond-badge cond-badge-${selectedInspeccion.inspeccion.condicion}`">
                  {{ COND_LABELS[selectedInspeccion.inspeccion.condicion] }}
                </span>
                &nbsp;{{ fmtDate(selectedInspeccion.inspeccion.fecha) }}
              </div>
            </div>
          </div>

          <div class="detail-section">
            <div class="detail-section-title">Información General</div>
            <div class="insp-detail-grid">
              <div class="insp-field"><span class="insp-label">Técnica</span><span>{{ selectedInspeccion.inspeccion.tecnica_codigo }} — {{ selectedInspeccion.inspeccion.tecnica_nombre }}</span></div>
              <div class="insp-field"><span class="insp-label">Componente</span><span>{{ selectedInspeccion.inspeccion.componente_nombre }}</span></div>
              <div class="insp-field"><span class="insp-label">Fecha</span><span>{{ fmtDateTime(selectedInspeccion.inspeccion.fecha) }}</span></div>
              <div class="insp-field"><span class="insp-label">Analista</span><span>{{ selectedInspeccion.inspeccion.analista || '—' }}</span></div>
              <div class="insp-field"><span class="insp-label">Est. Operacional</span><span>{{ ESTADOS_OP.find(e => e.value === selectedInspeccion.inspeccion.estado_operacional)?.label || selectedInspeccion.inspeccion.estado_operacional }}</span></div>
              <div v-if="selectedInspeccion.inspeccion.modo_falla" class="insp-field"><span class="insp-label">Modo de Falla</span><span>{{ selectedInspeccion.inspeccion.modo_falla }}</span></div>
              <div v-if="selectedInspeccion.inspeccion.norma_referencia" class="insp-field"><span class="insp-label">Norma</span><span>{{ selectedInspeccion.inspeccion.norma_referencia }}</span></div>
            </div>
            <div v-if="selectedInspeccion.inspeccion.observaciones" class="insp-obs">
              <span class="insp-label">Observaciones</span>
              <p>{{ selectedInspeccion.inspeccion.observaciones }}</p>
            </div>
          </div>

          <div v-if="selectedInspeccion.mediciones.length" class="detail-section">
            <div class="detail-section-title">Valores Medidos</div>
            <div class="mediciones-table">
              <div v-for="m in selectedInspeccion.mediciones" :key="m.id" class="medicion-row">
                <span class="med-nombre">{{ m.punto_nombre }}</span>
                <span class="med-valor">{{ m.valor ?? '—' }} <span class="med-unit">{{ m.unidad }}</span></span>
              </div>
            </div>
          </div>

          <div v-if="selectedInspeccion.archivos.length" class="detail-section">
            <div class="detail-section-title">Adjuntos</div>
            <div class="archivos-list">
              <button
                v-for="a in selectedInspeccion.archivos"
                :key="a.id"
                class="archivo-btn"
                @click="downloadArchivo(selectedInspeccion.inspeccion.id, a.id, a.nombre_original)"
              >
                📎 {{ a.nombre_original }}
              </button>
            </div>
          </div>
        </template>

        <!-- State 2: Inspection list for selected technique -->
        <template v-else-if="selectedNode">
          <div class="detail-header">
            <div class="detail-title-block">
              <div class="detail-tag">{{ selectedNode.activo.tag }}</div>
              <div class="detail-name">{{ selectedNode.activo.nombre }}</div>
              <div class="detail-meta">
                {{ selectedNode.comp ? selectedNode.comp.nombre : 'General' }}
                <span class="sep">›</span>
                <span class="tec-label">{{ selectedNode.tecnica.codigo }}</span> {{ selectedNode.tecnica.nombre }}
              </div>
            </div>
            <div>
              <button v-if="canWrite" class="btn btn-primary btn-sm" @click="openNewInspeccion">+ Agregar</button>
            </div>
          </div>

          <div v-if="loadingInspecciones" class="detail-loading"><div class="spinner" style="width:16px;height:16px;border-width:2px"></div></div>
          <div v-else-if="!inspecciones.length" class="detail-empty">Sin registros para esta técnica y componente</div>
          <div v-else class="insp-list">
            <div
              v-for="insp in inspecciones"
              :key="insp.id"
              class="insp-list-row"
              @click="selectInspeccion(insp.id)"
            >
              <div class="insp-list-left">
                <span :class="`cond-badge cond-badge-${insp.condicion}`">{{ COND_LABELS[insp.condicion] }}</span>
                <span class="insp-list-fecha">{{ fmtDate(insp.fecha) }}</span>
              </div>
              <div class="insp-list-right">
                <span v-if="insp.analista" class="insp-list-analista">{{ insp.analista }}</span>
                <span v-if="insp.observaciones" class="insp-list-obs">{{ insp.observaciones }}</span>
              </div>
              <span class="insp-list-arrow">›</span>
            </div>
          </div>
        </template>

        <!-- State 3: Nothing selected -->
        <div v-else class="detail-placeholder">
          <svg class="placeholder-icon-svg" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="8" y="6" width="32" height="36" rx="2"/><line x1="14" y1="16" x2="34" y2="16"/><line x1="14" y1="22" x2="34" y2="22"/><line x1="14" y1="28" x2="24" y2="28"/></svg>
          <div>Selecciona una técnica en el árbol para ver sus registros</div>
        </div>
      </div>
    </div>

    <!-- New Inspection modal -->
    <Teleport to="body">
      <div v-if="newInspModal.open" class="modal-overlay" @click.self="newInspModal.open = false">
        <div class="modal modal-insp">
          <div class="modal-header">
            <div>
              <h4>Registrar Inspección</h4>
              <div class="modal-sub">{{ selectedNode?.activo?.tag }} — {{ selectedNode?.activo?.nombre }}</div>
            </div>
            <button class="modal-close" @click="newInspModal.open = false">✕</button>
          </div>
          <div class="modal-body">
            <!-- Step 1: component + technique -->
            <div class="field-row-2">
              <div class="field">
                <label>Componente *</label>
                <select v-model="newInspModal.componente_id" @change="onComponenteChange">
                  <option value="">Seleccionar componente…</option>
                  <option v-for="c in newInspModal.componentes" :key="c.id" :value="c.id">
                    {{ c.nombre }} <span v-if="c.tipo_nombre">({{ c.tipo_nombre }})</span>
                  </option>
                </select>
              </div>
              <div class="field">
                <label>Técnica *</label>
                <select v-model="newInspModal.tecnica_id" :disabled="!newInspModal.componente_id" @change="onTecnicaChange">
                  <option value="">Seleccionar técnica…</option>
                  <option v-for="t in newInspModal.tecnicasDisponibles" :key="t.id" :value="t.id">
                    {{ t.codigo }} — {{ t.nombre }}
                  </option>
                </select>
              </div>
            </div>

            <div class="field-row-2">
              <div class="field">
                <label>Fecha *</label>
                <input type="datetime-local" v-model="newInspModal.fecha" />
              </div>
              <div class="field">
                <label>Analista</label>
                <input type="text" v-model="newInspModal.analista" placeholder="Nombre del analista" />
              </div>
            </div>

            <!-- Failure mode (optional, appears once technique is selected) -->
            <div v-if="newInspModal.modos_falla.length" class="field">
              <label>Modo de Falla <span class="optional">(opcional)</span></label>
              <select v-model="newInspModal.modo_falla_id">
                <option value="">Sin modo de falla identificado</option>
                <option v-for="m in newInspModal.modos_falla" :key="m.id" :value="m.id">
                  {{ m.modo_falla }}
                </option>
              </select>
            </div>

            <div class="field-row-2">
              <div class="field">
                <label>Estado Operacional *</label>
                <select v-model="newInspModal.estado_operacional">
                  <option v-for="e in ESTADOS_OP" :key="e.value" :value="e.value">{{ e.label }}</option>
                </select>
              </div>
              <div class="field">
                <label>Condición General *</label>
                <div class="cond-radio-group">
                  <label v-for="c in CONDICIONES" :key="c.value" :class="['cond-radio', `cond-radio-${c.value}`, { selected: newInspModal.condicion === c.value }]">
                    <input type="radio" :value="c.value" v-model="newInspModal.condicion" />
                    {{ c.label }}
                  </label>
                </div>
              </div>
            </div>

            <!-- Measuring points (optional) -->
            <div v-if="newInspModal.puntos.length" class="puntos-section">
              <div class="puntos-section-title">Valores Medidos <span class="optional">(opcional)</span></div>
              <div class="puntos-inputs">
                <div v-for="p in newInspModal.puntos" :key="p.id" class="punto-input-row">
                  <label class="punto-input-label">
                    {{ p.nombre }}
                    <span class="punto-input-unit">{{ p.unidad }}</span>
                  </label>
                  <input
                    type="number"
                    step="any"
                    v-model.number="newInspModal.valores[p.id]"
                    class="punto-input"
                    placeholder="—"
                  />
                </div>
              </div>
            </div>

            <div class="field">
              <label>Observaciones</label>
              <textarea v-model="newInspModal.observaciones" rows="2" placeholder="Observaciones generales…"></textarea>
            </div>

            <div class="field">
              <label>Adjuntos <span class="optional">(informes, fotos…)</span></label>
              <label class="file-upload-btn">
                <input type="file" multiple accept=".pdf,.doc,.docx,.xls,.xlsx,.png,.jpg,.jpeg" @change="onArchivosChange" style="display:none" />
                + Seleccionar archivos
              </label>
              <div v-if="newInspModal.archivos.length" class="file-list">
                <div v-for="(f, i) in newInspModal.archivos" :key="i" class="file-item">
                  <span class="file-name">{{ f.name }}</span>
                  <span class="file-size">({{ (f.size / 1024).toFixed(0) }} KB)</span>
                </div>
              </div>
            </div>

            <div v-if="newInspModal.error" class="error-alert">{{ newInspModal.error }}</div>
            <div class="modal-footer">
              <button class="btn btn-secondary" @click="newInspModal.open = false">Cancelar</button>
              <button class="btn btn-primary"
                :disabled="!newInspModal.componente_id || !newInspModal.tecnica_id || !newInspModal.condicion || newInspModal.saving"
                @click="submitInspeccion">
                {{ newInspModal.saving ? 'Guardando…' : 'Guardar' }}
              </button>
            </div>
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
import AssetFormModal from '@/components/AssetFormModal.vue'

const auth = useAuthStore()

const CRITICIDADES = [
  { key: 'critico', label: 'Crítico' },
  { key: 'esencial', label: 'Esencial' },
  { key: 'general', label: 'General' },
]
const COND_LABELS = { normal: 'Normal', observacion: 'Observación', alerta: 'Alerta', urgencia: 'Urgencia' }
const CONDICIONES = [
  { value: 'normal', label: 'Normal' },
  { value: 'observacion', label: 'Observación' },
  { value: 'alerta', label: 'Alerta' },
  { value: 'urgencia', label: 'Urgencia' },
]
const ESTADOS_OP = [
  { value: 'operativo',          label: 'Operativo' },
  { value: 'operativo_limitado', label: 'Op. Limitado' },
  { value: 'stand_by',           label: 'Stand By' },
  { value: 'fuera_de_servicio',  label: 'Fuera de Servicio' },
  { value: 'dado_de_baja',       label: 'Dado de Baja' },
]

// ─── Tree state ──────────────────────────────────────────────────────────────
const rawTree = ref([])
const loadingTree = ref(true)
const search = ref('')
const filters = reactive({ criticidad: [] })

const expandedNodes = reactive({
  contratos: new Set(),
  plantas: new Set(),
  sistemas: new Set(),
})

// Activo expansion (opens component/technique sub-tree)
const expandedActivos = reactive(new Set())
// Per-activo tree data (loaded on first expand)
const loadingActivoTree = reactive({})    // activo_id → boolean
const activoTreeData = reactive({})       // activo_id → { componentes, generalTecnicas }
// Per-activo expanded components/general nodes
const expandedComps = reactive({})        // activo_id → Set<compKey>

// ─── Detail panel state ───────────────────────────────────────────────────────
// selectedNode: { activoId, activo, compKey, comp (null=general), tecnicaId, tecnica }
const selectedNode = ref(null)
const inspecciones = ref([])
const loadingInspecciones = ref(false)
const selectedInspeccion = ref(null)   // full detail: { inspeccion, mediciones, archivos }
const loadingInspeccion = ref(false)

// ─── Asset form modal ─────────────────────────────────────────────────────────
const assetFormOpen = ref(false)
const assetFormContext = reactive({ contrato: '', planta: '', sistema: '' })

function openAssetForm(contrato = '', planta = '', sistema = '') {
  assetFormContext.contrato = contrato
  assetFormContext.planta = planta
  assetFormContext.sistema = sistema
  assetFormOpen.value = true
}

function onAssetSaved() {
  assetFormOpen.value = false
  loadTree()
}

// ─── New inspection modal ────────────────────────────────────────────────────
const newInspModal = reactive({
  open: false,
  saving: false,
  error: '',
  componentes: [],
  tecnicasDisponibles: [],
  modos_falla: [],
  puntos: [],
  valores: {},
  componente_id: '',
  tecnica_id: '',
  modo_falla_id: '',
  fecha: new Date().toISOString().slice(0, 16),
  analista: '',
  estado_operacional: 'operativo',
  condicion: '',
  observaciones: '',
  archivos: [],
})

const canWrite = computed(() => ['admin', 'ingeniero_confiabilidad', 'supervisor', 'tecnico_campo'].includes(auth.user?.role))
const hasActiveFilters = computed(() => search.value || filters.criticidad.length)

// ─── Filter + search ──────────────────────────────────────────────────────────
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

// ─── Tree toggle functions ─────────────────────────────────────────────────────
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

async function toggleActivo(activo) {
  if (expandedActivos.has(activo.id)) {
    expandedActivos.delete(activo.id)
    // Clear selection if it was inside this activo
    if (selectedNode.value?.activoId === activo.id) {
      selectedNode.value = null
      inspecciones.value = []
      selectedInspeccion.value = null
    }
  } else {
    expandedActivos.add(activo.id)
    // Load component+technique tree if not cached
    if (!activoTreeData[activo.id]) {
      loadingActivoTree[activo.id] = true
      try {
        const { data } = await api.get('/inspections/activo-tree', { params: { activo_id: activo.id } })
        activoTreeData[activo.id] = data
        expandedComps[activo.id] = reactive(new Set())
      } catch { /* ignore */ } finally {
        loadingActivoTree[activo.id] = false
      }
    }
  }
}

function toggleComp(activoId, compKey) {
  if (!expandedComps[activoId]) expandedComps[activoId] = reactive(new Set())
  const set = expandedComps[activoId]
  if (set.has(compKey)) set.delete(compKey)
  else set.add(compKey)
}

async function selectTecnica(activo, comp, tecnica) {
  selectedNode.value = {
    activoId: activo.id,
    activo,
    compKey: comp ? comp.id : '__general__',
    comp,
    tecnicaId: tecnica.id,
    tecnica,
  }
  selectedInspeccion.value = null
  inspecciones.value = []
  loadingInspecciones.value = true
  try {
    const params = { tecnica_id: tecnica.id, limit: 100 }
    if (comp) params.componente_id = comp.id
    else params.activo_id = activo.id
    const { data } = await api.get('/inspections/inspecciones', { params })
    inspecciones.value = data.inspecciones
  } catch { /* ignore */ } finally {
    loadingInspecciones.value = false
  }
}

async function selectInspeccion(id) {
  loadingInspeccion.value = true
  try {
    const { data } = await api.get(`/inspections/inspecciones/${id}`)
    selectedInspeccion.value = data
  } catch { /* ignore */ } finally {
    loadingInspeccion.value = false
  }
}

// ─── Inspection registration modal ────────────────────────────────────────────
function openNewInspeccion() {
  const node = selectedNode.value
  const treeData = node ? activoTreeData[node.activoId] : null

  newInspModal.open = true
  newInspModal.error = ''
  newInspModal.saving = false
  newInspModal.componentes = treeData?.componentes || []
  newInspModal.tecnicasDisponibles = []
  newInspModal.modos_falla = []
  newInspModal.puntos = []
  newInspModal.valores = {}
  newInspModal.condicion = ''
  newInspModal.observaciones = ''
  newInspModal.analista = auth.user ? `${auth.user.nombre} ${auth.user.apellido}`.trim() : ''
  newInspModal.fecha = new Date().toISOString().slice(0, 16)
  newInspModal.estado_operacional = 'operativo'
  newInspModal.archivos = []

  // Pre-fill from selected node
  if (node?.comp) {
    newInspModal.componente_id = node.comp.id
    newInspModal.tecnicasDisponibles = node.comp.tecnicas || []
    newInspModal.tecnica_id = node.tecnica.id
    onTecnicaChange()
  } else if (node) {
    // General: let user pick component
    newInspModal.componente_id = ''
    newInspModal.tecnica_id = node.tecnica.id
  } else {
    newInspModal.componente_id = ''
    newInspModal.tecnica_id = ''
  }
}

async function onComponenteChange() {
  newInspModal.tecnica_id = ''
  newInspModal.tecnicasDisponibles = []
  newInspModal.modos_falla = []
  newInspModal.modo_falla_id = ''
  newInspModal.puntos = []
  newInspModal.valores = {}
  if (!newInspModal.componente_id) return
  const node = selectedNode.value
  const treeData = node ? activoTreeData[node.activoId] : null
  const comp = treeData?.componentes.find((c) => c.id === newInspModal.componente_id)
  newInspModal.tecnicasDisponibles = comp?.tecnicas || []
}

async function onTecnicaChange() {
  newInspModal.puntos = []
  newInspModal.valores = {}
  newInspModal.modos_falla = []
  newInspModal.modo_falla_id = ''
  if (!newInspModal.tecnica_id) return
  const node = selectedNode.value
  const treeData = node ? activoTreeData[node.activoId] : null
  const comp = treeData?.componentes.find((c) => c.id === newInspModal.componente_id)
  try {
    const [puntosRes, modosRes] = await Promise.all([
      api.get('/inspections/puntos-tecnica', { params: { tecnica_id: newInspModal.tecnica_id } }),
      comp?.tipo_componente_id
        ? api.get('/inspections/modos-falla', { params: { tecnica_id: newInspModal.tecnica_id, tipo_componente_id: comp.tipo_componente_id } })
        : Promise.resolve({ data: { modos: [] } }),
    ])
    newInspModal.puntos = puntosRes.data.puntos
    newInspModal.modos_falla = modosRes.data.modos
  } catch { /* ignore */ }
}

function onArchivosChange(e) {
  newInspModal.archivos = Array.from(e.target.files || [])
}

async function submitInspeccion() {
  newInspModal.saving = true
  newInspModal.error = ''
  try {
    const { data } = await api.post('/inspections/inspecciones', {
      componente_id: newInspModal.componente_id,
      tecnica_id: newInspModal.tecnica_id,
      modo_falla_id: newInspModal.modo_falla_id || null,
      fecha: new Date(newInspModal.fecha).toISOString(),
      analista: newInspModal.analista || null,
      estado_operacional: newInspModal.estado_operacional,
      condicion: newInspModal.condicion,
      observaciones: newInspModal.observaciones || null,
    })

    const inspId = data.inspeccion.id

    // Save measurement values if any were filled
    const mediciones = newInspModal.puntos
      .filter((p) => newInspModal.valores[p.id] !== undefined && newInspModal.valores[p.id] !== null && newInspModal.valores[p.id] !== '')
      .map((p) => ({ punto_id: p.id, valor: newInspModal.valores[p.id] }))

    if (mediciones.length) {
      await api.put(`/inspections/inspecciones/${inspId}/mediciones`, { mediciones })
    }

    // Upload attached files
    for (const file of newInspModal.archivos) {
      const fd = new FormData()
      fd.append('archivo', file)
      fd.append('tipo', 'informe')
      await api.post(`/inspections/inspecciones/${inspId}/archivos`, fd)
    }

    newInspModal.open = false

    // Refresh the inspection list in the detail panel
    if (selectedNode.value) {
      const params = { tecnica_id: selectedNode.value.tecnicaId, limit: 100 }
      if (selectedNode.value.comp) params.componente_id = selectedNode.value.comp.id
      else params.activo_id = selectedNode.value.activoId
      const { data: refreshed } = await api.get('/inspections/inspecciones', { params })
      inspecciones.value = refreshed.inspecciones
    }
  } catch (err) {
    newInspModal.error = err.response?.data?.error || 'Error al guardar la inspección'
  } finally {
    newInspModal.saving = false
  }
}

async function downloadArchivo(inspId, archivoId, filename) {
  try {
    const { data } = await api.get(`/inspections/inspecciones/${inspId}/archivos/${archivoId}/download`)
    const a = document.createElement('a')
    a.href = data.url
    a.download = filename
    a.target = '_blank'
    a.click()
  } catch { /* ignore */ }
}

// ─── Format helpers ───────────────────────────────────────────────────────────
function fmtDate(d) {
  if (!d) return ''
  return new Date(d).toLocaleDateString('es-CO', { day: '2-digit', month: 'short', year: 'numeric' })
}

function fmtDateTime(d) {
  if (!d) return ''
  return new Date(d).toLocaleString('es-CO', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

// ─── Tree loading ─────────────────────────────────────────────────────────────
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

.view-toggles { display: flex; gap: 0.375rem; }
.toggle-btn { padding: 4px 8px; border: 1px solid var(--color-border); border-radius: 4px; background: #fff; font-size: 0.75rem; cursor: pointer; color: var(--color-text-secondary); }
.toggle-btn:hover, .toggle-btn.active { background: var(--color-brand); border-color: var(--color-brand); color: #fff; }

/* Panels */
.panels { display: grid; grid-template-columns: 400px 1fr; gap: 1rem; flex: 1; min-height: 0; }
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

/* Component row (level 4) */
.tree-row-comp {
  font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary);
  border-left: 2px solid transparent;
}
.tree-row-comp.expanded { border-left-color: var(--color-brand); background: #f8faff; }
.tree-row-comp:hover { background: #f0f4ff; }

/* Technique row (level 5) */
.tree-row-tecnica {
  font-size: 0.775rem; color: var(--color-text-secondary); padding: 0.375rem 1rem;
}
.tree-row-tecnica.selected { background: var(--color-brand-light) !important; }
.tree-row-tecnica.selected .tec-codigo, .tree-row-tecnica.selected .tec-nombre { color: var(--color-brand); }
.tree-row-tecnica:not(.no-tec):hover { background: #eef4ff; }
.tree-row-tecnica.no-tec { cursor: default; }

.tec-codigo { font-family: monospace; font-size: 0.7rem; color: var(--color-text-muted); text-transform: uppercase; margin-right: 0.375rem; flex-shrink: 0; }
.tec-nombre { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tec-nombre.muted { color: var(--color-text-muted); font-style: italic; font-weight: 400; }

.expand-icon { width: 12px; font-size: 0.6rem; color: var(--color-text-muted); flex-shrink: 0; }
.node-icon-svg { width: 15px; height: 15px; flex-shrink: 0; color: var(--color-text-muted); }
.tree-row-contrato .node-icon-svg { color: rgba(255,255,255,0.6); }
.tree-row-planta .node-icon-svg { color: var(--color-brand); opacity: 0.8; }
.tree-row-sistema .node-icon-svg { color: var(--color-text-secondary); }
.activo-icon-svg { width: 12px; height: 12px; color: var(--color-text-muted); }
.comp-icon-svg { width: 12px; height: 12px; color: var(--color-brand); opacity: 0.7; }
.node-label { flex: 1; }
.node-code { font-size: 0.7rem; color: var(--color-text-muted); font-family: monospace; }
.node-badges { display: flex; align-items: center; gap: 0.375rem; }

.indent-1 { width: 20px; flex-shrink: 0; }
.indent-2 { width: 40px; flex-shrink: 0; }
.indent-3 { width: 60px; flex-shrink: 0; }
.indent-4 { width: 76px; flex-shrink: 0; }
.indent-5 { width: 92px; flex-shrink: 0; }

/* Crit bar on activo rows */
.crit-bar { width: 3px; height: 28px; border-radius: 2px; flex-shrink: 0; background: var(--color-border); }
.crit-critico .crit-bar { background: #dc2626; }
.crit-esencial .crit-bar { background: #d97706; }
.crit-general .crit-bar { background: #16a34a; }

.activo-info { flex: 1; }
.activo-tag { font-weight: 700; display: block; font-family: monospace; }
.activo-name { font-size: 0.75rem; color: var(--color-text-muted); display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 140px; }
.activo-right { display: flex; align-items: center; gap: 0.5rem; flex-shrink: 0; }

.tree-row-activo.expanded { background: #f5f8ff; }
.tree-row-activo.match { background: #fef9e7; }

.count-badge { font-size: 0.7rem; background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 999px; padding: 0 6px; color: var(--color-text-muted); flex-shrink: 0; }
.count-badge.muted { opacity: 0.5; }

.quick-add-btn {
  width: 22px; height: 22px; border-radius: 50%; border: 1px solid var(--color-border);
  background: #fff; font-size: 0.875rem; cursor: pointer; display: flex; align-items: center; justify-content: center;
  color: var(--color-text-muted); line-height: 1; flex-shrink: 0; transition: all 0.15s;
}
.quick-add-btn:hover { background: var(--color-brand); border-color: var(--color-brand); color: #fff; }

/* Inline loading inside activo expansion */
.tree-inline-loading { display: flex; align-items: center; padding: 0.5rem 1rem 0.5rem 96px; }
.spinner-xs { width: 12px; height: 12px; border: 2px solid var(--color-border); border-top-color: var(--color-brand); border-radius: 50%; animation: spin 0.6s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

/* Detail panel */
.detail-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 0.75rem; }
.detail-title-block { flex: 1; min-width: 0; }
.detail-tag { font-size: 0.75rem; font-family: monospace; color: var(--color-text-muted); }
.detail-name { font-size: 1.125rem; font-weight: 700; }
.detail-meta { font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.25rem; display: flex; align-items: center; gap: 0.375rem; flex-wrap: wrap; }
.sep { color: var(--color-border); }
.tec-label { font-family: monospace; font-size: 0.75rem; }

.detail-section { display: flex; flex-direction: column; gap: 0.5rem; }
.detail-section-title { font-size: 0.75rem; font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; }
.detail-loading, .detail-empty { display: flex; align-items: center; justify-content: center; gap: 0.5rem; padding: 1.5rem; color: var(--color-text-muted); font-size: 0.875rem; }

.back-btn { background: none; border: none; cursor: pointer; color: var(--color-brand); font-size: 0.8125rem; padding: 0.25rem 0; font-weight: 600; }
.back-btn:hover { text-decoration: underline; }

/* Inspection detail fields */
.insp-detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem 1rem; }
.insp-field { display: flex; flex-direction: column; gap: 0.125rem; font-size: 0.8125rem; }
.insp-label { font-size: 0.7rem; font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.03em; }
.insp-obs p { font-size: 0.8125rem; color: var(--color-text-primary); margin: 0.25rem 0 0; white-space: pre-wrap; }

/* Measurements */
.mediciones-table { display: flex; flex-direction: column; gap: 0.25rem; }
.medicion-row { display: flex; justify-content: space-between; align-items: center; padding: 0.375rem 0.5rem; background: var(--color-bg); border-radius: 5px; font-size: 0.8125rem; }
.med-nombre { color: var(--color-text-secondary); }
.med-valor { font-weight: 600; font-family: monospace; }
.med-unit { font-family: inherit; font-weight: 400; font-size: 0.7rem; color: var(--color-text-muted); margin-left: 0.25rem; }

/* Attachments */
.archivos-list { display: flex; flex-direction: column; gap: 0.375rem; }
.archivo-btn { background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 6px; padding: 0.375rem 0.625rem; font-size: 0.8125rem; cursor: pointer; text-align: left; color: var(--color-brand); transition: background 0.1s; }
.archivo-btn:hover { background: #eef4ff; }

/* Inspection list (right panel) */
.insp-list { display: flex; flex-direction: column; gap: 0; }
.insp-list-row {
  display: flex; align-items: center; gap: 0.75rem; padding: 0.75rem 0.875rem;
  border-bottom: 1px solid var(--color-border); cursor: pointer; transition: background 0.1s;
}
.insp-list-row:hover { background: #f5f8ff; }
.insp-list-left { display: flex; align-items: center; gap: 0.5rem; flex-shrink: 0; }
.insp-list-fecha { font-size: 0.8rem; color: var(--color-text-muted); white-space: nowrap; }
.insp-list-right { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 0.125rem; }
.insp-list-analista { font-size: 0.775rem; color: var(--color-text-secondary); font-style: italic; }
.insp-list-obs { font-size: 0.775rem; color: var(--color-text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.insp-list-arrow { color: var(--color-text-muted); flex-shrink: 0; font-size: 1rem; }

/* Condition badges */
.cond-badge { display: inline-block; padding: 2px 7px; border-radius: 999px; font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.03em; white-space: nowrap; }
.cond-badge-normal { background: #f0fdf4; color: #15803d; }
.cond-badge-observacion { background: #eff6ff; color: #1d4ed8; }
.cond-badge-alerta { background: #fffbeb; color: #b45309; }
.cond-badge-urgencia { background: #fef2f2; color: #dc2626; }

.detail-placeholder { display: flex; flex-direction: column; align-items: center; justify-content: center; flex: 1; color: var(--color-text-muted); font-size: 0.9375rem; gap: 0.75rem; text-align: center; }
.placeholder-icon-svg { width: 48px; height: 48px; color: var(--color-border); }

/* Modals */
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 1000; padding: 1rem; }
.modal { background: #fff; border-radius: 12px; width: 100%; max-width: 480px; max-height: 90vh; overflow-y: auto; box-shadow: 0 20px 60px rgba(0,0,0,0.2); }
.modal-insp { max-width: 580px; }
.modal-header { display: flex; align-items: flex-start; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-border); }
.modal-header h4 { font-size: 1rem; font-weight: 700; margin: 0; }
.modal-sub { font-size: 0.75rem; color: var(--color-text-muted); }
.modal-close { background: none; border: none; cursor: pointer; font-size: 1rem; color: var(--color-text-muted); margin-left: 1rem; flex-shrink: 0; }
.modal-body { padding: 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
.modal-footer { display: flex; gap: 0.75rem; justify-content: flex-end; margin-top: 0.25rem; }

.field label { display: block; font-size: 0.8rem; font-weight: 500; color: var(--color-text-secondary); margin-bottom: 0.25rem; }
.field input, .field select, .field textarea { width: 100%; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.875rem; font-family: inherit; }
.field input:focus, .field select:focus, .field textarea:focus { outline: none; border-color: var(--color-brand); }
.field-row-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }

/* Condition radio group */
.cond-radio-group { display: flex; gap: 0.375rem; flex-wrap: wrap; }
.cond-radio { display: flex; align-items: center; gap: 0.25rem; padding: 0.3rem 0.625rem; border-radius: 6px; border: 1.5px solid var(--color-border); cursor: pointer; font-size: 0.8125rem; font-weight: 500; transition: all 0.1s; }
.cond-radio input[type="radio"] { display: none; }
.cond-radio-normal.selected { background: #f0fdf4; border-color: #16a34a; color: #15803d; }
.cond-radio-observacion.selected { background: #eff6ff; border-color: #3b82f6; color: #1d4ed8; }
.cond-radio-alerta.selected { background: #fffbeb; border-color: #f59e0b; color: #b45309; }
.cond-radio-urgencia.selected { background: #fef2f2; border-color: #ef4444; color: #dc2626; }
.cond-radio:hover:not(.selected) { background: #f8f9fa; border-color: #94a3b8; }

/* Measuring points inputs */
.puntos-section { border: 1px solid var(--color-border); border-radius: 8px; padding: 0.75rem; }
.puntos-section-title { font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary); margin-bottom: 0.625rem; }
.optional { font-weight: 400; color: var(--color-text-muted); font-style: italic; margin-left: 0.25rem; }
.puntos-inputs { display: flex; flex-direction: column; gap: 0.5rem; }
.punto-input-row { display: flex; align-items: center; gap: 0.5rem; }
.punto-input-label { flex: 1; font-size: 0.8125rem; color: var(--color-text-secondary); }
.punto-input-unit { font-size: 0.7rem; color: var(--color-text-muted); margin-left: 0.25rem; }
.punto-input { width: 100px; padding: 0.25rem 0.5rem; border: 1px solid var(--color-border); border-radius: 5px; font-size: 0.875rem; text-align: right; flex-shrink: 0; }
.punto-input:focus { outline: none; border-color: var(--color-brand); }

.file-upload-btn {
  display: inline-block; padding: 0.375rem 0.75rem; border: 1.5px dashed var(--color-border);
  border-radius: 6px; font-size: 0.8125rem; cursor: pointer; color: var(--color-brand);
  transition: background 0.1s; margin-top: 0.25rem;
}
.file-upload-btn:hover { background: #eff6ff; border-color: var(--color-brand); }
.file-list { margin-top: 0.5rem; display: flex; flex-direction: column; gap: 0.25rem; }
.file-item { display: flex; gap: 0.5rem; align-items: baseline; font-size: 0.8125rem; }
.file-name { font-weight: 500; }
.file-size { color: var(--color-text-muted); font-size: 0.75rem; }

.error-alert { background: #fef2f2; border: 1px solid #fecaca; color: #dc2626; padding: 0.5rem 0.75rem; border-radius: 6px; font-size: 0.8125rem; }

.btn-sm { padding: 0.25rem 0.75rem; font-size: 0.8125rem; }
</style>
