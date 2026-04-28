/**
 * Security audit tests — adversarial scenarios only.
 * These tests verify that attacks and edge cases are handled correctly.
 * All 38 original integration tests must still pass alongside these.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import speakeasy from 'speakeasy';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createApp } from '../src/index.js';
import { MAX_CHALLENGE_FAILURES, LOCKOUT_MINUTES } from '../src/auth.js';
import type { Db } from '../src/db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEST_DB = path.join(__dirname, '../security-test.db');

let app: Express.Application;
let db: Db;

beforeAll(() => {
  if (fs.existsSync(TEST_DB)) fs.unlinkSync(TEST_DB);
  ({ app, db } = createApp(TEST_DB));
});

afterAll(() => {
  db.close();
  if (fs.existsSync(TEST_DB)) fs.unlinkSync(TEST_DB);
});

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function registerAndLogin(email: string, pw = 'SecurePass99') {
  await request(app).post('/api/auth/register').send({ email, password: pw });
  const res = await request(app).post('/api/auth/login').send({ email, password: pw });
  return res.body.token as string;
}

async function enableMfa(sessionToken: string) {
  const setupRes = await request(app)
    .post('/api/auth/mfa/setup')
    .set('Authorization', `Bearer ${sessionToken}`)
    .send();
  const { manualKey } = setupRes.body;
  const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
  const verifyRes = await request(app)
    .post('/api/auth/mfa/verify-setup')
    .set('Authorization', `Bearer ${sessionToken}`)
    .send({ token: totp });
  return { manualKey, recoveryCodes: verifyRes.body.recoveryCodes as string[] };
}

async function loginWithMfa(email: string, manualKey: string, pw = 'SecurePass99') {
  const loginRes = await request(app).post('/api/auth/login').send({ email, password: pw });
  const { challengeToken } = loginRes.body;
  const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
  const challengeRes = await request(app)
    .post('/api/auth/mfa/challenge')
    .send({ challengeToken, token: totp });
  return { challengeToken, sessionToken: challengeRes.body.token };
}

// ─── Input Validation ────────────────────────────────────────────────────────

describe('Input validation', () => {
  it('register: rejects missing email', async () => {
    const res = await request(app).post('/api/auth/register').send({ password: 'Password123' });
    expect(res.status).toBe(400);
  });

  it('register: rejects missing password', async () => {
    const res = await request(app).post('/api/auth/register').send({ email: 'x@test.com' });
    expect(res.status).toBe(400);
  });

  it('register: rejects empty body', async () => {
    const res = await request(app).post('/api/auth/register').send({});
    expect(res.status).toBe(400);
  });

  it('register: rejects extremely long email (10k chars)', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'a'.repeat(10000) + '@b.com', password: 'Password123' });
    // Should not crash the server — 400 or 500 acceptable, never unhandled crash
    expect([400, 409, 500]).toContain(res.status);
  });

  it('challenge: rejects missing body fields', async () => {
    const res = await request(app).post('/api/auth/mfa/challenge').send({});
    expect(res.status).toBe(400);
  });

  it('challenge: rejects null token', async () => {
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken: null, token: null });
    expect(res.status).toBe(400);
  });

  it('challenge: rejects numeric token (type coercion attack)', async () => {
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken: 12345, token: 12345 });
    // Will fail on JWT verify — should be 401 not crash
    expect([400, 401]).toContain(res.status);
  });

  it('verify-setup: rejects missing token field', async () => {
    const token = await registerAndLogin('nototp@test.com');
    await request(app).post('/api/auth/mfa/setup').set('Authorization', `Bearer ${token}`).send();
    const res = await request(app)
      .post('/api/auth/mfa/verify-setup')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });
});

// ─── Authentication Bypass Attempts ─────────────────────────────────────────

describe('Auth bypass', () => {
  it('challenge token cannot call protected endpoints directly', async () => {
    const token = await registerAndLogin('bypasstest@test.com');
    const { manualKey } = await enableMfa(token);
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: 'bypasstest@test.com', password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;

    const res = await request(app)
      .get('/api/me')
      .set('Authorization', `Bearer ${challengeToken}`);
    expect(res.status).toBe(401);
    void manualKey; // used above
  });

  it('forged JWT (wrong secret) is rejected', async () => {
    // Sign with a different secret
    const { default: jwt } = await import('jsonwebtoken');
    const fakeToken = jwt.sign(
      { userId: 1, email: 'fake@test.com', type: 'session' },
      'wrong-secret',
      { expiresIn: '1h' }
    );
    const res = await request(app)
      .get('/api/me')
      .set('Authorization', `Bearer ${fakeToken}`);
    expect(res.status).toBe(401);
  });

  it('expired JWT is rejected', async () => {
    const { default: jwt } = await import('jsonwebtoken');
    const expiredToken = jwt.sign(
      { userId: 1, email: 'x@test.com', type: 'session' },
      'dev-only-jwt-secret-change-in-prod',
      { expiresIn: '-1s' }
    );
    const res = await request(app)
      .get('/api/me')
      .set('Authorization', `Bearer ${expiredToken}`);
    expect(res.status).toBe(401);
  });

  it('malformed Bearer token is rejected', async () => {
    const res = await request(app)
      .get('/api/me')
      .set('Authorization', 'Bearer not.a.jwt');
    expect(res.status).toBe(401);
  });

  it('missing Authorization header is rejected', async () => {
    const res = await request(app).get('/api/me');
    expect(res.status).toBe(401);
  });

  it('session token used as challenge token is rejected', async () => {
    const sessionToken = await registerAndLogin('session-as-challenge@test.com');
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken: sessionToken, token: '123456' });
    expect(res.status).toBe(401);
  });
});

// ─── Challenge Token Replay Prevention ───────────────────────────────────────

describe('Challenge token replay prevention', () => {
  let email: string;
  let manualKey: string;

  beforeAll(async () => {
    email = `replay-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    ({ manualKey } = await enableMfa(token));
  });

  it('cannot reuse the same challenge token after a successful MFA challenge', async () => {
    // First: successful challenge
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });

    const firstRes = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: totp });
    expect(firstRes.status).toBe(200);

    // Second attempt with same token: JTI already consumed
    const totp2 = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    const replayRes = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: totp2 });
    expect(replayRes.status).toBe(401);
    expect(replayRes.body.error).toMatch(/already used/i);
  });

  it('cannot reuse challenge token after a failed attempt', async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;

    // First attempt fails
    await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: '000000' });

    // Retry with same challengeToken (JTI consumed)
    const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    const retryRes = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: totp });
    expect(retryRes.status).toBe(401);
    expect(retryRes.body.error).toMatch(/already used/i);
  });
});

// ─── Brute-Force Lockout ─────────────────────────────────────────────────────

describe('Brute-force lockout', () => {
  let email: string;
  let manualKey: string;

  beforeAll(async () => {
    email = `bruteforce-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    ({ manualKey } = await enableMfa(token));
  });

  it(`locks account after ${MAX_CHALLENGE_FAILURES} consecutive failures`, async () => {
    const responses: number[] = [];

    for (let i = 0; i < MAX_CHALLENGE_FAILURES; i++) {
      const loginRes = await request(app)
        .post('/api/auth/login')
        .send({ email, password: 'SecurePass99' });
      const { challengeToken } = loginRes.body;
      const res = await request(app)
        .post('/api/auth/mfa/challenge')
        .send({ challengeToken, token: '000000' });
      responses.push(res.status);
    }

    // First N-1 should be 401 (wrong code), last should be 429 (locked)
    expect(responses.slice(0, MAX_CHALLENGE_FAILURES - 1)).toEqual(
      Array(MAX_CHALLENGE_FAILURES - 1).fill(401)
    );
    expect(responses[MAX_CHALLENGE_FAILURES - 1]).toBe(429);
  });

  it('rejects even valid TOTP while locked out', async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: totp });
    expect(res.status).toBe(429);
  });

  it('lockout is per-user (other user unaffected)', async () => {
    const otherEmail = `other-${Date.now()}@test.com`;
    const otherToken = await registerAndLogin(otherEmail);
    const { manualKey: otherKey } = await enableMfa(otherToken);

    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: otherEmail, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const totp = speakeasy.totp({ secret: otherKey, encoding: 'base32' });
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: totp });
    expect(res.status).toBe(200);
  });

  it('audit log contains mfa_lockout event', async () => {
    // Get a fresh session from the locked user's original session (pre-lockout)
    const freshSession = await registerAndLogin(`audit-lockcheck-${Date.now()}@test.com`);
    const auditRes = await request(app)
      .get('/api/audit')
      .set('Authorization', `Bearer ${freshSession}`);
    const events = auditRes.body.map((r: any) => r.event);
    expect(events).toContain('mfa_lockout');
  });
});

// ─── Recovery Code Security ───────────────────────────────────────────────────

describe('Recovery code security', () => {
  let email: string;
  let recoveryCodes: string[];
  let manualKey: string;

  beforeAll(async () => {
    email = `recovsec-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    ({ manualKey, recoveryCodes } = await enableMfa(token));
  });

  it('recovery code without dashes also works (normalization)', async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const noDash = recoveryCodes[0].replace(/-/g, '');
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: noDash });
    expect(res.status).toBe(200);
  });

  it('lowercase recovery code also works (normalization)', async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const lower = recoveryCodes[1].toLowerCase();
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: lower });
    expect(res.status).toBe(200);
  });

  it('each recovery code can only be used once (burned)', async () => {
    // codes[0] and [1] used above; try code[0] again
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: recoveryCodes[0] });
    expect(res.status).toBe(401);
  });

  it('all 8 codes are distinct values', () => {
    expect(new Set(recoveryCodes).size).toBe(8);
  });

  it('recovery codes are not returned on subsequent /mfa/status calls', async () => {
    const { sessionToken } = await loginWithMfa(email, manualKey);
    const res = await request(app)
      .get('/api/auth/mfa/status')
      .set('Authorization', `Bearer ${sessionToken}`);
    expect(res.body).not.toHaveProperty('recoveryCodes');
    expect(res.body).not.toHaveProperty('codes');
    // Only remainingRecoveryCodes count is returned
    expect(res.body.remainingRecoveryCodes).toBeTypeOf('number');
  });
});

// ─── Encryption at Rest ───────────────────────────────────────────────────────

describe('Encryption at rest', () => {
  it('TOTP secret is not stored in plaintext in the DB', async () => {
    const email = `enctest-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    const setupRes = await request(app)
      .post('/api/auth/mfa/setup')
      .set('Authorization', `Bearer ${token}`)
      .send();
    const { manualKey } = setupRes.body;

    // Read raw DB value
    const row = db.prepare(`
      SELECT mc.secret_enc FROM mfa_configs mc
      JOIN users u ON u.id = mc.user_id
      WHERE u.email = ?
    `).get(email) as { secret_enc: string } | undefined;

    expect(row).toBeDefined();
    // The stored value must NOT equal the plaintext base32 key
    expect(row!.secret_enc).not.toBe(manualKey);
    // Must contain iv:tag:ciphertext separator pattern
    expect(row!.secret_enc.split(':').length).toBe(3);
  });

  it('recovery codes are not stored in plaintext in the DB', async () => {
    const email = `rcenc-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    const { recoveryCodes } = await enableMfa(token);

    const row = db.prepare(`
      SELECT mc.recovery_codes FROM mfa_configs mc
      JOIN users u ON u.id = mc.user_id
      WHERE u.email = ?
    `).get(email) as { recovery_codes: string } | undefined;

    const stored: string[] = JSON.parse(row!.recovery_codes);
    // Stored values must be bcrypt hashes, not plaintext
    for (let i = 0; i < recoveryCodes.length; i++) {
      expect(stored[i]).not.toBe(recoveryCodes[i]);
      expect(stored[i]).toHaveLength(60); // bcrypt hash length
    }
  });
});

// ─── MFA Setup Edge Cases ────────────────────────────────────────────────────

describe('MFA setup edge cases', () => {
  it('re-setup before activation replaces the pending secret', async () => {
    const email = `resetup-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);

    const first = await request(app)
      .post('/api/auth/mfa/setup')
      .set('Authorization', `Bearer ${token}`)
      .send();
    const second = await request(app)
      .post('/api/auth/mfa/setup')
      .set('Authorization', `Bearer ${token}`)
      .send();

    // Manual keys should differ (new secret generated)
    expect(first.body.manualKey).not.toBe(second.body.manualKey);

    // Only the second secret should work for verification
    const oldTotp = speakeasy.totp({ secret: first.body.manualKey, encoding: 'base32' });
    const badRes = await request(app)
      .post('/api/auth/mfa/verify-setup')
      .set('Authorization', `Bearer ${token}`)
      .send({ token: oldTotp });
    expect(badRes.status).toBe(400);

    const goodTotp = speakeasy.totp({ secret: second.body.manualKey, encoding: 'base32' });
    const goodRes = await request(app)
      .post('/api/auth/mfa/verify-setup')
      .set('Authorization', `Bearer ${token}`)
      .send({ token: goodTotp });
    expect(goodRes.status).toBe(200);
  });

  it('verify-setup without calling setup first returns 400', async () => {
    const email = `nosetup-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    const res = await request(app)
      .post('/api/auth/mfa/verify-setup')
      .set('Authorization', `Bearer ${token}`)
      .send({ token: '123456' });
    expect(res.status).toBe(400);
  });
});

// ─── Concurrent Recovery Code Use ────────────────────────────────────────────

describe('Concurrent recovery code burn (race condition)', () => {
  it('only one of two concurrent uses of the same code succeeds', async () => {
    const email = `concurrent-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    const { recoveryCodes } = await enableMfa(token);
    const code = recoveryCodes[0];

    // Fire two challenge requests simultaneously with the same recovery code
    const [loginA, loginB] = await Promise.all([
      request(app).post('/api/auth/login').send({ email, password: 'SecurePass99' }),
      request(app).post('/api/auth/login').send({ email, password: 'SecurePass99' }),
    ]);

    const [resA, resB] = await Promise.all([
      request(app).post('/api/auth/mfa/challenge').send({
        challengeToken: loginA.body.challengeToken,
        token: code,
      }),
      request(app).post('/api/auth/mfa/challenge').send({
        challengeToken: loginB.body.challengeToken,
        token: code,
      }),
    ]);

    const statuses = [resA.status, resB.status].sort();
    // Exactly one 200 and one 401
    expect(statuses).toEqual([200, 401]);
  });
});

// ─── remainingAttempts countdown ────────────────────────────────────────────

describe('remainingAttempts in failure response', () => {
  let email: string;
  let manualKey: string;

  beforeAll(async () => {
    email = `remaining-${Date.now()}@test.com`;
    const token = await registerAndLogin(email);
    ({ manualKey } = await enableMfa(token));
  });

  it('decrements remainingAttempts on each failure', async () => {
    const results: number[] = [];
    for (let i = 0; i < MAX_CHALLENGE_FAILURES - 1; i++) {
      const loginRes = await request(app)
        .post('/api/auth/login')
        .send({ email, password: 'SecurePass99' });
      const { challengeToken } = loginRes.body;
      const res = await request(app)
        .post('/api/auth/mfa/challenge')
        .send({ challengeToken, token: '000000' });
      if (res.body.remainingAttempts !== undefined) {
        results.push(res.body.remainingAttempts);
      }
    }
    // Should count down: [3, 2, 1] for MAX=5
    for (let i = 1; i < results.length; i++) {
      expect(results[i]).toBeLessThan(results[i - 1]);
    }
    expect(results[results.length - 1]).toBe(1);
  });

  it(`final failure (attempt ${MAX_CHALLENGE_FAILURES}) returns 429 with no remainingAttempts`, async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email, password: 'SecurePass99' });
    const { challengeToken } = loginRes.body;
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: '000000' });
    expect(res.status).toBe(429);
    expect(res.body.remainingAttempts).toBeUndefined();
    void manualKey;
  });
});
