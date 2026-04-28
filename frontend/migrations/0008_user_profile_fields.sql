-- Add role field and remember-me session tracking to users table

ALTER TABLE users ADD COLUMN IF NOT EXISTS role text;

-- Track whether a session was created with "remember me" and when it expires,
-- independent of the JWT expiry. Allows server-side invalidation of extended sessions.
ALTER TABLE users ADD COLUMN IF NOT EXISTS session_expires_at timestamp;
ALTER TABLE users ADD COLUMN IF NOT EXISTS remember_me boolean DEFAULT false;
