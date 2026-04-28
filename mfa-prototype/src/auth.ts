import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import type { Db } from './db.js';

const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-jwt-secret-change-in-prod';
const BCRYPT_ROUNDS = 10;
export const MAX_CHALLENGE_FAILURES = 5;
export const LOCKOUT_MINUTES = 15;

export interface JWTPayload {
  userId: number;
  email: string;
  type: 'session' | 'mfa_challenge';
  jti?: string;
}

export async function registerUser(db: Db, email: string, password: string): Promise<number> {
  const hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const result = db.prepare('INSERT INTO users (email, password) VALUES (?, ?)').run(email, hash);
  return result.lastInsertRowid as number;
}

export async function verifyPassword(db: Db, email: string, password: string): Promise<{ id: number; email: string } | null> {
  const user = db.prepare('SELECT id, email, password FROM users WHERE email = ?').get(email) as
    | { id: number; email: string; password: string }
    | undefined;
  if (!user) return null;
  const ok = await bcrypt.compare(password, user.password);
  if (!ok) return null;
  return { id: user.id, email: user.email };
}

export function signToken(payload: JWTPayload, expiresIn: string): string {
  const jti = payload.type === 'mfa_challenge' ? crypto.randomUUID() : undefined;
  return jwt.sign({ ...payload, jti }, JWT_SECRET, { expiresIn } as jwt.SignOptions);
}

export function verifyToken(token: string): JWTPayload {
  return jwt.verify(token, JWT_SECRET) as JWTPayload;
}

// Replay prevention: mark a challenge JTI as used
export function consumeJti(db: Db, jti: string, expiresAt: Date): boolean {
  // Clean up expired JTIs first
  db.prepare("DELETE FROM used_challenge_jtis WHERE expires_at < datetime('now')").run();
  try {
    db.prepare('INSERT INTO used_challenge_jtis (jti, expires_at) VALUES (?, ?)')
      .run(jti, expiresAt.toISOString());
    return true;
  } catch {
    // UNIQUE constraint = already used
    return false;
  }
}

// Brute-force lockout helpers
export function isLockedOut(db: Db, userId: number): boolean {
  const cfg = db.prepare('SELECT lockout_until FROM mfa_configs WHERE user_id = ?').get(userId) as
    | { lockout_until: string | null } | undefined;
  if (!cfg?.lockout_until) return false;
  return new Date(cfg.lockout_until) > new Date();
}

export function recordFailedChallenge(db: Db, userId: number): { locked: boolean; remaining: number } {
  db.prepare(`
    UPDATE mfa_configs
    SET failed_challenge_count = failed_challenge_count + 1
    WHERE user_id = ?
  `).run(userId);

  const cfg = db.prepare('SELECT failed_challenge_count FROM mfa_configs WHERE user_id = ?').get(userId) as
    | { failed_challenge_count: number } | undefined;
  const count = cfg?.failed_challenge_count ?? 1;

  if (count >= MAX_CHALLENGE_FAILURES) {
    const lockoutUntil = new Date(Date.now() + LOCKOUT_MINUTES * 60 * 1000).toISOString();
    db.prepare('UPDATE mfa_configs SET lockout_until = ? WHERE user_id = ?').run(lockoutUntil, userId);
    return { locked: true, remaining: 0 };
  }
  return { locked: false, remaining: MAX_CHALLENGE_FAILURES - count };
}

export function clearFailedChallenges(db: Db, userId: number): void {
  db.prepare('UPDATE mfa_configs SET failed_challenge_count = 0, lockout_until = NULL WHERE user_id = ?')
    .run(userId);
}

export function auditLog(db: Db, event: string, userId: number | null, ip: string, detail?: string): void {
  db.prepare('INSERT INTO audit_log (event, user_id, ip, detail) VALUES (?, ?, ?, ?)')
    .run(event, userId, ip, detail ?? null);
}

export function getUser(db: Db, userId: number) {
  return db.prepare('SELECT id, email, created_at FROM users WHERE id = ?').get(userId) as
    | { id: number; email: string; created_at: string }
    | undefined;
}
