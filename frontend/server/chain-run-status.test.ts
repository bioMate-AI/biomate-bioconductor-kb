import { describe, expect, it } from 'vitest';
import { classifyChainRunStatus } from './chain-run-status';
import { executionRunStatusSchema } from '../shared/schema';

describe('chain to Run Manager status contract', () => {
  it.each(['partial', 'blocked', 'failed', 'error'])('makes %s terminal and unsuccessful with an explanation', status => {
    const result = classifyChainRunStatus(status);
    expect(result.status).toBe('failed');
    expect(result.terminal).toBe(true);
    expect(result.errorMessage).toBeTruthy();
    expect(executionRunStatusSchema.safeParse(result.status).success).toBe(true);
  });
  it('explains partial completion without claiming all outputs are invalid', () => {
    expect(classifyChainRunStatus('partial').errorMessage).toMatch(/partially completed/);
  });
  it.each(['succeeded', 'completed'])('maps %s to successful completion', raw => {
    expect(classifyChainRunStatus(raw)).toEqual({ status: 'completed', terminal: true });
  });
  it.each(['canceled', 'cancelled'])('makes %s terminal without reporting success', raw => {
    expect(classifyChainRunStatus(raw)).toEqual({ status: 'cancelled', terminal: true });
  });
  it('keeps approval resumable and allows the resumed state to become running', () => {
    expect(classifyChainRunStatus('awaiting_approval')).toEqual({ status: 'paused', terminal: false });
    expect(classifyChainRunStatus('running')).toEqual({ status: 'running', terminal: false });
  });
});
