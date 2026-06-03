-- ============================================================
-- Insight 360 — Routes Schema
-- 04-routes-schema.sql: Inspection routes and field assignments
-- ============================================================

CREATE TYPE routes.estado_ruta AS ENUM (
    'borrador',
    'activa',
    'en_progreso',
    'completada',
    'cancelada'
);

CREATE TYPE routes.frecuencia AS ENUM (
    'diaria',
    'semanal',
    'quincenal',
    'mensual',
    'trimestral',
    'semestral',
    'anual',
    'bajo_condicion'
);

-- Inspection route definition
CREATE TABLE routes.rutas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    descripcion     TEXT,
    frecuencia      routes.frecuencia NOT NULL,
    planta_id       UUID NOT NULL REFERENCES core.plantas(id) ON DELETE RESTRICT,
    responsable_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Measurement points included in a route (ordered)
CREATE TABLE routes.ruta_puntos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ruta_id         UUID NOT NULL REFERENCES routes.rutas(id) ON DELETE CASCADE,
    punto_id        UUID NOT NULL REFERENCES cbm.puntos_medicion(id) ON DELETE CASCADE,
    orden           INTEGER NOT NULL,
    instrucciones   TEXT,
    UNIQUE(ruta_id, punto_id),
    UNIQUE(ruta_id, orden)
);

-- Route execution instances
CREATE TABLE routes.ejecuciones (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ruta_id         UUID NOT NULL REFERENCES routes.rutas(id) ON DELETE RESTRICT,
    tecnico_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    estado          routes.estado_ruta NOT NULL DEFAULT 'en_progreso',
    fecha_inicio    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_fin       TIMESTAMPTZ,
    notas           TEXT,
    sincronizada    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Individual readings taken during an execution
CREATE TABLE routes.lecturas_ejecucion (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id    UUID NOT NULL REFERENCES routes.ejecuciones(id) ON DELETE CASCADE,
    punto_id        UUID NOT NULL REFERENCES cbm.puntos_medicion(id) ON DELETE RESTRICT,
    valor           NUMERIC(14,6) NOT NULL,
    timestamp_lectura TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notas           TEXT,
    offline_uuid    UUID UNIQUE
);

-- Indexes
CREATE INDEX idx_rutas_planta ON routes.rutas(planta_id);
CREATE INDEX idx_ruta_puntos_ruta ON routes.ruta_puntos(ruta_id);
CREATE INDEX idx_ejecuciones_ruta ON routes.ejecuciones(ruta_id);
CREATE INDEX idx_ejecuciones_tecnico ON routes.ejecuciones(tecnico_id);
CREATE INDEX idx_ejecuciones_estado ON routes.ejecuciones(estado);
CREATE INDEX idx_lecturas_ejecucion ON routes.lecturas_ejecucion(ejecucion_id);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION routes.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_rutas_updated_at
    BEFORE UPDATE ON routes.rutas
    FOR EACH ROW EXECUTE FUNCTION routes.set_updated_at();
