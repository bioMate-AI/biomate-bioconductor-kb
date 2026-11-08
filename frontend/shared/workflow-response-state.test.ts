import { describe, expect, it } from 'vitest';
import { hasPendingWorkflowClarification } from './workflow-response-state';
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
