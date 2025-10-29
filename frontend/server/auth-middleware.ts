import type { Request, Response, NextFunction } from 'express';
import { authService } from './auth-service';
import type { User } from '../shared/schema';

// Extend Express Request type to include user
declare global {
  namespace Express {
    interface Request {
      user?: Omit<User, 'password'>;
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

    // Get user from database
    const user = await authService.getUserById(payload.userId);
    if (!user) {
      res.status(401).json({ error: 'User not found' });
      return;
    }

    // Check subscription status
    const subscriptionStatus = authService.checkSubscriptionStatus(user);
    if (!subscriptionStatus.active) {
      res.status(403).json({ error: 'Subscription required', details: subscriptionStatus });
      return;
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
