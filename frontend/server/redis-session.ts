import { createClient } from 'redis';
import { RedisStore } from 'connect-redis';
import session from 'express-session';
import createMemoryStore from 'memorystore';

/**
 * Redis Session Store Configuration
 * Falls back to MemoryStore if Redis is not configured
 */

const REDIS_URL = process.env.REDIS_URL ||
  (process.env.REDIS_HOST
    ? `redis://${process.env.REDIS_HOST}:${process.env.REDIS_PORT || 6379}`
    : undefined);

let redisClient: ReturnType<typeof createClient> | null = null;
let isRedisConnected = false;

/**
 * Initialize Redis client
 */
async function initializeRedis() {
  if (!REDIS_URL) {
    console.warn('[Redis] Not configured - using MemoryStore. Set REDIS_URL or REDIS_HOST for production.');
    return null;
  }

  try {
    redisClient = createClient({
      url: REDIS_URL,
      socket: {
        reconnectStrategy: (retries) => {
          if (retries > 10) {
            console.error('[Redis] Max reconnection attempts reached');
            return new Error('Max reconnection attempts reached');
          }
          return Math.min(retries * 100, 3000);
        },
      },
    });

    redisClient.on('error', (err) => {
      console.error('[Redis] Error:', err);
      isRedisConnected = false;
    });

    redisClient.on('connect', () => {
      console.log('[Redis] Connecting...');
    });

    redisClient.on('ready', () => {
      console.log('[Redis] Connected and ready');
      isRedisConnected = true;
    });

    redisClient.on('reconnecting', () => {
      console.log('[Redis] Reconnecting...');
    });

    await redisClient.connect();
    return redisClient;
  } catch (error) {
    console.error('[Redis] Failed to initialize:', error);
    return null;
  }
}

/**
 * Create session store (Redis or Memory fallback)
 */
export async function createSessionStore() {
  // Try to initialize Redis
  const redis = await initializeRedis();

  if (redis && isRedisConnected) {
    console.log('[Session] Using RedisStore for distributed sessions');
    return new RedisStore({
      client: redis,
      prefix: 'biomate:sess:',
      ttl: 24 * 60 * 60, // 24 hours in seconds
    });
  }

  // Fallback to MemoryStore
  console.log('[Session] Using MemoryStore (development only - not suitable for production)');
  const MemoryStore = createMemoryStore(session);
  return new MemoryStore({
    checkPeriod: 86400000, // prune expired entries every 24h
  });
}

/**
 * Get Redis client (for other uses if needed)
 */
export function getRedisClient() {
  return redisClient;
}

/**
 * Check if Redis is connected
 */
export function isRedisReady(): boolean {
  return isRedisConnected;
}

/**
 * Close Redis connection gracefully
 */
export async function closeRedis() {
  if (redisClient && isRedisConnected) {
    try {
      await redisClient.quit();
      console.log('[Redis] Connection closed');
    } catch (error) {
      console.error('[Redis] Error closing connection:', error);
    }
  }
}

// Graceful shutdown
process.on('SIGTERM', closeRedis);
process.on('SIGINT', closeRedis);
