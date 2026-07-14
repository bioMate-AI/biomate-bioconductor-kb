import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from '../shared/schema';
import * as ltmSchema from '../shared/ltm-schema';

// Combine schemas
const combinedSchema = { ...schema, ...ltmSchema };

// ── Lazy initialization ──────────────────────────────────────────────────────
// Previously this module threw `DATABASE_URL environment variable is required`
// and opened a pg Pool at MODULE IMPORT time. That made importing ANY server
// module transitively crash when DATABASE_URL was unset — which broke offline
// tooling and CI gates (pm-test-wire's offline intent mapping, feedback-e2e's
// server boot) on every run, even though those paths never touch the database.
//
// A module-load-time env requirement is a fragility, not a safety check: the
// import order decides whether it fires. Defer both the DATABASE_URL check and
// the Pool creation to the FIRST actual database use, so importing server code
// is side-effect-free and the failure (when a query really runs without a DB)
// is explicit and actionable.

let _pool: Pool | null = null;
let _db: ReturnType<typeof drizzle<typeof combinedSchema>> | null = null;

function getPool(): Pool {
  if (!_pool) {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL environment variable is required');
    }
    _pool = new Pool({ connectionString: process.env.DATABASE_URL });
  }
  return _pool;
}

function getDb(): ReturnType<typeof drizzle<typeof combinedSchema>> {
  if (!_db) {
    _db = drizzle(getPool(), { schema: combinedSchema });
  }
  return _db;
}

// Lazy proxies preserve the historical `import { db, pool } from './db'`
// interface (property/method access) while deferring construction — and the
// DATABASE_URL requirement — to first use. Methods are bound to the real
// instance so `this` is correct.
function lazyProxy<T extends object>(resolve: () => T): T {
  return new Proxy({} as T, {
    get(_target, prop, receiver) {
      const real = resolve() as any;
      const value = Reflect.get(real, prop, receiver);
      return typeof value === 'function' ? value.bind(real) : value;
    },
    set(_target, prop, value) {
      const real = resolve() as any;
      real[prop] = value;
      return true;
    },
    has(_target, prop) {
      return prop in (resolve() as any);
    },
  });
}

export const pool: Pool = lazyProxy(getPool);
export const db: ReturnType<typeof drizzle<typeof combinedSchema>> = lazyProxy(getDb);

// Export schemas for use in queries
export { schema, ltmSchema };

// Health check function
export async function checkDatabaseConnection(): Promise<boolean> {
  try {
    const client = await getPool().connect();
    client.release();
    return true;
  } catch (error) {
    console.error('Database connection failed:', error);
    return false;
  }
}
