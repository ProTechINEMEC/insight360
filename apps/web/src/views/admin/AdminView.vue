<template>
  <div class="admin-view">
    <div class="page-header"><h3>Administración</h3></div>

    <div class="admin-tabs">
      <button :class="['tab', { active: tab === 'users' }]" @click="tab = 'users'">Usuarios</button>
    </div>

    <!-- Users management -->
    <div v-if="tab === 'users'" class="card">
      <div class="card-header-row">
        <span class="section-title">Usuarios del Sistema</span>
        <button class="btn btn-primary btn-sm" @click="showCreate = true">+ Nuevo Usuario</button>
      </div>
      <div v-if="loading" class="loading-box"><div class="spinner"></div></div>
      <table v-else>
        <thead>
          <tr>
            <th>Nombre</th>
            <th>Cédula</th>
            <th>Email</th>
            <th>Rol</th>
            <th>Estado</th>
            <th>Último Acceso</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="u in users" :key="u.id">
            <td>{{ u.nombre }} {{ u.apellido }}</td>
            <td>{{ u.cedula }}</td>
            <td>{{ u.email }}</td>
            <td><span class="badge badge-general">{{ ROLE_LABELS[u.role] || u.role }}</span></td>
            <td>
              <span :class="['badge', u.activo ? 'badge-general' : 'badge-critico']">
                {{ u.activo ? 'Activo' : 'Inactivo' }}
              </span>
            </td>
            <td class="text-muted">{{ u.ultimo_acceso ? new Date(u.ultimo_acceso).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' }) : 'Nunca' }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Create user modal -->
    <Teleport to="body">
      <div v-if="showCreate" class="modal-overlay" @click.self="showCreate = false">
        <div class="modal">
          <div class="modal-header">
            <h4>Nuevo Usuario</h4>
            <button class="modal-close" @click="showCreate = false">✕</button>
          </div>
          <form @submit.prevent="createUser" class="modal-body">
            <div class="form-grid">
              <div class="field"><label>Cédula *</label><input v-model="newUser.cedula" required /></div>
              <div class="field"><label>Rol *</label>
                <select v-model="newUser.role">
                  <option v-for="(label, key) in ROLE_LABELS" :key="key" :value="key">{{ label }}</option>
                </select>
              </div>
              <div class="field"><label>Nombre *</label><input v-model="newUser.nombre" required /></div>
              <div class="field"><label>Apellido *</label><input v-model="newUser.apellido" required /></div>
              <div class="field field-full"><label>Email *</label><input v-model="newUser.email" type="email" required /></div>
              <div class="field field-full"><label>Contraseña *</label><input v-model="newUser.password" type="password" minlength="8" required placeholder="Mínimo 8 caracteres" /></div>
            </div>
            <div v-if="createError" class="error-alert">{{ createError }}</div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" @click="showCreate = false">Cancelar</button>
              <button type="submit" class="btn btn-primary" :disabled="creating">{{ creating ? 'Guardando...' : 'Crear Usuario' }}</button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { api } from '@/services/api'

const tab = ref('users')
const loading = ref(true)
const users = ref([])
const showCreate = ref(false)
const creating = ref(false)
const createError = ref('')

const ROLE_LABELS = {
  admin: 'Administrador',
  ingeniero_confiabilidad: 'Ing. Confiabilidad',
  tecnico_campo: 'Técnico de Campo',
  supervisor: 'Supervisor',
  visualizador: 'Visualizador',
}

const newUser = reactive({ cedula: '', nombre: '', apellido: '', email: '', password: '', role: 'tecnico_campo' })

async function fetchUsers() {
  loading.value = true
  try {
    const { data } = await api.get('/users')
    users.value = data.users
  } finally {
    loading.value = false
  }
}

async function createUser() {
  creating.value = true
  createError.value = ''
  try {
    await api.post('/users', newUser)
    showCreate.value = false
    Object.assign(newUser, { cedula: '', nombre: '', apellido: '', email: '', password: '', role: 'tecnico_campo' })
    await fetchUsers()
  } catch (err) {
    createError.value = err.response?.data?.error || 'Error al crear usuario'
  } finally {
    creating.value = false
  }
}

onMounted(fetchUsers)
</script>

<style scoped>
.admin-view { display: flex; flex-direction: column; gap: 1rem; }
.admin-tabs { display: flex; border-bottom: 2px solid var(--color-border); }
.tab { padding: 0.625rem 1.25rem; background: none; border: none; border-bottom: 2px solid transparent; cursor: pointer; font-weight: 500; color: var(--color-text-muted); margin-bottom: -2px; font-size: 0.875rem; }
.tab.active { color: var(--color-brand); border-bottom-color: var(--color-brand); }
.card-header-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 1rem; }
.section-title { font-weight: 600; }
.btn-sm { padding: 0.25rem 0.75rem; font-size: 0.8125rem; }
.text-muted { color: var(--color-text-muted); font-size: 0.8125rem; }
.loading-box { display: flex; justify-content: center; padding: 2rem; }
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 1000; padding: 1rem; }
.modal { background: #fff; border-radius: 12px; width: 100%; max-width: 520px; box-shadow: 0 20px 60px rgba(0,0,0,0.2); }
.modal-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-border); }
.modal-header h4 { font-size: 1rem; font-weight: 700; }
.modal-close { background: none; border: none; cursor: pointer; font-size: 1rem; color: var(--color-text-muted); }
.modal-body { padding: 1.5rem; }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-bottom: 1rem; }
.field-full { grid-column: 1 / -1; }
.field label { display: block; font-size: 0.8rem; font-weight: 500; margin-bottom: 0.25rem; color: var(--color-text-secondary); }
.field input, .field select { width: 100%; padding: 0.5rem 0.75rem; border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.875rem; }
.error-alert { background: #fef2f2; border: 1px solid #fecaca; color: #dc2626; padding: 0.5rem 0.75rem; border-radius: 6px; font-size: 0.8125rem; margin-bottom: 1rem; }
.modal-footer { display: flex; gap: 0.75rem; justify-content: flex-end; }
</style>
