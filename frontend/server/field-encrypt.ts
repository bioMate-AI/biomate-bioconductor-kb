/**
 * Field-level AES-256-GCM encryption for sensitive database columns.
 *
 * Uses FIELD_ENCRYPTION_SECRET env var (falls back to a dev warning like JWT_SECRET).
 * The encoded format is: <iv_b64>:<tag_b64>:<ciphertext_b64>
 * This compact string is safe to store in any TEXT / VARCHAR column.
 *
 * Usage:
 *   import { encryptField, decryptField } from './field-encrypt';
 *
 *   // before INSERT / UPDATE:
 *   const stored = encryptField(plaintextApiKey);
 *
 *   // after SELECT, before using the value:
 *   const apiKey = decryptField(storedValue);
 */

import crypto from 'crypto';

const ALG = 'aes-256-gcm';

// Warning pattern mirrors JWT_SECRET handling in auth-service.ts
const _RAW_SECRET =
  process.env.FIELD_ENCRYPTION_SECRET ||
  'dev-only-insecure-field-secret-do-not-use-in-production';

if (!process.env.FIELD_ENCRYPTION_SECRET) {
  console.warn(
    '[field-encrypt] WARNING: FIELD_ENCRYPTION_SECRET not set — ' +
    'using insecure default for development only',
  );
}

/** Derive a 32-byte key from the secret using SHA-256 (fast, deterministic). */
function getKey(): Buffer {
  return crypto.createHash('sha256').update(_RAW_SECRET).digest();
}

/**
 * Encrypt a plaintext string.
 * Returns a compact "<iv_b64>:<tag_b64>:<ciphertext_b64>" string.
 */
export function encryptField(plaintext: string): string {
  const key = getKey();
  const iv = crypto.randomBytes(12); // 96-bit IV recommended for GCM
  const cipher = crypto.createCipheriv(ALG, key, iv) as crypto.CipherGCM;
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv.toString('base64'), tag.toString('base64'), enc.toString('base64')].join(':');
}

/**
 * Decrypt a value produced by encryptField().
 * Returns the original plaintext.
 * Throws if the ciphertext has been tampered with (GCM auth tag mismatch).
 *
 * If the value does not look like an encrypted field (no colons, plain text)
 * it is returned as-is so that pre-existing plaintext rows keep working
 * during a rolling migration.
 */
export function decryptField(encoded: string): string {
  // Graceful fallback: if this is a legacy plaintext value, return it directly.
  // An encrypted field always has exactly two ':' separators.
  const parts = encoded.split(':');
  if (parts.length !== 3) {
    return encoded;
  }

  const key = getKey();
  const [ivB64, tagB64, encB64] = parts;
  const iv = Buffer.from(ivB64, 'base64');
  const tag = Buffer.from(tagB64, 'base64');
  const enc = Buffer.from(encB64, 'base64');

  const decipher = crypto.createDecipheriv(ALG, key, iv) as crypto.DecipherGCM;
  decipher.setAuthTag(tag);
  return decipher.update(enc).toString('utf8') + decipher.final('utf8');
}
