import type { Request, Response, NextFunction } from 'express';
import { verifyToken } from './auth.js';

export interface AuthRequest extends Request {
  user?: { userId: number; email: string };
}

export function requireAuth(req: AuthRequest, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'No token provided' });
    return;
  }
  try {
    const payload = verifyToken(header.slice(7));
    if (payload.type !== 'session') {
      res.status(401).json({ error: 'Invalid token type' });
      return;
    }
    req.user = { userId: payload.userId, email: payload.email };
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}
