import { describe, it, expect, afterEach } from 'vitest';
import {
  OPERATION_SKILLS,
  operationSkillsEnabled,
  renderOperationSkillsBlock,
} from './operation-skills';

describe('operation-skills registry', () => {
  const prev = process.env.OPERATION_SKILLS_IN_DECOMP;
  afterEach(() => {
    if (prev === undefined) delete process.env.OPERATION_SKILLS_IN_DECOMP;
    else process.env.OPERATION_SKILLS_IN_DECOMP = prev;
  });

  it('includes the generator-adaptation operation skill with all contract fields', () => {
    const gen = OPERATION_SKILLS.find(s => s.name === 'generator-adaptation');
    expect(gen).toBeTruthy();
    expect(gen!.whenToUse).toMatch(/adapt|fine-tune|generative/i);
    expect(gen!.shape).toMatch(/single/i);
    expect(gen!.route).toMatch(/ml_training|Models/i);
    expect(gen!.presentation).toMatch(/model-version card/i);
    expect(gen!.notThis).toMatch(/dock|ADMET/i);
  });

  it('is INERT by default — no flag ⇒ empty block (cannot change live routing)', () => {
    delete process.env.OPERATION_SKILLS_IN_DECOMP;
    expect(operationSkillsEnabled()).toBe(false);
    expect(renderOperationSkillsBlock()).toBe('');
  });

  it('renders the operation-skills section only when the flag is on', () => {
    process.env.OPERATION_SKILLS_IN_DECOMP = '1';
    expect(operationSkillsEnabled()).toBe(true);
    const block = renderOperationSkillsBlock();
    expect(block).toContain('Operation skills');
    expect(block).toContain('generator-adaptation');
    expect(block).toContain('model-version card');
    // It must steer AWAY from the drug-discovery fan-out template.
    expect(block).toMatch(/do NOT force into the drug-discovery/i);
  });

  it('any other flag value stays inert', () => {
    process.env.OPERATION_SKILLS_IN_DECOMP = 'true';
    expect(renderOperationSkillsBlock()).toBe('');
  });
});
