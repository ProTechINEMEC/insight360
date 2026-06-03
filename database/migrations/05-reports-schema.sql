-- ============================================================
-- Insight 360 — Reports Schema
-- 05-reports-schema.sql: Report queue and generated reports
-- ============================================================

CREATE TYPE reports.estado_reporte AS ENUM (
    'pendiente',
    'generando',
    'completado',
    'fallido'
);

CREATE TYPE reports.tipo_reporte AS ENUM (
    'tendencia_activo',
    'salud_planta',
    'ruta_inspeccion',
    'diagnostico_falla',
    'resumen_ejecutivo'
);

-- Report generation queue (processed by Bull/Puppeteer)
CREATE TABLE reports.report_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo            reports.tipo_reporte NOT NULL,
    estado          reports.estado_reporte NOT NULL DEFAULT 'pendiente',
    solicitado_por  UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    parametros      JSONB NOT NULL DEFAULT '{}',   -- date range, asset IDs, etc.
    object_key      TEXT,                           -- MinIO key once generated
    error_mensaje   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ
);

-- Report templates (configurable by admins)
CREATE TABLE reports.plantillas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(200) NOT NULL,
    tipo            reports.tipo_reporte NOT NULL,
    configuracion   JSONB NOT NULL DEFAULT '{}',
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_report_queue_estado ON reports.report_queue(estado);
CREATE INDEX idx_report_queue_solicitado_por ON reports.report_queue(solicitado_por);
CREATE INDEX idx_report_queue_created_at ON reports.report_queue(created_at DESC);
