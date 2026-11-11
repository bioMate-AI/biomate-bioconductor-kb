import { describe, expect, it } from 'vitest';
import { formatRunTime, runStatusLabel, TERMINAL_STATUSES } from './training-logic';

describe('训练运行 row formatting', () => {
  it('labels an interrupted run as interrupted (terminal), never as queued', () => {
    expect(runStatusLabel('interrupted')).not.toBe(runStatusLabel('queued'));
    expect(TERMINAL_STATUSES.has('interrupted')).toBe(true);
    expect(runStatusLabel('some-new-state')).not.toBe(runStatusLabel('queued'));
  });

  it('formats the ISO run time as a local date-time, not the raw string', () => {
    const out = formatRunTime('2026-11-11T07:24:09.433Z', 'zh');
    expect(out).not.toContain('T07:24');
    expect(out).toMatch(/2026/);
    expect(formatRunTime('not a date', 'en')).toBe('not a date');
  });
});
