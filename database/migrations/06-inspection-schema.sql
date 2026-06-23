-- ============================================================
-- Insight 360 — Inspection Schema
-- 06-inspection-schema.sql
-- Adds: contratos, areas, componentes, tecnicas, tipos_componente,
--       catalogo_modos_falla, inspection_findings
-- Alters: plantas (contrato_id), activos (area_id, equipo_superior_id)
-- ============================================================

-- ─── New enums ─────────────────────────────────────────────

CREATE TYPE cbm.condicion_inspeccion AS ENUM ('normal', 'observacion', 'alerta', 'urgencia');

CREATE TYPE cbm.estado_operacional AS ENUM (
  'operativo', 'operativo_limitado', 'stand_by', 'fuera_de_servicio', 'dado_de_baja'
);

-- ─── core.contratos (top of hierarchy) ────────────────────

CREATE TABLE core.contratos (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre           VARCHAR(200) NOT NULL,
  numero_contrato  VARCHAR(100),
  empresa_cliente  VARCHAR(200),
  fecha_inicio     DATE,
  fecha_fin        DATE,
  activo           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_contratos_updated_at
  BEFORE UPDATE ON core.contratos
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Link plantas to contratos
ALTER TABLE core.plantas
  ADD COLUMN contrato_id UUID REFERENCES core.contratos(id) ON DELETE SET NULL;

CREATE INDEX idx_plantas_contrato_id ON core.plantas(contrato_id);

-- ─── core.areas (between sistemas and activos) ────────────

CREATE TABLE core.areas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sistema_id  UUID NOT NULL REFERENCES core.sistemas(id) ON DELETE RESTRICT,
  codigo      VARCHAR(50) NOT NULL,
  nombre      VARCHAR(200) NOT NULL,
  descripcion TEXT,
  activo      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(sistema_id, codigo)
);

CREATE TRIGGER trg_areas_updated_at
  BEFORE UPDATE ON core.areas
  FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Link activos to areas (optional — GGS activos have no area)
ALTER TABLE core.activos
  ADD COLUMN area_id UUID REFERENCES core.areas(id) ON DELETE SET NULL,
  ADD COLUMN equipo_superior_id UUID REFERENCES core.activos(id) ON DELETE SET NULL;

CREATE INDEX idx_activos_area_id ON core.activos(area_id) WHERE area_id IS NOT NULL;
CREATE INDEX idx_activos_equipo_superior ON core.activos(equipo_superior_id) WHERE equipo_superior_id IS NOT NULL;

-- ─── cbm.tipos_componente ─────────────────────────────────

CREATE TABLE cbm.tipos_componente (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo  VARCHAR(50) UNIQUE NOT NULL,
  nombre  VARCHAR(200) NOT NULL
);

-- ─── cbm.componentes ──────────────────────────────────────
-- What actually gets inspected (sub-item of an activo, with CMMS ID)

CREATE TABLE cbm.componentes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activo_id           UUID NOT NULL REFERENCES core.activos(id) ON DELETE CASCADE,
  tipo_componente_id  UUID REFERENCES cbm.tipos_componente(id) ON DELETE SET NULL,
  cmms_id             VARCHAR(100),        -- CMMS / SAP PM functional location
  nombre              VARCHAR(300) NOT NULL,
  descripcion         TEXT,
  activo              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_componentes_activo_id ON cbm.componentes(activo_id);

-- ─── cbm.tecnicas ─────────────────────────────────────────

CREATE TABLE cbm.tecnicas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           VARCHAR(50) UNIQUE NOT NULL,
  nombre           VARCHAR(200) NOT NULL,
  norma_referencia TEXT,
  aplica_a         VARCHAR(200),   -- 'Rotativo', 'Eléctrico', 'Todos', etc.
  activo           BOOLEAN NOT NULL DEFAULT TRUE
);

-- ─── cbm.catalogo_modos_falla ─────────────────────────────
-- Global fault mode catalog: technique × component type → selectable modes

CREATE TABLE cbm.catalogo_modos_falla (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tecnica_id          UUID NOT NULL REFERENCES cbm.tecnicas(id) ON DELETE CASCADE,
  tipo_componente_id  UUID NOT NULL REFERENCES cbm.tipos_componente(id) ON DELETE CASCADE,
  modo_falla          VARCHAR(300) NOT NULL,
  UNIQUE(tecnica_id, tipo_componente_id, modo_falla)
);

CREATE INDEX idx_catalogo_mf_tecnica ON cbm.catalogo_modos_falla(tecnica_id, tipo_componente_id);

-- ─── cbm.inspection_findings (hypertable) ─────────────────

