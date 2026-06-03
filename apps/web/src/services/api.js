import axios from 'axios'

// Base Axios instance for all API calls
export const api = axios.create({
  baseURL: `${import.meta.env.VITE_API_URL || ''}/api/v1`,
  withCredentials: true,  // Required for httpOnly refresh token cookie
  timeout: 30000,
})

// Flag to prevent multiple concurrent refresh attempts
let isRefreshing = false
let refreshQueue = []

function processQueue(error, token = null) {
  refreshQueue.forEach((p) => {
    if (error) p.reject(error)
    else p.resolve(token)
  })
  refreshQueue = []
}

// Request interceptor: attach access token from Pinia store
api.interceptors.request.use((config) => {
  // Dynamically import to avoid circular dependency
  // useAuthStore() cannot be called at module level (Pinia not yet initialized)
  const { useAuthStore } = require('@/stores/auth')
  const auth = useAuthStore()
  const token = auth.getAccessToken()
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// Response interceptor: handle 401 and auto-refresh
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config

    if (
      error.response?.status === 401 &&
      error.response?.data?.code === 'TOKEN_EXPIRED' &&
      !originalRequest._retry
    ) {
      if (isRefreshing) {
        // Queue this request until refresh completes
        return new Promise((resolve, reject) => {
          refreshQueue.push({ resolve, reject })
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`
          return api(originalRequest)
        })
      }

      originalRequest._retry = true
      isRefreshing = true

      try {
        const { useAuthStore } = await import('@/stores/auth')
        const auth = useAuthStore()
        const newToken = await auth.refreshAccessToken()
        processQueue(null, newToken)
        originalRequest.headers.Authorization = `Bearer ${newToken}`
        return api(originalRequest)
      } catch (refreshError) {
        processQueue(refreshError, null)
        // Refresh failed — force logout
        const { useAuthStore } = await import('@/stores/auth')
        const auth = useAuthStore()
        await auth.logout()
        return Promise.reject(refreshError)
      } finally {
        isRefreshing = false
      }
    }

    return Promise.reject(error)
  }
)

export default api
