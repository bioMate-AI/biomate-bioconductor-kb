import { describe, expect, it } from 'vitest';
import { IND_REPORT_ENABLED } from './feature-flags';

// IND Report is paused (2026-11-04): it must stay off unless VITE_ENABLE_IND_REPORT === "true".
// Every IND entry point (sidebar, /ind-report route, chat handoff chip, roll-into-IND affordance)
// keys off this one flag.
describe('IND_REPORT_ENABLED', () => {
  it('is off by default', () => {
    expect(import.meta.env.VITE_ENABLE_IND_REPORT).not.toBe('true');
    expect(IND_REPORT_ENABLED).toBe(false);
  });
});
