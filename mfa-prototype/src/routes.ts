import { Router } from 'express';
import type { Response } from 'express';
import {
  registerUser, verifyPassword, signToken, verifyToken, auditLog, getUser,
  isLockedOut, recordFailedChallenge, clearFailedChallenges, consumeJti,
} from './auth.js';
import {
  generateSecret, generateQRCode, verifyToken as verifyTOTP,
  generateRecoveryCodes, hashRecoveryCodes,
  storePendingSecret, activateMfa, getMfaConfig, getDecryptedSecret,
  verifyRecoveryCode, disableMfa,
} from './mfa.js';
import { requireAuth, type AuthRequest } from './middleware.js';
import type { Db } from './db.js';

export function buildRouter(db: Db): Router {
  const router = Router();

  // ─── Auth ────────────────────────────────────────────────────────────────

  router.post('/auth/register', async (req, res) => {
    const { email, password } = req.body ?? {};
    const emailValid = typeof email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
    if (!emailValid || !password || password.length < 8) {
      res.status(400).json({ error: 'valid email and password (min 8 chars) required' });
      return;
    }
    try {
      const userId = await registerUser(db, email, password);
      auditLog(db, 'register', userId, req.ip ?? '');
      res.status(201).json({ userId });
    } catch (e: any) {
      if (e.message?.includes('UNIQUE')) {
        res.status(409).json({ error: 'Email already registered' });
      } else {
        res.status(500).json({ error: 'Registration failed' });
      }
    }
  });

  router.post('/auth/login', async (req, res) => {
    const { email, password } = req.body ?? {};
    const user = await verifyPassword(db, email, password);
    if (!user) {
      auditLog(db, 'auth_failure', null, req.ip ?? '', email);
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }

    const cfg = getMfaConfig(db, user.id);
    if (cfg?.enabled) {
      // Issue a short-lived challenge token instead of a full session
      const challengeToken = signToken(
        { userId: user.id, email: user.email, type: 'mfa_challenge' },
        '5m',
      );
      auditLog(db, 'mfa_challenge_issued', user.id, req.ip ?? '');
      res.json({ mfaRequired: true, challengeToken });
    } else {
      const token = signToken(
        { userId: user.id, email: user.email, type: 'session' },
        '15m',
      );
      auditLog(db, 'login', user.id, req.ip ?? '');
      res.json({ token });
    }
  });

  // ─── MFA Setup ───────────────────────────────────────────────────────────

  router.post('/auth/mfa/setup', requireAuth, async (req: AuthRequest, res: Response) => {
    const { userId, email } = req.user!;
    const secret = generateSecret(email);
    storePendingSecret(db, userId, secret.base32);
    const qrCode = await generateQRCode(secret.otpauth_url!);
    auditLog(db, 'mfa_setup_started', userId, req.ip ?? '');
    res.json({ qrCode, manualKey: secret.base32 });
  });

  router.post('/auth/mfa/verify-setup', requireAuth, async (req: AuthRequest, res: Response) => {
    const { userId } = req.user!;
    const { token } = req.body ?? {};
    if (!token) { res.status(400).json({ error: 'token required' }); return; }

    const base32 = getDecryptedSecret(db, userId);
    if (!base32) { res.status(400).json({ error: 'MFA setup not initiated' }); return; }

    if (!verifyTOTP(base32, token)) {
      auditLog(db, 'mfa_setup_failure', userId, req.ip ?? '');
      res.status(400).json({ error: 'Invalid TOTP code' });
      return;
    }

    const plainCodes = generateRecoveryCodes();
    const hashedCodes = await hashRecoveryCodes(plainCodes);
    activateMfa(db, userId, hashedCodes);
    auditLog(db, 'mfa_enabled', userId, req.ip ?? '');
    res.json({ recoveryCodes: plainCodes });
  });

  router.post('/auth/mfa/disable', requireAuth, async (req: AuthRequest, res: Response) => {
    const { userId, email } = req.user!;
    const { password, token } = req.body ?? {};

    const user = await verifyPassword(db, email, password);
    if (!user) { res.status(401).json({ error: 'Invalid password' }); return; }

    const cfg = getMfaConfig(db, userId);
    if (!cfg?.enabled) { res.status(400).json({ error: 'MFA not enabled' }); return; }

    const base32 = getDecryptedSecret(db, userId);
    if (!base32 || !verifyTOTP(base32, token)) {
      res.status(400).json({ error: 'Invalid TOTP code' });
      return;
    }

    disableMfa(db, userId);
    auditLog(db, 'mfa_disabled', userId, req.ip ?? '');
    res.json({ ok: true });
  });

  router.get('/auth/mfa/status', requireAuth, (req: AuthRequest, res: Response) => {
    const cfg = getMfaConfig(db, req.user!.userId);
    res.json({
      enabled: cfg?.enabled === 1,
      verifiedAt: cfg?.verified_at ?? null,
      remainingRecoveryCodes: cfg ? (JSON.parse(cfg.recovery_codes) as string[]).length : 0,
    });
  });

  // ─── MFA Challenge ───────────────────────────────────────────────────────

  router.post('/auth/mfa/challenge', async (req, res) => {
    const { challengeToken, token } = req.body ?? {};
    if (!challengeToken || !token) {
      res.status(400).json({ error: 'challengeToken and token required' });
      return;
    }

    // Validate challenge token signature + expiry
    let payload: ReturnType<typeof verifyToken>;
    try {
      payload = verifyToken(challengeToken);
    } catch {
      res.status(401).json({ error: 'Invalid or expired challenge token' });
      return;
    }
    if (payload.type !== 'mfa_challenge' || !payload.jti) {
      res.status(401).json({ error: 'Invalid token type' });
      return;
    }

    const { userId, email, jti } = payload;

    // Replay prevention: consume JTI (one-use only)
    const tokenExp = new Date(Date.now() + 5 * 60 * 1000); // conservative upper bound
    if (!consumeJti(db, jti, tokenExp)) {
      auditLog(db, 'mfa_replay_attempt', userId, req.ip ?? '');
      res.status(401).json({ error: 'Challenge token already used' });
      return;
    }

    // Brute-force lockout check
    if (isLockedOut(db, userId)) {
      auditLog(db, 'mfa_lockout_blocked', userId, req.ip ?? '');
      res.status(429).json({ error: 'Account temporarily locked. Try again later.' });
      return;
    }

    const base32 = getDecryptedSecret(db, userId);
    if (!base32) { res.status(400).json({ error: 'MFA not configured' }); return; }

    let valid = verifyTOTP(base32, token);
    let usedRecovery = false;

    // Try recovery code if TOTP fails (synchronous + atomic)
    if (!valid) {
      valid = verifyRecoveryCode(db, userId, token);
      usedRecovery = valid;
    }

    if (!valid) {
      const { locked, remaining } = recordFailedChallenge(db, userId);
      auditLog(db, 'mfa_challenge_failure', userId, req.ip ?? '');
      if (locked) {
        auditLog(db, 'mfa_lockout', userId, req.ip ?? '');
        res.status(429).json({ error: 'Too many failed attempts. Account locked for 15 minutes.' });
      } else {
        res.status(401).json({ error: 'Invalid MFA code', remainingAttempts: remaining });
      }
      return;
    }

    clearFailedChallenges(db, userId);
    if (usedRecovery) auditLog(db, 'mfa_recovery_code_used', userId, req.ip ?? '');

    const sessionToken = signToken({ userId, email, type: 'session' }, '15m');
    auditLog(db, 'mfa_challenge_success', userId, req.ip ?? '');
    res.json({ token: sessionToken });
  });

  // ─── Protected example endpoint ──────────────────────────────────────────

  router.get('/me', requireAuth, (req: AuthRequest, res: Response) => {
    const user = getUser(db, req.user!.userId);
    const cfg = getMfaConfig(db, req.user!.userId);
    res.json({
      ...user,
      mfa: {
        enabled: cfg?.enabled === 1,
        verifiedAt: cfg?.verified_at ?? null,
      },
    });
  });

  // ─── Audit log (admin view for testing) ─────────────────────────────────

  router.get('/audit', requireAuth, (req: AuthRequest, res: Response) => {
    const rows = db.prepare('SELECT * FROM audit_log ORDER BY id DESC LIMIT 50').all();
    res.json(rows);
  });

  return router;
}
