-- ============================================================
-- Insight 360 — Auth Schema
-- 01-auth-schema.sql
-- ============================================================

-- Roles enum
CREATE TYPE auth.user_role AS ENUM (
    'admin',
    'ingeniero_confiabilidad',
    'tecnico_campo',
    'supervisor',
    'visualizador'
);

-- Users table
CREATE TABLE auth.users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cedula          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    apellido        VARCHAR(100) NOT NULL,
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    role            auth.user_role NOT NULL DEFAULT 'visualizador',
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_acceso   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Refresh tokens (stored server-side for revocation support)
CREATE TABLE auth.refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address  INET,
    user_agent  TEXT
);

-- Password reset tokens
CREATE TABLE auth.password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit log for auth events
CREATE TABLE auth.audit_log (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action      VARCHAR(50) NOT NULL,  -- LOGIN, LOGOUT, LOGIN_FAILED, TOKEN_REFRESH, PASSWORD_RESET
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_refresh_tokens_user_id ON auth.refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires_at ON auth.refresh_tokens(expires_at) WHERE NOT revoked;
CREATE INDEX idx_audit_log_user_id ON auth.audit_log(user_id);
CREATE INDEX idx_audit_log_created_at ON auth.audit_log(created_at DESC);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION auth.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

-- Seed: default admin user (password: Insight360!)
INSERT INTO auth.users (cedula, nombre, apellido, email, password_hash, role)
VALUES (
    '00000000',
    'Admin',
    'Sistema',
    'admin@inemec.com',
    crypt('Insight360!', gen_salt('bf', 12)),
    'admin'
);
