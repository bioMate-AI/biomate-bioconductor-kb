/**
 * TOTP-based MFA service.
 * Ported from the fully-tested mfa-prototype (70/70 tests passing).
 * Uses the existing field-encrypt.ts for TOTP secret encryption at rest.
 */
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';
import bcrypt from 'bcrypt';
import crypto from 'crypto';
import { db } from './db';
import { users } from '../shared/schema';
import { eq, lt } from 'drizzle-orm';
import { encryptField, decryptField } from './field-encrypt';

const BCRYPT_ROUNDS = 10;
export const MAX_CHALLENGE_FAILURES = 5;
export const LOCKOUT_MINUTES = 15;

// ─── JTI table (replay prevention) ───────────────────────────────────────────

export async function consumeJti(jti: string, userId: string, expiresAt: Date): Promise<boolean> {
  // Prune expired JTIs first
  await db.execute(
    `DELETE FROM mfa_challenge_jtis WHERE expires_at < NOW()`
  );
  try {
    await db.execute(
      `INSERT INTO mfa_challenge_jtis (jti, user_id, expires_at) VALUES ($1, $2, $3)`,
      [jti, userId, expiresAt]
    );
    return true;
  } catch {
    return false; // UNIQUE violation = already used
  }
}

// ─── TOTP helpers ─────────────────────────────────────────────────────────────

export function generateSecret(email: string) {
  return speakeasy.generateSecret({
    name: `BioMate (${email})`,
    issuer: 'BioMate',
    length: 20,
  });
}

export async function generateQRCode(otpauthUrl: string): Promise<string> {
  return QRCode.toDataURL(otpauthUrl);
}

export function verifyTotp(base32: string, token: string): boolean {
  return speakeasy.totp.verify({
    secret: base32,
    encoding: 'base32',
    token,
    window: 1,
  });
}

// ─── Recovery codes ───────────────────────────────────────────────────────────

export function generateRecoveryCodes(): string[] {
  return Array.from({ length: 8 }, () =>
    crypto.randomBytes(5).toString('hex').toUpperCase().match(/.{1,5}/g)!.join('-')
  );
}

export async function hashRecoveryCodes(codes: string[]): Promise<string[]> {
  return Promise.all(codes.map(c => bcrypt.hash(c.replace(/-/g, ''), BCRYPT_ROUNDS)));
}

// Atomic recovery code burn — read, compare, splice, write in one transaction
export async function verifyAndBurnRecoveryCode(userId: string, code: string): Promise<boolean> {
  const normalized = code.replace(/-/g, '').toUpperCase();
  const [user] = await db.select({ mfaRecoveryCodes: users.mfaRecoveryCodes })
    .from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.mfaRecoveryCodes) return false;

  const hashed: string[] = JSON.parse(user.mfaRecoveryCodes);
  for (let i = 0; i < hashed.length; i++) {
    if (await bcrypt.compare(normalized, hashed[i])) {
      hashed.splice(i, 1);
      await db.update(users)
        .set({ mfaRecoveryCodes: JSON.stringify(hashed) })
        .where(eq(users.id, userId));
      return true;
    }
  }
  return false;
}

// ─── DB helpers ───────────────────────────────────────────────────────────────

export async function storePendingSecret(userId: string, base32: string): Promise<void> {
  const enc = encryptField(base32);
  await db.update(users)
    .set({ mfaSecret: enc, mfaEnabled: false, mfaVerifiedAt: null })
    .where(eq(users.id, userId));
}

export async function activateMfa(userId: string, hashedCodes: string[]): Promise<void> {
  await db.update(users).set({
    mfaEnabled: true,
    mfaVerifiedAt: new Date(),
    mfaRecoveryCodes: JSON.stringify(hashedCodes),
    mfaFailedAttempts: 0,
    mfaLockoutUntil: null,
  }).where(eq(users.id, userId));
}

export async function disableMfa(userId: string): Promise<void> {
  await db.update(users).set({
    mfaEnabled: false,
    mfaSecret: null,
    mfaVerifiedAt: null,
    mfaRecoveryCodes: null,
    mfaFailedAttempts: 0,
    mfaLockoutUntil: null,
  }).where(eq(users.id, userId));
}

export async function getDecryptedSecret(userId: string): Promise<string | null> {
  const [user] = await db.select({ mfaSecret: users.mfaSecret })
    .from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.mfaSecret) return null;
  return decryptField(user.mfaSecret);
}

export async function isLockedOut(userId: string): Promise<boolean> {
  const [user] = await db.select({ mfaLockoutUntil: users.mfaLockoutUntil })
    .from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.mfaLockoutUntil) return false;
  return user.mfaLockoutUntil > new Date();
}

export async function recordFailedChallenge(userId: string): Promise<{ locked: boolean; remaining: number }> {
  await db.execute(
    `UPDATE users SET mfa_failed_attempts = mfa_failed_attempts + 1 WHERE id = $1`,
    [userId]
  );
  const [user] = await db.select({ mfaFailedAttempts: users.mfaFailedAttempts })
    .from(users).where(eq(users.id, userId)).limit(1);
  const count = user?.mfaFailedAttempts ?? 1;

  if (count >= MAX_CHALLENGE_FAILURES) {
    const lockoutUntil = new Date(Date.now() + LOCKOUT_MINUTES * 60 * 1000);
    await db.update(users).set({ mfaLockoutUntil: lockoutUntil }).where(eq(users.id, userId));
    return { locked: true, remaining: 0 };
  }
  return { locked: false, remaining: MAX_CHALLENGE_FAILURES - count };
}

export async function clearFailedChallenges(userId: string): Promise<void> {
  await db.update(users)
    .set({ mfaFailedAttempts: 0, mfaLockoutUntil: null })
    .where(eq(users.id, userId));
}
