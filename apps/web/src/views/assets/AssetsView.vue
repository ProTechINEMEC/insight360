<template>
  <div class="assets-view">
    <div class="page-header">
      <h3>Activos</h3>
      <button
        v-if="canWrite"
        class="btn btn-primary"
        @click="showCreateModal = true"
      >
        + Nuevo Activo
      </button>
    </div>

    <!-- Filters -->
    <div class="card filters">
      <div class="filter-row">
        <input
          v-model="filters.search"
          type="text"
          placeholder="Buscar por nombre, tag o código SAP..."
          class="search-input"
          @input="fetchAssets"
        />
        <select v-model="filters.criticidad" @change="fetchAssets">
          <option value="">Todas las criticidades</option>
          <option value="critico">Crítico</option>
          <option value="esencial">Esencial</option>
          <option value="general">General</option>
        </select>
        <select v-model="filters.sistema_id" @change="fetchAssets">
          <option value="">Todos los sistemas</option>
          <option v-for="s in sistemas" :key="s.id" :value="s.id">{{ s.nombre }}</option>
        </select>
      </div>
    </div>

    <!-- Assets table -->
    <div class="card">
      <div v-if="loading" class="loading-box"><div class="spinner"></div></div>
      <table v-else>
        <thead>
          <tr>
            <th>Tag / Nombre</th>
            <th>Sistema</th>
            <th>Planta</th>
            <th>Fabricante / Modelo</th>
            <th>Criticidad</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="a in assets" :key="a.id">
            <td>
              <div class="asset-name">{{ a.tag }}</div>
              <div class="asset-sub">{{ a.nombre }}</div>
            </td>
            <td>{{ a.sistema_nombre }}</td>
            <td>{{ a.planta_nombre }}</td>
            <td>
              <span v-if="a.fabricante">{{ a.fabricante }}</span>
              <span v-if="a.modelo" class="text-muted"> / {{ a.modelo }}</span>
              <span v-if="!a.fabricante" class="text-muted">—</span>
            </td>
            <td>
              <span :class="`badge badge-${a.criticidad}`">{{ a.criticidad }}</span>
            </td>
            <td class="actions-cell">
              <RouterLink :to="`/activos/${a.id}`" class="btn btn-secondary btn-sm">
                Ver
              </RouterLink>
            </td>
          </tr>
          <tr v-if="!assets.length && !loading">
            <td colspan="6" class="empty-cell">No se encontraron activos</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Create Asset Modal -->
    <Teleport to="body">
      <div v-if="showCreateModal" class="modal-overlay" @click.self="showCreateModal = false">
        <div class="modal">
          <div class="modal-header">
            <h4>Nuevo Activo</h4>
            <button class="modal-close" @click="showCreateModal = false">✕</button>
          </div>
          <form @submit.prevent="createAsset" class="modal-body">
            <div class="form-grid">
              <div class="field">
                <label>Sistema *</label>
                <select v-model="newAsset.sistema_id" required>
                  <option value="">Seleccionar sistema</option>
                  <option v-for="s in sistemas" :key="s.id" :value="s.id">{{ s.nombre }}</option>
                </select>
              </div>
              <div class="field">
                <label>Tag *</label>
                <input v-model="newAsset.tag" type="text" placeholder="COMP-001-A" required />
              </div>
              <div class="field field-full">
                <label>Nombre *</label>
                <input v-model="newAsset.nombre" type="text" placeholder="Compresor de Gas Principal" required />
              </div>
              <div class="field">
                <label>Código SAP</label>
                <input v-model="newAsset.codigo_sap" type="text" placeholder="1000XXXXX" />
              </div>
              <div class="field">
                <label>Criticidad *</label>
                <select v-model="newAsset.criticidad">
                  <option value="general">General</option>
                  <option value="esencial">Esencial</option>
                  <option value="critico">Crítico</option>
                </select>
              </div>
              <div class="field">
                <label>Fabricante</label>
                <input v-model="newAsset.fabricante" type="text" placeholder="GE, Siemens..." />
              </div>
              <div class="field">
                <label>Modelo</label>
                <input v-model="newAsset.modelo" type="text" />
              </div>
              <div class="field">
                <label>N° Serie</label>
                <input v-model="newAsset.numero_serie" type="text" />
              </div>
              <div class="field">
                <label>Fecha Instalación</label>
                <input v-model="newAsset.fecha_instalacion" type="date" />
              </div>
              <div class="field field-full">
                <label>Descripción</label>
                <textarea v-model="newAsset.descripcion" rows="2"></textarea>
              </div>
            </div>
            <div v-if="createError" class="error-alert">{{ createError }}</div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" @click="showCreateModal = false">Cancelar</button>
              <button type="submit" class="btn btn-primary" :disabled="creating">
                {{ creating ? 'Guardando...' : 'Crear Activo' }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/services/api'

const auth = useAuthStore()
const loading = ref(true)
const assets = ref([])
const sistemas = ref([])
const showCreateModal = ref(false)
const creating = ref(false)
const createError = ref('')

const filters = reactive({ search: '', criticidad: '', sistema_id: '' })

const canWrite = computed(() =>
  ['admin', 'ingeniero_confiabilidad', 'supervisor'].includes(auth.user?.role)
)

const newAsset = reactive({
  sistema_id: '', tag: '', nombre: '', codigo_sap: '',
  criticidad: 'general', fabricante: '', modelo: '',
  numero_serie: '', fecha_instalacion: '', descripcion: '',
})

async function fetchAssets() {
  loading.value = true
  try {
    const params = {}
    if (filters.search) params.search = filters.search
    if (filters.criticidad) params.criticidad = filters.criticidad
    if (filters.sistema_id) params.sistema_id = filters.sistema_id
    const { data } = await api.get('/assets', { params })
    assets.value = data.activos
  } catch (err) {
    console.error(err)
  } finally {
    loading.value = false
  }
}

async function createAsset() {
  creating.value = true
  createError.value = ''
  try {
    await api.post('/assets', newAsset)
    showCreateModal.value = false
    Object.assign(newAsset, { sistema_id: '', tag: '', nombre: '', codigo_sap: '', criticidad: 'general', fabricante: '', modelo: '', numero_serie: '', fecha_instalacion: '', descripcion: '' })
    await fetchAssets()
  } catch (err) {
    createError.value = err.response?.data?.error || 'Error al crear el activo'
  } finally {
    creating.value = false
  }
}

onMounted(async () => {
  const [, sistemasRes] = await Promise.allSettled([
    fetchAssets(),
    api.get('/assets/sistemas'),
  ])
  if (sistemasRes.status === 'fulfilled') {
    sistemas.value = sistemasRes.value.data.sistemas
  }
})
</script>

<style scoped>
.assets-view { display: flex; flex-direction: column; gap: 1rem; }

.filters { padding: 1rem 1.5rem; }

.filter-row {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
}

.search-input {
  flex: 1;
  min-width: 200px;
  padding: 0.5rem 0.75rem;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 0.875rem;
}

select {
  padding: 0.5rem 0.75rem;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 0.875rem;
  background: #fff;
  cursor: pointer;
}

.asset-name { font-weight: 500; font-size: 0.875rem; }
.asset-sub { font-size: 0.75rem; color: var(--color-text-muted); }
.text-muted { color: var(--color-text-muted); }

.actions-cell { width: 60px; }
.btn-sm { padding: 0.25rem 0.625rem; font-size: 0.75rem; }

.empty-cell {
  text-align: center;
  color: var(--color-text-muted);
  padding: 2rem;
}

.loading-box {
  display: flex;
  justify-content: center;
  padding: 2rem;
}

/* Modal */
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 1rem;
}

