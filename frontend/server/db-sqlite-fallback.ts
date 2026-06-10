import { drizzle } from 'drizzle-orm/better-sqlite3';
import Database from 'better-sqlite3';
import * as schema from '../shared/schema';

// SQLite fallback for testing when PostgreSQL is not available
const sqlite = new Database(':memory:'); // In-memory database for testing
export const db = drizzle(sqlite, { schema });

// Initialize schema
sqlite.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    email TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    organization TEXT,
    phone TEXT,
    trial_started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    trial_ends_at DATETIME DEFAULT (datetime('now', '+14 days')),
    trial_used INTEGER DEFAULT 0,
    stripe_customer_id TEXT,
    subscription_status TEXT DEFAULT 'trialing',
    subscription_tier TEXT DEFAULT 'academic',
    subscription_id TEXT,
    current_period_end DATETIME,
    email_verified INTEGER DEFAULT 0,
    verification_token TEXT,
    reset_password_token TEXT,
    reset_password_expires DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login_at DATETIME,
    terms_accepted_at DATETIME,
    marketing_emails_opt_in INTEGER DEFAULT 0
  );
`);

console.log('[Database] Using SQLite fallback (in-memory) for testing');

export { schema };

export async function checkDatabaseConnection(): Promise<boolean> {
  try {
    sqlite.prepare('SELECT 1').get();
    return true;
  } catch (error) {
    console.error('Database connection failed:', error);
    return false;
  }
}
