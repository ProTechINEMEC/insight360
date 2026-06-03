<template>
  <div class="dashboard">
    <!-- KPI strip -->
    <div class="kpi-grid">
      <div class="kpi-card">
        <div class="kpi-value">{{ assets.length }}</div>
        <div class="kpi-label">Total Activos</div>
      </div>
      <div class="kpi-card kpi-critico">
        <div class="kpi-value">{{ countCriticidad('critico') }}</div>
        <div class="kpi-label">Críticos</div>
      </div>
      <div class="kpi-card kpi-alerta">
        <div class="kpi-value">{{ countCriticidad('esencial') }}</div>
        <div class="kpi-label">Esenciales</div>
      </div>
      <div class="kpi-card kpi-health-critico">
        <div class="kpi-value">{{ healthCounts.critico }}</div>
        <div class="kpi-label">Salud Crítica</div>
      </div>
      <div class="kpi-card kpi-health-alerta">
        <div class="kpi-value">{{ healthCounts.alerta }}</div>
        <div class="kpi-label">En Alerta</div>
      </div>
      <div class="kpi-card kpi-health-bueno">
        <div class="kpi-value">{{ healthCounts.bueno }}</div>
        <div class="kpi-label">Saludables</div>
      </div>
    </div>

    <div class="row-grid">
      <!-- Critical assets health table -->
      <div class="card">
        <h4 class="section-title">Activos Críticos — Estado de Salud</h4>
        <div v-if="loadingAssets" class="loading-box"><div class="spinner"></div></div>
        <table v-else>
          <thead>
            <tr><th>Tag</th><th>Sistema</th><th>Criticidad</th><th>Salud</th><th>Score</th></tr>
          </thead>
          <tbody>
            <tr
              v-for="a in criticalAssets"
              :key="a.id"
              @click="router.push(`/activos/${a.id}`)"
              style="cursor:pointer"
            >
              <td>
                <div class="asset-tag">{{ a.tag }}</div>
                <div class="asset-name-sub">{{ a.nombre }}</div>
              </td>
              <td>{{ a.sistema_nombre }}</td>
              <td><span :class="`badge badge-${a.criticidad}`">{{ a.criticidad }}</span></td>
              <td>
                <span :class="`health-chip health-${a.health?.estado || 'desconocido'}`">
                  {{ ESTADO_LABELS[a.health?.estado] || 'Sin datos' }}
                </span>
              </td>
              <td class="score-cell">
                <span v-if="a.health?.score !== null && a.health?.score !== undefined">
                  {{ a.health.score }}/100
                </span>
                <span v-else class="text-muted">—</span>
              </td>
            </tr>
            <tr v-if="!criticalAssets.length">
              <td colspan="5" class="text-muted text-center">Sin activos críticos</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Plant summary -->
      <div class="card">
        <h4 class="section-title">Resumen por Planta</h4>
        <div v-if="loadingAssets" class="loading-box"><div class="spinner"></div></div>
        <div v-else>
          <div class="plant-row" v-for="p in plantSummary" :key="p.planta_id">
            <div class="plant-info">
              <div class="plant-name">{{ p.planta_nombre }}</div>
              <div class="plant-counts">
                <span class="badge badge-critico">{{ p.criticos }} críticos</span>
                <span class="badge badge-esencial">{{ p.esenciales }} esenciales</span>
                <span class="badge badge-general">{{ p.generales }} generales</span>
              </div>
            </div>
            <div class="plant-health">
              <div v-if="p.health_critico > 0" class="health-dot critico">{{ p.health_critico }}</div>
              <div v-if="p.health_alerta > 0" class="health-dot alerta">{{ p.health_alerta }}</div>
              <div v-if="p.health_bueno > 0" class="health-dot bueno">{{ p.health_bueno }}</div>
            </div>
          </div>
          <div v-if="!plantSummary.length" class="text-muted text-center" style="padding:1.5rem">Sin datos</div>
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
const loadingAssets = ref(true)
const assets = ref([])

const ESTADO_LABELS = { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: 'Sin datos' }

function countCriticidad(c) { return assets.value.filter((a) => a.criticidad === c).length }

const criticalAssets = computed(() => assets.value.filter((a) => a.criticidad === 'critico'))

