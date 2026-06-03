<template>
  <div class="trend-chart">
    <!-- Time range selector -->
    <div class="chart-controls">
      <div class="range-tabs">
        <button
          v-for="r in RANGES"
          :key="r.key"
          :class="['range-tab', { active: range === r.key }]"
          @click="setRange(r.key)"
        >{{ r.label }}</button>
      </div>
      <div class="chart-stats" v-if="stats">
        <span class="stat"><span class="stat-label">Mín</span>{{ fmtStat(stats.min) }} {{ punto.unidad }}</span>
        <span class="stat"><span class="stat-label">Máx</span>{{ fmtStat(stats.max) }} {{ punto.unidad }}</span>
        <span class="stat"><span class="stat-label">Prom</span>{{ fmtStat(stats.avg) }} {{ punto.unidad }}</span>
        <span class="stat"><span class="stat-label">σ</span>{{ fmtStat(stats.stddev) }}</span>
        <span class="stat"><span class="stat-label">N</span>{{ stats.count }}</span>
      </div>
    </div>

    <!-- Chart -->
    <div v-if="loading" class="chart-loading"><div class="spinner"></div></div>
    <div v-else-if="!readings.length" class="chart-empty">
      Sin datos en el período seleccionado
    </div>
    <v-chart v-else :option="chartOption" class="chart" autoresize />

    <!-- Recent readings table -->
    <div class="readings-table-header">
      <span class="section-label">Últimas lecturas</span>
    </div>
    <div class="readings-table-wrap">
      <table>
        <thead>
          <tr>
            <th>Fecha / Hora</th>
            <th>Valor</th>
            <th>Estado</th>
            <th>Fuente</th>
            <th>Notas</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in recentReadings" :key="r.time">
            <td>{{ formatTime(r.time) }}</td>
            <td><strong>{{ fmtStat(r.valor) }}</strong> {{ punto.unidad }}</td>
            <td>
              <span :class="`estado-badge estado-${getEstado(r.valor)}`">
                {{ ESTADO_LABELS[getEstado(r.valor)] }}
              </span>
            </td>
            <td class="text-muted">{{ r.fuente }}</td>
            <td class="text-muted">{{ r.notas || '—' }}</td>
          </tr>
          <tr v-if="!recentReadings.length">
            <td colspan="5" class="text-center text-muted">Sin lecturas</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import VChart from 'vue-echarts'
import { use } from 'echarts/core'
import { LineChart, ScatterChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent, MarkLineComponent, DataZoomComponent, ToolboxComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { api } from '@/services/api'

use([LineChart, ScatterChart, GridComponent, TooltipComponent, LegendComponent, MarkLineComponent, DataZoomComponent, ToolboxComponent, CanvasRenderer])

const props = defineProps({
  punto: { type: Object, required: true },
})

const RANGES = [
  { key: '7d', label: '7 días' },
  { key: '30d', label: '30 días' },
  { key: '90d', label: '90 días' },
  { key: '1y', label: '1 año' },
  { key: 'all', label: 'Todo' },
]
const RANGE_MS = { '7d': 7, '30d': 30, '90d': 90, '1y': 365 }
const ESTADO_LABELS = { bueno: 'Bueno', alerta: 'Alerta', critico: 'Crítico', desconocido: '—' }

const range = ref('30d')
const readings = ref([])
const stats = ref(null)
const loading = ref(false)

const recentReadings = computed(() => [...readings.value].reverse().slice(0, 20))

function getDateRange() {
  if (range.value === 'all') return {}
  const days = RANGE_MS[range.value]
  const from = new Date(Date.now() - days * 86400000)
  return { from: from.toISOString() }
}

function getEstado(valor) {
  if (valor === null) return 'desconocido'
  const p = props.punto
  if (p.limite_alarma !== null && Number(valor) >= Number(p.limite_alarma)) return 'critico'
  if (p.limite_alerta !== null && Number(valor) >= Number(p.limite_alerta)) return 'alerta'
  return 'bueno'
}

function fmtStat(v) {
  if (v === null || v === undefined) return '—'
  const n = Number(v)
  return n % 1 === 0 ? n : n.toFixed(3)
}

function formatTime(t) {
  return new Date(t).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })
}

async function load() {
  loading.value = true
  try {
    const params = { punto_id: props.punto.id, limit: 2000, ...getDateRange() }
    const [rRes, sRes] = await Promise.all([
      api.get('/measurements/readings', { params }),
      api.get('/measurements/stats', { params: { punto_id: props.punto.id, ...getDateRange() } }),
    ])
    readings.value = rRes.data.readings
    stats.value = sRes.data.stats
  } catch (err) {
    console.error(err)
  } finally {
    loading.value = false
  }
}

