-- Migration: Add User Authentication Columns
-- Date: 2025-10-14
-- Purpose: Add email verification, trial, and subscription tracking to galaxy_user table

-- Add authentication and verification columns
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS email_verified INTEGER DEFAULT 0;
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS verification_token TEXT;
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS verification_sent_at TEXT;
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS last_login_at TEXT;

-- Add trial and subscription columns
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS trial_starts_at TEXT;
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS trial_ends_at TEXT;
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial';
-- subscription_status: 'trial', 'active', 'past_due', 'canceled', 'none'

-- Add profile columns
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS profile_picture_url TEXT;
ALTER TABLE galaxy_user ADD COLUMN IF NOT EXISTS bio TEXT;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_galaxy_user_email_verified ON galaxy_user(email_verified);
CREATE INDEX IF NOT EXISTS idx_galaxy_user_subscription_status ON galaxy_user(subscription_status);
CREATE INDEX IF NOT EXISTS idx_galaxy_user_verification_token ON galaxy_user(verification_token);
CREATE INDEX IF NOT EXISTS idx_galaxy_user_trial_end ON galaxy_user(trial_ends_at);

-- Create user_sessions table for JWT token tracking
CREATE TABLE IF NOT EXISTS user_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE NOT NULL,
    user_id INTEGER NOT NULL,
    token TEXT UNIQUE NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    last_activity TEXT DEFAULT (datetime('now')),
    ip_address TEXT,
    user_agent TEXT,
    is_active INTEGER DEFAULT 1,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON user_sessions(token);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON user_sessions(user_id, is_active);

-- Create user_subscriptions table for payment tracking
CREATE TABLE IF NOT EXISTS user_subscriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    stripe_customer_id TEXT UNIQUE,
    stripe_subscription_id TEXT UNIQUE,
    plan_type TEXT DEFAULT 'monthly', -- 'monthly', 'annual'
    status TEXT DEFAULT 'trial', -- 'trial', 'active', 'past_due', 'canceled'
    trial_start TEXT,
    trial_end TEXT,
    current_period_start TEXT,
    current_period_end TEXT,
    cancel_at_period_end INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_stripe_customer ON user_subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_stripe_subscription ON user_subscriptions(stripe_subscription_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status ON user_subscriptions(status);

-- Create payment_transactions table for payment history
CREATE TABLE IF NOT EXISTS payment_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    stripe_payment_intent_id TEXT UNIQUE,
    amount REAL NOT NULL,
    currency TEXT DEFAULT 'USD',
    status TEXT NOT NULL, -- 'pending', 'succeeded', 'failed', 'refunded'
    description TEXT,
    metadata TEXT, -- JSON for additional info
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_user ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_stripe ON payment_transactions(stripe_payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_date ON payment_transactions(created_at DESC);

-- Trigger to update updated_at timestamp on user_subscriptions
CREATE TRIGGER IF NOT EXISTS update_user_subscriptions_timestamp
AFTER UPDATE ON user_subscriptions
BEGIN
    UPDATE user_subscriptions SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- Initialize trial for existing users (optional - run separately if needed)
-- UPDATE galaxy_user
-- SET trial_starts_at = datetime('now'),
--     trial_ends_at = datetime('now', '+10 days'),
--     subscription_status = 'trial'
-- WHERE subscription_status IS NULL;
