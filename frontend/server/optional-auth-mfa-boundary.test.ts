import { beforeEach, describe, expect, it, vi } from 'vitest';
import jwt from 'jsonwebtoken';
import type { Request, Response } from 'express';

// Only external boundaries are mocked. Token generation/verification and both
// authentication middlewares are the production implementations.
vi.mock('./db', () => ({ db: {} }));
vi.mock('./email-service', () => ({ emailService: {} }));
vi.mock('./galaxy-api-proxy', () => ({ GalaxyAPIProxy: class {} }));
vi.mock('./api-key-service', () => ({
  API_KEY_PREFIX: 'bm_live_',
  resolveApiKey: vi.fn(),
}));

import { authService } from './auth-service';
import { authenticateToken, optionalAuth } from './auth-middleware';
import { resolveApiKey } from './api-key-service';
import { hasPersonalSkillAccess } from './skill-access';

const user = {
  id: 'mfa-skill-user', email: 'mfa-skill@example.test', password: 'never-expose',
  galaxyApiKey: 'personal-galaxy-key', subscriptionStatus: 'active',
  subscriptionTier: 'academic', trialEndsAt: null, mfaEnabled: true,
};
const secret = process.env.JWT_SECRET || 'dev-only-insecure-secret-do-not-use-in-production';

function challengeToken() {
  return jwt.sign({
    userId: user.id, email: user.email, type: 'mfa_challenge',
    subscriptionStatus: user.subscriptionStatus, subscriptionTier: user.subscriptionTier,
    trialEndsAt: null, jti: 'pending-second-factor',
  }, secret, { expiresIn: '5m' });
}

function request(token?: string, cookie = false) {
  return {
    headers: token && !cookie ? { authorization: `Bearer ${token}` } : {},
    cookies: token && cookie ? { biomate_token: token } : {},
  } as Request;
}

function response() {
  const res = { status: vi.fn(), json: vi.fn() };
  res.status.mockReturnValue(res);
  return res as unknown as Response;
}

describe('optionalAuth second-factor boundary', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.mocked(resolveApiKey).mockReset().mockResolvedValue(null);
    vi.spyOn(authService, 'getUserById').mockResolvedValue(user as any);
  });

  it.each([false, true])('keeps a real pre-MFA JWT anonymous (cookie=%s)', async (cookie) => {
    const req = request(challengeToken(), cookie);
    const next = vi.fn();
    await optionalAuth(req, response(), next);
    expect(authService.getUserById).not.toHaveBeenCalled();
    expect(req.user).toBeUndefined();
    expect(hasPersonalSkillAccess(req.user)).toBe(false);
    expect(next.mock.calls).toEqual([[]]);
  });

  it.each([false, true])('denies the same JWT on protected routes before lookup (cookie=%s)', async (cookie) => {
    const req = request(challengeToken(), cookie);
    const res = response();
    const next = vi.fn();
    await authenticateToken(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
    expect(authService.getUserById).not.toHaveBeenCalled();
    expect(req.user).toBeUndefined();
  });

  it.each([false, true])('preserves real normal session JWTs (cookie=%s)', async (cookie) => {
    const req = request(authService.generateToken(user as any), cookie);
    const next = vi.fn();
    await optionalAuth(req, response(), next);
    expect(vi.mocked(authService.getUserById).mock.calls).toEqual([[user.id]]);
    expect(req.user?.id).toBe(user.id);
    expect(req.user).not.toHaveProperty('password');
    expect(hasPersonalSkillAccess(req.user)).toBe(true);
    expect(next.mock.calls).toEqual([[]]);
  });

  it.each([undefined, 'invalid-jwt'])('preserves anonymous/invalid-token access (%s)', async (token) => {
    const req = request(token);
    const next = vi.fn();
    await optionalAuth(req, response(), next);
    expect(req.user).toBeUndefined();
    expect(authService.getUserById).not.toHaveBeenCalled();
    expect(next.mock.calls).toEqual([[]]);
  });

  it.each(['bearer', 'header'])('preserves independently verified personal API-key access (%s)', async (source) => {
    const key = 'bm_live_test-personal-key';
    vi.mocked(resolveApiKey).mockResolvedValue({ userId: user.id, keyId: 'key-id' });
    const req = source === 'bearer' ? request(key) : request(challengeToken());
    if (source === 'header') req.headers['x-api-key'] = key;
    const next = vi.fn();
    await optionalAuth(req, response(), next);
    expect(vi.mocked(resolveApiKey).mock.calls).toEqual([[key]]);
    expect(vi.mocked(authService.getUserById).mock.calls).toEqual([[user.id]]);
    expect(req.user?.id).toBe(user.id);
    expect(req.user).not.toHaveProperty('password');
    expect(next.mock.calls).toEqual([[]]);
  });
});
