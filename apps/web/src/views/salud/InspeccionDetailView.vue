<template>
  <div class="insp-detail-view">
    <div v-if="loading" class="loading-state">Cargando inspección…</div>
    <div v-else-if="!inspeccion" class="error-state">Inspección no encontrada.</div>

    <template v-else>
      <!-- Breadcrumb -->
      <nav class="breadcrumb">
        <RouterLink to="/salud">Salud de Equipos</RouterLink>
        <span class="sep">›</span>
        <RouterLink :to="`/activos/${inspeccion.activo_id}`">{{ inspeccion.tag }} — {{ inspeccion.activo_nombre }}</RouterLink>
        <span class="sep">›</span>
        <span>Inspección {{ inspeccion.tecnica_codigo }}</span>
      </nav>

      <!-- Header card -->
      <div class="header-card">
        <div class="header-left">
          <div class="header-title">
            <span :class="`condicion-badge cond-${inspeccion.condicion}`">
              {{ CONDICION_LABELS[inspeccion.condicion] }}
            </span>
            <h1>{{ inspeccion.tecnica_nombre }}</h1>
            <span class="tecnica-norma" v-if="inspeccion.norma_referencia">{{ inspeccion.norma_referencia }}</span>
          </div>
          <div class="header-meta">
            <span class="meta-item">
              <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1" y="3" width="14" height="12" rx="1.5"/><path d="M5 1v4M11 1v4M1 7h14"/></svg>
              {{ formatDate(inspeccion.fecha) }}
            </span>
            <span class="meta-item">
              <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="5" r="3"/><path d="M2 14c0-3.3 2.7-6 6-6s6 2.7 6 6"/></svg>
              {{ inspeccion.analista || 'Sin analista' }}
            </span>
            <span class="meta-item">
              <span :class="`estado-badge estado-${inspeccion.estado_operacional}`">
                {{ ESTADO_LABELS[inspeccion.estado_operacional] }}
              </span>
            </span>
          </div>
        </div>
        <div class="header-right">
          <div class="header-asset">
            <div class="asset-tag">{{ inspeccion.tag }}</div>
            <div class="asset-name">{{ inspeccion.activo_nombre }}</div>
            <div class="asset-comp">{{ inspeccion.componente_nombre }}</div>
            <div class="asset-loc">{{ inspeccion.planta_nombre }} › {{ inspeccion.sistema_nombre }}</div>
          </div>
        </div>
      </div>

      <!-- Modo falla + observaciones -->
      <div class="info-row" v-if="inspeccion.modo_falla || inspeccion.observaciones">
        <div class="info-block" v-if="inspeccion.modo_falla">
          <div class="info-label">Modo de Falla</div>
          <div class="info-value">{{ inspeccion.modo_falla }}</div>
        </div>
        <div class="info-block" v-if="inspeccion.observaciones">
          <div class="info-label">Observaciones</div>
          <div class="info-value obs">{{ inspeccion.observaciones }}</div>
        </div>
      </div>

      <!-- Mediciones -->
      <section class="section" v-if="mediciones.length">
        <h2 class="section-title">Puntos de Medición</h2>
        <table class="mediciones-table">
          <thead>
            <tr>
              <th>Punto</th>
              <th>Valor</th>
              <th>Condición</th>
              <th>Observaciones</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in mediciones" :key="m.id">
              <td class="punto-name">
                {{ m.punto_nombre }}
                <span class="punto-unidad" v-if="m.unidad">{{ m.unidad }}</span>
              </td>
              <td class="punto-valor">
                <span v-if="m.valor !== null && m.valor !== undefined">{{ m.valor }}</span>
                <span v-else-if="m.valor_texto">{{ m.valor_texto }}</span>
                <span v-else class="no-data">—</span>
              </td>
              <td>
                <span v-if="m.condicion" :class="`cond-chip cond-${m.condicion}`">
                  {{ CONDICION_LABELS[m.condicion] }}
                </span>
                <span v-else class="no-data">—</span>
              </td>
              <td class="obs-cell">{{ m.observaciones || '—' }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="section no-data-section" v-else>
        <h2 class="section-title">Puntos de Medición</h2>
        <p class="empty-text">No se registraron valores de medición en esta inspección.</p>
      </section>

      <!-- Archivos adjuntos -->
      <section class="section">
        <div class="section-header">
          <h2 class="section-title">Archivos Adjuntos</h2>
          <label v-if="canWrite" class="upload-btn">
            <input type="file" multiple @change="handleFileUpload" :disabled="uploading" />
            <span>{{ uploading ? 'Subiendo…' : '+ Adjuntar Archivo' }}</span>
          </label>
        </div>

        <div v-if="!archivos.length" class="empty-text">No hay archivos adjuntos.</div>
        <div v-else class="archivos-list">
          <div v-for="a in archivos" :key="a.id" class="archivo-item">
            <div class="archivo-icon">
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M4 3h8l4 4v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M12 3v4h4"/></svg>
            </div>
            <div class="archivo-info">
              <span class="archivo-nombre">{{ a.nombre_original }}</span>
              <span class="archivo-meta">
                {{ a.tipo }} · {{ formatBytes(a.size_bytes) }} · {{ formatDate(a.created_at) }}
              </span>
            </div>
            <button class="download-btn" @click="downloadFile(a)">Descargar</button>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import api from '@/services/api'

const route = useRoute()
const auth = useAuthStore()
const canWrite = computed(() => ['admin','ingeniero_confiabilidad','supervisor','tecnico_campo'].includes(auth.user?.role))

import { computed } from 'vue'

const loading = ref(true)
const inspeccion = ref(null)
const mediciones = ref([])
const archivos = ref([])
const uploading = ref(false)

const CONDICION_LABELS = {
  normal: 'Normal',
  observacion: 'Observación',
  alerta: 'Alerta',
  urgencia: 'Urgencia',
}

const ESTADO_LABELS = {
  operativo: 'Operativo',
  operativo_limitado: 'Op. Limitado',
  stand_by: 'Stand-by',
  fuera_de_servicio: 'Fuera de Servicio',
  dado_de_baja: 'Dado de Baja',
}

function formatDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('es-CO', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function formatBytes(b) {
  if (!b) return ''
  if (b < 1024) return b + ' B'
  if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB'
  return (b / (1024 * 1024)).toFixed(1) + ' MB'
}

async function load() {
  try {
    const { data } = await api.get(`/inspections/inspecciones/${route.params.id}`)
    inspeccion.value = data.inspeccion
    mediciones.value = data.mediciones
    archivos.value = data.archivos
  } catch {
    inspeccion.value = null
  } finally {
    loading.value = false
  }
}

async function handleFileUpload(e) {
  const files = Array.from(e.target.files)
  if (!files.length) return
  uploading.value = true
  try {
    for (const file of files) {
      const fd = new FormData()
      fd.append('archivo', file)
      fd.append('tipo', 'reporte')
      const { data } = await api.post(`/inspections/inspecciones/${route.params.id}/archivos`, fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
      })
      archivos.value.push(data.archivo)
    }
  } finally {
    uploading.value = false
    e.target.value = ''
  }
}

async function downloadFile(archivo) {
  try {
    const { data } = await api.get(`/inspections/inspecciones/${route.params.id}/archivos/${archivo.id}/download`)
    window.open(data.url, '_blank')
  } catch {
    alert('Error al generar el enlace de descarga')
  }
}

onMounted(load)
</script>

<style scoped>
.insp-detail-view {
  padding: 24px;
  max-width: 1100px;
  margin: 0 auto;
  font-family: inherit;
}

.loading-state, .error-state {
  text-align: center;
  padding: 80px 0;
  color: #6b7280;
}

.breadcrumb {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: #6b7280;
  margin-bottom: 20px;
}
.breadcrumb a { color: #2563eb; text-decoration: none; }
.breadcrumb a:hover { text-decoration: underline; }
.sep { color: #d1d5db; }

/* Header card */
.header-card {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 24px;
  display: flex;
  gap: 24px;
  margin-bottom: 20px;
}
.header-left { flex: 1; }
.header-title { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; }
.header-title h1 { font-size: 20px; font-weight: 600; color: #111827; margin: 0; }
.tecnica-norma { font-size: 12px; color: #6b7280; }
.header-meta { display: flex; flex-wrap: wrap; gap: 16px; }
.meta-item { display: flex; align-items: center; gap: 6px; font-size: 13px; color: #374151; }
.meta-item svg { color: #9ca3af; flex-shrink: 0; }

.header-right { min-width: 220px; }
.header-asset {
  background: #f9fafb;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 16px;
}
.asset-tag { font-family: monospace; font-size: 14px; font-weight: 700; color: #1e40af; margin-bottom: 4px; }
.asset-name { font-size: 14px; font-weight: 600; color: #111827; margin-bottom: 4px; }
.asset-comp { font-size: 12px; color: #6b7280; margin-bottom: 6px; }
.asset-loc { font-size: 12px; color: #9ca3af; }

/* Condicion badges */
.condicion-badge {
  display: inline-block;
  padding: 3px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
}
.cond-normal { background: #dcfce7; color: #166534; }
.cond-observacion { background: #fef9c3; color: #854d0e; }
.cond-alerta { background: #ffedd5; color: #9a3412; }
.cond-urgencia { background: #fee2e2; color: #991b1b; }

/* Estado badges */
.estado-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 600;
}
.estado-operativo { background: #d1fae5; color: #065f46; }
.estado-operativo_limitado { background: #fef3c7; color: #92400e; }
.estado-stand_by { background: #e0e7ff; color: #3730a3; }
.estado-fuera_de_servicio { background: #fee2e2; color: #991b1b; }
.estado-dado_de_baja { background: #f3f4f6; color: #4b5563; }

/* Info row */
.info-row {
  display: flex;
  gap: 16px;
  margin-bottom: 20px;
}
.info-block {
  flex: 1;
  background: #f9fafb;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 14px 18px;
}
.info-label { font-size: 11px; font-weight: 600; color: #9ca3af; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 6px; }
.info-value { font-size: 14px; color: #374151; }
.info-value.obs { white-space: pre-wrap; line-height: 1.5; }

/* Sections */
.section { margin-bottom: 24px; }
.section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
.section-title { font-size: 15px; font-weight: 600; color: #374151; margin: 0 0 12px; }
.section-header .section-title { margin: 0; }

/* Mediciones table */
.mediciones-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  overflow: hidden;
}
.mediciones-table th {
  background: #f9fafb;
  padding: 10px 14px;
  text-align: left;
  font-weight: 600;
  color: #6b7280;
  font-size: 11px;
  text-transform: uppercase;
  border-bottom: 1px solid #e5e7eb;
}
.mediciones-table td {
  padding: 10px 14px;
  color: #374151;
  border-bottom: 1px solid #f3f4f6;
  vertical-align: top;
}
.mediciones-table tr:last-child td { border-bottom: none; }
.punto-name { font-weight: 500; color: #111827; }
.punto-unidad { font-size: 11px; color: #9ca3af; margin-left: 4px; font-family: monospace; }
.punto-valor { font-family: monospace; font-size: 14px; color: #1e40af; }
.cond-chip {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 12px;
  font-size: 11px;
  font-weight: 600;
}
.obs-cell { color: #6b7280; font-size: 12px; }
.no-data { color: #d1d5db; }
.no-data-section .empty-text { color: #9ca3af; font-size: 13px; }

/* Archivos */
.upload-btn {
  cursor: pointer;
  display: inline-block;
  padding: 6px 14px;
  font-size: 13px;
  font-weight: 500;
  color: #2563eb;
  border: 1px solid #bfdbfe;
  border-radius: 6px;
  background: #eff6ff;
}
.upload-btn:hover { background: #dbeafe; }
.upload-btn input[type="file"] { display: none; }

.empty-text { font-size: 13px; color: #9ca3af; padding: 16px 0; }

.archivos-list { display: flex; flex-direction: column; gap: 8px; }
.archivo-item {
  display: flex;
  align-items: center;
  gap: 12px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 12px 16px;
}
.archivo-icon { color: #6b7280; flex-shrink: 0; }
.archivo-info { flex: 1; }
.archivo-nombre { display: block; font-size: 13px; font-weight: 500; color: #111827; }
.archivo-meta { display: block; font-size: 11px; color: #9ca3af; margin-top: 2px; text-transform: capitalize; }
.download-btn {
  padding: 5px 12px;
  font-size: 12px;
  font-weight: 500;
  color: #2563eb;
  border: 1px solid #bfdbfe;
  border-radius: 5px;
  background: #fff;
  cursor: pointer;
  white-space: nowrap;
}
.download-btn:hover { background: #eff6ff; }
</style>
