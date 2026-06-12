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

-- ================================================================
-- Seed: Ecopetrol GGS — Tres campos de producción Casanare
-- ================================================================

INSERT INTO core.plantas (codigo, nombre, ubicacion) VALUES
  ('CUP-001', 'Campo Cupiagua',  'Piedemonte Llanero, Casanare, Colombia'),
  ('FLO-001', 'Campo Floreña',   'Piedemonte Llanero, Casanare, Colombia'),
  ('CUS-001', 'Campo Cusiana',   'Piedemonte Llanero, Casanare, Colombia');

-- Sistemas — Campo Cupiagua
INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'COMP', 'Sistema de Compresión de Gas',
  'Compresores centrífugos y reciprocantes para manejo de gas de alta presión'
FROM core.plantas WHERE codigo = 'CUP-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'SEP', 'Sistema de Separación',
  'Separadores bifásicos y trifásicos, deshidratación y filtración'
FROM core.plantas WHERE codigo = 'CUP-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'INYW', 'Sistema de Inyección de Agua',
  'Bombas de inyección de agua de formación al yacimiento'
FROM core.plantas WHERE codigo = 'CUP-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'ELEC', 'Sistema de Generación Eléctrica',
  'Generadores diesel y sistemas UPS para suministro eléctrico en campo'
FROM core.plantas WHERE codigo = 'CUP-001';

-- Sistemas — Campo Floreña
INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'COMP', 'Sistema de Compresión Boosting',
  'Compresores boosting para manejo de gas de baja presión'
FROM core.plantas WHERE codigo = 'FLO-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'DESH', 'Sistema de Deshidratación de Gas',
  'Deshidratación con trietilenglicol (TEG) y regeneración'
FROM core.plantas WHERE codigo = 'FLO-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'MED', 'Sistema de Medición Fiscal',
  'Medición fiscal de gas y análisis cromatográfico de composición'
FROM core.plantas WHERE codigo = 'FLO-001';

-- Sistemas — Campo Cusiana
INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'SEP', 'Sistema de Separación Bifásica',
  'Separación gas-líquido a alta y media presión en producción de crudo'
FROM core.plantas WHERE codigo = 'CUS-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'BOMB', 'Sistema de Bombeo de Crudo',
  'Bombas centrífugas multietapa para transferencia de crudo a oleoducto'
FROM core.plantas WHERE codigo = 'CUS-001';

INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
SELECT id, 'TGAS', 'Sistema de Tratamiento de Gas',
  'Compresión y acondicionamiento de gas asociado para exportación'
FROM core.plantas WHERE codigo = 'CUS-001';

-- ================================================================
-- Activos — Campo Cupiagua / Sistema de Compresión
-- ================================================================
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-101A', 'Compresor Centrífugo K-101A', 'Siemens', 'STC-SH 700',
  'SIE-2019-4471-A', '2019-03-15', 'critico', 'EQP-CUP-00101',
  'Compresor centrífugo de dos etapas para gas de alta presión. Potencia 8500 HP, caudal diseño 80 MMSCFD.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'COMP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-101B', 'Compresor Centrífugo K-101B', 'Siemens', 'STC-SH 700',
  'SIE-2019-4471-B', '2019-03-15', 'critico', 'EQP-CUP-00102',
  'Compresor centrífugo de dos etapas. Stand-by de K-101A. Mismas especificaciones de diseño.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'COMP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'TG-101', 'Turbina de Gas TG-101', 'Solar Turbines', 'Titan 130',
  'SOL-2018-8832', '2018-11-20', 'critico', 'EQP-CUP-00103',
  'Turbina de gas industrial de 15000 HP para accionamiento de K-101A. Combustible: gas natural.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'COMP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-201', 'Compresor Reciprocante K-201', 'Ariel Corporation', 'JGZ/4',
  'ARL-2020-1193', '2020-06-08', 'esencial', 'EQP-CUP-00104',
  'Compresor reciprocante de 4 cilindros para servicio de gas de baja presión. Caudal 15 MMSCFD.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'COMP';