const healthCounts = computed(() => {
  const counts = { bueno: 0, alerta: 0, critico: 0, desconocido: 0 }
  assets.value.forEach((a) => { counts[a.health?.estado || 'desconocido']++ })
  return counts
})

const plantSummary = computed(() => {
  const map = {}
  assets.value.forEach((a) => {
    if (!map[a.planta_id]) {
      map[a.planta_id] = {
        planta_id: a.planta_id, planta_nombre: a.planta_nombre,
        criticos: 0, esenciales: 0, generales: 0,
        health_critico: 0, health_alerta: 0, health_bueno: 0,
      }
    }
    const p = map[a.planta_id]
    if (a.criticidad === 'critico') p.criticos++
    else if (a.criticidad === 'esencial') p.esenciales++
    else p.generales++
    const h = a.health?.estado || 'desconocido'
    if (h === 'critico') p.health_critico++
    else if (h === 'alerta') p.health_alerta++
    else if (h === 'bueno') p.health_bueno++
  })
  return Object.values(map)
})

onMounted(async () => {
  try {
    const { data } = await api.get('/assets')
    // Load health for each asset in parallel (cap to 20 to avoid flooding)
    const list = data.activos
    const healthResults = await Promise.allSettled(
      list.map((a) => api.get(`/health/asset/${a.id}`))
    )
    assets.value = list.map((a, i) => ({
      ...a,
      health: healthResults[i].status === 'fulfilled' ? healthResults[i].value.data : null,
    }))
  } catch (err) {
    console.error(err)
  } finally {
    loadingAssets.value = false
  }
})
</script>

<style scoped>
.dashboard { display: flex; flex-direction: column; gap: 1.25rem; }

.kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 0.875rem; }
.kpi-card { background: #fff; border-radius: 12px; padding: 1.125rem 1.25rem; border: 1px solid var(--color-border); border-top: 3px solid var(--color-border); }
.kpi-card.kpi-critico { border-top-color: #dc2626; }
.kpi-card.kpi-alerta { border-top-color: #d97706; }
.kpi-card.kpi-health-critico { border-top-color: #dc2626; background: #fef9f9; }
.kpi-card.kpi-health-alerta { border-top-color: #d97706; background: #fffdf5; }
.kpi-card.kpi-health-bueno { border-top-color: #16a34a; background: #f9fef9; }
.kpi-value { font-size: 2rem; font-weight: 800; line-height: 1; color: var(--color-text-primary); }
.kpi-label { font-size: 0.75rem; color: var(--color-text-muted); margin-top: 0.25rem; }

.row-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
@media (max-width: 900px) { .row-grid { grid-template-columns: 1fr; } }

.section-title { font-size: 0.875rem; font-weight: 600; margin-bottom: 0.875rem; }

.asset-tag { font-weight: 600; font-size: 0.875rem; }
.asset-name-sub { font-size: 0.75rem; color: var(--color-text-muted); }
.score-cell { font-size: 0.8125rem; color: var(--color-text-secondary); }
.text-muted { color: var(--color-text-muted); }
.text-center { text-align: center; }

.health-chip { padding: 2px 8px; border-radius: 999px; font-size: 0.7rem; font-weight: 600; text-transform: uppercase; display: inline-block; }
.health-chip.health-bueno { background: #f0fdf4; color: #16a34a; }
.health-chip.health-alerta { background: #fffbeb; color: #d97706; }
.health-chip.health-critico { background: #fef2f2; color: #dc2626; }
.health-chip.health-desconocido { background: var(--color-bg); color: var(--color-text-muted); }

.loading-box { display: flex; justify-content: center; padding: 2rem; }

.plant-row { display: flex; align-items: center; justify-content: space-between; padding: 0.75rem 0; border-bottom: 1px solid var(--color-border); gap: 0.75rem; }
.plant-row:last-child { border-bottom: none; }
.plant-name { font-weight: 500; font-size: 0.875rem; margin-bottom: 0.375rem; }
.plant-counts { display: flex; gap: 0.375rem; flex-wrap: wrap; }
.plant-health { display: flex; gap: 0.375rem; align-items: center; flex-shrink: 0; }
.health-dot { width: 28px; height: 28px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 0.75rem; font-weight: 700; color: #fff; }
.health-dot.critico { background: #dc2626; }
.health-dot.alerta { background: #d97706; }
.health-dot.bueno { background: #16a34a; }
</style>
