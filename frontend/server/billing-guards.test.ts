// @vitest-environment node
// (server source checks: under jsdom, `URL` is the jsdom class and node:url fileURLToPath
// rejects it on CI's Node — ERR_INVALID_ARG_TYPE for every guard.)
// Regression guards for billing fixes that have NO other test coverage and each
// caused (or would cause) a silent production failure. These are deliberately
// source-invariant checks (read the file, assert the fix is present) — cheap, no
// heavy imports (server/stripe-service pull in db + galaxy), run in plain CI, and
// fail loudly if someone reverts the fix. See docs/20260807_BILLING_TEAM_CATCHUP.md.
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

describe('billing regression guards', () => {
  it('webhook path is excluded from the global body parser (else every Stripe webhook 400s)', () => {
    // Bug: a global express.json() parsed the webhook body before the route's
    // express.raw(), making constructEvent throw "payload must be string/Buffer".
    const src = read('./index.ts');
    // the raw-body exclusion predicate must reference the webhook path
    expect(src).toMatch(/\/api\/payments\/webhook/);
    // and the global json/urlencoded parsers must be gated by that predicate, not
    // applied unconditionally to all non-MCP paths
    expect(src).toMatch(/_needsRawBody/);
    const gated = src.match(/app\.use\(\(req[^)]*\)\s*=>\s*\(_needsRawBody\(req\)\s*\?\s*next\(\)/g) || [];
    expect(gated.length).toBeGreaterThanOrEqual(2); // json + urlencoded both gated
  });

  it('getPricingTiers exposes a canonical "premium" tier (else checkout tier=premium -> 400)', () => {
    // Bug: checkout.tsx sends tier="premium" but the map only had academic/
    // professional/enterprise -> "Unknown tier: premium" even with valid keys.
    const src = read('./stripe-service.ts');
    expect(src).toMatch(/getPricingTiers\s*\(\)\s*\{[\s\S]*?premium\s*:\s*\{/);
  });

  it('webhook maps subscriptions to the "premium" quota tier, not the non-existent "professional"', () => {
    // Bug: subscriptionTier was set to 'professional'/'academic', which have no
    // entry in quota_enforcer.DEFAULT_PLAN_LIMITS (premium=$120) -> wrong quota.
    const src = read('./stripe-service.ts');
    expect(src).not.toMatch(/tier\s*=\s*['"]professional['"]/);
    expect(src).toMatch(/tier\s*=\s*['"]premium['"]/);
  });

  it('add-credits dev fallback cannot fake credits in production', () => {
    // Bug: when Stripe was unconfigured, add-credits returned a success-shaped
    // {url:null} that the UI reported as "Credits added" WITHOUT any payment.
    const src = read('./routes.ts');
    // the dev fallback must be gated by an explicit flag AND non-production env
    expect(src).toMatch(/BILLING_DEV_CREDITS/);
    expect(src).toMatch(/NODE_ENV\s*!==\s*['"]production['"]/);
  });

  it('subscription change syncs the plan to the billing backend (else quota ignores it)', () => {
    // Bug: handleSubscriptionUpdate wrote only Postgres subscriptionTier; the
    // enforced Redis quota kept the signup cap -> paying Premium user capped at Free.
    const src = read('./stripe-service.ts');
    expect(src).toMatch(/_syncPlanToBilling/);   // helper exists
    expect(src).toMatch(/set_plan/);              // calls the backend endpoint
    // and it must actually be invoked from the subscription handler
    const subHandler = src.slice(src.indexOf('handleSubscriptionUpdate'));
    expect(subHandler).toMatch(/_syncPlanToBilling\(/);
  });

  it('Premium 14-day trial is gated by prior use (no repeat free trials)', () => {
    // Requirement: only users who have not used/passed their free trial get the
    // 14-day trial; repeat/expired-trial users are charged immediately.
    const src = read('./stripe-service.ts');
    expect(src).toMatch(/isTrialEligible/);
    // trial_period_days must be conditional on eligibility, not unconditional
    expect(src).toMatch(/trialEligible\s*\?\s*\{\s*trial_period_days:\s*14\s*\}/);
    // eligibility considers both the trialUsed flag and account age
    const fn = src.slice(src.indexOf('isTrialEligible'));
    expect(fn).toMatch(/trialUsed/);
    expect(fn).toMatch(/ageDays\s*>\s*14/);
  });
});
