/**
 * Locks the evidence-based pathology wording in the assistant catalog.
 * MCMICRO has a generated wrapper but no verified BioMate runtime path, so
 * presenting it as a runnable workflow would turn catalog text into a false
 * scientific capability claim.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const SOURCE = readFileSync(join(__dirname, 'galaxy-assistant.ts'), 'utf8');

describe('pathology / WSI capability claim guard', () => {
  it('does not advertise MCMICRO as a runnable BioMate workflow', () => {
    expect(SOURCE).toContain('MCMICRO for CODEX, CyCIF, and MIBI is a candidate integration under validation');
    expect(SOURCE).toContain('not a currently runnable BioMate workflow');
    expect(SOURCE).not.toContain('nf-core/mcmicro (multiplexed tissue imaging');
  });

  it('does not promise unsupported whole-slide pathology analysis', () => {
    expect(SOURCE).toContain('Do not promise whole-slide pathology analysis');
  });
});
