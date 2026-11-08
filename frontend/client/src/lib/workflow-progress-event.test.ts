import { describe, expect, it, vi } from 'vitest';
import { hasWorkflowProgressEvent, workflowProgressMessageId } from './workflow-progress-event';

describe('durable workflow progress identity', () => {
  const event = { kind: 'workflow.failed', friendly_message: 'Workflow hit an error', invocationId: 'run-a', eventId: 'event-17' };
  it('deduplicates timestamp-less replay after reload without comparing text', () => {
    const id = workflowProgressMessageId(event);
    vi.spyOn(Date, 'now').mockReturnValue(1234);
    expect(workflowProgressMessageId(event)).toBe(id);
    const persisted = JSON.parse(JSON.stringify([{ id, role: 'assistant', invocationId: 'run-a', metadata: { type: 'workflow_progress', eventId: 'event-17' } }]));
    expect(hasWorkflowProgressEvent(persisted, { ...event, friendly_message: 'Updated wording' }, id)).toBe(true);
    vi.restoreAllMocks();
  });
  it('preserves identical-looking failures belonging to different attempts and runs', () => {
    const id = workflowProgressMessageId(event);
    expect(workflowProgressMessageId({ ...event, eventId: 'event-18' })).not.toBe(id);
    expect(workflowProgressMessageId({ ...event, invocationId: 'run-b' })).not.toBe(id);
  });
  it('retains legacy timestamp identity without rewriting saved records', () => {
    expect(workflowProgressMessageId({ ...event, eventId: undefined, ts: 42 })).toBe('progress-run-a-workflow.failed-42');
  });
});
