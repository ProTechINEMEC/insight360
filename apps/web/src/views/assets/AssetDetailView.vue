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
        <h3>{{ asset.nombre }}</h3>
        <p class="asset-meta">
          {{ asset.planta_nombre }} &rsaquo; {{ asset.sistema_nombre }}
          <span :class="`badge badge-${asset.criticidad}`" style="margin-left: 0.5rem">{{ asset.criticidad }}</span>
        </p>
      </div>
    </div>

    <!-- Tabs -->
    <div class="tabs">
      <button v-for="t in tabs" :key="t.key" :class="['tab', { active: activeTab === t.key }]" @click="activeTab = t.key">
        {{ t.label }}
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
    <div v-if="activeTab === 'mediciones'">
      <div class="puntos-grid">
        <div v-for="punto in puntos" :key="punto.id" class="punto-card card">
          <div class="punto-header">
            <div>
              <div class="punto-nombre">{{ punto.nombre }}</div>
              <div class="punto-tipo">{{ punto.tipo }} · {{ punto.unidad }}</div>
            </div>
            <div class="punto-limits" v-if="punto.limite_alarma">
              <span class="limit-badge alerta">{{ punto.limite_alerta }} {{ punto.unidad }}</span>
              <span class="limit-badge alarma">{{ punto.limite_alarma }} {{ punto.unidad }}</span>
            </div>
          </div>
          <MiniChart :punto-id="punto.id" />
        </div>
      </div>
      <div v-if="!puntos.length" class="empty-state">
        Sin puntos de medición configurados para este activo.
      </div>
    </div>
  </div>

  <!-- Loading state -->
  <div v-else-if="loading" class="loading-box">
    <div class="spinner"></div>
  </div>

  <!-- Not found -->
  <div v-else class="card empty-state">
    Activo no encontrado.
    <RouterLink to="/activos">Volver a Activos</RouterLink>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/services/api'
import MiniChart from '@/components/MiniChart.vue'

const route = useRoute()
const asset = ref(null)
const puntos = ref([])
const loading = ref(true)
const activeTab = ref('info')

const tabs = [
  { key: 'info', label: 'Información General' },
  { key: 'mediciones', label: 'Mediciones' },
]

function formatDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('es-CO')
}

onMounted(async () => {
  try {
    const [assetRes, puntosRes] = await Promise.all([
      api.get(`/assets/${route.params.id}`),
      api.get('/measurements/puntos', { params: { activo_id: route.params.id } }),
    ])
    asset.value = assetRes.data.activo
    puntos.value = puntosRes.data.puntos
  } catch {
    asset.value = null
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
.asset-detail { display: flex; flex-direction: column; gap: 1rem; }

.detail-header { margin-bottom: 0.25rem; }

.breadcrumb {
  font-size: 0.8125rem;
  color: var(--color-text-muted);
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.25rem;
}

.breadcrumb a { color: var(--color-brand); }

.asset-meta { color: var(--color-text-muted); font-size: 0.875rem; margin-top: 0.25rem; }

.tabs {
  display: flex;
  gap: 0;
  border-bottom: 2px solid var(--color-border);
}

.tab {
  padding: 0.625rem 1.25rem;
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  color: var(--color-text-muted);
  margin-bottom: -2px;
}

.tab.active {
  color: var(--color-brand);
  border-bottom-color: var(--color-brand);
}

.info-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 1.25rem;
}

.field-full { grid-column: 1 / -1; }

.info-label { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 0.25rem; }
.info-value { font-size: 0.9375rem; font-weight: 500; }

.puntos-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 1rem;
}

.punto-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 0.75rem;
}

.punto-nombre { font-weight: 600; font-size: 0.9375rem; }
.punto-tipo { font-size: 0.75rem; color: var(--color-text-muted); margin-top: 0.125rem; }

.punto-limits { display: flex; gap: 0.375rem; flex-direction: column; align-items: flex-end; }
.limit-badge {
  font-size: 0.7rem;
  font-weight: 600;
  padding: 1px 6px;
  border-radius: 999px;
}
.limit-badge.alerta { background: #fffbeb; color: #d97706; }
.limit-badge.alarma { background: #fef2f2; color: #dc2626; }

.loading-box { display: flex; justify-content: center; align-items: center; padding: 4rem; }

.empty-state {
  text-align: center;
  color: var(--color-text-muted);
  padding: 3rem;
}
</style>
