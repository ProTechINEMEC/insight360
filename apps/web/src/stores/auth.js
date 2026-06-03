import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { api } from '@/services/api'
import router from '@/router'

export const useAuthStore = defineStore('auth', () => {
  // Access token is ONLY stored in Pinia memory — never localStorage/sessionStorage
  const accessToken = ref(null)
  const user = ref(null)
  const loading = ref(false)

  const isAuthenticated = computed(() => !!accessToken.value && !!user.value)

  async function login(email, password) {
    loading.value = true
    try {
      const { data } = await api.post('/auth/login', { email, password })
      accessToken.value = data.accessToken
      user.value = data.user
      return { success: true }
    } catch (err) {
      const message = err.response?.data?.error || 'Error de conexión'
      return { success: false, error: message }
    } finally {
      loading.value = false
    }
  }

  async function logout() {
    try {
      await api.post('/auth/logout')
    } catch {
      // Ignore errors — clear local state regardless
    } finally {
      accessToken.value = null
      user.value = null
      router.push({ name: 'Login' })
    }
  }

  // Called on app mount — tries to use the httpOnly refresh token cookie
  async function tryRestoreSession() {
    try {
      const { data } = await api.post('/auth/refresh')
      accessToken.value = data.accessToken
      user.value = data.user
    } catch {
      // No valid refresh token — user needs to log in
      accessToken.value = null
      user.value = null
    }
  }

  // Called by Axios interceptor when access token expires (401)
  async function refreshAccessToken() {
    const { data } = await api.post('/auth/refresh')
    accessToken.value = data.accessToken
    user.value = data.user
    return data.accessToken
  }

  function getAccessToken() {
    return accessToken.value
  }

  return {
    user,
    loading,
    isAuthenticated,
    login,
    logout,
    tryRestoreSession,
    refreshAccessToken,
    getAccessToken,
  }
})
