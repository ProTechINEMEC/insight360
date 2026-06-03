<template>
  <div class="dashboard">
    <!-- KPI strip -->
    <div class="kpi-grid">
      <div class="kpi-card" v-for="kpi in kpis" :key="kpi.label">
        <div class="kpi-value" :style="{ color: kpi.color }">{{ kpi.value }}</div>
        <div class="kpi-label">{{ kpi.label }}</div>
        <div class="kpi-sub" v-if="kpi.sub">{{ kpi.sub }}</div>
      </div>
    </div>

    <!-- Health by criticality -->
    <div class="row-grid">
      <div class="card">
        <h4 class="section-title">Estado de Activos Críticos</h4>
        <div v-if="loading.assets" class="loading-box"><div class="spinner"></div></div>
        <table v-else>
          <thead>
            <tr>
              <th>Tag</th>
              <th>Sistema</th>
              <th>Criticidad</th>
              <th>Salud</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in criticalAssets" :key="a.id" @click="goToAsset(a.id)" style="cursor:pointer">
              <td><strong>{{ a.tag }}</strong><br /><span class="text-muted">{{ a.nombre }}</span></td>
              <td>{{ a.sistema_nombre }}</td>
              <td>
                <span :class="`badge badge-${a.criticidad}`">{{ a.criticidad }}</span>
              </td>
              <td>
                <span :class="`badge badge-${a.health || 'general'}`">{{ healthLabel(a.health) }}</span>
              </td>
            </tr>
            <tr v-if="!criticalAssets.length">
              <td colspan="4" class="text-muted text-center">Sin activos críticos registrados</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="card">
        <h4 class="section-title">Resumen por Planta</h4>
        <div v-if="loading.assets" class="loading-box"><div class="spinner"></div></div>
        <div v-else>
          <div class="plant-row" v-for="p in plantSummary" :key="p.planta_id">
            <div class="plant-name">{{ p.planta_nombre }}</div>
            <div class="plant-stats">
              <span class="badge badge-critico">{{ p.criticos }} críticos</span>
              <span class="badge badge-esencial">{{ p.esenciales }} esenciales</span>
              <span class="badge badge-general">{{ p.generales }} generales</span>
            </div>
          </div>
          <div v-if="!plantSummary.length" class="text-muted">Sin datos</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/services/api'

const router = useRouter()
const loading = ref({ assets: true })
const assets = ref([])

const criticalAssets = computed(() =>
  assets.value.filter((a) => a.criticidad === 'critico').slice(0, 10)
)

const plantSummary = computed(() => {
  const map = {}
  assets.value.forEach((a) => {
    if (!map[a.planta_id]) {
      map[a.planta_id] = { planta_id: a.planta_id, planta_nombre: a.planta_nombre, criticos: 0, esenciales: 0, generales: 0 }
    }
    map[a.planta_id][`${a.criticidad}s`]++
  })
  return Object.values(map)
})

const kpis = computed(() => [
  { label: 'Total Activos', value: assets.value.length, color: '#1a1a2e' },
  { label: 'Críticos', value: assets.value.filter((a) => a.criticidad === 'critico').length, color: '#dc2626' },
  { label: 'Esenciales', value: assets.value.filter((a) => a.criticidad === 'esencial').length, color: '#d97706' },
  { label: 'Generales', value: assets.value.filter((a) => a.criticidad === 'general').length, color: '#16a34a' },
])

function healthLabel(h) {
  return { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: 'Sin datos' }[h] || 'Sin datos'
}

function goToAsset(id) {
  router.push(`/activos/${id}`)
}

onMounted(async () => {
  try {
    const { data } = await api.get('/assets')
    assets.value = data.activos
  } catch (err) {
    console.error(err)
  } finally {
    loading.value.assets = false
  }
})
</script>

<style scoped>
.dashboard { display: flex; flex-direction: column; gap: 1.5rem; }

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 1rem;
}

.kpi-card {
  background: #fff;
  border-radius: 12px;
  padding: 1.25rem 1.5rem;
  border: 1px solid var(--color-border);
}

.kpi-value {
  font-size: 2rem;
  font-weight: 700;
  line-height: 1;
  margin-bottom: 0.25rem;
}

.kpi-label {
  font-size: 0.8125rem;
  color: var(--color-text-muted);
}

.kpi-sub {
  font-size: 0.75rem;
  color: var(--color-text-muted);
  margin-top: 0.25rem;
}

.row-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
}

@media (max-width: 900px) {
  .row-grid { grid-template-columns: 1fr; }
}

.section-title {
  font-size: 0.9rem;
  font-weight: 600;
  margin-bottom: 1rem;
  color: var(--color-text-primary);
}

.text-muted { color: var(--color-text-muted); font-size: 0.8125rem; }
.text-center { text-align: center; }

.loading-box {
  display: flex;
  justify-content: center;
  padding: 2rem;
}

.plant-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.625rem 0;
  border-bottom: 1px solid var(--color-border);
}

.plant-row:last-child { border-bottom: none; }

.plant-name { font-weight: 500; font-size: 0.875rem; }
.plant-stats { display: flex; gap: 0.5rem; flex-wrap: wrap; }
</style>
