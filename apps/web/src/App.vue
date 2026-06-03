<template>
  <RouterView />
</template>

<script setup>
import { onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()

onMounted(async () => {
  // Try to restore session from refresh token cookie on app load
  await auth.tryRestoreSession()
})
</script>
