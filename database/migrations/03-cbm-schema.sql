-- ============================================================
-- Insight 360 — CBM Schema
-- 03-cbm-schema.sql: Measurement points, readings, health
-- CRITICAL: TimescaleDB hypertables must be created BEFORE any data insert
-- ============================================================

-- Measurement point types
CREATE TYPE cbm.tipo_punto AS ENUM (
    'vibracion',
    'temperatura',
    'presion',
    'caudal',
    'corriente',
    'voltaje',
    'rpm',
    'nivel',
    'otro'
);

-- Measurement points on an asset
CREATE TABLE cbm.puntos_medicion (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
    codigo          VARCHAR(50) NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    tipo            cbm.tipo_punto NOT NULL,
    unidad          VARCHAR(30) NOT NULL,       -- e.g., mm/s, °C, bar, A
    limite_alerta   NUMERIC(12,4),              -- yellow threshold
    limite_alarma   NUMERIC(12,4),              -- red threshold
    descripcion     TEXT,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(activo_id, codigo)
);

-- Measurement entries (TIME SERIES — becomes hypertable)
CREATE TABLE cbm.measurement_entries (
    time            TIMESTAMPTZ NOT NULL,
    punto_id        UUID NOT NULL REFERENCES cbm.puntos_medicion(id) ON DELETE CASCADE,
    valor           NUMERIC(14,6) NOT NULL,
    fuente          VARCHAR(50) DEFAULT 'manual',   -- manual, sensor, import
    registrado_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    notas           TEXT
);

-- Convert to TimescaleDB hypertable (chunk by 1 month)
SELECT create_hypertable(
    'cbm.measurement_entries',
    'time',
    chunk_time_interval => INTERVAL '1 month',
    if_not_exists => TRUE
);

-- Fault mode catalog
CREATE TABLE cbm.modos_falla (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
    codigo          VARCHAR(50) NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    descripcion     TEXT,
    consecuencia    TEXT,
    accion_correctiva TEXT,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(activo_id, codigo)
);

-- Health state enum
CREATE TYPE cbm.estado_salud AS ENUM ('bueno', 'alerta', 'critico', 'desconocido');

-- Asset health snapshots (calculated, stored for history)
CREATE TABLE cbm.health_snapshots (
    time            TIMESTAMPTZ NOT NULL,
    activo_id       UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
    estado          cbm.estado_salud NOT NULL DEFAULT 'desconocido',
    score           NUMERIC(5,2),               -- 0-100 health score
    detalle         JSONB                        -- per-punto breakdown
);

-- Convert health snapshots to hypertable
SELECT create_hypertable(
    'cbm.health_snapshots',
    'time',
    chunk_time_interval => INTERVAL '1 month',
    if_not_exists => TRUE
);

-- Inspection entries (structured field observations)
CREATE TABLE cbm.inspection_entries (
    time            TIMESTAMPTZ NOT NULL,
    activo_id       UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
    tecnico_id      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    observaciones   TEXT,
    hallazgos       JSONB,                      -- structured findings
    modo_falla_id   UUID REFERENCES cbm.modos_falla(id) ON DELETE SET NULL,
    sincronizado    BOOLEAN NOT NULL DEFAULT TRUE,  -- FALSE when from offline PWA
    offline_uuid    UUID,                   -- dedup via idx_inspections_offline                -- client-generated UUID for dedup
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Convert inspection entries to hypertable
SELECT create_hypertable(
    'cbm.inspection_entries',
    'time',
    chunk_time_interval => INTERVAL '1 month',
    if_not_exists => TRUE
);

-- Indexes (TimescaleDB recommends including time in compound indexes)
CREATE INDEX idx_measurements_punto_time ON cbm.measurement_entries(punto_id, time DESC);
CREATE INDEX idx_health_activo_time ON cbm.health_snapshots(activo_id, time DESC);
CREATE INDEX idx_inspections_activo_time ON cbm.inspection_entries(activo_id, time DESC);
CREATE INDEX idx_inspections_tecnico ON cbm.inspection_entries(tecnico_id);
CREATE INDEX idx_inspections_offline ON cbm.inspection_entries(offline_uuid) WHERE offline_uuid IS NOT NULL;

-- Compression policy (after 3 months)
-- TODO: Enable after columnstore setup: SELECT add_compression_policy('cbm.measurement_entries', INTERVAL '3 months');
-- TODO: Enable after columnstore setup: SELECT add_compression_policy('cbm.health_snapshots', INTERVAL '3 months');

-- Retention policy (keep 5 years)
-- TODO: Add after production sizing: SELECT add_retention_policy('cbm.measurement_entries', INTERVAL '5 years');
