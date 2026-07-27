import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { canonicalTier, meetsTier, canCollaborate, FREE_PROJECT_LIMIT } from './tier';

// Source-level contract: the gates are wired into project-routes AND guarded by
// the enforcement flag (so they can't silently drop or become always-on).
describe('tier gate wiring (project-routes.ts)', () => {
  const src = readFileSync(join(__dirname, 'project-routes.ts'), 'utf8');
  it('collaboration gate is called on all 3 collaboration endpoints', () => {
    const calls = src.match(/blockedByCollaborationTier\(req, res\)\) return/g) ?? [];
    expect(calls.length).toBe(3); // share-link, members invite, role change
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
