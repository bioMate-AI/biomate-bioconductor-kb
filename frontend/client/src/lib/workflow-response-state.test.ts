import { describe, expect, it } from 'vitest';
import { awaitsWorkflowInput, hasGeneratedWorkflow } from './workflow-response-state';

describe('workflow response state', () => {
  it('never turns explicit failure into generation success', () => {
    expect(hasGeneratedWorkflow({ success: false })).toBe(false);
    expect(hasGeneratedWorkflow({ error: 'missing inputs' })).toBe(false);
    expect(hasGeneratedWorkflow(undefined)).toBe(false);
  });
  it.each([
    [{ workflow_type: 'disambiguation' }, {}],
    [{ success: true, needs_user_feedback: true }, {}],
    [{ success: true }, { needsUserFeedback: true }],
    [{ success: true }, { intentClarification: { candidates: [{ id: 'a' }] } }],
    [{ success: true }, { paramClarifications: [{ param: 'matrix' }] }],
  ])('keeps a typed question out of executable workflow presentation', (workflow, metadata) => {
    expect(awaitsWorkflowInput(workflow, metadata)).toBe(true);
    expect(hasGeneratedWorkflow(workflow, metadata)).toBe(false);
  });
  it('accepts an actual workflow after clarification is resolved', () => {
    expect(hasGeneratedWorkflow({ success: true, steps: {} }, { paramClarifications: [] })).toBe(true);
    expect(hasGeneratedWorkflow({ steps: {} })).toBe(true);
    expect(hasGeneratedWorkflow({ nextflow_path: 'pipeline/main.nf', needs_user_feedback: true })).toBe(true);
  });

  // A chain/pipeline turn is a real proposal (its steps live in chain_steps / pipeline_steps, not
  // `steps`). It must classify as a generated workflow so the right-hand panel rebinds to it
  // instead of silently keeping the previous single workflow (2026-11-12 panel-stale bug).
  it('treats a chain / pipeline as a generated proposal, not awaiting-input', () => {
    expect(awaitsWorkflowInput({ success: true, workflow_type: 'chain', chain_steps: [{ id: 1 }] })).toBe(false);
    expect(hasGeneratedWorkflow({ success: true, workflow_type: 'chain', chain_steps: [{ id: 1 }] })).toBe(true);
    expect(hasGeneratedWorkflow({ success: true, workflow_type: 'pipeline', pipeline_steps: [{ id: 1 }] })).toBe(true);
    // Even when the chain carries a generic needs_user_feedback flag (its inputs still need
    // mapping), it is a proposal to show — not an "awaiting input" non-workflow turn.
    expect(hasGeneratedWorkflow({ success: true, workflow_type: 'chain', chain_steps: [{ id: 1 }], needs_user_feedback: true })).toBe(true);
    // A real disambiguation still blocks, chain or not.
    expect(hasGeneratedWorkflow({ workflow_type: 'disambiguation', chain_steps: [{ id: 1 }] })).toBe(false);
  });
});
