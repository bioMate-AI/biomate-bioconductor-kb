import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { randomBytes } from 'crypto';
import { db } from './db';
import { users, inviteCodes, inviteCodeUses } from '../shared/schema';
import { eq, and, sql } from 'drizzle-orm';
import type { User, SafeUser, InviteCode } from '../shared/schema';
import { emailService } from './email-service';
import { billingPlanForTier } from './plan-config';
import { GalaxyAPIProxy } from './galaxy-api-proxy';

const GALAXY_URL = process.env.GALAXY_URL ?? 'http://localhost:8081';
const BILLING_INTERNAL_KEY = process.env.BILLING_INTERNAL_KEY ?? 'dev-insecure-key';

// Production check is enforced at startup in index.ts.
// Here we just warn in dev if the secret is absent.
const _JWT_SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret-do-not-use-in-production';
if (!process.env.JWT_SECRET) {
  console.warn('[auth] WARNING: JWT_SECRET not set — using insecure default for development only');
}
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
  inviteCode?: string;
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
  user: SafeUser;
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

    // --- Invite code gate ---
    const requireInviteCode = process.env.REQUIRE_INVITE_CODE === 'true';
    let resolvedCode: InviteCode | null = null;

    if (requireInviteCode) {
      if (!data.inviteCode) {
        throw new Error('INVITE_CODE_REQUIRED');
      }
      const [code] = await db
        .select()
        .from(inviteCodes)
        .where(and(
          eq(inviteCodes.code, data.inviteCode.toUpperCase().trim()),
          eq(inviteCodes.active, true),
        ))
        .limit(1);

      if (!code) throw new Error('INVALID_INVITE_CODE');
      if (code.expiresAt && code.expiresAt < new Date()) throw new Error('INVITE_CODE_EXPIRED');
      if (code.maxUses !== null && code.usedCount >= code.maxUses) throw new Error('INVITE_CODE_EXHAUSTED');

      resolvedCode = code;
    } else if (data.inviteCode) {
      // Invite codes are optional but valid — try to resolve without blocking registration
      const [code] = await db
        .select()
        .from(inviteCodes)
        .where(and(
          eq(inviteCodes.code, data.inviteCode.toUpperCase().trim()),
          eq(inviteCodes.active, true),
        ))
        .limit(1);
      if (code && !(code.expiresAt && code.expiresAt < new Date()) &&
          !(code.maxUses !== null && code.usedCount >= code.maxUses)) {
        resolvedCode = code;
      }
    }

    // Check if email already exists
    const existing = await db.select().from(users).where(eq(users.email, data.email)).limit(1);
    if (existing.length > 0) {
      throw new Error('Email already registered');
    }

    // Hash password outside the transaction (CPU-bound, no need to hold a connection)
    const passwordHash = await bcrypt.hash(data.password, BCRYPT_ROUNDS);

    // Calculate trial end date — invite code overrides take precedence.
    // Defaults (30 days / professional) are tuned for invited beta users;
    // when REQUIRE_INVITE_CODE=false and no code is supplied these still apply.
    const now = new Date();
    const trialDays = resolvedCode?.trialDays ?? 30;
    const trialEndsAt = new Date(now.getTime() + trialDays * 24 * 60 * 60 * 1000);
    const subscriptionTier = resolvedCode?.subscriptionTier ?? 'professional';

    // Run user creation + invite code recording in a single transaction to prevent
    // TOCTOU races: re-check usedCount inside the transaction before committing.
    const newUser = await db.transaction(async (tx) => {
      // Re-check invite code inside the transaction to prevent concurrent over-use
      if (resolvedCode) {
        const [fresh] = await tx
          .select({ usedCount: inviteCodes.usedCount, maxUses: inviteCodes.maxUses })
          .from(inviteCodes)
          .where(eq(inviteCodes.id, resolvedCode.id))
          .limit(1);

        if (!fresh || (fresh.maxUses !== null && fresh.usedCount >= fresh.maxUses)) {
          throw new Error('INVITE_CODE_EXHAUSTED');
        }
      }

      const [created] = await tx
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
          subscriptionTier,
          termsAcceptedAt: now,
          marketingEmailsOptIn: data.marketingEmailsOptIn || false,
          inviteCodeId: resolvedCode?.id ?? null,
        })
        .returning();

      if (resolvedCode) {
        await tx.insert(inviteCodeUses).values({
          inviteCodeId: resolvedCode.id,
          userId: created.id,
        });
        await tx
          .update(inviteCodes)
          .set({ usedCount: sql`${inviteCodes.usedCount} + 1` })
          .where(eq(inviteCodes.id, resolvedCode.id));
      }

      return created;
    });

    // Generate JWT
    const token = this.generateToken(newUser);

    // Sync to billing service — fire-and-forget; don't block registration
    this.syncUserToBilling(newUser, resolvedCode?.quotaOverrideUsd ?? null);

    // Provision Galaxy user account — fire-and-forget; falls back to admin key if it fails
    this.provisionGalaxyUser(newUser.id, newUser.email);

    return {
      user: this.sanitizeUser(newUser),
      token,
      expiresIn: this.getTokenExpiresInSeconds(),
    };
  }

  /**
   * Provision a Galaxy user account for a newly registered BioMate user and
   * store the credentials back in the DB.  Fire-and-forget — registration
   * succeeds even if Galaxy is unreachable; the user falls back to the shared
   * admin key until provisioning succeeds (e.g. on next login).
   */
  private provisionGalaxyUser(biomateUserId: string, email: string): void {
    const adminProxy = new GalaxyAPIProxy();

    const attempt = async (attemptsLeft: number, delayMs: number): Promise<void> => {
      try {
        const { galaxyUserId, galaxyApiKey, galaxyUsername } =
          await adminProxy.provisionGalaxyUser(biomateUserId, email);
        await db
          .update(users)
          .set({ galaxyUserId, galaxyApiKey, galaxyUsername })
          .where(eq(users.id, biomateUserId));
        console.log(`[auth] Galaxy user provisioned for ${email}: ${galaxyUsername}`);
      } catch (err: any) {
        if (attemptsLeft > 1) {
          console.warn(
            `[auth] Galaxy provisioning attempt failed for ${email} — retrying in ${delayMs}ms (${attemptsLeft - 1} left):`,
            err.message
          );
          await new Promise(resolve => setTimeout(resolve, delayMs));
          return attempt(attemptsLeft - 1, delayMs * 2);
        }
        // All retries exhausted — BioMate account exists but no Galaxy isolation
        console.error(
          `[auth] Galaxy provisioning FAILED after 3 attempts for ${email}. ` +
          `User will fall back to shared admin key until re-provisioned. Error: ${err.message}`
        );
      }
    };

    attempt(3, 1000).catch(() => {/* already logged */});
  }

  /**
   * Register the new user with the billing service so their monthly quota
   * is seeded in Redis immediately.  If the billing service is down the
   * registration still succeeds — the quota enforcer will fail-open (unlimited)
   * until the billing service is reachable and the operator re-runs set_quota.
   */
  private syncUserToBilling(
    user: User,
    quotaOverrideUsd: string | null,
  ): void {
    const plan = billingPlanForTier(user.subscriptionTier || 'academic');

    const body: Record<string, unknown> = {
      user_id: String(user.id),
      email:   user.email,
      name:    user.fullName || user.email,
      plan,
    };

    fetch(`${GALAXY_URL}/internal/billing/register_user`, {
      method: 'POST',
      headers: {
        'Content-Type':    'application/json',
        'X-Internal-Key':  BILLING_INTERNAL_KEY,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(5000),
    })
      .then(async (resp) => {
        if (!resp.ok) {
          const text = await resp.text();
          console.warn('[billing] register_user failed:', resp.status, text);
          return;
        }
        // If the invite code specifies a custom quota, override the plan default
        if (quotaOverrideUsd) {
          await fetch(`${GALAXY_URL}/internal/billing/set_quota`, {
            method: 'POST',
            headers: {
              'Content-Type':   'application/json',
              'X-Internal-Key': BILLING_INTERNAL_KEY,
            },
            body: JSON.stringify({
              user_id:   String(user.id),
              quota_usd: parseFloat(quotaOverrideUsd),
            }),
            signal: AbortSignal.timeout(5000),
          }).catch((err) =>
            console.warn('[billing] set_quota (override) failed:', err.message),
          );
        }
      })
      .catch((err) =>
        console.warn('[billing] register_user unreachable:', err.message),
      );

    // Also register with the Java billing service (dual-write, fire-and-forget).
    // The Java service auto-creates a Lago customer + default subscription.
    const javaBillingUrl = process.env.JAVA_BILLING_SERVICE_URL;
    if (javaBillingUrl) {
      fetch(`${javaBillingUrl}/api/billing/customers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          externalId: `bm_${user.id}`,
          name:       user.fullName || user.email,
          email:      user.email,
          currency:   'USD',
        }),
        signal: AbortSignal.timeout(5000),
      }).catch((err) =>
        console.warn('[billing] java service registration failed:', err.message),
      );
    } else {
      // Fallback: create Lago customer + subscription directly when Java service is unavailable.
      // Used in dev/staging where JAVA_BILLING_SERVICE_URL is not set.
      const lagoUrl = process.env.LAGO_URL || process.env.LAGO_API_URL;
      const lagoKey = process.env.LAGO_API_KEY;
      if (lagoUrl && lagoKey) {
        const externalId = `bm_${user.id}`;
        // 1. Create/upsert customer
        fetch(`${lagoUrl}/api/v1/customers`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lagoKey}` },
          body: JSON.stringify({ customer: { external_id: externalId, name: user.fullName || user.email, email: user.email, currency: 'USD' } }),
          signal: AbortSignal.timeout(5000),
        }).then(() => {
          // 2. Create subscription (plan_code must match an existing Lago plan)
          const planCode = process.env.LAGO_PLAN_CODE || 'base';
          return fetch(`${lagoUrl}/api/v1/subscriptions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lagoKey}` },
            body: JSON.stringify({ subscription: { external_customer_id: externalId, external_id: `${externalId}_base`, plan_code: planCode } }),
            signal: AbortSignal.timeout(5000),
          });
        }).catch((err) =>
          console.warn('[billing] direct lago registration failed:', err.message),
        );
      }
    }
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

    // Re-attempt Galaxy provisioning if it failed during registration
    if (!user.galaxyApiKey) {
      console.log(`[auth] User ${user.email} has no Galaxy API key — re-attempting provisioning`);
      this.provisionGalaxyUser(user.id, user.email);
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
      const payload = jwt.verify(token, _JWT_SECRET) as JWTPayload;
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
  checkSubscriptionStatus(user: SafeUser): {
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
  async requestPasswordReset(email: string): Promise<{ sent: boolean; resetToken?: string }> {
    const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);

    // Don't reveal if email exists - security best practice
    if (!user) {
      return { sent: true };
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

    // Send email; if not configured, return token for dev bypass
    const emailSent = await emailService.sendPasswordResetEmail(user.email, token, user.fullName);

    return { sent: emailSent, resetToken: emailSent ? undefined : token };
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

    return jwt.sign(payload, _JWT_SECRET, {
      expiresIn: JWT_EXPIRES_IN as jwt.SignOptions['expiresIn'],
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
