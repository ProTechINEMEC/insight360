<template>
  <div class="app-layout">
    <!-- Sidebar -->
    <aside :class="['sidebar', { collapsed: sidebarCollapsed }]">
      <div class="sidebar-header">
        <img src="/favicon.svg" alt="Insight 360" class="sidebar-logo" />
        <span v-if="!sidebarCollapsed" class="sidebar-title">Insight 360</span>
      </div>

      <nav class="sidebar-nav">
        <RouterLink to="/" class="nav-item" :title="sidebarCollapsed ? 'Dashboard' : ''">
          <span class="nav-icon">&#9616;</span>
          <span v-if="!sidebarCollapsed" class="nav-label">Dashboard</span>
        </RouterLink>

        <RouterLink to="/activos" class="nav-item" :title="sidebarCollapsed ? 'Activos' : ''">
          <span class="nav-icon">&#9634;</span>
          <span v-if="!sidebarCollapsed" class="nav-label">Activos</span>
        </RouterLink>

        <RouterLink to="/mediciones" class="nav-item" :title="sidebarCollapsed ? 'Mediciones' : ''">
          <span class="nav-icon">&#9650;</span>
          <span v-if="!sidebarCollapsed" class="nav-label">Mediciones</span>
        </RouterLink>

        <RouterLink
          v-if="canAccessRoutes"
          to="/rutas"
          class="nav-item"
          :title="sidebarCollapsed ? 'Rutas' : ''"
        >
          <span class="nav-icon">&#9654;</span>
          <span v-if="!sidebarCollapsed" class="nav-label">Rutas de Inspección</span>
        </RouterLink>

        <RouterLink
          v-if="canAccessReports"
          to="/reportes"
          class="nav-item"
          :title="sidebarCollapsed ? 'Reportes' : ''"
        >
          <span class="nav-icon">&#9679;</span>
          <span v-if="!sidebarCollapsed" class="nav-label">Reportes</span>
        </RouterLink>

        <RouterLink
          v-if="isAdmin"
          to="/admin"
          class="nav-item"
          :title="sidebarCollapsed ? 'Administración' : ''"
        >
          <span class="nav-icon">&#9737;</span>
          <span v-if="!sidebarCollapsed" class="nav-label">Administración</span>
        </RouterLink>
      </nav>

      <div class="sidebar-footer">
        <button class="collapse-btn" @click="sidebarCollapsed = !sidebarCollapsed" :title="sidebarCollapsed ? 'Expandir' : 'Colapsar'">
          {{ sidebarCollapsed ? '▶' : '◀' }}
        </button>
      </div>
    </aside>

    <!-- Main area -->
    <div class="main-area">
      <!-- Topbar -->
      <header class="topbar">
        <div class="topbar-left">
          <h2 class="page-title">{{ pageTitle }}</h2>
        </div>
        <div class="topbar-right">
          <div class="user-menu" @click="userMenuOpen = !userMenuOpen">
            <div class="user-avatar">{{ userInitials }}</div>
            <div v-if="!sidebarCollapsed" class="user-info">
              <span class="user-name">{{ auth.user?.nombre }} {{ auth.user?.apellido }}</span>
              <span class="user-role">{{ roleLabel }}</span>
            </div>
            <div v-if="userMenuOpen" class="user-dropdown">
              <button @click="auth.logout()">Cerrar sesión</button>
            </div>
          </div>
        </div>
      </header>

      <!-- Page content -->
      <main class="content">
        <RouterView />
      </main>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const route = useRoute()
const sidebarCollapsed = ref(false)
const userMenuOpen = ref(false)

const ROLE_LABELS = {
  admin: 'Administrador',
  ingeniero_confiabilidad: 'Ing. Confiabilidad',
  tecnico_campo: 'Técnico de Campo',
  supervisor: 'Supervisor',
  visualizador: 'Visualizador',
}

