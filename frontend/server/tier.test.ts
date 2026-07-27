import { describe, it, expect } from 'vitest';
import { canonicalTier, meetsTier, canCollaborate, FREE_PROJECT_LIMIT } from './tier';

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
