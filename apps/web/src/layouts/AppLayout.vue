<template>
  <div class="app-layout">
    <!-- Topbar -->
    <header class="topbar">
      <div class="topbar-left">
        <img src="/favicon.svg" alt="Insight 360" class="topbar-logo" />
        <div class="topbar-brand">
          <span class="brand-name">Insight 360</span>
          <span class="brand-sub">Ecopetrol · GGS</span>
        </div>
      </div>
      <nav class="topbar-nav">
        <RouterLink to="/activos/arbol" class="nav-link">Árbol de Equipos</RouterLink>
        <RouterLink to="/salud" class="nav-link">Salud de Equipos</RouterLink>
      </nav>
      <div class="topbar-right">
        <div class="user-menu" @click="userMenuOpen = !userMenuOpen" v-click-outside="() => userMenuOpen = false">
          <div class="user-avatar">{{ userInitials }}</div>
          <div class="user-info">
            <span class="user-name">{{ auth.user?.nombre }} {{ auth.user?.apellido }}</span>
            <span class="user-role">{{ roleLabel }}</span>
          </div>
          <div v-if="userMenuOpen" class="user-dropdown">
            <button @click.stop="auth.logout()">Cerrar sesión</button>
          </div>
        </div>
      </div>
    </header>

    <!-- Page content -->
    <main class="content">
      <RouterView />
    </main>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const userMenuOpen = ref(false)

const ROLE_LABELS = {
  admin: 'Administrador',
  ingeniero_confiabilidad: 'Ing. Confiabilidad',
  tecnico_campo: 'Técnico de Campo',
  supervisor: 'Supervisor',
  visualizador: 'Visualizador',
}

const vClickOutside = {
  mounted(el, binding) {
    el._clickOutsideHandler = (e) => { if (!el.contains(e.target)) binding.value(e) }
    document.addEventListener('click', el._clickOutsideHandler)
  },
  unmounted(el) {
    document.removeEventListener('click', el._clickOutsideHandler)
  },
}

const userInitials = computed(() => {
  if (!auth.user) return '?'
  return `${auth.user.nombre?.[0] || ''}${auth.user.apellido?.[0] || ''}`.toUpperCase()
})
const roleLabel = computed(() => ROLE_LABELS[auth.user?.role] || auth.user?.role)
</script>

<style scoped>
.app-layout {
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
}

.topbar {
  height: 52px;
  background: var(--color-sidebar);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 1.25rem;
  flex-shrink: 0;
  border-bottom: 1px solid rgba(255,255,255,0.06);
}

.topbar-left {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.topbar-logo {
  width: 28px;
  height: 28px;
  flex-shrink: 0;
}

.topbar-brand {
  display: flex;
  flex-direction: column;
  line-height: 1.2;
}

.brand-name {
  font-size: 0.9375rem;
  font-weight: 700;
  color: #fff;
  letter-spacing: 0.01em;
}

.brand-sub {
  font-size: 0.7rem;
  color: rgba(255,255,255,0.5);
  letter-spacing: 0.04em;
}

.topbar-nav {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  flex: 1;
  padding: 0 1.5rem;
}

.nav-link {
  padding: 0.3rem 0.875rem;
  border-radius: 6px;
  font-size: 0.8125rem;
  font-weight: 500;
  color: rgba(255,255,255,0.65);
  text-decoration: none;
  transition: background 0.15s, color 0.15s;
}

.nav-link:hover {
  background: rgba(255,255,255,0.08);
  color: rgba(255,255,255,0.9);
}

.nav-link.router-link-active {
  background: rgba(255,255,255,0.12);
  color: #fff;
}

.topbar-right {
  display: flex;
  align-items: center;
}

.user-menu {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
  position: relative;
  padding: 0.25rem 0.5rem;
  border-radius: 6px;
  transition: background 0.15s;
}

.user-menu:hover {
  background: rgba(255,255,255,0.08);
}

.user-avatar {
  width: 30px;
  height: 30px;
  border-radius: 50%;
  background: var(--color-brand);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.7rem;
  font-weight: 700;
  flex-shrink: 0;
}

.user-name {
  font-size: 0.8125rem;
  font-weight: 500;
  color: rgba(255,255,255,0.9);
  display: block;
  white-space: nowrap;
}

.user-role {
  font-size: 0.68rem;
  color: rgba(255,255,255,0.45);
  display: block;
}

.user-dropdown {
  position: absolute;
  top: calc(100% + 6px);
  right: 0;
  background: #fff;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.15);
  min-width: 150px;
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
  border-radius: 8px;
}

.content {
  flex: 1;
  overflow-y: auto;
  background: var(--color-bg);
}
</style>
