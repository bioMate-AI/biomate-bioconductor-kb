import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import speakeasy from 'speakeasy';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createApp } from '../src/index.js';
import type { Db } from '../src/db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEST_DB = path.join(__dirname, '../test.db');

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

async function register(email: string, password = 'Password123') {
  const res = await request(app).post('/api/auth/register').send({ email, password });
  expect(res.status).toBe(201);
  return res.body.userId as number;
}

async function login(email: string, password = 'Password123') {
  const res = await request(app).post('/api/auth/login').send({ email, password });
  return res;
}

async function setupMfa(token: string): Promise<{ qrCode: string; manualKey: string }> {
  const res = await request(app)
    .post('/api/auth/mfa/setup')
    .set('Authorization', `Bearer ${token}`)
    .send();
  expect(res.status).toBe(200);
  return res.body;
}

async function verifySetup(sessionToken: string, totpToken: string) {
  const res = await request(app)
    .post('/api/auth/mfa/verify-setup')
    .set('Authorization', `Bearer ${sessionToken}`)
    .send({ token: totpToken });
  return res;
}

// ─── Registration ─────────────────────────────────────────────────────────────

describe('POST /api/auth/register', () => {
  it('registers a new user', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'newuser@test.com', password: 'Password123' });
    expect(res.status).toBe(201);
    expect(res.body.userId).toBeTypeOf('number');
  });

  it('rejects duplicate email', async () => {
    await register('dup@test.com');
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'dup@test.com', password: 'Password123' });
    expect(res.status).toBe(409);
  });

  it('rejects short password', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'x@test.com', password: 'short' });
    expect(res.status).toBe(400);
  });
});

// ─── Login (no MFA) ──────────────────────────────────────────────────────────

describe('POST /api/auth/login (no MFA)', () => {
  it('returns a session token for valid credentials', async () => {
    await register('login@test.com');
    const res = await login('login@test.com');
    expect(res.status).toBe(200);
    expect(res.body.token).toBeTruthy();
    expect(res.body.mfaRequired).toBeUndefined();
  });

  it('rejects wrong password', async () => {
    await register('bad@test.com');
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'bad@test.com', password: 'WrongPass1' });
    expect(res.status).toBe(401);
  });

  it('rejects unknown email', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'nobody@test.com', password: 'Password123' });
    expect(res.status).toBe(401);
  });
});

// ─── MFA Setup ────────────────────────────────────────────────────────────────

describe('MFA setup flow', () => {
  it('returns a QR code and manual key', async () => {
    await register('setup@test.com');
    const loginRes = await login('setup@test.com');
    const { token } = loginRes.body;

    const { qrCode, manualKey } = await setupMfa(token);
    expect(qrCode).toMatch(/^data:image\/png;base64,/);
    expect(manualKey).toMatch(/^[A-Z2-7]{32}$/);
  });

  it('requires auth', async () => {
    const res = await request(app).post('/api/auth/mfa/setup').send();
    expect(res.status).toBe(401);
  });

  it('activates MFA with a valid TOTP code and returns 8 recovery codes', async () => {
    await register('activate@test.com');
    const loginRes = await login('activate@test.com');
    const { token } = loginRes.body;

    const { manualKey } = await setupMfa(token);
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });

    const verifyRes = await verifySetup(token, totpToken);
    expect(verifyRes.status).toBe(200);
    expect(verifyRes.body.recoveryCodes).toHaveLength(8);
    for (const c of verifyRes.body.recoveryCodes) {
      expect(c).toMatch(/^[0-9A-F]{5}-[0-9A-F]{5}$/);
    }
  });

  it('rejects an invalid TOTP on verify-setup', async () => {
    await register('bad-verify@test.com');
    const loginRes = await login('bad-verify@test.com');
    const { token } = loginRes.body;
    await setupMfa(token);
    const res = await verifySetup(token, '000000');
    expect(res.status).toBe(400);
  });
});

