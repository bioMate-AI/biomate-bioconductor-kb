import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { canonicalTier, meetsTier, canCollaborate, FREE_PROJECT_LIMIT } from './tier';
import { quotaUsdForSubscriptionTier, billingPlanForCanonicalTier, CANONICAL_TIER_QUOTA_USD } from './plan-config';

// Reconciliation: entitlement (tier.ts) and billing (plan-config.ts + backend
// quota_enforcer.py) must agree on the canonical 4 tiers and their quota values.
describe('tier ↔ billing reconciliation', () => {
  it('canonical quota per tier matches decided pricing (free 5, premium 120, team/enterprise custom)', () => {
    expect(CANONICAL_TIER_QUOTA_USD.free).toBe(5.0);
    expect(CANONICAL_TIER_QUOTA_USD.premium).toBe(120.0);
    expect(CANONICAL_TIER_QUOTA_USD.team).toBeNull();       // custom
    expect(CANONICAL_TIER_QUOTA_USD.enterprise).toBeNull(); // custom
  });
  it('legacy subscriptionTier resolves to the right quota via canonical tier', () => {
    expect(quotaUsdForSubscriptionTier('academic')).toBe(5.0);     // → free
    expect(quotaUsdForSubscriptionTier('professional')).toBe(120.0); // → premium
    expect(quotaUsdForSubscriptionTier('team')).toBeNull();
    expect(quotaUsdForSubscriptionTier(undefined)).toBe(5.0);      // default free
  });
  it('canonical tier → Lago plan code', () => {
    expect(billingPlanForCanonicalTier('professional')).toBe('premium');
    expect(billingPlanForCanonicalTier('team')).toBe('team');
    expect(billingPlanForCanonicalTier('academic')).toBe('free');
  });
  it('backend quota_enforcer.py carries the same premium/team values + canonical map', () => {
    const py = readFileSync(join(__dirname, '../../backend/lib/galaxy/ai/billing/core/quota_enforcer.py'), 'utf8');
    expect(py).toMatch(/"premium":\s*120\.00/);
    expect(py).toMatch(/"team":\s*float\("inf"\)/);
    expect(py).toMatch(/"professional":\s*"premium"/); // _CANONICAL_TIER mirrors tier.ts
    expect(py).toMatch(/"academic":\s*"free"/);
  });
});

// Source-level contract: the gates are wired into project-routes AND guarded by
// the enforcement flag (so they can't silently drop or become always-on).
describe('tier gate wiring (project-routes.ts)', () => {
  const src = readFileSync(join(__dirname, 'project-routes.ts'), 'utf8');
  it('collaboration gate is called on every collaboration endpoint', () => {
    const calls = src.match(/blockedByCollaborationTier\(req, res\)\) return/g) ?? [];
    expect(calls.length).toBe(4); // share-link, members invite, role change, owner transfer
  });
  it('collaboration gate no-ops when enforcement is off', () => {
    expect(src).toMatch(/if \(!tierEnforcementEnabled\(\)\) return false/);
  });
  it('Free-tier project cap is enforced on POST /api/projects and guarded by the flag', () => {
    expect(src).toMatch(/PROJECT_LIMIT_REACHED/);
    expect(src).toMatch(/tierEnforcementEnabled\(\) && canonicalTier\(\(req as any\)\.user\?\.subscriptionTier\) === "free"/);
  });
});

describe('canonicalTier', () => {
  it('maps legacy values (academic==free)', () => {
    expect(canonicalTier('academic')).toBe('free');
    expect(canonicalTier('base')).toBe('free');
    expect(canonicalTier('free')).toBe('free');
    expect(canonicalTier('professional')).toBe('premium');
    expect(canonicalTier('pro')).toBe('premium');
    expect(canonicalTier('premium')).toBe('premium');
    expect(canonicalTier('team')).toBe('team');
    expect(canonicalTier('enterprise')).toBe('enterprise');
    expect(canonicalTier('admin')).toBe('enterprise');
  });
  it('is case/space insensitive and defaults unknown/empty to free', () => {
    expect(canonicalTier(' Professional ')).toBe('premium');
    expect(canonicalTier('TEAM')).toBe('team');
    expect(canonicalTier(undefined)).toBe('free');
    expect(canonicalTier(null)).toBe('free');
    expect(canonicalTier('mystery-plan')).toBe('free');
  });
});

describe('meetsTier (ranking free<premium<team<enterprise)', () => {
  it('respects the ladder', () => {
    expect(meetsTier('free', 'free')).toBe(true);
    expect(meetsTier('free', 'premium')).toBe(false);
    expect(meetsTier('professional', 'premium')).toBe(true); // legacy professional == premium
    expect(meetsTier('professional', 'team')).toBe(false);
    expect(meetsTier('team', 'team')).toBe(true);
    expect(meetsTier('team', 'premium')).toBe(true);
    expect(meetsTier('enterprise', 'team')).toBe(true);
  });
});

describe('canCollaborate (collaboration == Team boundary)', () => {
  it('only team and enterprise may collaborate', () => {
    expect(canCollaborate('free')).toBe(false);
    expect(canCollaborate('academic')).toBe(false);
    expect(canCollaborate('professional')).toBe(false); // premium is single-user
    expect(canCollaborate('premium')).toBe(false);
    expect(canCollaborate('team')).toBe(true);
    expect(canCollaborate('enterprise')).toBe(true);
    expect(canCollaborate('admin')).toBe(true);
  });
});

describe('FREE_PROJECT_LIMIT', () => {
  it('is 3', () => expect(FREE_PROJECT_LIMIT).toBe(3));
});
