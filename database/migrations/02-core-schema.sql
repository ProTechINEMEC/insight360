-- ============================================================
-- Insight 360 — Core Schema
-- 02-core-schema.sql: Asset hierarchy and classification
-- ============================================================

-- Plant/facility (top level)
CREATE TABLE core.plantas (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      VARCHAR(20) UNIQUE NOT NULL,
    nombre      VARCHAR(200) NOT NULL,
    ubicacion   TEXT,
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Systems within a plant
CREATE TABLE core.sistemas (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    planta_id   UUID NOT NULL REFERENCES core.plantas(id) ON DELETE RESTRICT,
    codigo      VARCHAR(30) NOT NULL,
    nombre      VARCHAR(200) NOT NULL,
    descripcion TEXT,
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(planta_id, codigo)
);

-- Equipment criticality
CREATE TYPE core.criticidad AS ENUM ('critico', 'esencial', 'general');

-- Equipment (activos)
CREATE TABLE core.activos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sistema_id      UUID NOT NULL REFERENCES core.sistemas(id) ON DELETE RESTRICT,
    codigo_sap      VARCHAR(50) UNIQUE,
    tag             VARCHAR(100) NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    descripcion     TEXT,
    fabricante      VARCHAR(100),
    modelo          VARCHAR(100),
    numero_serie    VARCHAR(100),
    fecha_instalacion DATE,
    criticidad      core.criticidad NOT NULL DEFAULT 'general',
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    foto_url        TEXT,         -- MinIO object key (never raw URL)
    metadata        JSONB,        -- flexible technical specs
    created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Archivos (documents, photos) - proxied via API only
CREATE TABLE core.archivos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID REFERENCES core.activos(id) ON DELETE CASCADE,
    nombre_original VARCHAR(255) NOT NULL,
    object_key      TEXT NOT NULL UNIQUE,  -- MinIO object key
    content_type    VARCHAR(100),
    size_bytes      BIGINT,
    uploaded_by     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_activos_sistema_id ON core.activos(sistema_id);
CREATE INDEX idx_activos_criticidad ON core.activos(criticidad);
CREATE INDEX idx_activos_codigo_sap ON core.activos(codigo_sap) WHERE codigo_sap IS NOT NULL;
CREATE INDEX idx_archivos_activo_id ON core.archivos(activo_id);

-- Updated_at triggers
CREATE OR REPLACE FUNCTION core.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_plantas_updated_at
    BEFORE UPDATE ON core.plantas
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

CREATE TRIGGER trg_sistemas_updated_at
    BEFORE UPDATE ON core.sistemas
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

CREATE TRIGGER trg_activos_updated_at
    BEFORE UPDATE ON core.activos
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Row-Level Security
ALTER TABLE core.activos ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.archivos ENABLE ROW LEVEL SECURITY;

-- RLS: all authenticated users can read; only ingenieros/admins can write
CREATE POLICY activos_read ON core.activos
    FOR SELECT USING (true);

CREATE POLICY activos_write ON core.activos
    FOR ALL USING (
        current_setting('app.current_user_role', true) IN ('admin', 'ingeniero_confiabilidad', 'supervisor')
    );

CREATE POLICY archivos_read ON core.archivos
    FOR SELECT USING (true);

CREATE POLICY archivos_write ON core.archivos
    FOR ALL USING (
        current_setting('app.current_user_role', true) IN ('admin', 'ingeniero_confiabilidad', 'supervisor')
    );

-- Seed: GGS plant (pilot)
INSERT INTO core.plantas (codigo, nombre, ubicacion)
VALUES ('GGS-001', 'Estación GGS Principal', 'Campo Cupiagua, Casanare, Colombia');

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'COMP-001', 'Sistema de Compresión', 'Compresores de gas de alta presión'
FROM core.plantas WHERE codigo = 'GGS-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'BOMB-001', 'Sistema de Bombeo', 'Bombas centrífugas de crudo'
FROM core.plantas WHERE codigo = 'GGS-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'ELEC-001', 'Sistema Eléctrico', 'Motores y transformadores'
FROM core.plantas WHERE codigo = 'GGS-001';