// ─── MFA Status ───────────────────────────────────────────────────────────────

describe('GET /api/auth/mfa/status', () => {
  it('reports not enabled before setup', async () => {
    await register('status1@test.com');
    const { body: { token } } = await login('status1@test.com');
    const res = await request(app)
      .get('/api/auth/mfa/status')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.enabled).toBe(false);
  });

  it('reports enabled after activation', async () => {
    await register('status2@test.com');
    const { body: { token } } = await login('status2@test.com');
    const { manualKey } = await setupMfa(token);
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    await verifySetup(token, totpToken);

    const res = await request(app)
      .get('/api/auth/mfa/status')
      .set('Authorization', `Bearer ${token}`);
    expect(res.body.enabled).toBe(true);
    expect(res.body.verifiedAt).toBeTruthy();
    expect(res.body.remainingRecoveryCodes).toBe(8);
  });
});

// ─── MFA Login flow ──────────────────────────────────────────────────────────

describe('Login with MFA enabled', () => {
  let email: string;
  let manualKey: string;
  let sessionToken: string;

  beforeAll(async () => {
    email = `mfalogin-${Date.now()}@test.com`;
    await register(email);
    const { body: { token } } = await login(email);
    sessionToken = token;
    const setup = await setupMfa(sessionToken);
    manualKey = setup.manualKey;
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    await verifySetup(sessionToken, totpToken);
  });

  it('returns mfaRequired + challengeToken on login', async () => {
    const res = await login(email);
    expect(res.status).toBe(200);
    expect(res.body.mfaRequired).toBe(true);
    expect(res.body.challengeToken).toBeTruthy();
    expect(res.body.token).toBeUndefined();
  });

  it('issues a session token after valid TOTP challenge', async () => {
    const loginRes = await login(email);
    const { challengeToken } = loginRes.body;
    const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: totp });
    expect(res.status).toBe(200);
    expect(res.body.token).toBeTruthy();
  });

  it('rejects an invalid TOTP on challenge', async () => {
    const loginRes = await login(email);
    const { challengeToken } = loginRes.body;
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: '000000' });
    expect(res.status).toBe(401);
  });

  it('rejects an expired challenge token', async () => {
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken: 'not.a.real.token', token: '123456' });
    expect(res.status).toBe(401);
  });

  it('rejects a session token used as challenge token', async () => {
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken: sessionToken, token: '123456' });
    expect(res.status).toBe(401);
  });
});

// ─── Recovery codes ───────────────────────────────────────────────────────────

describe('Recovery codes', () => {
  let email: string;
  let manualKey: string;
  let recoveryCodes: string[];
  let sessionToken: string;

  beforeAll(async () => {
    email = `recovery-${Date.now()}@test.com`;
    await register(email);
    const { body: { token } } = await login(email);
    sessionToken = token;
    const setup = await setupMfa(sessionToken);
    manualKey = setup.manualKey;
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    const verifyRes = await verifySetup(sessionToken, totpToken);
    recoveryCodes = verifyRes.body.recoveryCodes;
  });

  it('accepts a valid recovery code instead of TOTP', async () => {
    const loginRes = await login(email);
    const { challengeToken } = loginRes.body;
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: recoveryCodes[0] });
    expect(res.status).toBe(200);
    expect(res.body.token).toBeTruthy();
  });

  it('burns the used recovery code (cannot reuse)', async () => {
    const loginRes = await login(email);
    const { challengeToken } = loginRes.body;
    // recoveryCodes[0] was used above
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: recoveryCodes[0] });
    expect(res.status).toBe(401);
  });

  it('remaining count decrements after use', async () => {
    const res = await request(app)
      .get('/api/auth/mfa/status')
      .set('Authorization', `Bearer ${sessionToken}`);
    expect(res.body.remainingRecoveryCodes).toBe(7);
  });

  it('accepts a second recovery code', async () => {
    const loginRes = await login(email);
    const { challengeToken } = loginRes.body;
    const res = await request(app)
      .post('/api/auth/mfa/challenge')
      .send({ challengeToken, token: recoveryCodes[1] });
    expect(res.status).toBe(200);
  });
});

