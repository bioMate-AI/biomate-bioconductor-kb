/**
 * Per-user API keys for headless / connector (biomate-connector) access.
 *
 * A key looks like `bm_live_<url-safe-random>`. The plaintext is shown to the
 * user exactly once at creation and is never persisted — only its SHA-256 hash
 * is stored (see `api_keys` table / migrations/0010_api_keys.sql), so a DB leak
 * cannot yield usable keys.
 *
 * Connector requests present the key via `Authorization: Bearer bm_live_…` or
 * `X-API-Key: bm_live_…`; the auth middleware calls `resolveApiKey()` to map it
 * to the owning user, so connector traffic runs as that user (their own runs,
 * quota, history) — not a single shared service account.
 */
import { createHash, randomBytes } from 'crypto';
import { eq, desc } from 'drizzle-orm';
import { db } from './db';
import { apiKeys } from '../shared/schema';
import type { ApiKey } from '../shared/schema';

export const API_KEY_PREFIX = 'bm_live_';

export function hashApiKey(plaintext: string): string {
  return createHash('sha256').update(plaintext).digest('hex');
}

export interface GeneratedApiKey {
  plaintext: string; // returned to the user ONCE
  keyHash: string;
  keyPrefix: string; // display-only fingerprint, safe to store/show
}

/** Mint a fresh key. Caller persists keyHash + keyPrefix and returns plaintext once. */
export function generateApiKey(): GeneratedApiKey {
  const body = randomBytes(24).toString('base64url'); // ~32 url-safe chars
  const plaintext = API_KEY_PREFIX + body;
  return {
    plaintext,
    keyHash: hashApiKey(plaintext),
    keyPrefix: `${API_KEY_PREFIX}${body.slice(0, 4)}…${body.slice(-4)}`,
  };
}

export interface ApiKeyResolution {
  userId: string;
  keyId: string;
}

/**
 * Resolve a presented plaintext key to its owner. Returns null when the key is
 * malformed, unknown, or revoked. Best-effort stamps last_used_at.
 */
export async function resolveApiKey(plaintext: string): Promise<ApiKeyResolution | null> {
  if (!plaintext || !plaintext.startsWith(API_KEY_PREFIX)) return null;
  const keyHash = hashApiKey(plaintext);
  const rows = await db.select().from(apiKeys).where(eq(apiKeys.keyHash, keyHash)).limit(1);
  const rec = rows[0];
  if (!rec || rec.revokedAt) return null;
  // Fire-and-forget usage stamp — never block the request on it.
  db.update(apiKeys).set({ lastUsedAt: new Date() }).where(eq(apiKeys.id, rec.id)).catch(() => {});
  return { userId: rec.userId, keyId: rec.id };
}

/** List a user's keys (no secrets — masked fingerprint + metadata only). */
export async function listApiKeys(userId: string): Promise<ApiKey[]> {
  return db.select().from(apiKeys).where(eq(apiKeys.userId, userId)).orderBy(desc(apiKeys.createdAt));
}
