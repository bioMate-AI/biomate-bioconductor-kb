-- Schema-drift catch-up: frontend/shared/schema.ts:55-60 declares four
-- columns on `users` that were never added by a migration. /api/auth/register
-- fails on a fresh test deploy with `column "galaxy_user_id" does not exist`.
-- All four are nullable text, so adding them is non-destructive and works
-- against any prior state.

ALTER TABLE users ADD COLUMN IF NOT EXISTS galaxy_user_id  text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS galaxy_api_key  text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS galaxy_username text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_code_id  varchar;
