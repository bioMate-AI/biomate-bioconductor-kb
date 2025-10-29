import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { randomBytes } from 'crypto';
import { db } from './db';
import { users } from '../shared/schema';
import { eq, and } from 'drizzle-orm';
import type { User } from '../shared/schema';
import { emailService } from './email-service';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';
const BCRYPT_ROUNDS = 12;

export interface RegisterData {
  email: string;
  password: string;
  fullName: string;
  organization?: string;
  phone?: string;
  termsAccepted: boolean;
  marketingEmailsOptIn?: boolean;
}

export interface LoginData {
  email: string;
  password: string;
}

export interface JWTPayload {
  userId: string;
  email: string;
  subscriptionStatus: string;
  subscriptionTier: string;
  trialEndsAt: string | null;
}

export interface AuthResponse {
  user: Omit<User, 'password'>;
  token: string;
  expiresIn: number;
}

export class AuthService {
  /**
   * Register a new user
   */
  async register(data: RegisterData): Promise<AuthResponse> {
    // Check if terms were accepted
    if (!data.termsAccepted) {
      throw new Error('Terms of service must be accepted');
    }

    // Check if email already exists
    const existing = await db.select().from(users).where(eq(users.email, data.email)).limit(1);
    if (existing.length > 0) {
      throw new Error('Email already registered');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(data.password, BCRYPT_ROUNDS);

    // Calculate trial end date
    const now = new Date();
    const trialEndsAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000); // 7 days

    // Create user
    const [newUser] = await db
      .insert(users)
      .values({
        email: data.email,
        password: passwordHash,
        fullName: data.fullName,
        organization: data.organization,
        phone: data.phone,
        trialStartedAt: now,
        trialEndsAt: trialEndsAt,
        trialUsed: false,
        subscriptionStatus: 'trialing',
        subscriptionTier: 'academic',
        termsAcceptedAt: now,
        marketingEmailsOptIn: data.marketingEmailsOptIn || false,
      })
      .returning();

    // Generate JWT
    const token = this.generateToken(newUser);

    return {
      user: this.sanitizeUser(newUser),
      token,
      expiresIn: this.getTokenExpiresInSeconds(),
    };
  }

  /**
   * Login existing user
   */
  async login(data: LoginData): Promise<AuthResponse> {
    // Find user by email
    const [user] = await db.select().from(users).where(eq(users.email, data.email)).limit(1);

    if (!user) {
      throw new Error('Invalid credentials');
    }

    // Verify password
    const isValidPassword = await bcrypt.compare(data.password, user.password);
    if (!isValidPassword) {
      throw new Error('Invalid credentials');
    }

    // Check if trial has expired
    const now = new Date();
    const trialExpired = user.trialEndsAt && user.trialEndsAt < now && !user.trialUsed;
    const subscriptionActive =
      user.subscriptionStatus === 'active' &&
      (!user.currentPeriodEnd || user.currentPeriodEnd > now);

    if (trialExpired && !subscriptionActive) {
      throw new Error('TRIAL_EXPIRED');
    }

    // Update last login
    await db
      .update(users)
      .set({ lastLoginAt: now, updatedAt: now })
      .where(eq(users.id, user.id));

    // Generate JWT
    const token = this.generateToken(user);

    return {
      user: this.sanitizeUser(user),
      token,
      expiresIn: this.getTokenExpiresInSeconds(),
    };
  }

  /**
   * Verify JWT token
   */
  verifyToken(token: string): JWTPayload {
    try {
      const payload = jwt.verify(token, JWT_SECRET) as JWTPayload;
      return payload;
    } catch (error) {
      if (error instanceof jwt.TokenExpiredError) {
        throw new Error('TOKEN_EXPIRED');
      }
      throw new Error('INVALID_TOKEN');
    }
  }

  /**
   * Get user by ID (for middleware)
   */
  async getUserById(userId: string): Promise<User | null> {
    const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    return user || null;
  }

