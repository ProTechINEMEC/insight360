<template>
  <div class="auth-layout">
    <div class="auth-brand">
      <img src="/favicon.svg" alt="Insight 360" class="auth-logo" />
      <div class="auth-brand-text">
        <h1>Insight 360</h1>
        <p>Plataforma CBM — INEMEC S.A.</p>
      </div>
    </div>
    <div class="auth-card">
      <RouterView />
    </div>
    <div class="auth-footer">
      <span>INEMEC S.A. &copy; {{ year }}</span>
    </div>
  </div>
</template>

<script setup>
const year = new Date().getFullYear()
</script>

<style scoped>
.auth-layout {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: var(--color-bg-auth);
  padding: 1.5rem;
  gap: 1.5rem;
}

.auth-brand {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.auth-logo {
  width: 3rem;
  height: 3rem;
}

.auth-brand-text h1 {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--color-text-primary);
  margin: 0;
}

.auth-brand-text p {
  font-size: 0.8rem;
  color: var(--color-text-muted);
  margin: 0;
}

.auth-card {
  width: 100%;
  max-width: 400px;
  background: var(--color-surface);
  border-radius: 12px;
  padding: 2rem;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
}

.auth-footer {
  font-size: 0.75rem;
  color: var(--color-text-muted);
}
</style>
