import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { setApiAuthHandlers } from './services/api'
import './assets/main.css'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)

// Wire auth store into Axios interceptors after Pinia is initialized
import('./stores/auth').then(({ useAuthStore }) => {
  const auth = useAuthStore()
  setApiAuthHandlers(
    () => auth.getAccessToken(),
    () => auth.logout()
  )
})

app.mount('#app')
