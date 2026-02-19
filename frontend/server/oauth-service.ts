import passport from 'passport';
import { Strategy as GoogleStrategy } from 'passport-google-oauth20';
import { Strategy as GitHubStrategy } from 'passport-github2';
import { db } from './db';
import { users } from '../shared/schema';
import { eq } from 'drizzle-orm';
import type { User } from '../shared/schema';
import { authService } from './auth-service';

// OAuth configuration from environment
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const GITHUB_CLIENT_ID = process.env.GITHUB_CLIENT_ID;
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET;
const OAUTH_CALLBACK_URL = process.env.APP_URL || 'http://localhost:5000';

interface OAuthProfile {
  provider: 'google' | 'github';
  providerId: string;
  email: string;
  name: string;
  avatar?: string;
}

/**
 * OAuth Service - Handles Google and GitHub authentication
 */
export class OAuthService {
  private initialized = false;

  /**
   * Initialize Passport strategies
   */
  initialize() {
    if (this.initialized) {
      return;
    }

    // Google OAuth Strategy
    if (GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET) {
      passport.use(
        new GoogleStrategy(
          {
            clientID: GOOGLE_CLIENT_ID,
            clientSecret: GOOGLE_CLIENT_SECRET,
            callbackURL: `${OAUTH_CALLBACK_URL}/api/auth/google/callback`,
            scope: ['profile', 'email'],
          },
          async (accessToken, refreshToken, profile, done) => {
            try {
              const oauthProfile: OAuthProfile = {
                provider: 'google',
                providerId: profile.id,
                email: profile.emails?.[0]?.value || '',
                name: profile.displayName || '',
                avatar: profile.photos?.[0]?.value,
              };

              const user = await this.findOrCreateOAuthUser(oauthProfile);
              done(null, user);
            } catch (error) {
              done(error as Error);
            }
          }
        )
      );
      console.log('[OAuth] Google strategy initialized');
    } else {
      console.warn('[OAuth] Google OAuth not configured - set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET');
    }

    // GitHub OAuth Strategy
    if (GITHUB_CLIENT_ID && GITHUB_CLIENT_SECRET) {
      passport.use(
        new GitHubStrategy(
          {
            clientID: GITHUB_CLIENT_ID,
            clientSecret: GITHUB_CLIENT_SECRET,
            callbackURL: `${OAUTH_CALLBACK_URL}/api/auth/github/callback`,
            scope: ['user:email'],
          },
          async (accessToken: string, refreshToken: string, profile: any, done: any) => {
            try {
              const email = profile.emails?.[0]?.value || `${profile.username}@github.users.noreply.github.com`;

              const oauthProfile: OAuthProfile = {
                provider: 'github',
                providerId: profile.id,
                email: email,
                name: profile.displayName || profile.username || '',
                avatar: profile.photos?.[0]?.value || profile.avatar_url,
              };

              const user = await this.findOrCreateOAuthUser(oauthProfile);
              done(null, user);
            } catch (error) {
              done(error as Error);
            }
          }
        )
      );
      console.log('[OAuth] GitHub strategy initialized');
    } else {
      console.warn('[OAuth] GitHub OAuth not configured - set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET');
    }

    // Serialize/deserialize user for session support (optional with JWT)
    passport.serializeUser((user: any, done) => {
      done(null, user.id);
    });

    passport.deserializeUser(async (id: string, done) => {
      try {
        const user = await authService.getUserById(id);
        done(null, user);
      } catch (error) {
        done(error);
      }
    });

    this.initialized = true;
    console.log('[OAuth] Service initialized');
  }

  /**
   * Find existing user or create new OAuth user
   */
  private async findOrCreateOAuthUser(profile: OAuthProfile): Promise<User> {
    if (!profile.email) {
      throw new Error('Email is required for OAuth authentication');
    }

    // Check if user already exists by email
    const [existingUser] = await db
      .select()
      .from(users)
      .where(eq(users.email, profile.email))
      .limit(1);

    if (existingUser) {
      // User exists - update last login
      await db
        .update(users)
        .set({
          lastLoginAt: new Date(),
          updatedAt: new Date(),
        })
        .where(eq(users.id, existingUser.id));

      console.log(`[OAuth] Existing user logged in: ${profile.email} via ${profile.provider}`);
      return existingUser;
    }

    // Create new user from OAuth profile
    const now = new Date();
    const trialEndsAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000); // 7 days

    const [newUser] = await db
      .insert(users)
      .values({
        email: profile.email,
        password: '', // OAuth users don't have a password
        fullName: profile.name,
        emailVerified: true, // OAuth emails are pre-verified
        trialStartedAt: now,
        trialEndsAt: trialEndsAt,
        trialUsed: false,
        subscriptionStatus: 'trialing',
        subscriptionTier: 'academic',
        termsAcceptedAt: now, // Implicit acceptance via OAuth
        marketingEmailsOptIn: false,
        createdAt: now,
        updatedAt: now,
        lastLoginAt: now,
      })
      .returning();

    console.log(`[OAuth] New user created: ${profile.email} via ${profile.provider}`);
    return newUser;
  }

  /**
   * Check if OAuth is configured
   */
  isConfigured(): {
    google: boolean;
    github: boolean;
    any: boolean;
  } {
    const google = !!(GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET);
    const github = !!(GITHUB_CLIENT_ID && GITHUB_CLIENT_SECRET);

    return {
      google,
      github,
      any: google || github,
    };
  }

  /**
   * Generate JWT for OAuth authenticated user
   */
  generateToken(user: User): string {
    // Use the existing auth service to generate token
    return (authService as any).generateToken(user);
  }
}

// Export singleton instance
export const oauthService = new OAuthService();
