<template>
  <div class="asset-detail" v-if="asset">
    <!-- Header -->
    <div class="detail-header">
      <div>
        <div class="breadcrumb">
          <RouterLink to="/activos">Activos</RouterLink>
          <span>/</span>
          <span>{{ asset.tag }}</span>
        </div>
        <div class="detail-title-row">
          <h3>{{ asset.nombre }}</h3>
          <span :class="`badge badge-${asset.criticidad}`">{{ asset.criticidad }}</span>
          <span v-if="health" :class="`health-chip health-${health.estado}`">
            {{ ESTADO_LABELS[health.estado] }}
            <template v-if="health.score !== null"> · {{ health.score }}/100</template>
          </span>
        </div>
        <p class="asset-meta">{{ asset.planta_nombre }} &rsaquo; {{ asset.sistema_nombre }}</p>
      </div>
    </div>

    <!-- Tabs -->
    <div class="tabs">
      <button v-for="t in tabs" :key="t.key" :class="['tab', { active: activeTab === t.key }]" @click="activeTab = t.key">
        {{ t.label }}
        <span v-if="t.key === 'mediciones' && puntos.length" class="tab-count">{{ puntos.length }}</span>
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
  </div>

  <div v-else-if="loading" class="loading-box"><div class="spinner"></div></div>
  <div v-else class="card empty-state">
    Activo no encontrado. <RouterLink to="/activos">Volver</RouterLink>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/services/api'
import TrendChart from '@/components/TrendChart.vue'

const route = useRoute()
const asset = ref(null)
const puntos = ref([])
const health = ref(null)
const loading = ref(true)
const activeTab = ref('info')
const selectedPunto = ref(null)

const ESTADO_LABELS = { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: 'Sin datos' }

const tabs = [
  { key: 'info', label: 'Información General' },
  { key: 'mediciones', label: 'Mediciones' },
]

const puntosWithHealth = computed(() => {
  if (!health.value?.detalle) return puntos.value.map((p) => ({ ...p, estado: 'desconocido' }))
  return puntos.value.map((p) => ({
    ...p,
    estado: health.value.detalle[p.id]?.estado || 'desconocido',
  }))
})

function formatDate(d) { return d ? new Date(d).toLocaleDateString('es-CO') : '—' }
function formatTime(t) { return t ? new Date(t).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' }) : '' }
function fmtVal(v) {
  if (v === null) return '—'
  const n = Number(v)
  return n % 1 === 0 ? n : n.toFixed(3)
}

onMounted(async () => {
  try {
    const [assetRes, puntosRes, healthRes] = await Promise.allSettled([
      api.get(`/assets/${route.params.id}`),
      api.get('/measurements/latest', { params: { activo_id: route.params.id } }),
      api.get(`/health/asset/${route.params.id}`),
    ])
    if (assetRes.status === 'fulfilled') asset.value = assetRes.value.data.activo
    if (puntosRes.status === 'fulfilled') puntos.value = puntosRes.value.data.puntos
    if (healthRes.status === 'fulfilled') health.value = healthRes.value.data
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
</style>
