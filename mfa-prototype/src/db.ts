import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createDb(dbPath = path.join(__dirname, '../mfa.db')) {
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      email       TEXT UNIQUE NOT NULL,
      password    TEXT NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS mfa_configs (
      user_id               INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      secret_enc            TEXT NOT NULL,
      enabled               INTEGER NOT NULL DEFAULT 0,
      verified_at           TEXT,
      recovery_codes        TEXT NOT NULL DEFAULT '[]',
      failed_challenge_count INTEGER NOT NULL DEFAULT 0,
      lockout_until         TEXT
    );

    CREATE TABLE IF NOT EXISTS used_challenge_jtis (
      jti        TEXT PRIMARY KEY,
      expires_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS audit_log (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp  TEXT NOT NULL DEFAULT (datetime('now')),
      event      TEXT NOT NULL,
      user_id    INTEGER,
      ip         TEXT,
      detail     TEXT
    );
  `);

  return db;
}

export type Db = ReturnType<typeof createDb>;
