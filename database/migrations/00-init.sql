-- ============================================================
-- Insight 360 — Database Init
-- 00-init.sql: Extensions and schema creation
-- ============================================================

-- TimescaleDB extension (must be first)
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Additional extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create all schemas
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS cbm;
CREATE SCHEMA IF NOT EXISTS routes;
CREATE SCHEMA IF NOT EXISTS reports;

-- Search path
ALTER DATABASE insight360 SET search_path TO public, auth, core, cbm, routes, reports;
