import speakeasy from 'speakeasy';
import QRCode from 'qrcode';
import bcrypt, { compareSync } from 'bcryptjs';
import crypto from 'crypto';
import { encrypt, decrypt } from './encrypt.js';
import type { Db } from './db.js';

const ENC_SECRET = process.env.MFA_ENCRYPTION_SECRET || 'dev-only-mfa-secret-32-bytes-!!';

export function generateSecret(email: string) {
  return speakeasy.generateSecret({
    name: `BioMate MFA (${email})`,
    issuer: 'BioMate',
    length: 20,
  });
}

export async function generateQRCode(otpauthUrl: string): Promise<string> {
  return QRCode.toDataURL(otpauthUrl);
}

export function verifyToken(secret: string, token: string): boolean {
  return speakeasy.totp.verify({
    secret,
    encoding: 'base32',
    token,
    window: 1,
  });
}

export function generateRecoveryCodes(): string[] {
  return Array.from({ length: 8 }, () => {
    const raw = crypto.randomBytes(5).toString('hex').toUpperCase();
    return raw.match(/.{1,5}/g)!.join('-');
  });
}

export async function hashRecoveryCodes(codes: string[]): Promise<string[]> {
  return Promise.all(codes.map(c => bcrypt.hash(c.replace(/-/g, ''), 10)));
}

// --- DB helpers ---

export function storePendingSecret(db: Db, userId: number, base32: string): void {
  const enc = encrypt(base32, ENC_SECRET);
  const existing = db.prepare('SELECT user_id FROM mfa_configs WHERE user_id = ?').get(userId);
  if (existing) {
    db.prepare('UPDATE mfa_configs SET secret_enc = ?, enabled = 0, verified_at = NULL WHERE user_id = ?')
      .run(enc, userId);
  } else {
    db.prepare('INSERT INTO mfa_configs (user_id, secret_enc, enabled) VALUES (?, ?, 0)')
      .run(userId, enc);
  }
}

export function activateMfa(db: Db, userId: number, hashedCodes: string[]): void {
  db.prepare(`
    UPDATE mfa_configs
    SET enabled = 1, verified_at = datetime('now'), recovery_codes = ?
    WHERE user_id = ?
  `).run(JSON.stringify(hashedCodes), userId);
}

export function getMfaConfig(db: Db, userId: number) {
  return db.prepare('SELECT * FROM mfa_configs WHERE user_id = ?').get(userId) as {
    user_id: number;
    secret_enc: string;
    enabled: number;
    verified_at: string | null;
    recovery_codes: string;
  } | undefined;
}

export function getDecryptedSecret(db: Db, userId: number): string | null {
  const cfg = getMfaConfig(db, userId);
  if (!cfg) return null;
  return decrypt(cfg.secret_enc, ENC_SECRET);
}

// Atomic: read-compare-delete runs inside a SQLite exclusive transaction.
// Uses synchronous bcrypt so the transaction cannot be interleaved.
export function verifyRecoveryCode(db: Db, userId: number, code: string): boolean {
  const normalized = code.replace(/-/g, '').toUpperCase();

  const burnCode = db.transaction(() => {
    const cfg = getMfaConfig(db, userId);
    if (!cfg) return false;
    const hashed: string[] = JSON.parse(cfg.recovery_codes);
    for (let i = 0; i < hashed.length; i++) {
      if (compareSync(normalized, hashed[i])) {
        hashed.splice(i, 1);
        db.prepare('UPDATE mfa_configs SET recovery_codes = ? WHERE user_id = ?')
          .run(JSON.stringify(hashed), userId);
        return true;
      }
    }
    return false;
  });

  return burnCode() as boolean;
}

export function disableMfa(db: Db, userId: number): void {
  db.prepare(`
    UPDATE mfa_configs
    SET enabled = 0, verified_at = NULL, recovery_codes = '[]'
    WHERE user_id = ?
  `).run(userId);
}
