<template>
  <div class="mini-chart">
    <div v-if="loading" class="chart-loading"><div class="spinner" style="width:16px;height:16px;border-width:2px"></div></div>
    <div v-else-if="!readings.length" class="chart-empty">Sin datos</div>
    <div v-else>
      <v-chart :option="chartOption" class="chart" autoresize />
      <div class="chart-meta">
        <span>Último: <strong>{{ lastValue }} {{ punto.unidad }}</strong></span>
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
import { GridComponent, TooltipComponent, MarkLineComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { api } from '@/services/api'

use([LineChart, GridComponent, TooltipComponent, MarkLineComponent, CanvasRenderer])

const props = defineProps({
  punto: { type: Object, required: true },
})

const readings = ref([])
const loading = ref(true)

const lastValue = computed(() => {
  const v = readings.value.at(-1)?.valor
  if (v === null || v === undefined) return '—'
  return Number(v) % 1 === 0 ? v : Number(v).toFixed(3)
})
const lastTime = computed(() => {
  const t = readings.value.at(-1)?.time
  return t ? new Date(t).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' }) : ''
})

const chartOption = computed(() => ({
  animation: false,
  grid: { top: 4, right: 4, bottom: 4, left: 36, containLabel: false },
  tooltip: { trigger: 'axis', formatter: (p) => `${new Date(p[0].axisValue).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })}<br/><strong>${p[0].value[1]}</strong>` },
  xAxis: { type: 'time', show: false },
  yAxis: { type: 'value', axisLabel: { fontSize: 9 } },
  series: [{
    type: 'line',
    data: readings.value.map((r) => [r.time, Number(r.valor)]),
    lineStyle: { width: 1.5, color: '#D52B1E' },
    symbol: 'none',
    areaStyle: { color: 'rgba(213,43,30,0.08)' },
    markLine: props.punto.limite_alarma != null ? {
      silent: true, symbol: 'none',
      lineStyle: { color: '#dc2626', type: 'dashed', width: 1 },
      data: [{ yAxis: Number(props.punto.limite_alarma) }],
    } : undefined,
  }],
}))

onMounted(async () => {
  try {
    const { data } = await api.get('/measurements/readings', {
      params: { punto_id: props.punto.id, limit: 100 },
    })
    readings.value = data.readings
  } catch (err) {
    console.error(err)
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
.mini-chart { min-height: 80px; }
.chart { height: 110px; width: 100%; }
.chart-loading, .chart-empty { display: flex; align-items: center; justify-content: center; height: 80px; font-size: 0.8rem; color: var(--color-text-muted); }
.chart-meta { display: flex; justify-content: space-between; font-size: 0.7rem; color: var(--color-text-muted); margin-top: 0.25rem; }
</style>
