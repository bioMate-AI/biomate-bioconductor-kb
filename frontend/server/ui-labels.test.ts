import { describe, expect, it } from 'vitest';
import { runButtonLabel } from './ui-labels';
import en from '../client/src/locales/en/common.json';
import zh from '../client/src/locales/zh/common.json';

// A reply must name the button exactly as the panel renders it.
describe('runButtonLabel', () => {
  it('matches the client locale bundles', () => {
    expect(runButtonLabel('zh')).toBe((zh as any).workflow.actions.confirm_and_run);
    expect(runButtonLabel('en')).toBe((en as any).workflow.actions.confirm_and_run);
    expect(runButtonLabel('zh')).toBe('确认并运行');
    expect(runButtonLabel(undefined)).toBe(runButtonLabel('en'));
  });
});
