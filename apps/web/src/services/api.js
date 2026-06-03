import axios from 'axios'

// Base Axios instance for all API calls
export const api = axios.create({
  baseURL: '/api/v1',
  withCredentials: true,  // Required for httpOnly refresh token cookie
  timeout: 30000,
})

// Token getter — set from auth store after Pinia is initialized
let _getToken = () => null
let _onUnauthorized = () => {}

export function setApiAuthHandlers(getToken, onUnauthorized) {
  _getToken = getToken
  _onUnauthorized = onUnauthorized
}

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

// Request interceptor: attach access token from auth store
api.interceptors.request.use((config) => {
  const token = _getToken()
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
        const { data } = await api.post('/auth/refresh')
        const newToken = data.accessToken
        processQueue(null, newToken)
        originalRequest.headers.Authorization = `Bearer ${newToken}`
        return api(originalRequest)
      } catch (refreshError) {
        processQueue(refreshError, null)
        _onUnauthorized()
        return Promise.reject(refreshError)
      } finally {
        isRefreshing = false
      }
    }

    return Promise.reject(error)
  }
)

export default api
