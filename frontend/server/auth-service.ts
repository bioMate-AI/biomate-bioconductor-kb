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
import { encryptField, decryptField } from './field-encrypt';

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
  role?: string;
  phone?: string;
  termsAccepted: boolean;
  marketingEmailsOptIn?: boolean;
  inviteCode?: string;
}

export interface LoginData {
  email: string;
  password: string;
  rememberMe?: boolean;
}

export interface JWTPayload {
  userId: string;
  email: string;
  subscriptionStatus: string;
  subscriptionTier: string;
  trialEndsAt: string | null;
  type?: 'session' | 'mfa_challenge';
  jti?: string;
}

export interface AuthResponse {
  user: SafeUser;
  token: string;
  expiresIn: number;  // seconds
  rememberMe?: boolean;
}

export interface MfaChallengeResponse {
  mfaRequired: true;
  challengeToken: string;
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
    // Defaults (14 days / professional) for public trial users.
    // Invite codes can override for extended trials or different tiers.
    const now = new Date();
    const trialDays = resolvedCode?.trialDays ?? 14;
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
          role: data.role,
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

    // Note: previously this issued a fire-and-forget sendVerificationEmail
    // here. That moved to the /api/auth/register route handler so the route
    // can capture the verification token and return it in the response (dev
    // / no-SMTP environments surface a "click this link to verify"
    // affordance — without the token, that link rendered as ?token=null and
    // 404'd into the React error path).

    // Provision Galaxy user account synchronously so the JWT we just issued
    // can be used for /api/ai_assistant/* on the very first chat turn. If
    // Galaxy is slow/unreachable, falls back to fire-and-forget retries and
    // we return the un-provisioned user (same behaviour as before commit
    // bf4787b54's proxy-fix dependency).
    let userForResponse = newUser;
    const provisioned = await this.provisionGalaxyUser(newUser.id, newUser.email);
    if (provisioned) {
      // Reload to pick up the freshly-stored galaxyUserId / galaxyApiKey /
      // galaxyUsername columns. We don't decrypt the key here — it's
      // sanitized out of the response either way; we just want the response
      // to honestly reflect that provisioning is done.
      const reloaded = await db.select().from(users).where(eq(users.id, newUser.id)).limit(1);
      if (reloaded[0]) userForResponse = reloaded[0];
    }

