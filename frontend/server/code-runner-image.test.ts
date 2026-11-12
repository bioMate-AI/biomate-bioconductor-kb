import { afterEach, describe, expect, it } from 'vitest';
import { RUN_CODE_BASE_IMAGE, RUN_CODE_PREFERRED_IMAGE, _resetSandboxImage, resolveSandboxImage } from './code-runner';

afterEach(() => { _resetSandboxImage(); delete process.env.RUN_CODE_IMAGE; });

describe('run_code sandbox image (CJK fonts for plot labels, founder 2026-11-12)', () => {
  it('uses the CJK-font image when the host has it', async () => {
    expect(await resolveSandboxImage(async (img) => img === RUN_CODE_PREFERRED_IMAGE)).toBe(RUN_CODE_PREFERRED_IMAGE);
  });
  it('falls back to the base image when it is missing', async () => {
    expect(await resolveSandboxImage(async () => false)).toBe(RUN_CODE_BASE_IMAGE);
  });
  it('RUN_CODE_IMAGE always wins', async () => {
    process.env.RUN_CODE_IMAGE = 'custom:1';
    expect(await resolveSandboxImage(async () => true)).toBe('custom:1');
  });
});
