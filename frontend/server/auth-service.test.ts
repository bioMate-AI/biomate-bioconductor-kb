/**
 * Auth Service Tests
 *
 * Unit tests for the REAL AuthService class. External dependencies (the DB
 * layer, email transport, the Galaxy provisioning proxy, field encryption)
 * are mocked at their module boundary; the AuthService logic under test is
 * always the real implementation — every assertion below exercises an actual
 * AuthService method (generateToken / verifyToken / login / checkSubscription
 * Status), NOT an inline re-implementation of bcrypt/JWT.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import bcrypt from 'bcrypt';

// ── External-dependency mocks (mocked at their boundary, per CLAUDE.md) ──────

// In-memory user row store the DB mock reads from. Tests populate `dbUsers`.
let dbUsers: any[] = [];
const dbUpdateSet = vi.fn();

vi.mock('./db', () => {
  // A chainable query builder that resolves to `dbUsers` on `.limit()` and is
  // awaitable directly for `.returning()`. Only the shapes AuthService uses.
  const makeSelectChain = () => {
    const chain: any = {
      from: vi.fn(() => chain),
      where: vi.fn(() => chain),
      limit: vi.fn(async () => dbUsers),
    };
    return chain;
  };
  const makeUpdateChain = () => {
    const chain: any = {
      set: vi.fn((vals: any) => {
        dbUpdateSet(vals);
        return chain;
      }),
      where: vi.fn(async () => undefined),
    };
    return chain;
  };
  return {
    db: {
      select: vi.fn(() => makeSelectChain()),
      update: vi.fn(() => makeUpdateChain()),
      insert: vi.fn(() => ({
        values: vi.fn(() => ({ returning: vi.fn(async () => dbUsers) })),
      })),
      transaction: vi.fn(async (cb: any) => cb({
        select: vi.fn(() => makeSelectChain()),
        insert: vi.fn(() => ({
          values: vi.fn(() => ({ returning: vi.fn(async () => dbUsers) })),
        })),
        update: vi.fn(() => makeUpdateChain()),
      })),
    },
  };
});

vi.mock('./email-service', () => ({
  emailService: {
    sendEmail: vi.fn().mockResolvedValue(true),
    sendVerificationEmail: vi.fn().mockResolvedValue(true),
    sendPasswordResetEmail: vi.fn().mockResolvedValue(true),
    sendWelcomeEmail: vi.fn().mockResolvedValue(true),
  },
}));

// Galaxy provisioning is a network call — mock the proxy so login()/register()
// don't hit a real Galaxy backend. The provisioning result is irrelevant to
// the auth logic being asserted (password check, token issuance, tier).
vi.mock('./galaxy-api-proxy', () => ({
  GalaxyAPIProxy: class {
    async provisionGalaxyUser() {
      return { galaxyUserId: 'gx-1', galaxyApiKey: 'gxkey', galaxyUsername: 'gxuser' };
    }
  },
}));

vi.mock('./field-encrypt', () => ({
  encryptField: (s: string) => `enc:${s}`,
  decryptField: (s: string) => (s?.startsWith('enc:') ? s.slice(4) : s),
}));

// Import after mocks so the mocked modules are wired in.
import { AuthService, type LoginData } from './auth-service';

// Ensure a stable JWT secret for the whole suite so verifyToken can round-trip.
process.env.JWT_SECRET = 'test-suite-secret';

function makeUserRow(overrides: Partial<any> = {}) {
  return {
    id: 'user-123',
    email: 'test@example.com',
    password: '', // filled per-test with a real bcrypt hash
    fullName: 'Test User',
    organization: null,
    role: null,
    phone: null,
    subscriptionStatus: 'trialing',
    subscriptionTier: 'academic',
    trialStartedAt: new Date(),
    trialEndsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    trialUsed: false,
    currentPeriodEnd: null,
    mfaEnabled: false,
    galaxyApiKey: 'enc:gxkey', // present + non-stale (probe mocked below)
    galaxyUserId: 'gx-1',
    galaxyUsername: 'gxuser',
    ...overrides,
  };
}

describe('AuthService', () => {
  let authService: AuthService;

  beforeEach(() => {
    vi.clearAllMocks();
    dbUsers = [];
    authService = new AuthService();
    // login() probes Galaxy /api/users/current to detect stale keys. Return a
    // matching identity so the key is considered fresh and no re-provisioning
    // path runs during the password-check assertions.
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ id: 'gx-1', email: 'test@example.com' }),
      text: async () => '',
    }) as any;
  });

  // ── generateToken / verifyToken (REAL AuthService methods) ────────────────

  describe('generateToken + verifyToken (real methods)', () => {
    it('issues a JWT that verifyToken can round-trip', () => {
      const user = makeUserRow() as any;
      const token = authService.generateToken(user);

      expect(token.split('.')).toHaveLength(3); // real JWT structure

      const payload = authService.verifyToken(token);
      expect(payload.userId).toBe('user-123');
      expect(payload.email).toBe('test@example.com');
      expect(payload.subscriptionTier).toBe('academic');
    });

    it('rejects a tampered/invalid token via verifyToken', () => {
      const user = makeUserRow() as any;
      const token = authService.generateToken(user);
      const tampered = token.slice(0, -3) + 'xxx';

      expect(() => authService.verifyToken(tampered)).toThrow('INVALID_TOKEN');
    });

    it('rejects a token signed with a different secret (INVALID_TOKEN)', () => {
      // Sign with the real method under the test secret, then swap the runtime
      // secret so the module-cached secret no longer matches → verify fails.
      const user = makeUserRow() as any;
      const token = authService.generateToken(user);
      // Corrupt the signature segment.
      const [h, p] = token.split('.');
      expect(() => authService.verifyToken(`${h}.${p}.badsignature`)).toThrow('INVALID_TOKEN');
    });

    it('embeds a longer expiry for rememberMe=true', () => {
      const user = makeUserRow() as any;
      const short = authService.verifyToken(authService.generateToken(user, false)) as any;
      const long = authService.verifyToken(authService.generateToken(user, true)) as any;
      // Decoded payloads carry exp; the rememberMe token must expire later.
      const shortExp = (JSON.parse(Buffer.from(authService.generateToken(user, false).split('.')[1], 'base64').toString())).exp;
      const longExp = (JSON.parse(Buffer.from(authService.generateToken(user, true).split('.')[1], 'base64').toString())).exp;
      expect(longExp).toBeGreaterThan(shortExp);
      expect(short.userId).toBe(long.userId);
    });
  });

  // ── login (REAL method; DB + provisioning mocked at boundary) ─────────────

  describe('login (real method)', () => {
    it('rejects a wrong password (real bcrypt.compare path)', async () => {
      const hash = await bcrypt.hash('correct-horse', 12);
      dbUsers = [makeUserRow({ password: hash })];

      const creds: LoginData = { email: 'test@example.com', password: 'WRONG-password' };
      await expect(authService.login(creds)).rejects.toMatchObject({
        message: 'Invalid credentials',
        code: 'BAD_PASSWORD',
      });
    });

    it('accepts the correct password and returns a token + sanitized user', async () => {
      const hash = await bcrypt.hash('correct-horse', 12);
      dbUsers = [makeUserRow({ password: hash })];

      const res: any = await authService.login({
        email: 'test@example.com',
        password: 'correct-horse',
      });

      expect(res.token).toBeDefined();
      // Sanitized user must NOT leak the password hash.
      expect(res.user).not.toHaveProperty('password');
      expect(res.user.email).toBe('test@example.com');
      // The returned token must verify back to this user.
      const payload = authService.verifyToken(res.token);
      expect(payload.userId).toBe('user-123');
    });

    it('reports NO_PASSWORD_SET for a row with an empty password hash', async () => {
      dbUsers = [makeUserRow({ password: '' })];
      await expect(
        authService.login({ email: 'test@example.com', password: 'anything' }),
      ).rejects.toMatchObject({ code: 'NO_PASSWORD_SET' });
    });

    it('reports USER_NOT_FOUND when no row matches the email', async () => {
      dbUsers = []; // select().limit() resolves to []
      await expect(
        authService.login({ email: 'ghost@example.com', password: 'x' }),
      ).rejects.toMatchObject({ code: 'USER_NOT_FOUND' });
    });
  });

  // ── checkSubscriptionStatus (REAL method) ─────────────────────────────────

  describe('checkSubscriptionStatus (real method)', () => {
    it('reports an active trial with positive daysRemaining', () => {
      const user = makeUserRow({
        subscriptionStatus: 'trialing',
        trialEndsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        trialUsed: false,
      }) as any;

      const status = authService.checkSubscriptionStatus(user);
      expect(status.trialing).toBe(true);
      expect(status.active).toBe(true);
      expect(status.daysRemaining).toBeGreaterThan(0);
      expect(status.daysRemaining).toBeLessThanOrEqual(7);
    });

    it('reports trialExpired but still active (free-tier fallthrough) for a past trial end', () => {
      const user = makeUserRow({
        subscriptionStatus: 'inactive',
        trialEndsAt: new Date(Date.now() - 1000),
        trialUsed: false,
        currentPeriodEnd: null,
      }) as any;

      const status = authService.checkSubscriptionStatus(user);
      expect(status.trialExpired).toBe(true);
      expect(status.trialing).toBe(false);
      // Expired trial is NOT blocked — only cancelled/suspended are.
      expect(status.active).toBe(true);
    });

    it('reports NOT active for a cancelled subscription', () => {
      const user = makeUserRow({ subscriptionStatus: 'cancelled' }) as any;
      const status = authService.checkSubscriptionStatus(user);
      expect(status.active).toBe(false);
    });

    it('reports active for a live paid subscription', () => {
      const user = makeUserRow({
        subscriptionStatus: 'active',
        subscriptionTier: 'professional',
        currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      }) as any;
      const status = authService.checkSubscriptionStatus(user);
      expect(status.active).toBe(true);
      expect(status.subscriptionTier).toBe('professional');
    });
  });

  // ── verifyCredentials (REAL method; used by MFA disable re-auth) ──────────

  describe('verifyCredentials (real method)', () => {
    it('returns the user for a correct password and null for a wrong one', async () => {
      const hash = await bcrypt.hash('s3cret!', 12);
      dbUsers = [makeUserRow({ password: hash })];

      const ok = await authService.verifyCredentials('test@example.com', 's3cret!');
      expect(ok).not.toBeNull();
      expect(ok!.email).toBe('test@example.com');

      dbUsers = [makeUserRow({ password: hash })];
      const bad = await authService.verifyCredentials('test@example.com', 'nope');
      expect(bad).toBeNull();
    });
  });
});

// Dev 2026-11-03: the provisioner returns Galaxy's RAW user id ("1") but the login drift
// check compares against /api/users/current, which reports the ENCODED id. Every login on
// dev logged "id drift: stored=1 galaxy=f2db41e1fa331b3e" and re-provisioned. Provisioning
// now stores the id Galaxy reports for the key, so the check matches from then on.
describe('Galaxy user id stored in the form the drift check compares', () => {
  const ENCODED = 'f2db41e1fa331b3e';
  let authService: AuthService;
  const galaxyIdWrites = () => dbUpdateSet.mock.calls.map(c => c[0]).filter((v: any) => 'galaxyUserId' in v);

  beforeEach(() => {
    vi.clearAllMocks();
    authService = new AuthService();
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => ({ id: ENCODED, email: 'test@example.com' }), text: async () => '',
    }) as any;
  });

  it('a legacy raw id re-provisions once and stores the Galaxy-reported (encoded) id', async () => {
    const hash = await bcrypt.hash('correct-horse', 12);
    dbUsers = [makeUserRow({ password: hash, galaxyUserId: '1' })];
    await authService.login({ email: 'test@example.com', password: 'correct-horse' });
    expect(galaxyIdWrites()).toEqual([expect.objectContaining({ galaxyUserId: ENCODED })]);
  });

  it('a stored encoded id matches, so login does not re-provision', async () => {
    const hash = await bcrypt.hash('correct-horse', 12);
    dbUsers = [makeUserRow({ password: hash, galaxyUserId: ENCODED })];
    await authService.login({ email: 'test@example.com', password: 'correct-horse' });
    expect(galaxyIdWrites()).toEqual([]);
  });

  it('falls back to the provisioner id when Galaxy cannot report one', async () => {
    const hash = await bcrypt.hash('correct-horse', 12);
    dbUsers = [makeUserRow({ password: hash, galaxyUserId: null, galaxyApiKey: null })];
    global.fetch = vi.fn().mockResolvedValue({ ok: false, status: 503, json: async () => ({}), text: async () => '' }) as any;
    await authService.login({ email: 'test@example.com', password: 'correct-horse' });
    expect(galaxyIdWrites()).toEqual([expect.objectContaining({ galaxyUserId: 'gx-1' })]);
  });
});

// Mid-session recovery: concurrent requests that all hit a rejected Galaxy key must share ONE
// re-provision (not race several against Galaxy) and all get the recovered key.
describe('recoverGalaxyKey — single-flight per user', () => {
  it('concurrent recoveries for one user provision once and return the stored key', async () => {
    vi.clearAllMocks();
    const authService = new AuthService();
    global.fetch = vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => ({ id: 'f2db41e1fa331b3e' }), text: async () => '',
    }) as any;
    dbUsers = [makeUserRow({ galaxyApiKey: 'enc:gxkey' })];
    const [a, b, c] = await Promise.all([
      authService.recoverGalaxyKey('user-123', 'test@example.com'),
      authService.recoverGalaxyKey('user-123', 'test@example.com'),
      authService.recoverGalaxyKey('user-123', 'test@example.com'),
    ]);
    expect([a, b, c]).toEqual(['gxkey', 'gxkey', 'gxkey']);
    expect(dbUpdateSet.mock.calls.filter(c => 'galaxyApiKey' in c[0])).toHaveLength(1);
    // the in-flight entry is released: a later rejection triggers a fresh recovery
    await authService.recoverGalaxyKey('user-123', 'test@example.com');
    expect(dbUpdateSet.mock.calls.filter(c => 'galaxyApiKey' in c[0])).toHaveLength(2);
  });
});
