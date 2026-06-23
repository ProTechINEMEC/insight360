-- ============================================================
-- Insight 360 — Inspection Model v2
-- 07-inspection-v2.sql
-- Adds: puntos_medicion_tecnica, inspecciones, inspeccion_mediciones,
--       inspeccion_archivos, activo_archivos, campos_extra_definicion,
--       activo_campos_extra
-- Alters: core.activos (location fields)
-- Migrates: inspection_findings -> inspecciones
-- ============================================================

-- ─── cbm.puntos_medicion_tecnica ──────────────────────────
-- Measuring points defined at the technique level.
-- Shared across ALL components that use this technique.

CREATE TABLE cbm.puntos_medicion_tecnica (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tecnica_id  UUID NOT NULL REFERENCES cbm.tecnicas(id) ON DELETE CASCADE,
  nombre      VARCHAR(200) NOT NULL,
  unidad      VARCHAR(50),
  descripcion TEXT,
  orden       INTEGER NOT NULL DEFAULT 0,
  activo      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_puntos_tec_tecnica ON cbm.puntos_medicion_tecnica(tecnica_id) WHERE activo = TRUE;

-- ─── cbm.inspecciones ─────────────────────────────────────
-- One inspection report per (component × technique × date).
-- Replaces inspection_findings as the primary inspection table.

CREATE TABLE cbm.inspecciones (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  componente_id      UUID NOT NULL REFERENCES cbm.componentes(id) ON DELETE CASCADE,
  tecnica_id         UUID NOT NULL REFERENCES cbm.tecnicas(id) ON DELETE RESTRICT,
  fecha              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  analista           VARCHAR(200),
  estado_operacional cbm.estado_operacional NOT NULL DEFAULT 'operativo',
  condicion          cbm.condicion_inspeccion NOT NULL,
  modo_falla_id      UUID REFERENCES cbm.catalogo_modos_falla(id) ON DELETE SET NULL,
  observaciones      TEXT,
  creado_por         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_inspecciones_componente_fecha ON cbm.inspecciones(componente_id, fecha DESC);
CREATE INDEX idx_inspecciones_tecnica ON cbm.inspecciones(tecnica_id);
CREATE INDEX idx_inspecciones_condicion ON cbm.inspecciones(condicion);

-- ─── cbm.inspeccion_mediciones ────────────────────────────
-- Measured values for each point in an inspection.

CREATE TABLE cbm.inspeccion_mediciones (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspeccion_id UUID NOT NULL REFERENCES cbm.inspecciones(id) ON DELETE CASCADE,
  punto_id      UUID NOT NULL REFERENCES cbm.puntos_medicion_tecnica(id) ON DELETE RESTRICT,
  valor         NUMERIC(16,4),
  valor_texto   TEXT,
  condicion     cbm.condicion_inspeccion,
  observaciones TEXT,
  UNIQUE(inspeccion_id, punto_id)
);

CREATE INDEX idx_mediciones_inspeccion ON cbm.inspeccion_mediciones(inspeccion_id);

-- ─── cbm.inspeccion_archivos ──────────────────────────────
-- Files attached to an inspection (reports, photos, evidence).

CREATE TABLE cbm.inspeccion_archivos (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspeccion_id    UUID NOT NULL REFERENCES cbm.inspecciones(id) ON DELETE CASCADE,
  nombre_original  VARCHAR(500) NOT NULL,
  object_key       VARCHAR(500) NOT NULL,
  content_type     VARCHAR(100),
  size_bytes       BIGINT,
  tipo             VARCHAR(50) NOT NULL DEFAULT 'reporte',
  uploaded_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_insp_archivos_inspeccion ON cbm.inspeccion_archivos(inspeccion_id);

-- ─── cbm.activo_archivos ──────────────────────────────────
-- Files attached directly to a machine (manuals, photos, location docs).

CREATE TABLE cbm.activo_archivos (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activo_id        UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
  nombre_original  VARCHAR(500) NOT NULL,
  object_key       VARCHAR(500) NOT NULL,
  content_type     VARCHAR(100),
  size_bytes       BIGINT,
  tipo             VARCHAR(50) NOT NULL DEFAULT 'otro',
  descripcion      TEXT,
  uploaded_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_activo_archivos_activo ON cbm.activo_archivos(activo_id);

-- ─── cbm.campos_extra_definicion ──────────────────────────
-- Admin-defined custom fields for machines.
-- tipo: texto | numero | fecha | dropdown

CREATE TABLE cbm.campos_extra_definicion (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre    VARCHAR(200) NOT NULL,
  tipo      VARCHAR(20) NOT NULL CHECK (tipo IN ('texto','numero','fecha','dropdown')),
  opciones  JSONB,           -- for tipo=dropdown: ["op1","op2",...]
  orden     INTEGER NOT NULL DEFAULT 0,
  activo    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── cbm.activo_campos_extra ──────────────────────────────
-- Custom field values per machine.

CREATE TABLE cbm.activo_campos_extra (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activo_id  UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
  campo_id   UUID NOT NULL REFERENCES cbm.campos_extra_definicion(id) ON DELETE CASCADE,
  valor      TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(activo_id, campo_id)
);

CREATE INDEX idx_activo_campos_extra_activo ON cbm.activo_campos_extra(activo_id);

-- ─── core.activos — location fields ───────────────────────

ALTER TABLE core.activos
  ADD COLUMN ubicacion_fisica TEXT,
  ADD COLUMN latitud  DECIMAL(10,7),
  ADD COLUMN longitud DECIMAL(10,7);

-- ============================================================
-- SEED: Standard measuring points per technique
-- ============================================================

DO $$
DECLARE
  t_vib  UUID;
  t_term UUID;
  t_ace  UUID;
  t_ult  UUID;
  t_mce  UUID;
  t_ele  UUID;
  t_rec  UUID;
  t_cor  UUID;
  t_ope  UUID;
  t_esp  UUID;
BEGIN
  SELECT id INTO t_vib  FROM cbm.tecnicas WHERE codigo = 'VIB';
  SELECT id INTO t_term FROM cbm.tecnicas WHERE codigo = 'TERM';
  SELECT id INTO t_ace  FROM cbm.tecnicas WHERE codigo = 'ACE';
  SELECT id INTO t_ult  FROM cbm.tecnicas WHERE codigo = 'ULT';
  SELECT id INTO t_mce  FROM cbm.tecnicas WHERE codigo = 'MCE';
  SELECT id INTO t_ele  FROM cbm.tecnicas WHERE codigo = 'ELE';
  SELECT id INTO t_rec  FROM cbm.tecnicas WHERE codigo = 'REC';
  SELECT id INTO t_cor  FROM cbm.tecnicas WHERE codigo = 'COR';
  SELECT id INTO t_ope  FROM cbm.tecnicas WHERE codigo = 'OPE';
  SELECT id INTO t_esp  FROM cbm.tecnicas WHERE codigo = 'ESP';

  -- VIB — Vibraciones (ISO 10816/20816)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_vib, 'Velocidad H', 'mm/s', 'Velocidad de vibración — dirección horizontal', 1),
    (t_vib, 'Velocidad V', 'mm/s', 'Velocidad de vibración — dirección vertical', 2),
    (t_vib, 'Velocidad A', 'mm/s', 'Velocidad de vibración — dirección axial', 3),
    (t_vib, 'Aceleración H', 'g', 'Aceleración de vibración — dirección horizontal', 4),
    (t_vib, 'Aceleración V', 'g', 'Aceleración de vibración — dirección vertical', 5),
    (t_vib, 'Aceleración A', 'g', 'Aceleración de vibración — dirección axial', 6),
    (t_vib, 'Desplazamiento H', 'μm', 'Desplazamiento pico-pico — dirección horizontal', 7),
    (t_vib, 'Desplazamiento V', 'μm', 'Desplazamiento pico-pico — dirección vertical', 8);

  -- TERM — Termografía (ISO 18434)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_term, 'Temperatura Máxima', '°C', 'Temperatura máxima detectada en el punto de medición', 1),
    (t_term, 'Temperatura Mínima', '°C', 'Temperatura mínima detectada', 2),
    (t_term, 'Temperatura Diferencial', '°C', 'Delta T respecto a punto de referencia o ambiente', 3),
    (t_term, 'Temperatura Ambiente', '°C', 'Temperatura ambiente en el momento de la inspección', 4),
    (t_term, 'Emisividad', '-', 'Valor de emisividad configurado en el equipo', 5);

  -- ACE — Análisis de Aceite (ISO 4406 / ASTM D2272)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_ace, 'Viscosidad a 40°C', 'cSt', 'Viscosidad cinemática a 40°C', 1),
    (t_ace, 'Viscosidad a 100°C', 'cSt', 'Viscosidad cinemática a 100°C', 2),
    (t_ace, 'Índice de Viscosidad', '-', 'Índice de viscosidad calculado', 3),
    (t_ace, 'TAN', 'mgKOH/g', 'Número ácido total', 4),
    (t_ace, 'TBN', 'mgKOH/g', 'Número básico total', 5),
    (t_ace, 'Contenido de Agua', '%', 'Porcentaje de agua en volumen', 6),
    (t_ace, 'Hierro (Fe)', 'ppm', 'Concentración de hierro — desgaste de acero', 7),
    (t_ace, 'Cobre (Cu)', 'ppm', 'Concentración de cobre — cojinetes y bronces', 8),
    (t_ace, 'Aluminio (Al)', 'ppm', 'Concentración de aluminio — pistones', 9),
    (t_ace, 'Sílice (Si)', 'ppm', 'Contaminación por arena/polvo', 10),
    (t_ace, 'Partículas ISO 4, 6, 14', '-', 'Código de limpieza ISO 4406', 11);

  -- ULT — Ultrasonido (ASTM E797)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_ult, 'Espesor Punto 1', 'mm', 'Espesor medido en punto de control 1', 1),
    (t_ult, 'Espesor Punto 2', 'mm', 'Espesor medido en punto de control 2', 2),
    (t_ult, 'Espesor Punto 3', 'mm', 'Espesor medido en punto de control 3', 3),
    (t_ult, 'Espesor Punto 4', 'mm', 'Espesor medido en punto de control 4', 4),
    (t_ult, 'Espesor Mínimo', 'mm', 'Valor mínimo registrado en todos los puntos', 5),
    (t_ult, 'Nivel dB (Arco Eléctrico)', 'dBμV', 'Nivel de señal ultrasónica — detección de arco', 6);

  -- MCE — Medición MCEMAX (Análisis Motor Eléctrico)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_mce, 'Resistencia de Aislamiento', 'MΩ', 'Medición con megóhmetro 1kV/5kV', 1),
    (t_mce, 'Índice de Polarización', '-', 'IP = R10min / R1min (debe ser ≥ 2.0)', 2),
    (t_mce, 'Resistencia DC (L1)', 'Ω', 'Resistencia CC en fase L1', 3),
    (t_mce, 'Resistencia DC (L2)', 'Ω', 'Resistencia CC en fase L2', 4),
    (t_mce, 'Resistencia DC (L3)', 'Ω', 'Resistencia CC en fase L3', 5),
    (t_mce, 'Reactancia Inductiva', 'Ω', 'Reactancia inductiva del devanado', 6),
    (t_mce, 'RIC (%)', '%', 'Resistencia de aislamiento al tierra (inductancia relativa)', 7),
    (t_mce, 'Corriente de Fuga', 'μA', 'Corriente de fuga total a tierra', 8);

  -- ELE — Pruebas Eléctricas (medición operacional)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_ele, 'Voltaje L1-L2', 'V', 'Tensión línea L1-L2', 1),
    (t_ele, 'Voltaje L2-L3', 'V', 'Tensión línea L2-L3', 2),
    (t_ele, 'Voltaje L3-L1', 'V', 'Tensión línea L3-L1', 3),
    (t_ele, 'Corriente L1', 'A', 'Corriente en fase L1', 4),
    (t_ele, 'Corriente L2', 'A', 'Corriente en fase L2', 5),
    (t_ele, 'Corriente L3', 'A', 'Corriente en fase L3', 6),
    (t_ele, 'Potencia Activa', 'kW', 'Potencia activa consumida', 7),
    (t_ele, 'Potencia Aparente', 'kVA', 'Potencia aparente', 8),
    (t_ele, 'Factor de Potencia', '-', 'Factor de potencia (cos φ)', 9),
    (t_ele, 'Desbalance de Voltaje', '%', 'Desbalance porcentual de tensiones de línea', 10);

  -- REC — Análisis Equipo Reciprocante (compresores reciprocantes)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_rec, 'Presión Succión', 'psi', 'Presión en manifold de succión', 1),
    (t_rec, 'Presión Descarga', 'psi', 'Presión en manifold de descarga', 2),
    (t_rec, 'Temperatura Succión', '°C', 'Temperatura gas en succión', 3),
    (t_rec, 'Temperatura Descarga', '°C', 'Temperatura gas en descarga', 4),
    (t_rec, 'Contrapresión', 'psi', 'Contrapresión medida en descarga', 5),
    (t_rec, 'Relación de Compresión', '-', 'Pd/Ps — relación de compresión real', 6),
    (t_rec, 'Nivel Vibraci\u00f3n Cig\u00fce\u00f1al', 'mm/s', 'Vibración en cojinetes del cigüeñal', 7),
    (t_rec, 'Temperatura Cojinete Principal', '°C', 'Temperatura cojinetes principales', 8);

  -- COR — Coronografía (descargas parciales en equipos eléctricos MT/AT)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_cor, 'Nivel DP Fase A', 'dBμV', 'Nivel descarga parcial en fase A', 1),
    (t_cor, 'Nivel DP Fase B', 'dBμV', 'Nivel descarga parcial en fase B', 2),
    (t_cor, 'Nivel DP Fase C', 'dBμV', 'Nivel descarga parcial en fase C', 3),
    (t_cor, 'Corriente de Fuga', 'μA', 'Corriente de fuga a tierra medida', 4),
    (t_cor, 'Temperatura Punto Caliente', '°C', 'Temperatura máxima detectada termográficamente', 5);

  -- OPE — Variables Operativas / Inspección de Operación
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_ope, 'Temperatura de Operación', '°C', 'Temperatura de proceso en operación normal', 1),
    (t_ope, 'Presión de Operación', 'psi', 'Presión de proceso en operación normal', 2),
    (t_ope, 'Caudal', 'm³/h', 'Caudal de operación', 3),
    (t_ope, 'RPM', 'RPM', 'Velocidad de rotación operacional', 4),
    (t_ope, 'Nivel', '%', 'Nivel en recipiente o tanque', 5),
    (t_ope, 'Corriente de Operaci\u00f3n', 'A', 'Corriente consumida en operación', 6);

  -- ESP — Análisis de Espesores (ultrasonido de espesor de pared)
  INSERT INTO cbm.puntos_medicion_tecnica (tecnica_id, nombre, unidad, descripcion, orden) VALUES
    (t_esp, 'Espesor Nominal', 'mm', 'Espesor nominal de diseño', 1),
    (t_esp, 'Espesor Medido Mínimo', 'mm', 'Espesor mínimo medido en todos los puntos', 2),
    (t_esp, 'Espesor Medido Máximo', 'mm', 'Espesor máximo medido en todos los puntos', 3),
    (t_esp, 'Espesor Mínimo Admisible', 'mm', 'Espesor mínimo admisible por norma', 4),
    (t_esp, 'P\u00e9rdida de Espesor', '%', 'Porcentaje de pérdida respecto al nominal', 5),
    (t_esp, 'Tasa de Corrosión', 'mm/año', 'Tasa de corrosión estimada', 6);

  -- VIS — Inspección Visual (no measuring points — qualitative only)
  -- No rows inserted: VIS is purely visual assessment via condicion + observaciones

END $$;

-- ============================================================
-- MIGRATE: inspection_findings → cbm.inspecciones
-- Each finding becomes one inspection record (1:1 migration)
-- ============================================================

INSERT INTO cbm.inspecciones (
  id, componente_id, tecnica_id, fecha,
  analista, estado_operacional, condicion,
  modo_falla_id, observaciones, creado_por, created_at
)
SELECT
  gen_random_uuid(),
  componente_id,
  tecnica_id,
  time AS fecha,
  analista,
  estado_operacional,
  condicion,
  modo_falla_id,
  observaciones,
  creado_por,
  created_at
FROM cbm.inspection_findings;
