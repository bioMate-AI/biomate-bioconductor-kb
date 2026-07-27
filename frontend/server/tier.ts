/**
 * tier.ts — canonical plan-tier vocabulary + entitlement checks.
 *
 * Decision: docs/20260727_TIER_MODEL_DECISION.md.
 *   free | premium | team | enterprise
 *   - free:       solo, 3-project cap, private OK. self-serve $0.
 *   - premium:    solo, unlimited, priority. self-serve $100/mo.
 *   - team:       + collaboration (share/invite/roles/RBAC). custom.
 *   - enterprise: + SSO/audit/BAA. custom.
 *
 * The DB `subscriptionTier` column is historically inconsistent
 * (free/professional/academic/base). canonicalTier() normalizes it at read time
 * (no migration required) so gates can trust a 4-value enum.
 */
export type CanonicalTier = 'free' | 'premium' | 'team' | 'enterprise';

// Legacy → canonical. Per product owner: academic == free.
const TIER_MAP: Record<string, CanonicalTier> = {
  '': 'free',
  free: 'free',
  academic: 'free',   // no separate academic tier — equals free
  base: 'free',        // default/unset
  professional: 'premium',
  pro: 'premium',
  premium: 'premium',
  team: 'team',
  enterprise: 'enterprise',
  admin: 'enterprise', // internal admin → top entitlements
};

const RANK: Record<CanonicalTier, number> = { free: 0, premium: 1, team: 2, enterprise: 3 };

export function canonicalTier(raw?: string | null): CanonicalTier {
  if (!raw) return 'free';
  return TIER_MAP[raw.toLowerCase().trim()] ?? 'free';
}

/** True if the user's (possibly legacy) tier is at least `min`. */
export function meetsTier(rawTier: string | null | undefined, min: CanonicalTier): boolean {
  return RANK[canonicalTier(rawTier)] >= RANK[min];
}

/** Collaboration (share links, members, roles) requires Team or above. */
export function canCollaborate(rawTier: string | null | undefined): boolean {
  return meetsTier(rawTier, 'team');
}

/** Free tier is capped at this many OWNED active projects. */
export const FREE_PROJECT_LIMIT = 3;

/**
 * Master switch. Tier enforcement stays OFF until (a) the `team` tier is
 * provisioned in billing and (b) upgrade-CTA UI ships — otherwise every current
 * user (all free/premium) would lose the collaboration they already have. Turn
 * on with TIER_ENFORCEMENT=on once the rollout is ready.
 */
export function tierEnforcementEnabled(): boolean {
  return process.env.TIER_ENFORCEMENT === 'on';
}