  /**
   * Check subscription status
   */
  checkSubscriptionStatus(user: User): {
    active: boolean;
    trialing: boolean;
    trialExpired: boolean;
    daysRemaining: number;
    subscriptionStatus: string;
    subscriptionTier: string;
  } {
    const now = new Date();

    const trialActive = user.trialEndsAt ? user.trialEndsAt > now && !user.trialUsed : false;
    const subscriptionActive =
      user.subscriptionStatus === 'active' &&
      (!user.currentPeriodEnd || user.currentPeriodEnd > now);

    let daysRemaining = 0;
    if (trialActive && user.trialEndsAt) {
      daysRemaining = Math.ceil((user.trialEndsAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
    }

    return {
      active: trialActive || subscriptionActive,
      trialing: trialActive,
      trialExpired: user.trialEndsAt ? user.trialEndsAt <= now : false,
      daysRemaining,
      subscriptionStatus: user.subscriptionStatus || 'trialing',
      subscriptionTier: user.subscriptionTier || 'academic',
    };
  }

  /**
   * Send verification email
   */
  async sendVerificationEmail(userId: string): Promise<boolean> {
    const user = await this.getUserById(userId);
    if (!user) {
      throw new Error('User not found');
    }

    if (user.emailVerified) {
      throw new Error('Email already verified');
    }

    // Generate verification token
    const token = this.generateVerificationToken();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    // Save token to database
    await db
      .update(users)
      .set({
        verificationToken: token,
        resetPasswordExpires: expiresAt, // Reuse this field for verification expiry
        updatedAt: new Date(),
      })
      .where(eq(users.id, userId));

    // Send email
    return await emailService.sendVerificationEmail(user.email, token, user.fullName);
  }

  /**
   * Verify email with token
   */
  async verifyEmail(token: string): Promise<Omit<User, 'password'>> {
    // Find user by verification token
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.verificationToken, token))
      .limit(1);

    if (!user) {
      throw new Error('Invalid verification token');
    }

    if (user.emailVerified) {
      throw new Error('Email already verified');
    }

    // Check if token expired (using resetPasswordExpires field)
    if (user.resetPasswordExpires && user.resetPasswordExpires < new Date()) {
      throw new Error('Verification token expired');
    }

    // Mark email as verified
    await db
      .update(users)
      .set({
        emailVerified: true,
        verificationToken: null,
        resetPasswordExpires: null,
        updatedAt: new Date(),
      })
      .where(eq(users.id, user.id));

    // Send welcome email
    await emailService.sendWelcomeEmail(user.email, user.fullName);

    return this.sanitizeUser(user);
  }

  /**
   * Request password reset
   */
  async requestPasswordReset(email: string): Promise<boolean> {
    const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);

    // Don't reveal if email exists - security best practice
    if (!user) {
      return true; // Pretend it worked
    }

    // Generate reset token
    const token = this.generateVerificationToken();
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

    // Save token to database
    await db
      .update(users)
      .set({
        resetPasswordToken: token,
        resetPasswordExpires: expiresAt,
        updatedAt: new Date(),
      })
      .where(eq(users.id, user.id));

    // Send email
    await emailService.sendPasswordResetEmail(user.email, token, user.fullName);

    return true;
  }

  /**
   * Reset password with token
   */
  async resetPassword(token: string, newPassword: string): Promise<boolean> {
    // Find user by reset token
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.resetPasswordToken, token))
      .limit(1);

    if (!user) {
      throw new Error('Invalid reset token');
    }

    // Check if token expired
    if (!user.resetPasswordExpires || user.resetPasswordExpires < new Date()) {
      throw new Error('Reset token expired');
    }

    // Hash new password
    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);

    // Update password and clear reset token
    await db
      .update(users)
      .set({
        password: passwordHash,
        resetPasswordToken: null,
        resetPasswordExpires: null,
        updatedAt: new Date(),
      })
      .where(eq(users.id, user.id));

    return true;
  }

  /**
   * Generate secure random token for verification/reset
   */
  private generateVerificationToken(): string {
    return randomBytes(32).toString('hex');
  }

  /**
   * Generate JWT token
   */
  private generateToken(user: User): string {
    const payload: JWTPayload = {
      userId: user.id,
      email: user.email,
      subscriptionStatus: user.subscriptionStatus || 'trialing',
      subscriptionTier: user.subscriptionTier || 'academic',
      trialEndsAt: user.trialEndsAt ? user.trialEndsAt.toISOString() : null,
    };

    return jwt.sign(payload, JWT_SECRET, {
      expiresIn: JWT_EXPIRES_IN,
      issuer: 'biomate.com',
      subject: user.id,
    });
  }

  /**
   * Get token expiration in seconds
   */
  private getTokenExpiresInSeconds(): number {
    // Parse JWT_EXPIRES_IN (e.g., "7d", "24h", "3600s")
    const match = JWT_EXPIRES_IN.match(/^(\d+)([dhms])$/);
    if (!match) return 604800; // Default 7 days

    const value = parseInt(match[1]);
    const unit = match[2];

    switch (unit) {
      case 'd':
        return value * 24 * 60 * 60;
      case 'h':
        return value * 60 * 60;
      case 'm':
        return value * 60;
      case 's':
        return value;
      default:
        return 604800;
    }
  }

  /**
   * Remove sensitive fields from user object
   */
  private sanitizeUser(user: User): Omit<User, 'password'> {
    const { password, ...safeUser } = user;
    return safeUser;
  }
}

// Export singleton instance
export const authService = new AuthService();
