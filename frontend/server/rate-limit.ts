import rateLimit from 'express-rate-limit';
import type { Request, Response } from 'express';

/**
 * Rate limiting configuration for different endpoints
 * Helps prevent brute force attacks and API abuse
 */

// General API rate limit - 100 requests per 15 minutes
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // 100 requests per window
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true, // Return rate limit info in `RateLimit-*` headers
  legacyHeaders: false, // Disable `X-RateLimit-*` headers
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'RATE_LIMIT_EXCEEDED',
      message: 'Too many requests. Please try again later.',
    });
  },
});

// Strict rate limit for authentication endpoints - 5 attempts per 15 minutes
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 attempts per window
  skipSuccessfulRequests: false, // Count all attempts
  message: 'Too many login attempts, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'TOO_MANY_ATTEMPTS',
      message: 'Too many authentication attempts. Please try again in 15 minutes.',
    });
  },
});

// More lenient for registration - 3 registrations per hour per IP
export const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3, // 3 registrations per window
  message: 'Too many registration attempts, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'REGISTRATION_LIMIT_EXCEEDED',
      message: 'Too many registration attempts. Please try again in 1 hour.',
    });
  },
});

// Password reset rate limit - 3 attempts per hour
export const passwordResetLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3, // 3 attempts per window
  message: 'Too many password reset requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'PASSWORD_RESET_LIMIT_EXCEEDED',
      message: 'Too many password reset requests. Please try again in 1 hour.',
    });
  },
});

// Email verification rate limit - 5 attempts per hour
export const emailVerificationLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5, // 5 attempts per window
  message: 'Too many verification attempts, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'VERIFICATION_LIMIT_EXCEEDED',
      message: 'Too many verification attempts. Please try again in 1 hour.',
    });
  },
});

// File upload rate limit - 20 uploads per hour
export const uploadLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 20, // 20 uploads per window
  message: 'Too many upload requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'UPLOAD_LIMIT_EXCEEDED',
      message: 'Too many upload requests. Please try again in 1 hour.',
    });
  },
});

// Workflow execution rate limit - 10 workflows per hour (adjust based on compute costs)
export const workflowLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 10, // 10 workflow executions per window
  message: 'Too many workflow execution requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'WORKFLOW_LIMIT_EXCEEDED',
      message: 'Workflow execution limit reached. Please try again in 1 hour or upgrade your plan.',
    });
  },
});
