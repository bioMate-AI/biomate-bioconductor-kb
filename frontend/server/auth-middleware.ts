import type { Request, Response, NextFunction } from 'express';
import { authService } from './auth-service';
import type { SafeUser } from '../shared/schema';

// Extend Express Request type to include user
declare global {
  namespace Express {
    interface Request {
      user?: SafeUser;
    }
  }
}

/**
 * Middleware to verify JWT token and attach user to request
 */
export async function authenticateToken(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    // Get token from Authorization header or cookie
    let token: string | undefined;

    // Check Authorization header
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7);
    }

    // Check cookie
    if (!token && req.cookies && req.cookies.biomate_token) {
      token = req.cookies.biomate_token;
    }

    if (!token) {
      res.status(401).json({ error: 'Not authenticated' });
      return;
    }

    // Verify token
    const payload = authService.verifyToken(token);

    // Reject MFA challenge tokens — only valid for /api/auth/mfa/challenge
    if (payload.type === 'mfa_challenge') {
      res.status(401).json({ error: 'MFA challenge token cannot be used for authenticated requests' });
      return;
    }

    // Get user from database
    const user = await authService.getUserById(payload.userId);
    if (!user) {
      res.status(401).json({ error: 'User not found' });
      return;
    }

    // Check subscription status
    const subscriptionStatus = authService.checkSubscriptionStatus(user);
    if (!subscriptionStatus.active) {
      // E2E bypass: X-E2E-Test-Token allows tests to run against fixture
      // users whose trial has expired. Auth still must succeed first
      // (above) — this only waives the subscription gate, never the
      // identity check. Production NEVER bypasses; only non-prod node
      // env. Matches the canonical dev token used by frontend/e2e/
      // api-smoke.e2e.ts which falls back to the same default if
      // E2E_TEST_TOKEN isn't set in the runtime env.
      const e2eToken = req.headers['x-e2e-test-token'];
      const expectedToken =
        process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
      const isNonProd = process.env.NODE_ENV !== 'production';
      const isE2eBypass = isNonProd && e2eToken === expectedToken;
      if (!isE2eBypass) {
        res.status(403).json({ error: 'Subscription required', details: subscriptionStatus });
        return;
      }
      console.log(`[Auth] E2E-token subscription bypass for user ${user.id}`);
    }

    // Attach user to request (without password)
    const { password, ...safeUser } = user;
    req.user = safeUser;

    next();
  } catch (error: any) {
    if (error.message === 'TOKEN_EXPIRED') {
      res.status(401).json({ error: 'Token expired' });
    } else if (error.message === 'INVALID_TOKEN') {
      res.status(401).json({ error: 'Invalid token' });
    } else {
      console.error('Authentication error:', error);
      res.status(500).json({ error: 'Authentication failed' });
    }
  }
}

/**
 * Optional authentication middleware - doesn't fail if no token
 */
export async function optionalAuth(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    // Get token from Authorization header or cookie
    let token: string | undefined;

    // Check Authorization header
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7);
    }

    // Check cookie
    if (!token && req.cookies && req.cookies.biomate_token) {
      token = req.cookies.biomate_token;
    }

    if (!token) {
      // No token, continue without user
      next();
      return;
    }

    // Verify token
    const payload = authService.verifyToken(token);

    // Get user from database
    const user = await authService.getUserById(payload.userId);
    if (user) {
      // Attach user to request (without password)
      const { password, ...safeUser } = user;
      req.user = safeUser;
    }

    next();
  } catch (error) {
    // Token invalid or expired, continue without user
    next();
  }
}
