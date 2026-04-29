-- MFA columns for TOTP-based two-factor authentication
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS mfa_secret          TEXT,
  ADD COLUMN IF NOT EXISTS mfa_enabled         BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS mfa_verified_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS mfa_recovery_codes  TEXT,
  ADD COLUMN IF NOT EXISTS mfa_failed_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mfa_lockout_until   TIMESTAMPTZ;

-- One-use challenge JTI table (replay prevention)
CREATE TABLE IF NOT EXISTS mfa_challenge_jtis (
  jti         TEXT PRIMARY KEY,
  user_id     VARCHAR REFERENCES users(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-clean expired JTIs (runs at query time via index)
CREATE INDEX IF NOT EXISTS idx_mfa_jtis_expires ON mfa_challenge_jtis(expires_at);
