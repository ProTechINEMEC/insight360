import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  // Auth layout
  {
    path: '/auth',
    component: () => import('@/layouts/AuthLayout.vue'),
    children: [
      {
        path: 'login',
        name: 'Login',
        component: () => import('@/views/auth/LoginView.vue'),
        meta: { guestOnly: true },
      },
    ],
  },

  // App layout (authenticated)
  {
    path: '/',
    component: () => import('@/layouts/AppLayout.vue'),
    meta: { requiresAuth: true },
    children: [
      {
        path: '',
        redirect: '/activos/arbol',
      },
      {
        path: 'activos',
        name: 'Assets',
        component: () => import('@/views/assets/AssetsView.vue'),
      },
      {
        path: 'activos/arbol',
        name: 'AssetTree',
        component: () => import('@/views/assets/AssetTreeView.vue'),
      },
      {
        path: 'salud',
        name: 'SaludEquipos',
        component: () => import('@/views/salud/SaludEquiposView.vue'),
      },
      {
        path: 'activos/:id',
        name: 'AssetDetail',
        component: () => import('@/views/assets/AssetDetailView.vue'),
      },
      {
        path: 'mediciones',
        name: 'Measurements',
        component: () => import('@/views/measurements/MeasurementsView.vue'),
      },
      {
        path: 'rutas',
        name: 'Routes',
        component: () => import('@/views/routes/RoutesView.vue'),
        meta: { roles: ['admin', 'ingeniero_confiabilidad', 'supervisor', 'tecnico_campo'] },
      },
      {
        path: 'rutas/:id/ejecucion',
        name: 'RouteExecution',
        component: () => import('@/views/routes/RouteExecutionView.vue'),
        meta: { roles: ['tecnico_campo', 'supervisor'] },
      },
      {
        path: 'reportes',
        name: 'Reports',
        component: () => import('@/views/reports/ReportsView.vue'),
        meta: { roles: ['admin', 'ingeniero_confiabilidad', 'supervisor'] },
      },
      {
        path: 'inspecciones/:id',
        name: 'InspeccionDetail',
        component: () => import('@/views/salud/InspeccionDetailView.vue'),
      },
      {
        path: 'tecnicas',
        name: 'TecnicasAdmin',
        component: () => import('@/views/admin/TecnicasAdminView.vue'),
        meta: { roles: ['admin', 'ingeniero_confiabilidad'] },
      },
      {
        path: 'admin',
        name: 'Admin',
        component: () => import('@/views/admin/AdminView.vue'),
        meta: { roles: ['admin'] },
      },
    ],
  },

  // Catch-all redirect
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

// Navigation guard
router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'Login', query: { redirect: to.fullPath } }
  }

  if (to.meta.guestOnly && auth.isAuthenticated) {
    return { name: 'Dashboard' }
  }

  // Role-based access
  if (to.meta.roles && auth.user && !to.meta.roles.includes(auth.user.role)) {
    return { name: 'Dashboard' }
  }
})

export default router
