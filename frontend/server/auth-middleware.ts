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
  // If a prior middleware (e.g. authenticateStaticApiKey) already set req.user, skip JWT check.
  if (req.user) { next(); return; }

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
 * Static API key authentication for headless connector clients.
 *
 * Accepts `X-API-Key: <key>` header or `Authorization: Bearer <key>` where
 * the key is NOT a JWT (doesn't start with "eyJ").
 *
 * Configuration (environment variables on the BioMate server):
 *   BIOMATE_CONNECTOR_API_KEY  — the secret key the connector sends
 *   BIOMATE_CONNECTOR_USER_ID  — the numeric user ID to attach to the request
 *
 * If neither env var is set this middleware is a no-op and passes through.
 * Allows MCP clients (Claude Code, Cursor, CI pipelines) to authenticate
 * without a browser OAuth flow.
 */
export async function authenticateStaticApiKey(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const serviceKey = process.env.BIOMATE_CONNECTOR_API_KEY;
  const serviceUserId = process.env.BIOMATE_CONNECTOR_USER_ID;

  if (!serviceKey || !serviceUserId) {
    // Not configured — skip silently (fall through to JWT auth).
    return next();
  }

  // Extract provided key: prefer X-API-Key, then Bearer token that isn't a JWT.
  let providedKey: string | undefined;
  const xApiKey = req.headers['x-api-key'];
  if (typeof xApiKey === 'string' && xApiKey.length > 0) {
    providedKey = xApiKey;
  } else {
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      const candidate = authHeader.substring(7);
      if (!candidate.startsWith('eyJ')) {
        // Not a JWT — treat as opaque API key.
        providedKey = candidate;
      }
    }
  }

  if (!providedKey) {
    return next(); // No API key provided; fall through to JWT auth.
  }

  if (providedKey !== serviceKey) {
    res.status(401).json({ error: 'Invalid API key' });
    return;
  }

  // Key matches — attach the configured service account user.
  try {
    const user = await authService.getUserById(serviceUserId);
    if (!user) {
      res.status(401).json({ error: 'Connector service account not found (check BIOMATE_CONNECTOR_USER_ID)' });
      return;
    }
    const { password, ...safeUser } = user;
    req.user = safeUser;
    next();
  } catch (error: any) {
    console.error('[Auth] API key user lookup failed:', error);
    res.status(500).json({ error: 'Authentication failed' });
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
