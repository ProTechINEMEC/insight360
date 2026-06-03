// Shared constants and utilities between API and Web

const ROLES = ['admin', 'ingeniero_confiabilidad', 'tecnico_campo', 'supervisor', 'visualizador']

const CRITICIDADES = ['critico', 'esencial', 'general']

const TIPOS_PUNTO = ['vibracion', 'temperatura', 'presion', 'caudal', 'corriente', 'voltaje', 'rpm', 'nivel', 'otro']

const ROLE_LABELS = {
  admin: 'Administrador',
  ingeniero_confiabilidad: 'Ing. Confiabilidad',
  tecnico_campo: 'Técnico de Campo',
  supervisor: 'Supervisor',
  visualizador: 'Visualizador',
}

module.exports = { ROLES, CRITICIDADES, TIPOS_PUNTO, ROLE_LABELS }
