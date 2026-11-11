import { describe, expect, it } from 'vitest';
import { decideWorkflowReplyState, hasPendingWorkflowClarification } from './workflow-response-state';
describe('execution clarification boundary', () => {
  it('blocks outstanding typed input and candidate questions', () => {
    expect(hasPendingWorkflowClarification({ workflow_type: 'disambiguation' })).toBe(true);
    expect(hasPendingWorkflowClarification({}, { paramClarifications: [{ param: 'matrix' }] })).toBe(true);
    expect(hasPendingWorkflowClarification({}, { intentClarification: { candidates: [{ id: 'a' }] } })).toBe(true);
    expect(hasPendingWorkflowClarification({ needs_user_feedback: true, candidate_workflows: [{ id: 'a' }] })).toBe(true);
  });
  it('allows a resolved proposal to reach the separate input and confidence gates', () => {
    expect(hasPendingWorkflowClarification({ workflow_type: 'nextflow', needs_user_feedback: true }, { paramClarifications: [] })).toBe(false);
    expect(hasPendingWorkflowClarification({ workflow_type: 'nextflow' }, { intentClarification: null })).toBe(false);
  });
});

describe('workflow reply state (selected in code, not by the model)', () => {
  const base = { isWorkflowTurn: true, runnableWorkflow: true, generationFailed: false, hasInlineData: false, messageCarriesData: false, unboundRequiredInputs: [] as unknown[] };
  it('generated workflow with its required data input unbound → generated_needs_input (never "could not generate")', () => {
    expect(decideWorkflowReplyState({ ...base, unboundRequiredInputs: [{ name: 'input' }] })).toBe('generated_needs_input');
    // Inline non-data (e.g. a genome build) does not make the samplesheet bound.
    expect(decideWorkflowReplyState({ ...base, hasInlineData: true, unboundRequiredInputs: [{ name: 'input' }] })).toBe('generated_needs_input');
  });
  it('generated workflow with inputs bound, or data in the message → generated_ready', () => {
    expect(decideWorkflowReplyState(base)).toBe('generated_ready');
    expect(decideWorkflowReplyState({ ...base, messageCarriesData: true, unboundRequiredInputs: [{ name: 'input' }] })).toBe('generated_ready');
  });
  it('real generation failures keep their existing formats', () => {
    const failed = { ...base, runnableWorkflow: false, generationFailed: true };
    expect(decideWorkflowReplyState(failed)).toBe('clarification_needed');
    expect(decideWorkflowReplyState({ ...failed, hasInlineData: true })).toBe('technical_failure');
    expect(decideWorkflowReplyState({ ...failed, isWorkflowTurn: false })).toBe('other');
  });
});
