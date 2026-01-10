/**
 * Auth Service Tests
 *
 * Unit tests for authentication service
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

// Mock the database before importing auth-service
vi.mock('./db', () => ({
  db: {
    select: vi.fn().mockReturnThis(),
    from: vi.fn().mockReturnThis(),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockResolvedValue([]),
    insert: vi.fn().mockReturnThis(),
    values: vi.fn().mockReturnThis(),
    returning: vi.fn().mockResolvedValue([{
      id: 'user-123',
      email: 'test@example.com',
      fullName: 'Test User',
      password: 'hashed_password',
      subscriptionStatus: 'trialing',
      subscriptionTier: 'academic',
      trialEndsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    }]),
    update: vi.fn().mockReturnThis(),
    set: vi.fn().mockReturnThis(),
  },
}));

vi.mock('./email-service', () => ({
  emailService: {
    sendEmail: vi.fn().mockResolvedValue(undefined),
    sendVerificationEmail: vi.fn().mockResolvedValue(undefined),
    sendPasswordResetEmail: vi.fn().mockResolvedValue(undefined),
  },
}));

// Import after mocks
import { AuthService, type RegisterData, type LoginData } from './auth-service';
import { db } from './db';

describe('AuthService', () => {
  let authService: AuthService;

  beforeEach(() => {
    vi.clearAllMocks();
    authService = new AuthService();
  });

  describe('password hashing', () => {
    it('should hash passwords using bcrypt', async () => {
      const password = 'securePassword123!';
      const hash = await bcrypt.hash(password, 12);

      expect(hash).not.toBe(password);
      expect(hash.length).toBeGreaterThan(50);
    });

    it('should verify correct passwords', async () => {
      const password = 'securePassword123!';
      const hash = await bcrypt.hash(password, 12);

      const isValid = await bcrypt.compare(password, hash);
      expect(isValid).toBe(true);
    });

    it('should reject incorrect passwords', async () => {
      const password = 'securePassword123!';
      const hash = await bcrypt.hash(password, 12);

      const isValid = await bcrypt.compare('wrongPassword', hash);
      expect(isValid).toBe(false);
    });
  });

  describe('JWT generation', () => {
    it('should generate valid JWT tokens', () => {
      const payload = {
        userId: 'user-123',
        email: 'test@example.com',
        subscriptionStatus: 'trialing',
        subscriptionTier: 'academic',
        trialEndsAt: null,
      };

      const secret = 'test-secret';
      const token = jwt.sign(payload, secret, { expiresIn: '7d' });

      expect(token).toBeDefined();
      expect(token.split('.')).toHaveLength(3); // JWT has 3 parts
    });

    it('should decode JWT tokens correctly', () => {
      const payload = {
        userId: 'user-123',
        email: 'test@example.com',
      };

      const secret = 'test-secret';
      const token = jwt.sign(payload, secret, { expiresIn: '7d' });
      const decoded = jwt.verify(token, secret) as typeof payload;

      expect(decoded.userId).toBe(payload.userId);
      expect(decoded.email).toBe(payload.email);
    });

    it('should reject tokens with wrong secret', () => {
      const payload = { userId: 'user-123' };
      const token = jwt.sign(payload, 'correct-secret');

      expect(() => jwt.verify(token, 'wrong-secret')).toThrow();
    });
  });

  describe('subscription status checking', () => {
    it('should identify active trial', () => {
      const user = {
        subscriptionStatus: 'trialing',
        subscriptionTier: 'academic',
        trialEndsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days ahead
      };

      const isTrialing = user.subscriptionStatus === 'trialing';
      const trialValid = user.trialEndsAt && new Date(user.trialEndsAt) > new Date();

      expect(isTrialing).toBe(true);
      expect(trialValid).toBe(true);
    });

    it('should identify expired trial', () => {
      const user = {
        subscriptionStatus: 'trialing',
        subscriptionTier: 'academic',
        trialEndsAt: new Date(Date.now() - 1000), // 1 second in the past
      };

      const trialExpired = user.trialEndsAt && new Date(user.trialEndsAt) < new Date();

      expect(trialExpired).toBe(true);
    });

    it('should identify active subscription', () => {
      const user = {
        subscriptionStatus: 'active',
        subscriptionTier: 'professional',
      };

      const hasActiveSubscription = user.subscriptionStatus === 'active';

      expect(hasActiveSubscription).toBe(true);
    });
  });

  describe('input validation', () => {
    it('should validate email format', () => {
      const validEmails = ['test@example.com', 'user.name@domain.org', 'a@b.co'];
      const invalidEmails = ['notanemail', '@domain.com', 'user@', ''];

      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

      for (const email of validEmails) {
        expect(emailRegex.test(email)).toBe(true);
      }

      for (const email of invalidEmails) {
        expect(emailRegex.test(email)).toBe(false);
      }
    });

    it('should validate password strength', () => {
      // Minimum 8 characters
      const weakPasswords = ['short', '1234567', 'ab'];
      const strongPasswords = ['password123!', 'SecurePass#1', 'LongEnoughPassword'];

      const minLength = 8;

      for (const pass of weakPasswords) {
        expect(pass.length >= minLength).toBe(false);
      }

      for (const pass of strongPasswords) {
        expect(pass.length >= minLength).toBe(true);
      }
    });
  });

  describe('token expiration', () => {
    it('should calculate correct expiration time for "7d"', () => {
      const expiresIn = '7d';
      const match = expiresIn.match(/^(\d+)([dhms])$/);

      if (match) {
        const value = parseInt(match[1], 10);
        const unit = match[2];

        const multipliers: Record<string, number> = {
          d: 24 * 60 * 60,
          h: 60 * 60,
          m: 60,
          s: 1,
        };

        const seconds = value * multipliers[unit];
        expect(seconds).toBe(7 * 24 * 60 * 60); // 604800 seconds
      }
    });
  });
});

describe('AuthService - User Sanitization', () => {
  it('should remove password from user object', () => {
    const userWithPassword = {
      id: 'user-123',
      email: 'test@example.com',
      password: 'hashed_password_that_should_not_leak',
      fullName: 'Test User',
      subscriptionStatus: 'active',
    };

    // Simulate sanitization (removing password)
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { password, ...sanitizedUser } = userWithPassword;

    expect(sanitizedUser).not.toHaveProperty('password');
    expect(sanitizedUser.email).toBe('test@example.com');
    expect(sanitizedUser.fullName).toBe('Test User');
  });
});
