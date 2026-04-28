import { describe, it, expect } from 'vitest';
import speakeasy from 'speakeasy';
import { encrypt, decrypt } from '../src/encrypt.js';
import {
  generateSecret, verifyToken, generateRecoveryCodes, hashRecoveryCodes,
} from '../src/mfa.js';

const SECRET = 'test-encryption-secret-32-bytes!';

describe('encrypt/decrypt', () => {
  it('round-trips plaintext', () => {
    const plain = 'JBSWY3DPEHPK3PXP'; // sample base32
    expect(decrypt(encrypt(plain, SECRET), SECRET)).toBe(plain);
  });

  it('different iv each time', () => {
    const plain = 'hello';
    expect(encrypt(plain, SECRET)).not.toBe(encrypt(plain, SECRET));
  });

  it('throws on tampered ciphertext', () => {
    const enc = encrypt('hello', SECRET);
    const parts = enc.split(':');
    parts[2] = Buffer.from('tampered').toString('base64');
    expect(() => decrypt(parts.join(':'), SECRET)).toThrow();
  });
});

describe('TOTP', () => {
  it('generates a valid secret', () => {
    const s = generateSecret('test@example.com');
    expect(s.base32).toBeTruthy();
    expect(s.otpauth_url).toMatch(/otpauth:\/\/totp/);
    expect(s.otpauth_url).toContain('test%40example.com');
  });

  it('verifies a live TOTP token', () => {
    const s = generateSecret('test@example.com');
    const token = speakeasy.totp({ secret: s.base32, encoding: 'base32' });
    expect(verifyToken(s.base32, token)).toBe(true);
  });

  it('rejects a wrong token', () => {
    const s = generateSecret('test@example.com');
    expect(verifyToken(s.base32, '000000')).toBe(false);
  });

  it('rejects an expired token (window=1 → 30s)', () => {
    const s = generateSecret('test@example.com');
    // Token for 3 steps ago (90 seconds)
    const oldToken = speakeasy.totp({
      secret: s.base32,
      encoding: 'base32',
      time: Math.floor(Date.now() / 1000) - 90,
    });
    expect(verifyToken(s.base32, oldToken)).toBe(false);
  });
});

describe('recovery codes', () => {
  it('generates 8 codes in XXXXX-XXXXX format', () => {
    const codes = generateRecoveryCodes();
    expect(codes).toHaveLength(8);
    for (const c of codes) expect(c).toMatch(/^[0-9A-F]{5}-[0-9A-F]{5}$/);
  });

  it('all codes are unique', () => {
    const codes = generateRecoveryCodes();
    expect(new Set(codes).size).toBe(8);
  });

  it('hashes are bcrypt (60 chars)', async () => {
    const codes = generateRecoveryCodes();
    const hashed = await hashRecoveryCodes(codes);
    expect(hashed).toHaveLength(8);
    for (const h of hashed) expect(h).toHaveLength(60);
  });
});
