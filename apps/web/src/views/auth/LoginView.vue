<template>
  <div class="login-view">
    <h2 class="login-title">Iniciar Sesión</h2>

    <form @submit.prevent="handleLogin" novalidate>
      <div class="field">
        <label for="email">Correo electrónico</label>
        <input
          id="email"
          v-model="form.email"
          type="email"
          placeholder="usuario@inemec.com"
          autocomplete="email"
          :disabled="auth.loading"
          required
        />
      </div>

      <div class="field">
        <label for="password">Contraseña</label>
        <div class="password-wrapper">
          <input
            id="password"
            v-model="form.password"
            :type="showPassword ? 'text' : 'password'"
            placeholder="••••••••"
            autocomplete="current-password"
            :disabled="auth.loading"
            required
          />
          <button type="button" class="toggle-password" @click="showPassword = !showPassword" tabindex="-1">
            {{ showPassword ? '🙈' : '👁' }}
          </button>
        </div>
      </div>

      <div v-if="errorMessage" class="error-alert" role="alert">
        {{ errorMessage }}
      </div>

      <button type="submit" class="btn-submit" :disabled="auth.loading || !form.email || !form.password">
        <span v-if="auth.loading">Iniciando sesión...</span>
        <span v-else>Iniciar Sesión</span>
      </button>
    </form>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const form = ref({ email: '', password: '' })
const errorMessage = ref('')
const showPassword = ref(false)

async function handleLogin() {
  errorMessage.value = ''
  const result = await auth.login(form.value.email, form.value.password)

  if (result.success) {
    const redirect = route.query.redirect || '/'
    router.push(redirect)
  } else {
    errorMessage.value = result.error
  }
}
</script>

<style scoped>
.login-title {
  font-size: 1.25rem;
  font-weight: 700;
  margin: 0 0 1.5rem;
  color: var(--color-text-primary);
}

.field {
  margin-bottom: 1rem;
}

.field label {
  display: block;
  font-size: 0.8125rem;
  font-weight: 500;
  color: var(--color-text-secondary);
  margin-bottom: 0.375rem;
}

.field input {
  width: 100%;
  padding: 0.625rem 0.75rem;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  font-size: 0.875rem;
  color: var(--color-text-primary);
  background: var(--color-surface);
  transition: border-color 0.15s;
  box-sizing: border-box;
}

.field input:focus {
  outline: none;
  border-color: var(--color-brand);
  box-shadow: 0 0 0 3px rgba(213, 43, 30, 0.1);
}

.field input:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.password-wrapper {
  position: relative;
}

.password-wrapper input {
  padding-right: 2.5rem;
}

.toggle-password {
  position: absolute;
  right: 0.5rem;
  top: 50%;
  transform: translateY(-50%);
  background: none;
  border: none;
  cursor: pointer;
  font-size: 1rem;
  padding: 0.25rem;
  line-height: 1;
}

.error-alert {
  background: #fef2f2;
  border: 1px solid #fecaca;
  color: #dc2626;
  padding: 0.625rem 0.75rem;
  border-radius: 6px;
  font-size: 0.8125rem;
  margin-bottom: 1rem;
}

.btn-submit {
  width: 100%;
  padding: 0.75rem;
  background: var(--color-brand);
  color: #fff;
  border: none;
  border-radius: 6px;
  font-size: 0.9375rem;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
  margin-top: 0.5rem;
}

.btn-submit:hover:not(:disabled) {
  opacity: 0.9;
}

.btn-submit:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