    return {
      user: this.sanitizeUser(userForResponse),
      token,
      expiresIn: this.getTokenExpiresInSeconds(),
    };
  }

  /**
   * Provision a Galaxy user account for a newly registered BioMate user and
   * store the credentials back in the DB. Pattern: ATTEMPT-ONCE synchronously
   * (so the JWT we just issued is usable immediately for `/api/ai_assistant/*`
   * routes that require the per-user Galaxy key — see chat-stream proxy fix
   * in commit bf4787b54). If the first call succeeds the row has its
   * galaxyApiKey before register returns. If it fails or Galaxy is slow, we
   * fall back to the existing fire-and-forget retry loop, and the user lands
   * on the broken-admin path for their first turn (same behaviour as before).
   *
   * @returns true if the first synchronous attempt succeeded (galaxyApiKey
   *   is now persisted to PG), false if it threw and we fell back to
   *   fire-and-forget retries.
   */
  private async provisionGalaxyUser(biomateUserId: string, email: string): Promise<boolean> {
    const adminProxy = new GalaxyAPIProxy();
    try {
      const { galaxyUserId, galaxyApiKey, galaxyUsername } =
        await adminProxy.provisionGalaxyUser(biomateUserId, email);
      const encryptedApiKey = galaxyApiKey ? encryptField(galaxyApiKey) : galaxyApiKey;
      await db
        .update(users)
        .set({ galaxyUserId, galaxyApiKey: encryptedApiKey, galaxyUsername })
        .where(eq(users.id, biomateUserId));
      console.log(`[auth] Galaxy user provisioned for ${email}: ${galaxyUsername}`);
      return true;
    } catch (firstErr: any) {
      console.warn(
        `[auth] Galaxy provisioning first attempt failed for ${email} — falling back to async retries:`,
        firstErr.message
      );
      // Fire-and-forget retry chain — same behaviour as pre-bf4787b54 for the
      // failure path. User's first chat turn will fall back to the admin key
      // (which is broken when its api_keys row is missing) until provisioning
      // catches up on a subsequent login.
      const retry = async (attemptsLeft: number, delayMs: number): Promise<void> => {
        try {
          const { galaxyUserId, galaxyApiKey, galaxyUsername } =
            await adminProxy.provisionGalaxyUser(biomateUserId, email);
          const encryptedApiKey = galaxyApiKey ? encryptField(galaxyApiKey) : galaxyApiKey;
          await db
            .update(users)
            .set({ galaxyUserId, galaxyApiKey: encryptedApiKey, galaxyUsername })
            .where(eq(users.id, biomateUserId));
          console.log(`[auth] Galaxy user provisioned (retry) for ${email}: ${galaxyUsername}`);
        } catch (err: any) {
          if (attemptsLeft > 1) {
            console.warn(
              `[auth] Galaxy provisioning retry failed for ${email} — retrying in ${delayMs}ms (${attemptsLeft - 1} left):`,
              err.message
            );
            await new Promise(resolve => setTimeout(resolve, delayMs));
            return retry(attemptsLeft - 1, delayMs * 2);
          }
          console.error(
            `[auth] Galaxy provisioning FAILED after retries for ${email}. ` +
            `User will fall back to shared admin key until re-provisioned. Error: ${err.message}`
          );
        }
      };
      retry(2, 2000).catch(() => {/* already logged */});
      return false;
    }
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
   * Login existing user.
   *
   * rememberMe=false → 24-hour session (cookie expires when browser closes, JWT lives 24h)
   * rememberMe=true  → 30-day session (cookie persists, JWT lives 30d)
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

    // Trial-expiry policy (2026-06-12): when the 2-week trial has ended
    // and the user hasn't upgraded, they DROP DOWN TO THE FREE PLAN — they
    // do NOT get blocked from login. Previously this threw TRIAL_EXPIRED
    // and the client redirected to /pricing?from=trial-expired, but the
    // /pricing route is commented out, so the user landed on a 404. Quota
    // enforcement at the workflow / chat layer is responsible for honoring
    // the free-tier limits; auth is no longer the gate.
    const now = new Date();
    const trialExpired = user.trialEndsAt && user.trialEndsAt < now && !user.trialUsed;
    const subscriptionActive =
      user.subscriptionStatus === 'active' &&
      (!user.currentPeriodEnd || user.currentPeriodEnd > now);

    if (trialExpired && !subscriptionActive && user.subscriptionTier === 'trial') {
      // Demote to free tier so downstream code stops checking trial state
      // and just enforces free-plan quotas. Idempotent — re-login won't
      // re-write if the tier already moved.
      try {
        await db
          .update(users)
          .set({ subscriptionTier: 'free', subscriptionStatus: 'inactive', updatedAt: new Date() })
          .where(eq(users.id, user.id));
        user.subscriptionTier = 'free';
        user.subscriptionStatus = 'inactive';
        console.log(`[auth] User ${user.email} trial expired → demoted to free plan`);
      } catch (e: any) {
        console.warn(`[auth] trial→free demotion failed for ${user.email}:`, e?.message ?? e);
      }
    }

    // Re-attempt Galaxy provisioning if it failed during registration
    if (!user.galaxyApiKey) {
      console.log(`[auth] User ${user.email} has no Galaxy API key — re-attempting provisioning`);
      await this.provisionGalaxyUser(user.id, user.email);
    } else {
      // Stored key may be stale — Galaxy's universe.sqlite gets reset by
      // sync_to_dev DB swaps OR by other admins, leaving PG rows that point
      // at no-longer-valid api_keys rows. The original guard only fired on
      // probe 401/no-response — but /api/whoami silently 500s and other
      // endpoints time out when the key authenticates to a non-existent
      // user (galaxyUserId drift). Validate via /api/users/current which
      // returns the resolved user's encoded id; if it doesn't match
      // user.galaxyUserId OR returns any non-2xx, treat the key as stale.
      // See docs/20260610_STALE_GALAXY_USER_DRIFT.md for the root cause.
      try {
        const decrypted = decryptField(user.galaxyApiKey);
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8080';
        const probe = await fetch(`${galaxyUrl}/api/users/current`, {
          method: 'GET',
          headers: { 'X-API-Key': decrypted || '' },
          signal: AbortSignal.timeout(5000),
        }).catch(() => null);

        let isStale = false;
        let staleReason = '';
        if (!probe) {
          isStale = true;
          staleReason = 'no-response (network/timeout)';
        } else if (!probe.ok) {
          isStale = true;
          staleReason = `HTTP ${probe.status}`;
        } else {
          // Confirm Galaxy resolves the key to the SAME user we stored.
          // Galaxy returns an encoded id; we compare directly against the
          // stored galaxyUserId (also encoded form on disk for newer rows;
          // older rows are numeric — accept either form by string match).
          try {
            const body = await probe.json();
            const galaxyResolvedId = String(body?.id ?? '');
            const storedId = String(user.galaxyUserId ?? '');
            const galaxyEmail = String(body?.email ?? '');
            if (!galaxyResolvedId) {
              isStale = true;
              staleReason = 'Galaxy returned no id';
            } else if (storedId && galaxyResolvedId !== storedId) {
              isStale = true;
              staleReason = `id drift: stored=${storedId} galaxy=${galaxyResolvedId}`;
            } else if (galaxyEmail && galaxyEmail.toLowerCase() !== user.email.toLowerCase()) {
              isStale = true;
              staleReason = `email drift: BioMate=${user.email} Galaxy=${galaxyEmail}`;
            }
          } catch (parseErr) {
            isStale = true;
            staleReason = `unparseable response (${parseErr})`;
          }
        }

        if (isStale) {
          console.warn(`[auth] User ${user.email} galaxyApiKey is stale (${staleReason}) — clearing + re-provisioning`);
          await db.update(users)
            .set({ galaxyApiKey: null, galaxyUserId: null, galaxyUsername: null })
            .where(eq(users.id, user.id));
          await this.provisionGalaxyUser(user.id, user.email);
        }
      } catch (e: any) {
        console.warn(`[auth] galaxyApiKey validation skipped for ${user.email}: ${e?.message ?? e}`);
      }
    }

    // If MFA is enabled, issue a short-lived challenge token instead of a full session
    if (user.mfaEnabled) {
      const jti = randomBytes(16).toString('hex');
      const challengeToken = jwt.sign(
        {
          userId: user.id,
          email: user.email,
          subscriptionStatus: user.subscriptionStatus ?? 'trialing',
          subscriptionTier: user.subscriptionTier ?? 'academic',
          trialEndsAt: user.trialEndsAt?.toISOString() ?? null,
          type: 'mfa_challenge',
          jti,
        } satisfies JWTPayload,
        _JWT_SECRET,
        { expiresIn: '5m' }
      );
      return { mfaRequired: true, challengeToken } as any;
    }

    const rememberMe = data.rememberMe ?? false;
    // 30 days if remembered, 24 hours otherwise
    const sessionSeconds = rememberMe ? 30 * 24 * 60 * 60 : 24 * 60 * 60;
    const sessionExpiresAt = new Date(now.getTime() + sessionSeconds * 1000);

    // Update last login + session metadata
    await db
      .update(users)
      .set({ lastLoginAt: now, updatedAt: now, rememberMe, sessionExpiresAt })
      .where(eq(users.id, user.id));

    // Generate JWT with duration matching the session choice
    const token = this.generateToken(user, rememberMe);

    return {
      user: this.sanitizeUser(user),
      token,
      expiresIn: sessionSeconds,
      rememberMe,
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

  /** Verify email + password — used by MFA disable to re-authenticate */
  async verifyCredentials(email: string, password: string): Promise<User | null> {
    const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);
    if (!user) return null;
    const ok = await bcrypt.compare(password, user.password);
    return ok ? user : null;
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
   * Send verification email.
   *
   * Overloaded return:
   *   - default: Promise<boolean>  (true if email actually sent)
   *   - with { returnToken: true }: Promise<string|null>  (token string;
   *     null only if user already verified)
   *
   * Why the overload: in dev / no-SMTP environments, the registration UI
   * surfaces a "use this link to verify" affordance — and that needs the
   * raw token. The token is always generated and persisted (line ~611);
   * the only thing that varies is whether the email transport succeeds.
   * Returning the token lets the caller surface it to the user when SMTP
   * isn't configured.
   */
  async sendVerificationEmail(userId: string): Promise<boolean>;
  async sendVerificationEmail(userId: string, opts: { returnToken: true }): Promise<string | null>;
  async sendVerificationEmail(userId: string, opts?: { returnToken?: boolean }): Promise<boolean | string | null> {
    const user = await this.getUserById(userId);
    if (!user) {
      throw new Error('User not found');
    }

    if (user.emailVerified) {
      if (opts?.returnToken) return null;
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

    // Send email — fire-and-forget when caller asked for the token (it's
    // expected that SMTP may not be wired and the caller will surface the
    // link). Awaited on the boolean path for backward compatibility.
    if (opts?.returnToken) {
      emailService.sendVerificationEmail(user.email, token, user.fullName).catch(() => {});
      return token;
    }
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
  generateToken(user: User, rememberMe = false): string {
    const payload: JWTPayload = {
      userId: user.id,
      email: user.email,
      subscriptionStatus: user.subscriptionStatus || 'trialing',
      subscriptionTier: user.subscriptionTier || 'academic',
      trialEndsAt: user.trialEndsAt ? user.trialEndsAt.toISOString() : null,
    };

    // rememberMe=false → 24h; rememberMe=true → 30d; registration always uses JWT_EXPIRES_IN default
    const expiresIn = rememberMe ? '30d' : '24h';

    return jwt.sign(payload, _JWT_SECRET, {
      expiresIn: expiresIn as jwt.SignOptions['expiresIn'],
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
