/**
 * plan-config.ts — Canonical mapping between BioMate subscription tiers and
 * the Lago billing plan codes / monthly quota caps.
 *
 * The backend DEFAULT_PLAN_LIMITS in quota_enforcer.py is the authoritative
 * source for quota amounts; this file mirrors those values so the Node.js
 * server can:
 *   1. Pass the correct plan code to /internal/billing/register_user at sign-up.
 *   2. Apply tier-aware messaging in quota-exceeded responses.
 *
 * Lago plan codes: "free" | "basic" | "pro" | "enterprise"
 * BioMate tiers:   "trial" | "academic" | "professional" | "enterprise" | "admin"
 *
 * Canonical product tiers (docs/20260727_TIER_MODEL_DECISION.md): free | premium |
 * team | enterprise. `canonicalTier()` in ./tier is the single ENTITLEMENT source;
 * the CANONICAL_* tables below are the single QUOTA + plan source per tier. The
 * legacy TIER_* maps are retained for the existing trial/academic accounts.
 */
import { canonicalTier, type CanonicalTier } from "./tier";

/** Frontend subscription tier → Lago billing plan code */
export const TIER_TO_BILLING_PLAN: Record<string, string> = {
  trial:        'free',
  academic:     'free',
  professional: 'basic',
  enterprise:   'pro',
  admin:        'enterprise', // custom / unlimited
};

/**
 * Frontend subscription tier → monthly quota cap in USD.
 * null means unlimited (admin accounts).
 * Must stay in sync with DEFAULT_PLAN_LIMITS in quota_enforcer.py.
 */
export const TIER_QUOTA_USD: Record<string, number | null> = {
  trial:        5.00,
  academic:     5.00,
  professional: 25.00,
  enterprise:   500.00,
  admin:        null,
};

export function billingPlanForTier(tier: string): string {
  return TIER_TO_BILLING_PLAN[tier] ?? 'free';
}

export function quotaUsdForTier(tier: string): number | null {
  return tier in TIER_QUOTA_USD ? TIER_QUOTA_USD[tier] : 5.00;
}

// ─── Canonical tier reconciliation ──────────────────────────────────────────
// One QUOTA + Lago-plan source per canonical tier. Backend quota_enforcer.py
// DEFAULT_PLAN_LIMITS must carry the same values (free 5, premium 120, team/
// enterprise custom). Trial is orthogonal to tier: a 14-day $25 budget (Lago
// plan 'base'/'basic'), NOT a tier — a trial user is `premium` entitlement with
// a $25 spend cap.

/** Canonical tier → monthly quota USD. null = custom/unlimited (sales-negotiated). */
export const CANONICAL_TIER_QUOTA_USD: Record<CanonicalTier, number | null> = {
  free:        5.00,
  premium:   120.00,   // $100/mo plan, $120 credit allowance
  team:        null,   // custom / negotiated
  enterprise:  null,   // custom / negotiated
};

/** Canonical tier → Lago billing plan code. */
export const CANONICAL_TIER_TO_BILLING_PLAN: Record<CanonicalTier, string> = {
  free:       'free',
  premium:    'premium',   // new $120 plan; legacy 'pro' ($500) stays grandfathered
  team:       'team',
  enterprise: 'enterprise',
};

/** Quota for a user from their (possibly legacy) subscriptionTier, via the canonical tier. */
export function quotaUsdForSubscriptionTier(subscriptionTier: string | null | undefined): number | null {
  return CANONICAL_TIER_QUOTA_USD[canonicalTier(subscriptionTier)];
}

/** Lago plan code for a user's canonical tier. */
export function billingPlanForCanonicalTier(subscriptionTier: string | null | undefined): string {
  return CANONICAL_TIER_TO_BILLING_PLAN[canonicalTier(subscriptionTier)];
}