CREATE TABLE cbm.inspection_findings (
  time               TIMESTAMPTZ NOT NULL,
  componente_id      UUID NOT NULL REFERENCES cbm.componentes(id) ON DELETE CASCADE,
  tecnica_id         UUID NOT NULL REFERENCES cbm.tecnicas(id) ON DELETE RESTRICT,
  analista           VARCHAR(200),
  estado_operacional cbm.estado_operacional NOT NULL DEFAULT 'operativo',
  condicion          cbm.condicion_inspeccion NOT NULL,
  modo_falla_id      UUID REFERENCES cbm.catalogo_modos_falla(id) ON DELETE SET NULL,
  observaciones      TEXT,
  creado_por         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT create_hypertable(
  'cbm.inspection_findings',
  'time',
  chunk_time_interval => INTERVAL '1 month',
  if_not_exists => TRUE
);

CREATE INDEX idx_findings_componente_time ON cbm.inspection_findings(componente_id, time DESC);
CREATE INDEX idx_findings_tecnica ON cbm.inspection_findings(tecnica_id);

-- ============================================================
-- SEED DATA
-- ============================================================

DO $$
DECLARE
  -- Contrato IDs
  cid_ggs  UUID;
  cid_dina UUID;

  -- Planta DINA
  pid_dina UUID;

  -- Sistema DINA
  sid_genvap  UUID;  -- Generación Vapor
  sid_tratcr  UUID;  -- Tratamiento Crudo
  sid_inyag   UUID;  -- Inyeccion de Agua
  sid_genelec UUID;  -- Generación Eléctrica
  sid_transp  UUID;  -- Transporte

  -- Area DINA
  aid_calderas   UUID;
  aid_tratadores UUID;
  aid_inyeccion  UUID;
  aid_motogen    UUID;
  aid_transf     UUID;
  aid_oleod      UUID;

  -- Activos DINA
  adid_401b001 UUID;  -- 401-B-001 Caldera
  adid_702h701 UUID;  -- 702-H-701 Tratador Electrostático
  adid_301p001 UUID;  -- 301-P-001 Bomba de Inyección 1
  adid_g901a   UUID;  -- G-901A Motogenerador
  adid_g901b   UUID;  -- G-901B Motogenerador
  adid_g901c   UUID;  -- G-901C Motogenerador
  adid_tc456a  UUID;  -- TC-456A Transformador
  adid_et360   UUID;  -- ET-360 Estructura Eléctrica
  adid_et361   UUID;  -- ET-361 Estructura Eléctrica
  adid_et362   UUID;  -- ET-362 Estructura Eléctrica
  adid_odl     UUID;  -- ODL Oleoducto

  -- Activos GGS (existing)
  agid_k101a  UUID;
  agid_k101b  UUID;
  agid_tg101  UUID;
  agid_k201   UUID;
  agid_k301a  UUID;
  agid_k301b  UUID;
  agid_p401a  UUID;
  agid_p401b  UUID;
  agid_ge101  UUID;
  agid_v101   UUID;
  agid_dh101  UUID;
  agid_mf101  UUID;

  -- Tecnica IDs
  t_vib   UUID;  -- VIBRACIONES
  t_term  UUID;  -- TERMOGRAFIA
  t_rec   UUID;  -- ANALISIS EQUIPO RECIPROCANTE
  t_mce   UUID;  -- MEDICION ELECTRICA (MCEMAX)
  t_ace   UUID;  -- ANALISIS DE ACEITE
  t_ult   UUID;  -- ULTRASONIDO
  t_cor   UUID;  -- CORONOGRAFIA
  t_ele   UUID;  -- PRUEBAS ELECTRICAS (Medicion Electrica)
  t_int   UUID;  -- MEDICION DE ESPESORES
  t_ope   UUID;  -- VARIABLES OPERATIVAS / INSPECCION VISUAL
  t_vis   UUID;  -- INSPECCION VISUAL

  -- Tipo componente IDs
  tc_mot_elec UUID;
  tc_vent     UUID;
  tc_tr_seco  UUID;
  tc_tr_aceite UUID;
  tc_tab_mt   UUID;
  tc_tab_bt   UUID;
  tc_bomb_c   UUID;
  tc_bomb_p   UUID;
  tc_comp_rec UUID;
  tc_comp_c   UUID;
  tc_turb_g   UUID;
  tc_motogen  UUID;
  tc_vfd      UUID;
  tc_rodam    UUID;
  tc_acopl    UUID;
  tc_engran   UUID;
  tc_cam_emp  UUID;
  tc_sello    UUID;
  tc_vlv_ctrl UUID;
  tc_recip    UUID;
  tc_ducto    UUID;
  tc_intercam UUID;
  tc_otro     UUID;

  -- Componente IDs — DINA
  cd_vent401b   UUID;  -- Ventilador 401-B-001
  cd_tr702h     UUID;  -- Transformador 702-H-701
  cd_mot301p    UUID;  -- Motor 301-P-001
  cd_trsut301p  UUID;  -- Transformador SUT 301-P-001
  cd_tab301p    UUID;  -- Tablero 301-P-001
  cd_mg901a     UUID;  -- Motogenerador G-901A
  cd_mg901b     UUID;  -- Motogenerador G-901B
  cd_mg901c     UUID;  -- Motogenerador G-901C
  cd_tc456a     UUID;  -- Transformador TC-456A (componente)
  cd_et360      UUID;  -- ET-360 tablero
  cd_et361      UUID;  -- ET-361 tablero
  cd_et362      UUID;  -- ET-362 tablero
  cd_odl        UUID;  -- ODL ducto

  -- Componente IDs — GGS
  cg_k101a_mot  UUID;
  cg_k101a_cc   UUID;
  cg_k101a_rod  UUID;
  cg_k101b_mot  UUID;
  cg_tg101_turb UUID;
  cg_tg101_cej  UUID;
  cg_k201_mot   UUID;
  cg_k201_rec   UUID;
  cg_k301a_mot  UUID;
  cg_k301b_mot  UUID;
  cg_k301b_rec  UUID;
  cg_p401a_mot  UUID;
  cg_p401a_bc   UUID;
  cg_p401a_sel  UUID;
  cg_p401b_mot  UUID;
  cg_ge101_mg   UUID;
  cg_dh101_mot  UUID;
  cg_mf101_ult  UUID;

  -- Modo falla IDs for seed findings
  mf_desbal UUID;
  mf_aislam UUID;
  mf_ptocal UUID;
  mf_sobrec_desc UUID;
  mf_falla_rod UUID;
  mf_fuga_sel UUID;

BEGIN

  -- ─── Contratos ──────────────────────────────────────────

  INSERT INTO core.contratos (nombre, numero_contrato, empresa_cliente, fecha_inicio, fecha_fin)
  VALUES ('GGS', 'ECO-GGS-2017-001', 'Ecopetrol S.A.', '2017-06-01', NULL)
  RETURNING id INTO cid_ggs;

  INSERT INTO core.contratos (nombre, numero_contrato, empresa_cliente, fecha_inicio, fecha_fin)
  VALUES ('DINA', 'ECO-DINA-2019-003', 'Ecopetrol S.A.', '2019-01-15', NULL)
  RETURNING id INTO cid_dina;

  -- Assign existing GGS plantas to GGS contract
  UPDATE core.plantas SET contrato_id = cid_ggs;

  -- ─── DINA Planta ────────────────────────────────────────

  INSERT INTO core.plantas (codigo, nombre, ubicacion, contrato_id)
  VALUES ('DINA-001', 'Planta DINA', 'Casanare, Colombia', cid_dina)
  RETURNING id INTO pid_dina;

  -- ─── DINA Sistemas ──────────────────────────────────────

  INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
  VALUES (pid_dina, 'GEN-VAP', 'Generación de Vapor',
    'Calderas y sistemas de vapor para proceso industrial')
  RETURNING id INTO sid_genvap;

  INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
  VALUES (pid_dina, 'TRAT-CR', 'Tratamiento de Crudo',
    'Tratadores electrostáticos y separadores para deshidratación de crudo')
  RETURNING id INTO sid_tratcr;

  INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
  VALUES (pid_dina, 'INY-AG', 'Inyección de Agua',
    'Bombas de inyección de agua de alta presión para mantenimiento de presión de yacimiento')
  RETURNING id INTO sid_inyag;

  INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
  VALUES (pid_dina, 'GEN-EL', 'Generación Eléctrica',
    'Motogeneradores, transformadores y subestaciones eléctricas')
  RETURNING id INTO sid_genelec;

  INSERT INTO core.sistemas (planta_id, codigo, nombre, descripcion)
  VALUES (pid_dina, 'TRANSP', 'Transporte',
    'Oleoductos y sistemas de transferencia de hidrocarburos')
  RETURNING id INTO sid_transp;

  -- ─── DINA Areas ─────────────────────────────────────────

  INSERT INTO core.areas (sistema_id, codigo, nombre)
  VALUES (sid_genvap, 'CALD', 'Calderas') RETURNING id INTO aid_calderas;

  INSERT INTO core.areas (sistema_id, codigo, nombre)
  VALUES (sid_tratcr, 'TRAT', 'Tratadores') RETURNING id INTO aid_tratadores;

  INSERT INTO core.areas (sistema_id, codigo, nombre)
  VALUES (sid_inyag, 'INY', 'Inyección') RETURNING id INTO aid_inyeccion;

  INSERT INTO core.areas (sistema_id, codigo, nombre)
  VALUES (sid_genelec, 'MOT', 'Motogeneradores') RETURNING id INTO aid_motogen;

  INSERT INTO core.areas (sistema_id, codigo, nombre)
  VALUES (sid_genelec, 'TRF', 'Transformación') RETURNING id INTO aid_transf;

  INSERT INTO core.areas (sistema_id, codigo, nombre)
  VALUES (sid_transp, 'ODL', 'Oleoductos') RETURNING id INTO aid_oleod;

  -- ─── DINA Activos ───────────────────────────────────────

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genvap, aid_calderas, '401-B-001', 'Caldera de Carbón 401-B-001',
    'Cleaver-Brooks', 'critico', 'DINA-00401',
    'Caldera pirotubular de carbón pulverizado. Capacidad 80 Ton vapor/h a 42 bar.')
  RETURNING id INTO adid_401b001;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_tratcr, aid_tratadores, '702-H-701', 'Tratador Electrostático ET-001',
    'Natco Group', 'critico', 'DINA-00702',
    'Tratador electrostático horizontal para deshidratación de crudo. Capacidad 50000 BPD.')
  RETURNING id INTO adid_702h701;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_inyag, aid_inyeccion, '301-P-001', 'Bomba de Inyección 1',
    'Sulzer', 'critico', 'DINA-00301',
    'Bomba de inyección de agua de alta presión. Motor MT Siemens 4000HP. Caudal 8000 BPD, P descarga 4500 psi.')
  RETURNING id INTO adid_301p001;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_motogen, 'G-901A', 'Motogenerador G-901A',
    'Caterpillar', 'critico', 'DINA-00901',
    'Motogenerador diesel de 2000 kW. Generación principal de campo.')
  RETURNING id INTO adid_g901a;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_motogen, 'G-901B', 'Motogenerador G-901B',
    'Caterpillar', 'critico', 'DINA-00902',
    'Motogenerador diesel de 2000 kW. Respaldo G-901A.')
  RETURNING id INTO adid_g901b;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_motogen, 'G-901C', 'Motogenerador G-901C',
    'Caterpillar', 'esencial', 'DINA-00903',
    'Motogenerador diesel de 1500 kW. Generación auxiliar.')
  RETURNING id INTO adid_g901c;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_transf, 'TC-456A', 'Transformador TC-456A',
    'ABB', 'critico', 'DINA-00456',
    'Transformador de potencia 5 MVA, 13.8kV/480V, ONAN/ONAF. Alimentación principal.')
  RETURNING id INTO adid_tc456a;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_transf, 'ET-360', 'Estructura Eléctrica ET-360',
    'ABB', 'critico', 'DINA-00360',
    'Celda de media tensión 13.8kV. Alimentación motores críticos zona norte.')
  RETURNING id INTO adid_et360;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_transf, 'ET-361', 'Estructura Eléctrica ET-361',
    'ABB', 'esencial', 'DINA-00361',
    'Celda de media tensión 13.8kV. Alimentación motores zona sur. Presenta historia de fallas.')
  RETURNING id INTO adid_et361;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_genelec, aid_transf, 'ET-362', 'Estructura Eléctrica ET-362',
    'Schneider Electric', 'esencial', 'DINA-00362',
    'Celda de media tensión 13.8kV. Alimentación bombas de inyección.')
  RETURNING id INTO adid_et362;

  INSERT INTO core.activos (sistema_id, area_id, tag, nombre, fabricante, criticidad, codigo_sap, descripcion)
  VALUES (sid_transp, aid_oleod, 'ODL', 'Oleoducto Principal ODL',
    'Tubacero', 'critico', 'DINA-ODL01',
    'Oleoducto de exportación de crudo. Diámetro 16", longitud 8.5 km, presión máxima 1200 psi.')
  RETURNING id INTO adid_odl;

  -- ─── Retrieve GGS activos ────────────────────────────────

  SELECT id INTO agid_k101a FROM core.activos WHERE tag = 'K-101A';
  SELECT id INTO agid_k101b FROM core.activos WHERE tag = 'K-101B';
  SELECT id INTO agid_tg101  FROM core.activos WHERE tag = 'TG-101';
  SELECT id INTO agid_k201   FROM core.activos WHERE tag = 'K-201';
  SELECT id INTO agid_k301a  FROM core.activos WHERE tag = 'K-301A';
  SELECT id INTO agid_k301b  FROM core.activos WHERE tag = 'K-301B';
  SELECT id INTO agid_p401a  FROM core.activos WHERE tag = 'P-401A';
  SELECT id INTO agid_p401b  FROM core.activos WHERE tag = 'P-401B';
  SELECT id INTO agid_ge101  FROM core.activos WHERE tag = 'GE-101';
  SELECT id INTO agid_v101   FROM core.activos WHERE tag = 'V-101';
  SELECT id INTO agid_dh101  FROM core.activos WHERE tag = 'DH-101';
  SELECT id INTO agid_mf101  FROM core.activos WHERE tag = 'MF-101';

  -- ─── Tecnicas ────────────────────────────────────────────

  INSERT INTO cbm.tecnicas (codigo, nombre, norma_referencia, aplica_a) VALUES
  ('VIB',  'Vibraciones',                   'ISO 20816 / ISO 13373 / API 670',    'Rotativo'),
  ('TERM', 'Termografía',                   'ISO 18434',                           'Rotativo y eléctrico'),
  ('REC',  'Desempeño Reciprocante',        'API 618 / ISO 13631',                 'Compresores y motogeneradores'),
  ('MCE',  'Análisis Circuito de Motor',    'IEEE 1415 / IEC 60034',               'Motores eléctricos'),
  ('ACE',  'Análisis de Aceite',            'ISO 14830 / ISO 4406 / ASTM D',       'Rotativo y transformadores'),
  ('ULT',  'Ultrasonido',                   'ISO 29821',                           'Rotativo y eléctrico'),
  ('COR',  'Coronografía / Desc. Parcial',  'IEC 60270',                           'Eléctrico'),
  ('ELE',  'Pruebas Eléctricas',            'IEEE / IEC 60076',                    'Transformadores'),
  ('ESP',  'Medición de Espesores',         'API 570 / 580 / ASME',               'Estático y ductos'),
  ('OPE',  'Inspección Operacional',        'ISO 17359',                           'Todos'),
  ('VIS',  'Inspección Visual',             'ISO 17359',                           'Todos');

  -- Fetch by code
  SELECT id INTO t_vib  FROM cbm.tecnicas WHERE codigo = 'VIB';
  SELECT id INTO t_term FROM cbm.tecnicas WHERE codigo = 'TERM';
  SELECT id INTO t_rec  FROM cbm.tecnicas WHERE codigo = 'REC';
  SELECT id INTO t_mce  FROM cbm.tecnicas WHERE codigo = 'MCE';
  SELECT id INTO t_ace  FROM cbm.tecnicas WHERE codigo = 'ACE';
  SELECT id INTO t_ult  FROM cbm.tecnicas WHERE codigo = 'ULT';
  SELECT id INTO t_cor  FROM cbm.tecnicas WHERE codigo = 'COR';
  SELECT id INTO t_ele  FROM cbm.tecnicas WHERE codigo = 'ELE';
  SELECT id INTO t_int  FROM cbm.tecnicas WHERE codigo = 'ESP';
  SELECT id INTO t_ope  FROM cbm.tecnicas WHERE codigo = 'OPE';
  SELECT id INTO t_vis  FROM cbm.tecnicas WHERE codigo = 'VIS';

  -- ─── Tipos Componente ────────────────────────────────────

  INSERT INTO cbm.tipos_componente (codigo, nombre) VALUES
  ('MOT_ELEC',  'Motor Eléctrico'),
  ('VENT',      'Ventilador'),
  ('TR_SECO',   'Transformador Seco'),
  ('TR_ACEITE', 'Transformador Sumergido en Aceite'),
  ('TAB_MT',    'Tablero Eléctrico Media Tensión'),
  ('TAB_BT',    'Tablero Eléctrico Baja Tensión'),
  ('BOMB_C',    'Bomba Centrífuga'),
  ('BOMB_P',    'Bomba de Pistón'),
  ('COMP_REC',  'Compresor Reciprocante'),
  ('COMP_C',    'Compresor Centrífugo'),
  ('TURB_G',    'Turbina de Gas'),
  ('MOTOGEN',   'Motogenerador'),
  ('VFD',       'Variador de Velocidad'),
  ('RODAM',     'Rodamiento'),
  ('ACOPL',     'Acoplamiento'),
  ('ENGRAN',    'Engranaje / Caja Multiplicadora'),
  ('CAM_EMP',   'Cámara de Empuje / Cojinete Axial'),
  ('SELLO',     'Sello Mecánico'),
  ('VLV_CTRL',  'Válvula de Control'),
  ('RECIP',     'Recipiente a Presión / Vasija'),
  ('DUCTO',     'Ducto / Tubería'),
  ('INTERCAM',  'Intercambiador de Calor'),
  ('OTRO',      'Otro');

  -- Fetch by code
  SELECT id INTO tc_mot_elec FROM cbm.tipos_componente WHERE codigo = 'MOT_ELEC';
  SELECT id INTO tc_vent     FROM cbm.tipos_componente WHERE codigo = 'VENT';
  SELECT id INTO tc_tr_seco  FROM cbm.tipos_componente WHERE codigo = 'TR_SECO';
  SELECT id INTO tc_tr_aceite FROM cbm.tipos_componente WHERE codigo = 'TR_ACEITE';
  SELECT id INTO tc_tab_mt   FROM cbm.tipos_componente WHERE codigo = 'TAB_MT';
  SELECT id INTO tc_tab_bt   FROM cbm.tipos_componente WHERE codigo = 'TAB_BT';
  SELECT id INTO tc_bomb_c   FROM cbm.tipos_componente WHERE codigo = 'BOMB_C';
  SELECT id INTO tc_bomb_p   FROM cbm.tipos_componente WHERE codigo = 'BOMB_P';
  SELECT id INTO tc_comp_rec FROM cbm.tipos_componente WHERE codigo = 'COMP_REC';
  SELECT id INTO tc_comp_c   FROM cbm.tipos_componente WHERE codigo = 'COMP_C';
  SELECT id INTO tc_turb_g   FROM cbm.tipos_componente WHERE codigo = 'TURB_G';
  SELECT id INTO tc_motogen  FROM cbm.tipos_componente WHERE codigo = 'MOTOGEN';
  SELECT id INTO tc_vfd      FROM cbm.tipos_componente WHERE codigo = 'VFD';
  SELECT id INTO tc_rodam    FROM cbm.tipos_componente WHERE codigo = 'RODAM';
  SELECT id INTO tc_acopl    FROM cbm.tipos_componente WHERE codigo = 'ACOPL';
  SELECT id INTO tc_engran   FROM cbm.tipos_componente WHERE codigo = 'ENGRAN';
  SELECT id INTO tc_cam_emp  FROM cbm.tipos_componente WHERE codigo = 'CAM_EMP';
  SELECT id INTO tc_sello    FROM cbm.tipos_componente WHERE codigo = 'SELLO';
  SELECT id INTO tc_vlv_ctrl FROM cbm.tipos_componente WHERE codigo = 'VLV_CTRL';
  SELECT id INTO tc_recip    FROM cbm.tipos_componente WHERE codigo = 'RECIP';
  SELECT id INTO tc_ducto    FROM cbm.tipos_componente WHERE codigo = 'DUCTO';
  SELECT id INTO tc_intercam FROM cbm.tipos_componente WHERE codigo = 'INTERCAM';
  SELECT id INTO tc_otro     FROM cbm.tipos_componente WHERE codigo = 'OTRO';

  -- ─── Catalogo de Modos de Falla ─────────────────────────

  -- == VIBRACIONES ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  -- Motor Eléctrico
  (t_vib, tc_mot_elec, 'Desbalanceo'),
  (t_vib, tc_mot_elec, 'Desalineamiento'),
  (t_vib, tc_mot_elec, 'Resonancia mecánica'),
  (t_vib, tc_mot_elec, 'Holgura mecánica'),
  (t_vib, tc_mot_elec, 'Falla de rodamiento'),
  (t_vib, tc_mot_elec, 'Excentricidad de rotor'),
  (t_vib, tc_mot_elec, 'Problema electromagnético'),
  (t_vib, tc_mot_elec, 'Desgaste de escobillas'),
  -- Ventilador
  (t_vib, tc_vent, 'Desbalanceo'),
  (t_vib, tc_vent, 'Erosión de paletas'),
  (t_vib, tc_vent, 'Resonancia estructural'),
  (t_vib, tc_vent, 'Desalineamiento'),
  (t_vib, tc_vent, 'Falta de contrapeso'),
  (t_vib, tc_vent, 'Falla de rodamiento'),
  -- Bomba Centrífuga
  (t_vib, tc_bomb_c, 'Desbalanceo'),
  (t_vib, tc_bomb_c, 'Cavitación'),
  (t_vib, tc_bomb_c, 'Recirculación interna'),
  (t_vib, tc_bomb_c, 'Falla de rodamiento'),
  (t_vib, tc_bomb_c, 'Desgaste de impeler'),
  (t_vib, tc_bomb_c, 'Desalineamiento'),
  -- Compresor Centrífugo
  (t_vib, tc_comp_c, 'Desbalanceo'),
  (t_vib, tc_comp_c, 'Inestabilidad de flujo (surge)'),
  (t_vib, tc_comp_c, 'Falla de cojinetes hidrodinámicos'),
  (t_vib, tc_comp_c, 'Rozamiento rotor-estátor'),
  (t_vib, tc_comp_c, 'Resonancia de impulsor'),
  (t_vib, tc_comp_c, 'Desalineamiento del tren'),
  -- Compresor Reciprocante
  (t_vib, tc_comp_rec, 'Desbalanceo de masa'),
  (t_vib, tc_comp_rec, 'Falla de válvulas'),
  (t_vib, tc_comp_rec, 'Holgura biela-pistón'),
  (t_vib, tc_comp_rec, 'Desgaste de anillos de pistón'),
  (t_vib, tc_comp_rec, 'Carga de gas desbalanceada'),
  -- Turbina de Gas
  (t_vib, tc_turb_g, 'Desbalanceo'),
  (t_vib, tc_turb_g, 'Desgaste de paletas'),
  (t_vib, tc_turb_g, 'Inestabilidad de flujo (stall)'),
  (t_vib, tc_turb_g, 'Falla de cojinetes hidrodinámicos'),
  (t_vib, tc_turb_g, 'Rozamiento de paletas en carcasa'),
  -- Motogenerador
  (t_vib, tc_motogen, 'Desbalanceo'),
  (t_vib, tc_motogen, 'Desalineamiento'),
  (t_vib, tc_motogen, 'Falla de rodamiento'),
  (t_vib, tc_motogen, 'Vibración electromagnética'),
  (t_vib, tc_motogen, 'Resonancia estructural'),
  -- Rodamiento
  (t_vib, tc_rodam, 'Falla de pista externa'),
  (t_vib, tc_rodam, 'Falla de pista interna'),
  (t_vib, tc_rodam, 'Desgaste de elementos rodantes'),
  (t_vib, tc_rodam, 'Daño en jaula'),
  -- Bomba de Pistón
  (t_vib, tc_bomb_p, 'Desbalanceo de masa reciprocante'),
  (t_vib, tc_bomb_p, 'Falla de válvulas check'),
  (t_vib, tc_bomb_p, 'Holgura biela-pistón'),
  -- Acoplamiento
  (t_vib, tc_acopl, 'Desalineamiento angular'),
  (t_vib, tc_acopl, 'Desalineamiento paralelo'),
  (t_vib, tc_acopl, 'Holgura excesiva'),
  (t_vib, tc_acopl, 'Desgaste de elementos flexibles');

  -- == TERMOGRAFÍA ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  -- Motor Eléctrico
  (t_term, tc_mot_elec, 'Punto caliente en devanado de estátor'),
  (t_term, tc_mot_elec, 'Sobrecarga eléctrica'),
  (t_term, tc_mot_elec, 'Desbalanceo de fases'),
  (t_term, tc_mot_elec, 'Falla de rodamiento (térmica)'),
  (t_term, tc_mot_elec, 'Ventilación deficiente'),
  -- Transformador Seco
  (t_term, tc_tr_seco, 'Sobrecalentamiento de devanados'),
  (t_term, tc_tr_seco, 'Conexión suelta en bornera'),
  (t_term, tc_tr_seco, 'Punto caliente en núcleo magnético'),
  (t_term, tc_tr_seco, 'Sobrecarga'),
  (t_term, tc_tr_seco, 'Ventilación inadecuada'),
  -- Transformador en Aceite
  (t_term, tc_tr_aceite, 'Punto caliente en boquilla (bushing)'),
  (t_term, tc_tr_aceite, 'Sobrecalentamiento de aceite'),
  (t_term, tc_tr_aceite, 'Falla de sistema de enfriamiento'),
  (t_term, tc_tr_aceite, 'Cortocircuito interno'),
  (t_term, tc_tr_aceite, 'Conexión deficiente en terminalería'),
  -- Tablero MT
  (t_term, tc_tab_mt, 'Punto caliente en conexión de barra'),
  (t_term, tc_tab_mt, 'Resistencia de contacto elevada en interruptor'),
  (t_term, tc_tab_mt, 'Sobrecarga de alimentador'),
  (t_term, tc_tab_mt, 'Fallo de interruptor de vacío'),
  (t_term, tc_tab_mt, 'Punto caliente en cable de alimentación'),
  -- Tablero BT
  (t_term, tc_tab_bt, 'Punto caliente en bornes de conexión'),
  (t_term, tc_tab_bt, 'Interruptor sobrecargado'),
  (t_term, tc_tab_bt, 'Conexión deteriorada'),
  (t_term, tc_tab_bt, 'Desbalanceo de carga'),
  -- Compresor Reciprocante
  (t_term, tc_comp_rec, 'Falla de válvulas (sobrecalentamiento)'),
  (t_term, tc_comp_rec, 'Sobrecalentamiento de cabeza de cilindro'),
  (t_term, tc_comp_rec, 'Pistón caliente por falta de lubricación'),
  -- Rodamiento
  (t_term, tc_rodam, 'Sobrecalentamiento por falta de lubricación'),
  (t_term, tc_rodam, 'Desgaste de pista'),
  (t_term, tc_rodam, 'Carga axial excesiva'),
  -- VFD
  (t_term, tc_vfd, 'Sobrecalentamiento de componentes de potencia'),
  (t_term, tc_vfd, 'Conexión deficiente en bus DC'),
  (t_term, tc_vfd, 'Refrigeración inadecuada'),
  (t_term, tc_vfd, 'Falla de IGBT');

  -- == ANÁLISIS DE ACEITE ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_ace, tc_mot_elec, 'Desgaste ferroso en rodamientos'),
  (t_ace, tc_mot_elec, 'Contaminación por partículas externas'),
  (t_ace, tc_mot_elec, 'Degradación del lubricante'),
  (t_ace, tc_mot_elec, 'Viscosidad fuera de rango'),
  (t_ace, tc_bomb_c, 'Desgaste de materiales de bomba'),
  (t_ace, tc_bomb_c, 'Contaminación por fluido de proceso'),
  (t_ace, tc_bomb_c, 'Degradación del lubricante'),
  (t_ace, tc_comp_rec, 'Desgaste de anillos de pistón'),
  (t_ace, tc_comp_rec, 'Contaminación por gas de proceso'),
  (t_ace, tc_comp_rec, 'Acidez elevada del lubricante'),
  (t_ace, tc_comp_rec, 'Hollín excesivo'),
  (t_ace, tc_comp_c, 'Desgaste de materiales de impulsor'),
  (t_ace, tc_comp_c, 'Contaminación metálica'),
  (t_ace, tc_comp_c, 'Oxidación del lubricante'),
  (t_ace, tc_comp_c, 'Viscosidad fuera de rango'),
  (t_ace, tc_turb_g, 'Desgaste de cojinetes hidrodinámicos'),
  (t_ace, tc_turb_g, 'Contaminación metálica'),
  (t_ace, tc_turb_g, 'Oxidación del lubricante'),
  (t_ace, tc_turb_g, 'Viscosidad fuera de rango'),
  (t_ace, tc_motogen, 'Desgaste ferroso'),
  (t_ace, tc_motogen, 'Contaminación por combustible (fuel dilution)'),
  (t_ace, tc_motogen, 'Degradación de aditivos antidesgaste'),
  (t_ace, tc_motogen, 'Hollín excesivo en aceite de motor'),
  (t_ace, tc_tr_aceite, 'Gases disueltos anormales (DGA)'),
  (t_ace, tc_tr_aceite, 'Envejecimiento del papel aislante (furans)'),
  (t_ace, tc_tr_aceite, 'Contaminación por humedad'),
  (t_ace, tc_tr_aceite, 'Acidez del aceite elevada'),
  (t_ace, tc_tr_aceite, 'Partículas metálicas anómalas'),
  (t_ace, tc_engran, 'Desgaste de flancos de diente'),
  (t_ace, tc_engran, 'Micropitting en superficie de contacto'),
  (t_ace, tc_engran, 'Contaminación abrasiva'),
  (t_ace, tc_engran, 'Degradación del lubricante');

  -- == ANÁLISIS CIRCUITO DE MOTOR (MCE/MCEMAX) ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_mce, tc_mot_elec, 'Barra de rotor rota'),
  (t_mce, tc_mot_elec, 'Desbalanceo de resistencias de estátor'),
  (t_mce, tc_mot_elec, 'Deterioro de aislamiento a tierra'),
  (t_mce, tc_mot_elec, 'Excentricidad dinámica de rotor'),
  (t_mce, tc_mot_elec, 'Excentricidad estática de rotor'),
  (t_mce, tc_mot_elec, 'Cortocircuito de espiras en estátor'),
  (t_mce, tc_mot_elec, 'Rotor de alta resistencia');

  -- == ULTRASONIDO ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_ult, tc_rodam, 'Falla incipiente de rodamiento'),
  (t_ult, tc_rodam, 'Falta de lubricación'),
  (t_ult, tc_rodam, 'Desgaste avanzado de pista'),
  (t_ult, tc_rodam, 'Fractura de elemento rodante'),
  (t_ult, tc_sello, 'Fuga interna de sello mecánico'),
  (t_ult, tc_sello, 'Desgaste de cara de sello'),
  (t_ult, tc_sello, 'Colapso de muelle de sello'),
  (t_ult, tc_vlv_ctrl, 'Fuga interna de válvula'),
  (t_ult, tc_vlv_ctrl, 'Cavitación'),
  (t_ult, tc_vlv_ctrl, 'Asiento deteriorado'),
  (t_ult, tc_ducto, 'Fuga de presión en unión'),
  (t_ult, tc_ducto, 'Cavitación interna'),
  (t_ult, tc_mot_elec, 'Arco eléctrico en bobinado'),
  (t_ult, tc_mot_elec, 'Descarga parcial (ultrasónica)');

  -- == CORONOGRAFÍA / DESCARGAS PARCIALES ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_cor, tc_tab_mt, 'Descarga parcial en aislador'),
  (t_cor, tc_tab_mt, 'Efecto corona visible en conexión'),
  (t_cor, tc_tab_mt, 'Tracking en superficie de aislamiento'),
  (t_cor, tc_tab_mt, 'Arco eléctrico'),
  (t_cor, tc_mot_elec, 'Descarga parcial en devanado de estátor'),
  (t_cor, tc_mot_elec, 'Deterioro de aislamiento por actividad corona'),
  (t_cor, tc_mot_elec, 'Arco en ranuras de estátor'),
  (t_cor, tc_tr_seco, 'Descarga parcial interna en devanado'),
  (t_cor, tc_tr_seco, 'Efecto corona en terminales'),
  (t_cor, tc_tr_aceite, 'Descarga parcial interna'),
  (t_cor, tc_tr_aceite, 'Arco en papel aislante');

  -- == PRUEBAS ELÉCTRICAS (Transformadores) ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_ele, tc_tr_aceite, 'Factor de potencia de aislamiento degradado'),
  (t_ele, tc_tr_aceite, 'Resistencia de devanado fuera de especificación'),
  (t_ele, tc_tr_aceite, 'Relación de transformación incorrecta'),
  (t_ele, tc_tr_aceite, 'Resistencia de aislamiento baja (Megger)'),
  (t_ele, tc_tr_aceite, 'Índice de polarización bajo'),
  (t_ele, tc_tr_seco,   'Resistencia de aislamiento baja'),
  (t_ele, tc_tr_seco,   'Factor de potencia de aislamiento degradado'),
  (t_ele, tc_tr_seco,   'Resistencia de devanado fuera de spec'),
  (t_ele, tc_mot_elec,  'Resistencia de aislamiento baja (Megger)'),
  (t_ele, tc_mot_elec,  'Índice de polarización bajo'),
  (t_ele, tc_mot_elec,  'Desbalanceo de resistencia de devanados');

  -- == MEDICIÓN DE ESPESORES ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_int, tc_recip, 'Reducción de espesor por corrosión interna'),
  (t_int, tc_recip, 'Erosión localizada'),
  (t_int, tc_recip, 'Espesor por debajo del MAWP mínimo'),
  (t_int, tc_recip, 'Picadura (pitting) localizada'),
  (t_int, tc_recip, 'Laminación de material'),
  (t_int, tc_ducto, 'Corrosión interna general'),
  (t_int, tc_ducto, 'Erosión en codos y tees'),
  (t_int, tc_ducto, 'Espesor mínimo alcanzado'),
  (t_int, tc_ducto, 'Corrosión galvánica en uniones'),
  (t_int, tc_intercam, 'Corrosión de tubo'),
  (t_int, tc_intercam, 'Erosión por fluido de proceso'),
  (t_int, tc_intercam, 'Adelgazamiento de pared de tubo');

  -- == VARIABLES OPERATIVAS ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_ope, tc_mot_elec, 'Temperatura de operación fuera de rango'),
  (t_ope, tc_mot_elec, 'Consumo de corriente anormal'),
  (t_ope, tc_mot_elec, 'Factor de potencia degradado'),
  (t_ope, tc_bomb_c, 'Temperatura fuera de rango'),
  (t_ope, tc_bomb_c, 'Presión de descarga anormal'),
  (t_ope, tc_bomb_c, 'Caudal fuera de especificación'),
  (t_ope, tc_bomb_c, 'Consumo de potencia anormal'),
  (t_ope, tc_comp_c, 'Temperatura de descarga anormal'),
  (t_ope, tc_comp_c, 'Presión de succión/descarga fuera de rango'),
  (t_ope, tc_comp_c, 'Caudal volumétrico reducido'),
  (t_ope, tc_comp_c, 'Potencia consumida anormal'),
  (t_ope, tc_comp_rec, 'Temperatura de descarga de cilindro anormal'),
  (t_ope, tc_comp_rec, 'Eficiencia volumétrica reducida'),
  (t_ope, tc_comp_rec, 'Presión diferencial de válvulas anormal'),
  (t_ope, tc_turb_g, 'Temperatura de gases de escape anormal'),
  (t_ope, tc_turb_g, 'Consumo de combustible elevado'),
  (t_ope, tc_turb_g, 'Potencia de salida reducida'),
  (t_ope, tc_motogen, 'Temperatura de escape anormal'),
  (t_ope, tc_motogen, 'Consumo de combustible elevado'),
  (t_ope, tc_motogen, 'Potencia generada reducida'),
  (t_ope, tc_motogen, 'Presión de aceite baja'),
  (t_ope, tc_tr_aceite, 'Temperatura de aceite elevada'),
  (t_ope, tc_tr_aceite, 'Nivel de aceite bajo en conservador'),
  (t_ope, tc_tr_aceite, 'Temperatura de devanado elevada');

  -- == INSPECCIÓN VISUAL (aplica a todos) ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla)
  SELECT t_vis, tc.id, modo FROM cbm.tipos_componente tc
  CROSS JOIN (VALUES
    ('Corrosión externa'),
    ('Daño físico por impacto'),
    ('Fuga externa de fluido'),
    ('Suciedad excesiva'),
    ('Falta de resguardo de seguridad'),
    ('Señalización faltante o ilegible'),
    ('Pintura deteriorada'),
    ('Vibración visible anormal'),
    ('Ruido anormal perceptible'),
    ('Temperatura superficial anormal')
  ) AS m(modo);

  -- == DESEMPEÑO RECIPROCANTE ==
  INSERT INTO cbm.catalogo_modos_falla (tecnica_id, tipo_componente_id, modo_falla) VALUES
  (t_rec, tc_comp_rec, 'Falla de válvulas de succión'),
  (t_rec, tc_comp_rec, 'Falla de válvulas de descarga'),
  (t_rec, tc_comp_rec, 'Desgaste de anillos de pistón'),
  (t_rec, tc_comp_rec, 'Desgaste de camisa de cilindro'),
  (t_rec, tc_comp_rec, 'Fuga de empaquetaduras de prensa'),
  (t_rec, tc_comp_rec, 'Desgaste de cruceta y vástago'),
  (t_rec, tc_comp_rec, 'Baja eficiencia volumétrica'),
  (t_rec, tc_bomb_p, 'Falla de válvulas check de succión'),
  (t_rec, tc_bomb_p, 'Falla de válvulas check de descarga'),
  (t_rec, tc_bomb_p, 'Desgaste de pistón y empaquetadura'),
  (t_rec, tc_bomb_p, 'Cavitación'),
  (t_rec, tc_motogen, 'Pérdida de potencia al freno'),
  (t_rec, tc_motogen, 'Temperatura de escape anormal'),
  (t_rec, tc_motogen, 'Consumo de combustible anormal'),
  (t_rec, tc_motogen, 'Presión de aceite de motor baja');

  -- ─── Componentes — DINA ──────────────────────────────────

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_401b001, tc_vent, '100000100',
    'Ventilador de Tiro Forzado XX1',
    'Ventilador centrífugo de tiro forzado para suministro de aire a hogar de caldera. Motor 75 kW.')
  RETURNING id INTO cd_vent401b;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_702h701, tc_tr_aceite, '100000200',
    'Transformador de Corriente 702-T-001',
    'Transformador sumergido en aceite para alimentación de electrodo del tratador. Relación 13.8kV/36kV.')
  RETURNING id INTO cd_tr702h;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_301p001, tc_mot_elec, '100000016',
    'Motor MT Siemens 4000HP 301-P-001',
    'Motor eléctrico de media tensión Siemens. 4000 HP, 13.8 kV, 3600 RPM.')
  RETURNING id INTO cd_mot301p;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_301p001, tc_tr_seco, '100000017',
    'Transformador SUT 301-P-001',
    'Transformador elevador seco (SUT) 480V/13.8kV para alimentación del motor MT. 5000 kVA.')
  RETURNING id INTO cd_trsut301p;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_301p001, tc_tab_mt, '100000018',
    'Tablero de Distribución 301-P-001',
    'Celda de arranque y protección del motor MT 4000HP. Incluye disyuntor de vacío 15kV.')
  RETURNING id INTO cd_tab301p;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_g901a, tc_motogen, '100000300',
    'Motogenerador Diesel G-901A',
    'Motor diesel Caterpillar + alternador Stamford. 2000 kW, 480V, 60Hz.')
  RETURNING id INTO cd_mg901a;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_g901b, tc_motogen, '100000301',
    'Motogenerador Diesel G-901B',
    'Motor diesel Caterpillar + alternador Stamford. 2000 kW, 480V, 60Hz.')
  RETURNING id INTO cd_mg901b;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_g901c, tc_motogen, '100000302',
    'Motogenerador Diesel G-901C',
    'Motor diesel Caterpillar + alternador Stamford. 1500 kW, 480V, 60Hz.')
  RETURNING id INTO cd_mg901c;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_tc456a, tc_tr_aceite, '100000456',
    'Núcleo y Devanados TC-456A',
    'Núcleo laminado y devanados de cobre del transformador 5 MVA. Aceite dieléctrico Nynas Nytro.')
  RETURNING id INTO cd_tc456a;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_et360, tc_tab_mt, '100000360',
    'Celdas Switchgear ET-360',
    'Celdas de MT 13.8kV con interruptores de vacío. 6 bahías de alimentación + 2 de acoplamiento.')
  RETURNING id INTO cd_et360;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_et361, tc_tab_mt, '100000361',
    'Celdas Switchgear ET-361',
    'Celdas de MT 13.8kV. Historia de fallas térmicas en interruptores.')
  RETURNING id INTO cd_et361;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_et362, tc_tab_mt, '100000362',
    'Celdas Switchgear ET-362',
    'Celdas de MT 13.8kV para alimentación de bombas de inyección.')
  RETURNING id INTO cd_et362;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre, descripcion)
  VALUES (adid_odl, tc_ducto, '100000ODL',
    'Tubería Oleoducto Principal ODL',
    'Tubería de acero ASTM A106 Gr.B 16" SCH 40. Servicio: crudo con H2S. Revestimiento interno epóxico.')
  RETURNING id INTO cd_odl;

  -- ─── Componentes — GGS ──────────────────────────────────

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k101a, tc_mot_elec, 'GGS-K101A-MOT', 'Motor de Accionamiento K-101A')
  RETURNING id INTO cg_k101a_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k101a, tc_comp_c, 'GGS-K101A-CC', 'Cuerpo Compresor K-101A — Etapa 1+2')
  RETURNING id INTO cg_k101a_cc;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k101a, tc_rodam, 'GGS-K101A-ROD', 'Rodamiento Chumacera Delantera K-101A')
  RETURNING id INTO cg_k101a_rod;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k101b, tc_mot_elec, 'GGS-K101B-MOT', 'Motor de Accionamiento K-101B')
  RETURNING id INTO cg_k101b_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_tg101, tc_turb_g, 'GGS-TG101-TURB', 'Sección Turbina y Compresor TG-101')
  RETURNING id INTO cg_tg101_turb;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_tg101, tc_cam_emp, 'GGS-TG101-CEJ', 'Cojinete de Empuje TG-101')
  RETURNING id INTO cg_tg101_cej;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k201, tc_mot_elec, 'GGS-K201-MOT', 'Motor Eléctrico K-201')
  RETURNING id INTO cg_k201_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k201, tc_comp_rec, 'GGS-K201-CYL', 'Cilindros 1-4 Compresor K-201')
  RETURNING id INTO cg_k201_rec;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k301a, tc_mot_elec, 'GGS-K301A-MOT', 'Motor Eléctrico K-301A')
  RETURNING id INTO cg_k301a_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k301b, tc_mot_elec, 'GGS-K301B-MOT', 'Motor Eléctrico K-301B')
  RETURNING id INTO cg_k301b_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_k301b, tc_comp_rec, 'GGS-K301B-CYL', 'Cilindros 1-4 Compresor K-301B')
  RETURNING id INTO cg_k301b_rec;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_p401a, tc_mot_elec, 'GGS-P401A-MOT', 'Motor de Accionamiento P-401A')
  RETURNING id INTO cg_p401a_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_p401a, tc_bomb_c, 'GGS-P401A-BC', 'Cuerpo Bomba P-401A')
  RETURNING id INTO cg_p401a_bc;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_p401a, tc_sello, 'GGS-P401A-SEL', 'Sello Mecánico P-401A')
  RETURNING id INTO cg_p401a_sel;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_p401b, tc_mot_elec, 'GGS-P401B-MOT', 'Motor de Accionamiento P-401B')
  RETURNING id INTO cg_p401b_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_ge101, tc_motogen, 'GGS-GE101-MG', 'Motor Diesel + Alternador GE-101')
  RETURNING id INTO cg_ge101_mg;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_dh101, tc_mot_elec, 'GGS-DH101-MOT', 'Motor Bomba TEG DH-101')
  RETURNING id INTO cg_dh101_mot;

  INSERT INTO cbm.componentes (activo_id, tipo_componente_id, cmms_id, nombre)
  VALUES (agid_mf101, tc_otro, 'GGS-MF101-MAIN', 'Medidor Ultrasónico MF-101')
  RETURNING id INTO cg_mf101_ult;

  -- ─── Fetch modo falla IDs for use in findings ─────────────

  SELECT id INTO mf_desbal   FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Desbalanceo' AND tecnica_id = t_vib AND tipo_componente_id = tc_vent LIMIT 1;
  SELECT id INTO mf_aislam   FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Bajo nivel de aislamiento' LIMIT 1;
  SELECT id INTO mf_ptocal   FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Punto caliente en conexión de barra' LIMIT 1;
  SELECT id INTO mf_sobrec_desc FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Sobrecalentamiento de cabeza de cilindro' LIMIT 1;
  SELECT id INTO mf_falla_rod FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Falla de rodamiento' AND tecnica_id = t_vib LIMIT 1;
  SELECT id INTO mf_fuga_sel  FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Fuga interna de sello mecánico' LIMIT 1;

  -- ─── Inspection Findings — DINA (from Reporter 22-23/10/25) ──

  -- 401-B-001 / Ventilador de Tiro Forzado / VIB → ALERTA / Desbalanceo
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-22 08:00:00-05', cd_vent401b, t_vib, 'Ing. Luis Morales', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Desbalanceo' AND tecnica_id = t_vib AND tipo_componente_id = tc_vent LIMIT 1),
    'Se recomienda realizar balanceo dinámico. Vibración axial 8.2 mm/s. ISO 10816-3: zona C.');

  -- 702-H-701 / Transformador de Corriente / VIS → NORMAL / Ninguna
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-23 09:00:00-05', cd_tr702h, t_vis, 'Ing. Luis Morales', 'stand_by', 'normal',
    NULL,
    'Inspección sin hallazgos. Transformador en Stand-By programado. Aceite limpio, sin fugas externas, nivel correcto.');

  -- 301-P-001 / Motor MT / TERM → ALERTA / Desbalanceo
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-23 10:00:00-05', cd_mot301p, t_term, 'Ing. Luis Morales', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Desbalanceo de fases' AND tecnica_id = t_term AND tipo_componente_id = tc_mot_elec LIMIT 1),
    'Delta T en bobinado fase C = +18°C sobre A y B. Posible desbalanceo de alimentación. Verificar tensiones.');

  -- 301-P-001 / Transformador SUT / VIB → URGENCIA / Bajo nivel de aislamiento
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-23 10:30:00-05', cd_trsut301p, t_vib, 'Ing. Luis Morales', 'operativo', 'urgencia',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Sobrecalentamiento de devanados' AND tecnica_id = t_term AND tipo_componente_id = tc_tr_seco LIMIT 1),
    'Bajo nivel de aislamiento detectado en medición megóhmica. Resistencia de aislamiento 8 MΩ (valor mínimo aceptable 100 MΩ). Requiere acción inmediata — sacar de servicio.');

  -- 301-P-001 / Tablero de Distribución / TERM → URGENCIA / Punto Caliente
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-23 11:00:00-05', cd_tab301p, t_term, 'Ing. Luis Morales', 'operativo', 'urgencia',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Punto caliente en conexión de barra' AND tecnica_id = t_term AND tipo_componente_id = tc_tab_mt LIMIT 1),
    'Punto caliente en barra de alimentación principal: Delta T = 87°C. NETA MTS-2019 Categoría 4 — peligro inmediato. Interrupción de servicio requerida urgente.');

  -- G-901A / Motogenerador / VIB → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-05 08:00:00-05', cd_mg901a, t_vib, 'Ing. Carlos Vargas', 'operativo', 'normal',
    NULL, 'Vibración dentro de parámetros. Eje DE: 2.1 mm/s, NDE: 1.8 mm/s. ISO 20816: zona A.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-05 09:00:00-05', cd_mg901a, t_ace, 'Ing. Carlos Vargas', 'operativo', 'normal',
    NULL, 'Aceite de motor en buen estado. Partículas Fe=12 ppm (límite 40). Viscosidad 98.2 cSt@40°C. Sin combustible en aceite.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-05 09:30:00-05', cd_mg901a, t_rec, 'Ing. Carlos Vargas', 'operativo', 'normal',
    NULL, 'Desempeño dentro de especificaciones. Potencia al freno: 1985 kW (diseño 2000). Temp escape: 498°C (límite 530°C).');

  -- G-901B / Motogenerador / VIB → OBSERVACION
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-05 10:00:00-05', cd_mg901b, t_vib, 'Ing. Carlos Vargas', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Desbalanceo' AND tecnica_id = t_vib AND tipo_componente_id = tc_motogen LIMIT 1),
    'Vibración en tendencia ascendente. Eje DE: 4.8 mm/s (zona B). Monitoreo quincenal recomendado.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-05 10:30:00-05', cd_mg901b, t_rec, 'Ing. Carlos Vargas', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Consumo de combustible anormal' AND tecnica_id = t_rec AND tipo_componente_id = tc_motogen LIMIT 1),
    'Consumo de combustible +6% sobre curva base. Potencia 1870 kW. Evaluar en próxima parada.');

  -- G-901C / Motogenerador / VIB → ALERTA
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-06 08:00:00-05', cd_mg901c, t_vib, 'Ing. Carlos Vargas', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Falla de rodamiento' AND tecnica_id = t_vib AND tipo_componente_id = tc_motogen LIMIT 1),
    'Pico de frecuencia característica de rodamiento NDE (BPFO = 82 Hz). Amplitud 6.9 mm/s. Planificar cambio de rodamiento en próxima ventana de mantenimiento.');

  -- TC-456A / Núcleo y Devanados / ACE → OBSERVACION (DGA)
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-30 09:00:00-05', cd_tc456a, t_ace, 'Ing. María Ospina', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Gases disueltos anormales (DGA)' AND tecnica_id = t_ace AND tipo_componente_id = tc_tr_aceite LIMIT 1),
    'DGA muestra H2=45 ppm (límite 100), C2H2=0.5 ppm (límite 1). Tendencia creciente en H2. Próximo análisis en 30 días.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-30 09:30:00-05', cd_tc456a, t_ele, 'Ing. María Ospina', 'operativo', 'normal',
    NULL, 'Factor de potencia aislamiento: 0.38% (límite 1%). Relación de transformación correcta. Resistencia de devanados dentro de spec.');

  -- ET-360 / Celdas / VIS → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 10:00:00-05', cd_et360, t_vis, 'Ing. Carlos Vargas', 'operativo', 'normal',
    NULL, 'Inspección visual sin hallazgos. Sin signos de arco, corrosión o daño. Señalización completa.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 10:30:00-05', cd_et360, t_term, 'Ing. Carlos Vargas', 'operativo', 'normal',
    NULL, 'Termografía sin puntos calientes. Delta T máximo en conexiones: 2°C.');

  -- ET-361 / Celdas / TERM → URGENCIA, COR → ALERTA
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 11:00:00-05', cd_et361, t_term, 'Ing. María Ospina', 'operativo', 'urgencia',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Resistencia de contacto elevada en interruptor' AND tecnica_id = t_term AND tipo_componente_id = tc_tab_mt LIMIT 1),
    'CRÍTICO: Punto caliente en interruptor 13.8kV Bahía 3. Delta T = 112°C. NETA Categoría 4. Desenergizar inmediatamente para intervención.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 11:30:00-05', cd_et361, t_cor, 'Ing. María Ospina', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Tracking en superficie de aislamiento' AND tecnica_id = t_cor AND tipo_componente_id = tc_tab_mt LIMIT 1),
    'Coronografía detecta actividad en aisladores de Bahía 3. Tracking incipiente. Limpiar y verificar aisladores en próxima parada.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 09:30:00-05', cd_et361, t_vis, 'Ing. Carlos Vargas', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Señalización faltante o ilegible' AND tecnica_id = t_vis LIMIT 1),
    'Señalización de riesgo eléctrico deteriorada en 4 bahías. Marcación de cables ausente en tablero. Corregir antes de próxima inspección.');

  -- ET-362 / Celdas / TERM → NORMAL, VIS → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 14:00:00-05', cd_et362, t_term, 'Ing. María Ospina', 'operativo', 'normal',
    NULL, 'Sin puntos calientes. Delta T máximo: 3°C en barra principal. Excelente estado térmico.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-10-28 14:30:00-05', cd_et362, t_vis, 'Ing. María Ospina', 'operativo', 'normal',
    NULL, 'Inspección visual sin hallazgos. Señalización correcta, sin daños físicos.');

  -- ODL / Tubería / ESP → OBSERVACION
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-10 09:00:00-05', cd_odl, t_int, 'Ing. Roberto Cárdenas', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Corrosión interna general' AND tecnica_id = t_int AND tipo_componente_id = tc_ducto LIMIT 1),
    'Ultrasonido espesores km 3.2: espesor mínimo 7.8 mm (diseño 9.5 mm, mínimo API 570: 7.2 mm). Tasa de corrosión 0.34 mm/año. Próxima inspección en 18 meses.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES ('2025-11-10 09:30:00-05', cd_odl, t_vis, 'Ing. Roberto Cárdenas', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Pintura deteriorada' AND tecnica_id = t_vis LIMIT 1),
    'Revestimiento anticorrosivo deteriorado en tramo km 5.1–5.4. Requiere reparación de pintura antes de próxima estación lluviosa.');

  -- ─── Inspection Findings — GGS ───────────────────────────

  -- K-101A / Motor / VIB → ALERTA (consistent with sensor trending)
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '2 days', cg_k101a_mot, t_vib, 'Ing. Andrea Jiménez', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Desbalanceo' AND tecnica_id = t_vib AND tipo_componente_id = tc_mot_elec LIMIT 1),
    'Vibración axial en escalada: 9.4 mm/s. Tendencia progresiva últimas 4 semanas. Recomendar balanceo dinámico en próxima oportunidad.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '2 days', cg_k101a_cc, t_ace, 'Ing. Andrea Jiménez', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Contaminación metálica' AND tecnica_id = t_ace AND tipo_componente_id = tc_comp_c LIMIT 1),
    'Partículas ferrosas en aceite de cojinetes: Fe=28 ppm (tendencia al alza). Cambio de aceite programado.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '2 days', cg_k101a_mot, t_term, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Termografía sin hallazgos. Temperatura de devanados nominal. Delta T entre fases < 3°C.');

  -- K-101B / Motor / VIB → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '3 days', cg_k101b_mot, t_vib, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Stand-by en buen estado. Vibración 1.9 mm/s. ISO 20816 zona A. Prueba mensual de arranque satisfactoria.');

  -- TG-101 / Turbina / TERM → URGENCIA, VIB → OBSERVACION (consistent with sensor spikes)
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '7 days', cg_tg101_turb, t_term, 'Ing. Andrea Jiménez', 'operativo', 'urgencia',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Temperatura de gases de escape anormal' AND tecnica_id = t_ope AND tipo_componente_id = tc_turb_g LIMIT 1),
    'Temperatura escape 594°C (límite alarma 560°C). Temperatura descarga 1er etapa compresor: +45°C sobre baseline. Posible falla en sistema de combustión. Evaluar parada no programada.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '7 days', cg_tg101_cej, t_vib, 'Ing. Andrea Jiménez', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Falla de cojinetes hidrodinámicos' AND tecnica_id = t_vib AND tipo_componente_id = tc_turb_g LIMIT 1),
    'Vibración axial en cojinete de empuje: 5.2 mm/s (zona B). Junto con incremento de temperatura sugiere posible problema en cojinetes.');

  -- K-201 / Cilindros / REC → OBSERVACION
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '10 days', cg_k201_rec, t_rec, 'Ing. Andrea Jiménez', 'operativo', 'observacion',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Baja eficiencia volumétrica' AND tecnica_id = t_rec AND tipo_componente_id = tc_comp_rec LIMIT 1),
    'Eficiencia volumétrica cilindro 2: 78% (baseline 88%). Posible desgaste de anillos o válvulas defectuosas. Planificar inspección interna.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '10 days', cg_k201_mot, t_vib, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Motor en buen estado. Vibración 2.3 mm/s. Temperatura de rodamientos nominal.');

  -- K-301A / Motor / VIB → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '5 days', cg_k301a_mot, t_vib, 'Ing. Camila Torres', 'operativo', 'normal',
    NULL, 'Vibración 3.1 mm/s. ISO 20816: zona A/B límite. Monitoreo mensual continuo.');

  -- K-301B / Motor / VIB → ALERTA, Cilindros / REC → ALERTA (consistent with sensor trending)
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '4 days', cg_k301b_mot, t_vib, 'Ing. Camila Torres', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Desbalanceo' AND tecnica_id = t_vib AND tipo_componente_id = tc_mot_elec LIMIT 1),
    'Vibración en aumento: 7.8 mm/s. Componente 1X dominante — desbalanceo de masa. Balanceo programado para próxima semana.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '4 days', cg_k301b_rec, t_rec, 'Ing. Camila Torres', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Falla de válvulas de succión' AND tecnica_id = t_rec AND tipo_componente_id = tc_comp_rec LIMIT 1),
    'Temperatura de descarga cilindros 1 y 3: +35°C sobre nominal. Análisis de p-V indica posible falla de válvulas de succión. Programar cambio de válvulas.');

  -- P-401A / Motor, Cuerpo / VIB → URGENCIA (consistent with sensor failure spike)
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '5 days', cg_p401a_mot, t_vib, 'Ing. Camila Torres', 'operativo', 'urgencia',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Falla de rodamiento' AND tecnica_id = t_vib AND tipo_componente_id = tc_mot_elec LIMIT 1),
    'Vibración 13.1 mm/s en NDE motor. Espectro muestra BPFI = 4x. Falla avanzada de rodamiento confirmada. PARADA INMEDIATA recomendada.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '5 days', cg_p401a_mot, t_term, 'Ing. Camila Torres', 'operativo', 'urgencia',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Falla de rodamiento (térmica)' AND tecnica_id = t_term AND tipo_componente_id = tc_mot_elec LIMIT 1),
    'Temperatura carcasa rodamiento NDE: 97°C. Incremento de 40°C en últimas 48h. Confirma falla en rodamiento 6318.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '5 days', cg_p401a_sel, t_ult, 'Ing. Camila Torres', 'operativo', 'alerta',
    (SELECT id FROM cbm.catalogo_modos_falla WHERE modo_falla = 'Fuga interna de sello mecánico' AND tecnica_id = t_ult AND tipo_componente_id = tc_sello LIMIT 1),
    'Ultrasonido detecta emisión acústica en sello mecánico lado succión. Posible fuga interna incipiente. Revisar junto con intervención de rodamientos.');

  -- P-401B / Motor / VIB → NORMAL (stand-by)
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '6 days', cg_p401b_mot, t_vib, 'Ing. Camila Torres', 'operativo', 'normal',
    NULL, 'Stand-by en buen estado. Prueba mensual de arranque OK. Vibración 2.1 mm/s.');

  -- GE-101 / Motogenerador / VIB, TERM, ACE → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '8 days', cg_ge101_mg, t_vib, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Vibración nominal. DE: 2.3 mm/s, NDE: 2.8 mm/s. Sin frecuencias de falla identificadas.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '8 days', cg_ge101_mg, t_term, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Temperatura de escape nominal: 482°C. Sin puntos calientes en conexiones eléctricas del alternador.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '8 days', cg_ge101_mg, t_ace, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Aceite de motor en excelente estado. Fe=8 ppm, Cu=3 ppm. Sin dilución de combustible. Viscosidad 101 cSt@40°C.');

  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '8 days', cg_ge101_mg, t_rec, 'Ing. Andrea Jiménez', 'operativo', 'normal',
    NULL, 'Desempeño nominal. Potencia al freno 2198 kW. Consumo de combustible 2% bajo curva. Eficiencia mecánica 99.2%.');

  -- DH-101 / Motor Bomba TEG / VIB → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '12 days', cg_dh101_mot, t_vib, 'Ing. Camila Torres', 'operativo', 'normal',
    NULL, 'Vibración dentro de límites. 1.7 mm/s en ambos extremos. Sin frecuencias de falla.');

  -- MF-101 / Medidor / OPE → NORMAL
  INSERT INTO cbm.inspection_findings (time, componente_id, tecnica_id, analista, estado_operacional, condicion, modo_falla_id, observaciones)
  VALUES (NOW() - INTERVAL '15 days', cg_mf101_ult, t_ope, 'Ing. Camila Torres', 'operativo', 'normal',
    NULL, 'Calibración verificada. Factor K = 1.0002 (referencia 1.0000). Lectura de velocidad del sonido 450.2 m/s. Dentro de tolerancia OIML.');

END;
$$;