-- Activos — Campo Cupiagua / Sistema de Separación
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'V-101', 'Separador Bifásico V-101', 'Exterran', 'HP-2500-48',
  'EXT-2018-0441', '2018-09-10', 'critico', 'EQP-CUP-00201',
  'Separador bifásico gas-líquido horizontal. P diseño 2500 psi, diámetro 48", longitud 20 ft.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'SEP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'V-102', 'Separador Trifásico V-102', 'Exterran', 'HP-2500-60',
  'EXT-2018-0442', '2018-09-10', 'critico', 'EQP-CUP-00202',
  'Separador trifásico gas-crudo-agua. P diseño 2500 psi, diámetro 60", longitud 30 ft.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'SEP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'V-201', 'Deshidratador de Gas V-201', 'CECO Environmental', 'TEG-500',
  'CEQ-2019-2210', '2019-05-22', 'esencial', 'EQP-CUP-00203',
  'Deshidratador con TEG. Capacidad 500 MMSCFD, punto de rocío objetivo -10°C.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'SEP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'F-101', 'Filtro Coalescente F-101', 'Peco Facet', 'HMF-4',
  'PEC-2021-7734', '2021-02-14', 'general', 'EQP-CUP-00204',
  'Filtro coalescente para remoción de líquidos en corriente de gas. Eficiencia 99.99%.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'SEP';

-- Activos — Campo Cupiagua / Inyección de Agua
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'P-101A', 'Bomba de Inyección de Agua P-101A', 'Sulzer', 'BB2 250-390',
  'SUL-2018-3301-A', '2018-10-05', 'esencial', 'EQP-CUP-00301',
  'Bomba centrífuga multietapa para inyección de agua al yacimiento. Caudal 5000 BPD, P descarga 3200 psi.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'INYW';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'P-101B', 'Bomba de Inyección de Agua P-101B', 'Sulzer', 'BB2 250-390',
  'SUL-2018-3301-B', '2018-10-05', 'esencial', 'EQP-CUP-00302',
  'Bomba centrífuga multietapa. Stand-by de P-101A. Mismas especificaciones de diseño.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'INYW';

-- Activos — Campo Cupiagua / Generación Eléctrica
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'GE-101', 'Generador Diesel GE-101', 'Caterpillar', '3516C',
  'CAT-2018-GEN01', '2018-08-20', 'critico', 'EQP-CUP-00401',
  'Generador diesel principal de campo. Potencia 2250 kW, 480 V, 60 Hz. Combustible ACPM.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'ELEC';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'GE-102', 'Generador Diesel GE-102', 'Caterpillar', '3516C',
  'CAT-2018-GEN02', '2018-08-20', 'esencial', 'EQP-CUP-00402',
  'Generador diesel de respaldo. Potencia 2250 kW. Arranca automáticamente ante falla de GE-101.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUP-001' AND s.codigo = 'ELEC';

-- ================================================================
-- Activos — Campo Floreña / Compresión Boosting
-- ================================================================
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-301A', 'Compresor Boosting K-301A', 'Ariel Corporation', 'KBZ/4',
  'ARL-2020-2281-A', '2020-08-14', 'critico', 'EQP-FLO-00101',
  'Compresor reciprocante boosting de 4 cilindros. Manejo de gas de baja presión 50-200 psi.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'COMP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-301B', 'Compresor Boosting K-301B', 'Ariel Corporation', 'KBZ/4',
  'ARL-2020-2281-B', '2020-08-14', 'critico', 'EQP-FLO-00102',
  'Compresor reciprocante boosting de 4 cilindros. Stand-by de K-301A.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'COMP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-302', 'Compresor de Reinyección K-302', 'Nuovo Pignone', 'BCL 406/B',
  'GEO-2021-5512', '2021-03-28', 'esencial', 'EQP-FLO-00103',
  'Compresor centrífugo para reinyección de gas. P descarga hasta 3500 psi. Motor eléctrico 5000 kW.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'COMP';

-- Activos — Campo Floreña / Deshidratación
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'DH-101', 'Deshidratador TEG DH-101', 'CECO Environmental', 'TEG-800',
  'CEQ-2020-3340', '2020-09-10', 'esencial', 'EQP-FLO-00201',
  'Unidad de deshidratación con TEG. Capacidad 800 MMSCFD, punto de rocío -20°C a 900 psi.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'DESH';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'REG-101', 'Regenerador TEG REG-101', 'CECO Environmental', 'REG-500',
  'CEQ-2020-3341', '2020-09-10', 'general', 'EQP-FLO-00202',
  'Regenerador de TEG con sistema de destilación. Temperatura regeneración 200°C.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'DESH';

