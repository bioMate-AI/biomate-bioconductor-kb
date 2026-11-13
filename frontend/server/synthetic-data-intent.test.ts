/**
 * run_code's synthetic-input guard decides from INTENT, not a keyword list (audit round 9, dev
 * 2026-11-12): a zh project chat asked for 示例数据 (an example expr.csv + boxplot + report.md) and
 * run_code was refused twice — `SIMULATION_REQUEST_RE` knew 模拟/合成数据 but not 示例数据, nor
 * English "example data". The intent classifier already read the request ("用户明确要求…直接生成示例
 * CSV"); it now says so in a structured field, `user_requested_synthetic_data`, and the guard uses it.
 * The keyword list remains only as the fallback when no intent is available (the classifier failed
 * or the decomposition is the degraded keyword last resort).
 */
import { describe, it, expect, vi } from 'vitest';

vi.mock('./db', () => ({ db: {}, pool: {} }));
vi.mock('./conversation-state', () => ({
  conversationStateManager: { getState: vi.fn(), setState: vi.fn(), clear: vi.fn() },
}));
vi.mock('./user-patterns-service', () => ({
  userPatternsService: { getUserContext: vi.fn().mockResolvedValue({}) },
}));

import { syntheticDataAllowed } from './execution-integrity';
import { GalaxyAssistant } from './galaxy-assistant';

const parse = (raw: any, msg: string) =>
  (GalaxyAssistant.prototype as any).parseIntentResult.call(Object.create(GalaxyAssistant.prototype), raw, msg);

describe('intent → user_requested_synthetic_data', () => {
  it('is parsed from the classifier output (single and multi intent)', () => {
    expect(parse({ type: 'general_question', user_requested_synthetic_data: true }, 'x').userRequestedSyntheticData).toBe(true);
    expect(parse({ type: 'general_question', user_requested_synthetic_data: false }, 'x').userRequestedSyntheticData).toBe(false);
    expect(parse({ intents: [{ id: 'a', type: 'general_question' }], user_requested_synthetic_data: true }, 'x').userRequestedSyntheticData).toBe(true);
  });
  it('is unknown (undefined) when the classifier did not say', () => {
    expect(parse({ type: 'general_question' }, 'x').userRequestedSyntheticData).toBeUndefined();
  });
});

describe('syntheticDataAllowed', () => {
  it('zh request for example data, intent says synthetic → allowed', () => {
    expect(syntheticDataAllowed(true, '生成一个示例数据 expr.csv，画箱线图，写 report.md')).toBe(true);
  });
  it('"use example data to demo DESeq2", intent says synthetic → allowed', () => {
    expect(syntheticDataAllowed(true, 'use example data to demo DESeq2')).toBe(true);
  });
  it('analysis of the user\'s own data, intent says not synthetic → refused', () => {
    expect(syntheticDataAllowed(false, 'analyze my uploaded counts')).toBe(false);
    // The intent decides even when a word in the message looks like a simulation keyword.
    expect(syntheticDataAllowed(false, 'analyze my uploaded counts from the simulation folder')).toBe(false);
  });
  it('no intent available → the documented keyword fallback', () => {
    expect(syntheticDataAllowed(undefined, 'run a Monte Carlo simulation of the dose curve')).toBe(true);
    expect(syntheticDataAllowed(undefined, 'analyze my uploaded counts')).toBe(false);
  });
});
