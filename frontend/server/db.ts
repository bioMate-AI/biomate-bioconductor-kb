import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from '../shared/schema';
import * as ltmSchema from '../shared/ltm-schema';

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL environment variable is required');
}

// Create connection pool
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Combine schemas
const combinedSchema = { ...schema, ...ltmSchema };

// Create Drizzle instance with combined schema
export const db = drizzle(pool, { schema: combinedSchema });

// Export schemas and raw pool for use in queries
export { schema, ltmSchema, pool };

// Health check function
export async function checkDatabaseConnection(): Promise<boolean> {
  try {
    const client = await pool.connect();
    client.release();
    return true;
  } catch (error) {
    console.error('Database connection failed:', error);
    return false;
  }
}
