<template>
  <div class="mini-chart">
    <div v-if="loading" class="chart-loading"><div class="spinner" style="width:16px;height:16px;border-width:2px"></div></div>
    <div v-else-if="!readings.length" class="chart-empty">Sin datos de medición</div>
    <div v-else>
      <v-chart :option="chartOption" class="chart" autoresize />
      <div class="chart-meta">
        <span>Último: <strong>{{ lastValue }} {{ punto?.unidad }}</strong></span>
        <span class="chart-time">{{ lastTime }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import VChart from 'vue-echarts'
import { use } from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { api } from '@/services/api'

use([LineChart, GridComponent, TooltipComponent, CanvasRenderer])

const props = defineProps({ puntoId: { type: String, required: true } })

const readings = ref([])
const punto = ref(null)
const loading = ref(true)

const lastValue = computed(() => readings.value.at(-1)?.valor ?? '—')
const lastTime = computed(() => {
  const t = readings.value.at(-1)?.time
  return t ? new Date(t).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' }) : ''
})

const chartOption = computed(() => ({
  grid: { top: 8, right: 8, bottom: 8, left: 40, containLabel: false },
  tooltip: {
    trigger: 'axis',
    formatter: (params) => {
      const p = params[0]
      return `${new Date(p.axisValue).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })}<br/><strong>${p.value}</strong>`
    },
  },
  xAxis: { type: 'time', show: false },
  yAxis: { type: 'value', axisLabel: { fontSize: 10 } },
  series: [{
    type: 'line',
    data: readings.value.map((r) => [r.time, parseFloat(r.valor)]),
    lineStyle: { width: 1.5, color: '#D52B1E' },
    symbol: 'none',
    areaStyle: { color: 'rgba(213,43,30,0.08)' },
    markLine: punto.value?.limite_alarma ? {
      silent: true,
      symbol: 'none',
      lineStyle: { color: '#dc2626', type: 'dashed', width: 1 },
      data: [{ yAxis: parseFloat(punto.value.limite_alarma) }],
    } : undefined,
  }],
}))

onMounted(async () => {
  try {
    const [pRes, rRes] = await Promise.all([
      api.get('/measurements/puntos', { params: { activo_id: 'skip' } }).catch(() => ({ data: { puntos: [] } })),
      api.get('/measurements/readings', { params: { punto_id: props.puntoId, limit: 100 } }),
    ])
    readings.value = rRes.data.readings
  } catch (err) {
    console.error(err)
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
.mini-chart { min-height: 100px; }
.chart { height: 120px; width: 100%; }
.chart-loading, .chart-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 80px;
  font-size: 0.8rem;
  color: var(--color-text-muted);
}
.chart-meta {
  display: flex;
  justify-content: space-between;
  font-size: 0.75rem;
  color: var(--color-text-muted);
  margin-top: 0.25rem;
}
.chart-time { color: var(--color-text-muted); }
</style>
