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
});