-- Activos — Campo Floreña / Medición Fiscal
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'MF-101', 'Medidor Fiscal Ultrasónico MF-101', 'Krohne', 'ALTOSONIC V12',
  'KRO-2021-8821', '2021-07-15', 'critico', 'EQP-FLO-00301',
  'Medidor fiscal de gas ultrasónico de 12 trayectorias. Certificado OIML R137. Rango 5-120 MMSCFD.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'MED';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'CR-101', 'Cromatógrafo de Gas CR-101', 'ABB', 'PGC2000',
  'ABB-2021-4430', '2021-07-15', 'esencial', 'EQP-FLO-00302',
  'Cromatógrafo de proceso en línea para análisis de composición del gas. Ciclo 4 min.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'FLO-001' AND s.codigo = 'MED';

-- ================================================================
-- Activos — Campo Cusiana / Separación Bifásica
-- ================================================================
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'V-401', 'Separador de Alta Presión V-401', 'Exterran', 'HAP-3000-60',
  'EXT-2017-0881', '2017-06-12', 'critico', 'EQP-CUS-00101',
  'Separador bifásico de alta presión. P diseño 3000 psi, diámetro 60", caudal 40000 BPD.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'SEP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'V-402', 'Separador de Producción V-402', 'Exterran', 'HP-2500-60',
  'EXT-2017-0882', '2017-06-12', 'critico', 'EQP-CUS-00102',
  'Separador de producción bifásico horizontal. Segunda etapa de separación, P 1200 psi.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'SEP';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'V-403', 'Separador de Prueba V-403', 'Exterran', 'HP-1500-48',
  'EXT-2017-0883', '2017-06-12', 'general', 'EQP-CUS-00103',
  'Separador de prueba para caracterización de pozos. P diseño 1500 psi, diámetro 48".'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'SEP';

-- Activos — Campo Cusiana / Bombeo de Crudo
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'P-401A', 'Bomba Centrífuga de Crudo P-401A', 'Sulzer', 'BB2 300-450',
  'SUL-2017-4401-A', '2017-08-25', 'critico', 'EQP-CUS-00201',
  'Bomba centrífuga multietapa para transferencia de crudo al oleoducto. Caudal 30000 BPD, P 1800 psi.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'BOMB';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'P-401B', 'Bomba Centrífuga de Crudo P-401B', 'Sulzer', 'BB2 300-450',
  'SUL-2017-4401-B', '2017-08-25', 'critico', 'EQP-CUS-00202',
  'Bomba centrífuga multietapa. Stand-by de P-401A. Conmutación automática ante falla.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'BOMB';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'P-501', 'Bomba de Transferencia P-501', 'Flowserve', 'PVXM 125-250',
  'FLW-2022-6612', '2022-01-18', 'esencial', 'EQP-CUS-00203',
  'Bomba de transferencia de crudo a tanques de almacenamiento. Caudal 8000 BPD.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'BOMB';

-- Activos — Campo Cusiana / Tratamiento de Gas
INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'K-401', 'Compresor de Gas K-401', 'Solar Turbines', 'Mars 90',
  'SOL-2017-9901', '2017-10-30', 'critico', 'EQP-CUS-00301',
  'Turbina-compresor de gas asociado. Potencia 11400 HP, caudal 60 MMSCFD, P descarga 1000 psi.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'TGAS';

INSERT INTO core.activos (sistema_id, tag, nombre, fabricante, modelo, numero_serie, fecha_instalacion, criticidad, codigo_sap, descripcion)
SELECT s.id, 'MD-401', 'Deshidratador Molecular MD-401', 'UOP', 'Molsiv-800',
  'UOP-2022-1122', '2022-04-05', 'esencial', 'EQP-CUS-00302',
  'Deshidratador molecular (tamiz). Punto de rocío -40°C. Ciclo de regeneración cada 8h.'
FROM core.sistemas s JOIN core.plantas p ON s.planta_id = p.id
WHERE p.codigo = 'CUS-001' AND s.codigo = 'TGAS';
