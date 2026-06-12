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

-- ================================================================
-- Seed: Puntos de medición y lecturas históricas (Ecopetrol GGS)
-- Health states designed:
--   CRÍTICO  → TG-101 (exhaust+cojinetes spike), P-401A (fallo mecánico)
--   ALERTA   → K-101A (vibración en escalada), V-102 (nivel/presión altos), K-301B (tendencia)
--   BUENO    → K-101B, K-201, V-101, P-101A, GE-101, K-301A, MF-101, DH-101, V-401, V-402, P-401B, K-401
--   SIN DATA → K-302, V-201, F-101, P-101B, GE-102, REG-101, CR-101, V-403, P-501, MD-401
-- ================================================================

DO $$
DECLARE
  ak101a UUID; ak101b UUID; atg101 UUID; ak201  UUID;
  av101  UUID; av102  UUID;
  ap101a UUID;
  age101 UUID;
  ak301a UUID; ak301b UUID;
  adh101 UUID;
  amf101 UUID;
  av401  UUID; av402  UUID;
  ap401a UUID; ap401b UUID;
  ak401  UUID;
  p UUID;
BEGIN
  SELECT id INTO ak101a FROM core.activos WHERE tag = 'K-101A';
  SELECT id INTO ak101b FROM core.activos WHERE tag = 'K-101B';
  SELECT id INTO atg101 FROM core.activos WHERE tag = 'TG-101';
  SELECT id INTO ak201  FROM core.activos WHERE tag = 'K-201';
  SELECT id INTO av101  FROM core.activos WHERE tag = 'V-101';
  SELECT id INTO av102  FROM core.activos WHERE tag = 'V-102';
  SELECT id INTO ap101a FROM core.activos WHERE tag = 'P-101A';
  SELECT id INTO age101 FROM core.activos WHERE tag = 'GE-101';
  SELECT id INTO ak301a FROM core.activos WHERE tag = 'K-301A';
  SELECT id INTO ak301b FROM core.activos WHERE tag = 'K-301B';
  SELECT id INTO adh101 FROM core.activos WHERE tag = 'DH-101';
  SELECT id INTO amf101 FROM core.activos WHERE tag = 'MF-101';
  SELECT id INTO av401  FROM core.activos WHERE tag = 'V-401';
  SELECT id INTO av402  FROM core.activos WHERE tag = 'V-402';
  SELECT id INTO ap401a FROM core.activos WHERE tag = 'P-401A';
  SELECT id INTO ap401b FROM core.activos WHERE tag = 'P-401B';
  SELECT id INTO ak401  FROM core.activos WHERE tag = 'K-401';

  -- ============================================================
  -- K-101A — ALERTA (vibración axial en escalada progresiva)
  -- Score: VIB-AX critico(0) + TMP bueno(100) + PRS bueno(100) = 66.7 → alerta
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak101a, 'VIB-K101A-AX', 'Vibración Axial', 'vibracion', 'mm/s', 7.1, 11.2,
    'Acelerómetro axial en chumacera delantera — ISO 10816-3') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    ROUND((4.5 + (EXTRACT(EPOCH FROM (t-(NOW()-INTERVAL '30 days')))/86400.0/30.0)*8.5 + (random()-0.5)*0.4)::numeric, 2),
    'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak101a, 'TMP-K101A-DIS', 'Temperatura Descarga', 'temperatura', '°C', 150.0, 180.0,
    'RTD Pt100 en línea de descarga del compresor') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((136.0+(random()-0.5)*6.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak101a, 'PRS-K101A-DIS', 'Presión Descarga', 'presion', 'psi', 1100.0, 1200.0,
    'Transmisor de presión en manifold de descarga') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((978.0+(random()-0.5)*20.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- K-101B — BUENO (stand-by, operando normalmente)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak101b, 'VIB-K101B-AX', 'Vibración Axial', 'vibracion', 'mm/s', 7.1, 11.2,
    'Acelerómetro axial en chumacera delantera — ISO 10816-3') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((4.0+(random()-0.5)*0.5)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak101b, 'TMP-K101B-DIS', 'Temperatura Descarga', 'temperatura', '°C', 150.0, 180.0,
    'RTD Pt100 en línea de descarga') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((131.0+(random()-0.5)*5.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak101b, 'RPM-K101B', 'Velocidad de Rotación', 'rpm', 'RPM', 8500.0, 9000.0,
    'Sensor de velocidad en eje principal') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((7840.0+(random()-0.5)*80.0)::numeric,0), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- TG-101 — CRÍTICO (spike de temperatura hace 7 días)
  -- Score: TMP-EXH critico(0) + TMP-BRG critico(0) + VIB bueno(100) = 33.3 → crítico
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (atg101, 'TMP-TG101-EXH', 'Temperatura Exhaust', 'temperatura', '°C', 510.0, 540.0,
    'Termopar tipo K en gases de escape de la turbina') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    CASE WHEN t > NOW()-INTERVAL '7 days'
      THEN ROUND((545.0+(random()-0.5)*7.0)::numeric,1)
      ELSE ROUND((487.0+(random()-0.5)*10.0)::numeric,1)
    END, 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (atg101, 'TMP-TG101-BRG', 'Temperatura Cojinetes', 'temperatura', '°C', 90.0, 110.0,
    'RTD Pt100 en cojinetes de soporte del eje de turbina') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    CASE WHEN t > NOW()-INTERVAL '7 days'
      THEN ROUND((116.0+(random()-0.5)*4.0)::numeric,1)
      ELSE ROUND((81.0+(random()-0.5)*4.0)::numeric,1)
    END, 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (atg101, 'VIB-TG101', 'Vibración Eje', 'vibracion', 'mm/s', 7.1, 11.2,
    'Sonda de vibración en eje principal de la turbina') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((3.7+(random()-0.5)*0.5)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  -- ============================================================
  -- K-201 — BUENO
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak201, 'VIB-K201', 'Vibración Global', 'vibracion', 'mm/s', 7.1, 11.2,
    'Acelerómetro en carcasa del compresor reciprocante') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((3.5+(random()-0.5)*0.5)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '8 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak201, 'TMP-K201-DIS', 'Temperatura Descarga', 'temperatura', '°C', 150.0, 180.0,
    'Temperatura gas en manifold de descarga') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((126.0+(random()-0.5)*6.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '8 hours') t;

  -- ============================================================
  -- V-101 — BUENO
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av101, 'NIV-V101', 'Nivel de Líquido', 'nivel', '%', 75.0, 90.0,
    'Transmisor de nivel diferencial en separador bifásico') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((51.0+(random()-0.5)*12.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av101, 'PRS-V101', 'Presión de Operación', 'presion', 'psi', 900.0, 950.0,
    'Transmisor de presión en cabezal del separador') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((815.0+(random()-0.5)*25.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  -- ============================================================
  -- V-102 — ALERTA (nivel y presión consistentemente en zona alerta)
  -- Score: NIV alerta(50) + PRS alerta(50) = 50 → alerta
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av102, 'NIV-V102', 'Nivel de Líquido', 'nivel', '%', 75.0, 90.0,
    'Transmisor de nivel diferencial en separador trifásico') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((78.5+(random()-0.5)*4.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av102, 'PRS-V102', 'Presión de Operación', 'presion', 'psi', 900.0, 950.0,
    'Transmisor de presión en cabezal del separador trifásico') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((913.0+(random()-0.5)*9.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  -- ============================================================
  -- P-101A — BUENO
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ap101a, 'VIB-P101A', 'Vibración Global', 'vibracion', 'mm/s', 4.5, 7.1,
    'Vibración global en carcasa de bomba — ISO 10816-7') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((3.1+(random()-0.5)*0.4)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ap101a, 'TMP-P101A-BRG', 'Temperatura Rodamientos', 'temperatura', '°C', 75.0, 90.0,
    'RTD Pt100 en rodamientos de empuje de la bomba') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((66.0+(random()-0.5)*4.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- GE-101 — BUENO
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (age101, 'TMP-GE101-MTR', 'Temperatura Motor', 'temperatura', '°C', 85.0, 100.0,
    'Temperatura de operación del motor diesel Caterpillar 3516C') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((75.0+(random()-0.5)*5.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (age101, 'VIB-GE101', 'Vibración', 'vibracion', 'mm/s', 4.5, 7.1,
    'Vibración en carcasa del grupo electrógeno') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((2.6+(random()-0.5)*0.4)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- K-301A — BUENO (Floreña)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak301a, 'VIB-K301A', 'Vibración Global', 'vibracion', 'mm/s', 7.1, 11.2,
    'Acelerómetro en carcasa del compresor boosting') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((5.0+(random()-0.5)*0.5)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak301a, 'TMP-K301A-DIS', 'Temperatura Descarga', 'temperatura', '°C', 140.0, 165.0,
    'Temperatura gas en línea de descarga del boosting') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((127.0+(random()-0.5)*5.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak301a, 'PRS-K301A-DIS', 'Presión Descarga', 'presion', 'psi', 800.0, 850.0,
    'Transmisor de presión en manifold de descarga boosting') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((718.0+(random()-0.5)*15.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- K-301B — ALERTA (vibración y temperatura en tendencia ascendente)
  -- Score: VIB alerta(50) + TMP alerta(50) = 50 → alerta
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak301b, 'VIB-K301B', 'Vibración Global', 'vibracion', 'mm/s', 7.1, 11.2,
    'Acelerómetro en carcasa del compresor boosting K-301B') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    ROUND((5.0 + (EXTRACT(EPOCH FROM (t-(NOW()-INTERVAL '30 days')))/86400.0/30.0)*3.5 + (random()-0.5)*0.3)::numeric, 2),
    'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak301b, 'TMP-K301B-DIS', 'Temperatura Descarga', 'temperatura', '°C', 140.0, 165.0,
    'Temperatura gas en línea de descarga del boosting K-301B') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    ROUND((124.0 + (EXTRACT(EPOCH FROM (t-(NOW()-INTERVAL '30 days')))/86400.0/30.0)*22.0 + (random()-0.5)*3.0)::numeric, 1),
    'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- DH-101 — BUENO (Floreña deshidratador)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (adh101, 'TMP-DH101-ABS', 'Temperatura Absorbedor', 'temperatura', '°C', 55.0, 65.0,
    'Temperatura TEG en entrada torre absorbedora') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((41.0+(random()-0.5)*4.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '8 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (adh101, 'NIV-DH101-TEG', 'Nivel TEG Absorbedor', 'nivel', '%', 80.0, 90.0,
    'Nivel de TEG en el absorbedor') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((61.0+(random()-0.5)*8.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '8 hours') t;

  -- ============================================================
  -- MF-101 — BUENO (Medidor fiscal — solo seguimiento de caudal)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (amf101, 'CAU-MF101-GAS', 'Caudal Fiscal de Gas', 'caudal', 'MMSCFD', NULL, NULL,
    'Caudal de gas natural medido fiscalmente — sin límites operacionales') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((47.2+(random()-0.5)*3.5)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '1 hour') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (amf101, 'PRS-MF101', 'Presión de Medición', 'presion', 'psi', 950.0, 1000.0,
    'Presión en punto de medición fiscal — debe ser estable') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((843.0+(random()-0.5)*12.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '1 hour') t;

  -- ============================================================
  -- V-401 — BUENO (Cusiana alta presión)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av401, 'NIV-V401', 'Nivel de Líquido', 'nivel', '%', 70.0, 85.0,
    'Transmisor de nivel diferencial en separador de alta presión') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((43.0+(random()-0.5)*10.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av401, 'PRS-V401', 'Presión de Operación', 'presion', 'psi', 1400.0, 1500.0,
    'Presión de operación separador HAP-3000') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((1245.0+(random()-0.5)*30.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  -- ============================================================
  -- V-402 — BUENO (Cusiana producción)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av402, 'NIV-V402', 'Nivel de Líquido', 'nivel', '%', 70.0, 85.0,
    'Nivel de líquido en separador de producción') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((57.0+(random()-0.5)*8.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (av402, 'PRS-V402', 'Presión de Operación', 'presion', 'psi', 1400.0, 1500.0,
    'Presión de operación separador de producción') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((1108.0+(random()-0.5)*25.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  -- ============================================================
  -- P-401A — CRÍTICO (fallo mecánico hace 5 días — vibración + temperatura)
  -- Score: VIB critico(0) + TMP-BRG critico(0) = 0 → crítico
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ap401a, 'VIB-P401A', 'Vibración Global', 'vibracion', 'mm/s', 4.5, 7.1,
    'Vibración global en carcasa — posible daño en rodamientos') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    CASE WHEN t > NOW()-INTERVAL '5 days'
      THEN ROUND((13.1+(random()-0.5)*1.5)::numeric,2)
      ELSE ROUND((3.3+(random()-0.5)*0.4)::numeric,2)
    END, 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ap401a, 'TMP-P401A-BRG', 'Temperatura Rodamientos', 'temperatura', '°C', 75.0, 90.0,
    'RTD en rodamientos de empuje — deterioro confirmado') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p,
    CASE WHEN t > NOW()-INTERVAL '5 days'
      THEN ROUND((97.0+(random()-0.5)*4.0)::numeric,1)
      ELSE ROUND((63.0+(random()-0.5)*3.0)::numeric,1)
    END, 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- P-401B — BUENO (stand-by activo, operando en lugar de P-401A)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ap401b, 'VIB-P401B', 'Vibración Global', 'vibracion', 'mm/s', 4.5, 7.1,
    'Vibración global en carcasa de bomba P-401B') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((2.9+(random()-0.5)*0.4)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ap401b, 'TMP-P401B-BRG', 'Temperatura Rodamientos', 'temperatura', '°C', 75.0, 90.0,
    'RTD en rodamientos de empuje de P-401B') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((62.0+(random()-0.5)*3.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '6 hours') t;

  -- ============================================================
  -- K-401 — BUENO (Cusiana turbina-compresor Solar Mars 90)
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak401, 'VIB-K401', 'Vibración Eje', 'vibracion', 'mm/s', 7.1, 11.2,
    'Sonda de vibración en eje principal del compresor K-401') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((5.3+(random()-0.5)*0.5)::numeric,2), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak401, 'TMP-K401-EXH', 'Temperatura Exhaust', 'temperatura', '°C', 510.0, 540.0,
    'Temperatura gases de exhaust turbina Solar Mars 90') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((482.0+(random()-0.5)*8.0)::numeric,1), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma, descripcion)
  VALUES (ak401, 'RPM-K401', 'Velocidad de Rotación', 'rpm', 'RPM', 14800.0, 15200.0,
    'Sensor de velocidad en eje principal K-401') RETURNING id INTO p;
  INSERT INTO cbm.measurement_entries (time, punto_id, valor, fuente)
  SELECT t, p, ROUND((14240.0+(random()-0.5)*120.0)::numeric,0), 'sensor'
  FROM generate_series(NOW()-INTERVAL '30 days', NOW(), INTERVAL '4 hours') t;

  -- ============================================================
  -- Puntos sin datos (activos nuevos / sin instrumentación aún):
  -- K-302, V-201, F-101, P-101B, GE-102, REG-101, CR-101, V-403, P-501, MD-401
  -- Solo se definen los puntos — aparecerán como "Sin datos" en el árbol
  -- ============================================================
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'VIB-K302', 'Vibración Global', 'vibracion', 'mm/s', 7.1, 11.2 FROM core.activos WHERE tag = 'K-302';
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'TMP-K302-DIS', 'Temperatura Descarga', 'temperatura', '°C', 150.0, 180.0 FROM core.activos WHERE tag = 'K-302';

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'TMP-V201', 'Temperatura Absorbedor', 'temperatura', '°C', 55.0, 65.0 FROM core.activos WHERE tag = 'V-201';
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'NIV-V201-TEG', 'Nivel TEG', 'nivel', '%', 80.0, 90.0 FROM core.activos WHERE tag = 'V-201';

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'VIB-P101B', 'Vibración Global', 'vibracion', 'mm/s', 4.5, 7.1 FROM core.activos WHERE tag = 'P-101B';
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'TMP-P101B-BRG', 'Temperatura Rodamientos', 'temperatura', '°C', 75.0, 90.0 FROM core.activos WHERE tag = 'P-101B';

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'TMP-GE102-MTR', 'Temperatura Motor', 'temperatura', '°C', 85.0, 100.0 FROM core.activos WHERE tag = 'GE-102';
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'VIB-GE102', 'Vibración', 'vibracion', 'mm/s', 4.5, 7.1 FROM core.activos WHERE tag = 'GE-102';

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'TMP-REG101', 'Temperatura Regeneración', 'temperatura', '°C', 195.0, 210.0 FROM core.activos WHERE tag = 'REG-101';

  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'TMP-MD401', 'Temperatura Regeneración', 'temperatura', '°C', 260.0, 300.0 FROM core.activos WHERE tag = 'MD-401';
  INSERT INTO cbm.puntos_medicion (activo_id, codigo, nombre, tipo, unidad, limite_alerta, limite_alarma)
  SELECT id, 'PRS-MD401', 'Presión de Operación', 'presion', 'psi', 950.0, 1000.0 FROM core.activos WHERE tag = 'MD-401';

END $$;