function setRange(r) {
  range.value = r
  load()
}

const markLines = computed(() => {
  const data = []
  if (props.punto.limite_alerta !== null) {
    data.push({
      yAxis: Number(props.punto.limite_alerta),
      name: `Alerta ${props.punto.limite_alerta}`,
      lineStyle: { color: '#d97706', type: 'dashed', width: 1.5 },
      label: { formatter: `Alerta: {c}`, color: '#d97706', position: 'insideEndTop' },
    })
  }
  if (props.punto.limite_alarma !== null) {
    data.push({
      yAxis: Number(props.punto.limite_alarma),
      name: `Alarma ${props.punto.limite_alarma}`,
      lineStyle: { color: '#dc2626', type: 'dashed', width: 1.5 },
      label: { formatter: `Alarma: {c}`, color: '#dc2626', position: 'insideEndTop' },
    })
  }
  return data
})

const chartOption = computed(() => ({
  animation: false,
  grid: { top: 16, right: 16, bottom: 60, left: 56, containLabel: false },
  tooltip: {
    trigger: 'axis',
    formatter(params) {
      const p = params[0]
      return `${formatTime(p.axisValue)}<br/><strong>${fmtStat(p.value[1])} ${props.punto.unidad}</strong>`
    },
  },
  toolbox: {
    feature: { saveAsImage: { title: 'Guardar' } },
    right: 16,
    top: 0,
  },
  dataZoom: [
    { type: 'inside', xAxisIndex: 0 },
    { type: 'slider', xAxisIndex: 0, height: 20, bottom: 8 },
  ],
  xAxis: { type: 'time', axisLabel: { fontSize: 11 } },
  yAxis: {
    type: 'value',
    name: props.punto.unidad,
    nameTextStyle: { fontSize: 11 },
    axisLabel: { fontSize: 11 },
  },
  series: [{
    type: 'line',
    data: readings.value.map((r) => [r.time, Number(r.valor)]),
    lineStyle: { width: 2, color: '#D52B1E' },
    itemStyle: { color: '#D52B1E' },
    symbol: readings.value.length < 100 ? 'circle' : 'none',
    symbolSize: 4,
    areaStyle: { color: 'rgba(213,43,30,0.06)' },
    markLine: markLines.value.length ? {
      silent: true,
      symbol: 'none',
      data: markLines.value,
    } : undefined,
  }],
}))

onMounted(load)
watch(() => props.punto.id, load)
</script>

<style scoped>
.trend-chart { display: flex; flex-direction: column; gap: 1rem; }

.chart-controls {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 0.75rem;
}

.range-tabs { display: flex; gap: 0; }
.range-tab {
  padding: 0.375rem 0.75rem;
  background: var(--color-bg);
  border: 1px solid var(--color-border);
  border-right: none;
  font-size: 0.8125rem;
  cursor: pointer;
  color: var(--color-text-secondary);
}
.range-tab:first-child { border-radius: 6px 0 0 6px; }
.range-tab:last-child { border-right: 1px solid var(--color-border); border-radius: 0 6px 6px 0; }
.range-tab.active { background: var(--color-brand); border-color: var(--color-brand); color: #fff; }

.chart-stats { display: flex; gap: 1.25rem; flex-wrap: wrap; }
.stat { font-size: 0.8125rem; }
.stat-label { font-size: 0.7rem; color: var(--color-text-muted); display: block; }

.chart { height: 300px; width: 100%; }
.chart-loading, .chart-empty { height: 200px; display: flex; align-items: center; justify-content: center; color: var(--color-text-muted); }

.readings-table-header { margin-top: 0.25rem; }
.section-label { font-size: 0.8rem; font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.05em; }

.readings-table-wrap { max-height: 240px; overflow-y: auto; border: 1px solid var(--color-border); border-radius: 8px; }
table { width: 100%; border-collapse: collapse; font-size: 0.8125rem; }
th { padding: 0.5rem 0.75rem; font-size: 0.7rem; font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; border-bottom: 1px solid var(--color-border); background: var(--color-bg); position: sticky; top: 0; }
td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--color-border); }
tr:last-child td { border-bottom: none; }

.estado-badge { display: inline-block; padding: 1px 6px; border-radius: 999px; font-size: 0.68rem; font-weight: 600; text-transform: uppercase; }
.estado-badge.estado-bueno { background: #f0fdf4; color: #16a34a; }
.estado-badge.estado-alerta { background: #fffbeb; color: #d97706; }
.estado-badge.estado-critico { background: #fef2f2; color: #dc2626; }
.estado-badge.estado-desconocido { background: var(--color-bg); color: var(--color-text-muted); }

.text-muted { color: var(--color-text-muted); }
.text-center { text-align: center; }
</style>