.modal {
  background: #fff;
  border-radius: 12px;
  width: 100%;
  max-width: 640px;
  max-height: 90vh;
  overflow-y: auto;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2);
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.25rem 1.5rem;
  border-bottom: 1px solid var(--color-border);
}

.modal-header h4 { font-size: 1rem; font-weight: 700; }

.modal-close {
  background: none;
  border: none;
  cursor: pointer;
  font-size: 1rem;
  color: var(--color-text-muted);
}

.modal-body { padding: 1.5rem; }

.form-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
  margin-bottom: 1rem;
}

.field-full { grid-column: 1 / -1; }

.field label {
  display: block;
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--color-text-secondary);
  margin-bottom: 0.25rem;
}

.field input, .field select, .field textarea {
  width: 100%;
  padding: 0.5rem 0.75rem;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 0.875rem;
  font-family: inherit;
}

.field input:focus, .field select:focus, .field textarea:focus {
  outline: none;
  border-color: var(--color-brand);
}

.error-alert {
  background: #fef2f2;
  border: 1px solid #fecaca;
  color: #dc2626;
  padding: 0.5rem 0.75rem;
  border-radius: 6px;
  font-size: 0.8125rem;
  margin-bottom: 1rem;
}

.modal-footer {
  display: flex;
  gap: 0.75rem;
  justify-content: flex-end;
}
</style>