const PAGE_TITLES = {
  Dashboard: 'Dashboard',
  Assets: 'Activos',
  AssetDetail: 'Detalle de Activo',
  Measurements: 'Mediciones',
  Routes: 'Rutas de Inspección',
  RouteExecution: 'Ejecución de Ruta',
  Reports: 'Reportes',
  Admin: 'Administración',
}

const userInitials = computed(() => {
  if (!auth.user) return '?'
  return `${auth.user.nombre?.[0] || ''}${auth.user.apellido?.[0] || ''}`.toUpperCase()
})

const roleLabel = computed(() => ROLE_LABELS[auth.user?.role] || auth.user?.role)
const pageTitle = computed(() => PAGE_TITLES[route.name] || 'Insight 360')

const isAdmin = computed(() => auth.user?.role === 'admin')
const canAccessRoutes = computed(() => ['admin', 'ingeniero_confiabilidad', 'supervisor', 'tecnico_campo'].includes(auth.user?.role))
const canAccessReports = computed(() => ['admin', 'ingeniero_confiabilidad', 'supervisor'].includes(auth.user?.role))
</script>

<style scoped>
.app-layout {
  display: flex;
  height: 100vh;
  overflow: hidden;
}

.sidebar {
  width: 240px;
  min-width: 240px;
  background: var(--color-sidebar);
  color: #fff;
  display: flex;
  flex-direction: column;
  transition: width 0.2s ease, min-width 0.2s ease;
  overflow: hidden;
}

.sidebar.collapsed {
  width: 56px;
  min-width: 56px;
}

.sidebar-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1rem;
  height: 56px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.sidebar-logo {
  width: 28px;
  height: 28px;
  flex-shrink: 0;
}

.sidebar-title {
  font-size: 1rem;
  font-weight: 700;
  white-space: nowrap;
  color: #fff;
}

.sidebar-nav {
  flex: 1;
  padding: 0.5rem 0;
  overflow-y: auto;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.625rem 1rem;
  color: rgba(255, 255, 255, 0.7);
  text-decoration: none;
  font-size: 0.875rem;
  transition: background 0.15s, color 0.15s;
  white-space: nowrap;
}

.nav-item:hover,
.nav-item.router-link-active {
  background: rgba(255, 255, 255, 0.1);
  color: #fff;
}

.nav-item.router-link-exact-active {
  background: var(--color-brand);
  color: #fff;
}

.nav-icon {
  font-size: 1rem;
  flex-shrink: 0;
  width: 24px;
  text-align: center;
}

.sidebar-footer {
  padding: 0.5rem;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  display: flex;
  justify-content: flex-end;
}

.collapse-btn {
  background: none;
  border: none;
  color: rgba(255, 255, 255, 0.5);
  cursor: pointer;
  padding: 0.25rem 0.5rem;
  font-size: 0.75rem;
}

.collapse-btn:hover {
  color: #fff;
}

/* Main area */
.main-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--color-bg);
}

.topbar {
  height: 56px;
  background: #fff;
  border-bottom: 1px solid var(--color-border);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 1.5rem;
  flex-shrink: 0;
}

.page-title {
  font-size: 1rem;
  font-weight: 600;
  margin: 0;
  color: var(--color-text-primary);
}

.topbar-right {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.user-menu {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
  position: relative;
}

.user-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: var(--color-brand);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.75rem;
  font-weight: 600;
  flex-shrink: 0;
}

.user-name {
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-text-primary);
  display: block;
}

.user-role {
  font-size: 0.7rem;
  color: var(--color-text-muted);
  display: block;
}

.user-dropdown {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  background: #fff;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
  min-width: 160px;
  z-index: 100;
}

.user-dropdown button {
  width: 100%;
  padding: 0.625rem 1rem;
  text-align: left;
  background: none;
  border: none;
  cursor: pointer;
  font-size: 0.875rem;
  color: var(--color-text-primary);
}

.user-dropdown button:hover {
  background: var(--color-bg);
}

.content {
  flex: 1;
  overflow-y: auto;
  padding: 1.5rem;
}
</style>