// ─── Disable MFA ─────────────────────────────────────────────────────────────

describe('Disable MFA', () => {
  let email: string;
  let manualKey: string;
  let sessionToken: string;

  beforeAll(async () => {
    email = `disable-${Date.now()}@test.com`;
    await register(email);
    const { body: { token } } = await login(email);
    sessionToken = token;
    const setup = await setupMfa(sessionToken);
    manualKey = setup.manualKey;
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    await verifySetup(sessionToken, totpToken);
  });

  it('disables MFA with correct password + TOTP', async () => {
    const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    const res = await request(app)
      .post('/api/auth/mfa/disable')
      .set('Authorization', `Bearer ${sessionToken}`)
      .send({ password: 'Password123', token: totp });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('login no longer requires MFA after disable', async () => {
    const res = await login(email);
    expect(res.status).toBe(200);
    expect(res.body.mfaRequired).toBeUndefined();
    expect(res.body.token).toBeTruthy();
  });

  it('rejects disable with wrong password', async () => {
    // Re-enable first
    const { body: { token } } = await login(email);
    const setup = await setupMfa(token);
    const totpToken = speakeasy.totp({ secret: setup.manualKey, encoding: 'base32' });
    await verifySetup(token, totpToken);

    const totp = speakeasy.totp({ secret: setup.manualKey, encoding: 'base32' });
    const res = await request(app)
      .post('/api/auth/mfa/disable')
      .set('Authorization', `Bearer ${token}`)
      .send({ password: 'WrongPass1', token: totp });
    expect(res.status).toBe(401);
  });
});

// ─── Protected routes ────────────────────────────────────────────────────────

describe('Protected routes', () => {
  it('/me requires auth', async () => {
    const res = await request(app).get('/api/me');
    expect(res.status).toBe(401);
  });

  it('/me returns user info with MFA status', async () => {
    await register('me@test.com');
    const { body: { token } } = await login('me@test.com');
    const res = await request(app)
      .get('/api/me')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.email).toBe('me@test.com');
    expect(res.body.mfa.enabled).toBe(false);
  });

  it('challenge token cannot access protected routes', async () => {
    await register('challenge-guard@test.com');
    const { body: { token } } = await login('challenge-guard@test.com');
    const { manualKey } = await setupMfa(token);
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    await verifySetup(token, totpToken);

    const loginRes = await login('challenge-guard@test.com');
    const { challengeToken } = loginRes.body;

    const res = await request(app)
      .get('/api/me')
      .set('Authorization', `Bearer ${challengeToken}`);
    expect(res.status).toBe(401);
  });
});

// ─── Audit log ────────────────────────────────────────────────────────────────

describe('Audit log', () => {
  it('records events for a full MFA cycle', async () => {
    await register('audit@test.com');
    const { body: { token } } = await login('audit@test.com');
    const { manualKey } = await setupMfa(token);
    const totpToken = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    await verifySetup(token, totpToken);

    const loginRes = await login('audit@test.com');
    const { challengeToken } = loginRes.body;
    const totp = speakeasy.totp({ secret: manualKey, encoding: 'base32' });
    await request(app).post('/api/auth/mfa/challenge').send({ challengeToken, token: totp });

    const auditRes = await request(app)
      .get('/api/audit')
      .set('Authorization', `Bearer ${token}`);
    expect(auditRes.status).toBe(200);

    const events = auditRes.body.map((r: any) => r.event);
    expect(events).toContain('register');
    expect(events).toContain('mfa_setup_started');
    expect(events).toContain('mfa_enabled');
    expect(events).toContain('mfa_challenge_issued');
    expect(events).toContain('mfa_challenge_success');
  });
});
