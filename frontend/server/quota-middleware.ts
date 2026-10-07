/**
 * quota-middleware.ts — Gates compute-intensive endpoints behind the per-user
 * monthly quota tracked in Redis by the billing service.
 *
 * Authenticated users  → checked against billing quota (Python /api/billing/quota)
 * Unauthenticated users → conservative IP-based rate limit (no billing account)
 *
 * Fail-open: if the billing service is unreachable the request is allowed through
 * rather than blocking users due to infrastructure issues.
 */

import rateLimit from 'express-rate-limit';
import type { Request, Response, NextFunction } from 'express';

const GALAXY_URL = process.env.GALAXY_URL ?? 'http://localhost:8081';

// E2E bypass: same token the request-level rate limiter uses. Only active when
// E2E_TEST_TOKEN env var is set (dev-only by convention).
const _E2E_TOKEN = process.env.E2E_TEST_TOKEN;
function isE2EBypass(req: Request): boolean {
  // NEVER bypass in production, even if the token env is present (mirrors auth-middleware.ts).
  // A leaked/copied E2E_TEST_TOKEN must not become a billing/auth bypass on the paying platform.
  if (process.env.NODE_ENV === 'production') return false;
  if (!_E2E_TOKEN) return false;
  return req.headers['x-e2e-test-token'] === _E2E_TOKEN;
}

/**
 * Billing quota is a SaaS (our own AWS platform) concept. On-premise deployments run the customer's
 * own compute/infra and do NOT meter per-user quota, so enforcement must be skippable.
 *
 * FAIL-SAFE by design: quota is ENFORCED by default and can only be disabled by an EXPLICIT opt-out.
 * We deliberately do NOT infer "don't bill" from infra vars (NEXTFLOW_USE_AWS / S3_ENDPOINT_URL): a
 * stray or loosely-spelled infra var (e.g. NEXTFLOW_USE_AWS=1, or an S3 VPC/FIPS/PrivateLink endpoint)
 * must never silently turn billing OFF on the paying platform.
 *
 * To disable on-premise, set ONE of (checked case-insensitively):
 *   - BIOMATE_QUOTA_ENFORCEMENT = off | false | 0 | no   (dedicated quota toggle)
 *   - BIOMATE_DEPLOYMENT        = onprem | on-prem | on_prem | onpremise | on-premise
 * BIOMATE_QUOTA_ENFORCEMENT = on | true | 1 | yes forces enforcement.
 */
export function quotaEnforcementEnabled(): boolean {
  const explicit = (process.env.BIOMATE_QUOTA_ENFORCEMENT || '').trim().toLowerCase();
  if (['off', 'false', '0', 'no'].includes(explicit)) return false;
  if (['on', 'true', '1', 'yes'].includes(explicit)) return true;
  const dep = (process.env.BIOMATE_DEPLOYMENT || '').trim().toLowerCase();
  if (['onprem', 'on-prem', 'on_prem', 'onpremise', 'on-premise'].includes(dep)) return false;
  return true; // DEFAULT: enforce (fail-safe)
}

// Tight IP-based fallback for callers without a billing account
const unauthLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => isE2EBypass(req),
  handler: (_req: Request, res: Response) => {
    res.status(429).json({
      success: false,
      error: 'UNAUTHENTICATED_LIMIT_EXCEEDED',
      message: 'Please sign in to use this feature. Guest access is limited to 5 requests per hour.',
    });
  },
});

/**
 * Returns Express middleware that enforces billing quota for authenticated users.
 *
 * - Admin tier → allowed unconditionally
 * - Authenticated → proxies GET /api/billing/quota; returns 402 if over_quota
 * - Unauthenticated → IP-based rate limit (5/hr)
 *
 * @param resourceName  Human-readable label for error messages (e.g. "AI generation")
 */
export function checkBillingQuota(resourceName: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    // Deployment toggle: skip entirely on-premise / when quota enforcement is disabled, and for
    // E2E-bypass requests. On-prem runs the customer's own compute — no SaaS quota metering.
    if (!quotaEnforcementEnabled() || isE2EBypass(req)) {
      return next();
    }

    const user = (req as any).user;

    if (!user) {
      return unauthLimiter(req, res, next);
    }

    // Admin accounts are unlimited
    if (user.subscriptionTier === 'admin') {
      return next();
    }

    try {
      const resp = await fetch(`${GALAXY_URL}/api/billing/quota`, {
        headers: { Authorization: `Bearer ${user.id}` },
        signal: AbortSignal.timeout(3000), // 3s timeout — fail open if slow
      });

      if (resp.ok) {
        const data = await resp.json() as {
          over_quota?: boolean;
          quota_usd?: number;
          used_usd?: number;
        };

        if (data.over_quota) {
          const cap = data.quota_usd != null
            ? `$${data.quota_usd.toFixed(2)}/month`
            : 'your plan limit';
          return res.status(402).json({
            success: false,
            error: 'QUOTA_EXCEEDED',
            resource: resourceName,
            message: `Monthly compute quota exceeded (${cap}). Add credits or wait for your billing cycle to reset.`,
            quota_usd: data.quota_usd,
            used_usd: data.used_usd,
          });
        }
      }
      // Non-OK response or quota not exceeded → allow through
    } catch {
      // Billing service unreachable → fail open to avoid blocking users
    }

    return next();
  };
}
