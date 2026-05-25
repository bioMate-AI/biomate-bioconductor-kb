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
 */

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
