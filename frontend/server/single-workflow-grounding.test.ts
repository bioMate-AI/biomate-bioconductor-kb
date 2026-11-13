import { describe, it, expect } from 'vitest';
import {
  isSingleBoundWorkflow,
  singleWorkflowGroundingDirective,
} from './single-workflow-grounding';

describe('isSingleBoundWorkflow', () => {
  it('is true for a plain workflow_ga payload', () => {
    expect(
      isSingleBoundWorkflow({
        success: true,
        workflow_ga: { name: 'Admet Pred' },
      }),
    ).toBe(true);
  });

  it('is false for chain / pipeline / cryosparc payloads', () => {
    expect(isSingleBoundWorkflow({ workflow_type: 'chain', workflow_ga: { name: 'x' } })).toBe(false);
    expect(isSingleBoundWorkflow({ workflow_type: 'pipeline', pipeline_steps: [{}, {}] })).toBe(false);
    expect(isSingleBoundWorkflow({ chain_name: 'Library Triage', chain_steps: [{}] })).toBe(false);
    expect(isSingleBoundWorkflow({ workflow_type: 'cryosparc' })).toBe(false);
  });

  it('is false when unbound or errored', () => {
    expect(isSingleBoundWorkflow(null)).toBe(false);
    expect(isSingleBoundWorkflow({ error: 'fail', workflow_ga: { name: 'x' } })).toBe(false);
    expect(isSingleBoundWorkflow({ success: true })).toBe(false);
  });
});

describe('singleWorkflowGroundingDirective', () => {
  it('constrains single-workflow replies away from fake multi-step chains', () => {
    const d = singleWorkflowGroundingDirective(
      { success: true, workflow_ga: { name: 'Admet Pred' } },
      'Admet Pred',
    );
    expect(d).toMatch(/ENGINE-BOUND SINGLE WORKFLOW/);
    expect(d).toMatch(/Admet Pred/);
    expect(d).toMatch(/Do NOT narrate a multi-step composite pipeline/);
    expect(d).not.toMatch(/force real chain/i);
  });

  it('returns empty for a real chain payload (no constraint — chain composition owns that path)', () => {
    expect(
      singleWorkflowGroundingDirective({
        workflow_type: 'chain',
        chain_steps: [{ name: 'dock' }, { name: 'admet' }],
      }),
    ).toBe('');
  });
});
