import type { Message } from '@shared/schema';

export interface WorkflowProgressEvent {
  kind: string;
  friendly_message: string;
  ts?: number;
  technical?: any;
  invocationId?: string;
  /** Durable producer/SSE identity, retained unchanged through replay. */
  eventId?: string;
}

export function workflowProgressMessageId(event: WorkflowProgressEvent): string {
  return event.eventId
    ? `progress-event-${encodeURIComponent(event.invocationId ?? 'inv')}-${encodeURIComponent(event.eventId)}`
    : `progress-${event.invocationId ?? 'inv'}-${event.kind}-${event.ts ?? Date.now()}`;
}

export function hasWorkflowProgressEvent(messages: Message[], event: WorkflowProgressEvent, messageId: string): boolean {
  return messages.some(message => message.id === messageId || (!!event.eventId
    && message.metadata?.type === 'workflow_progress'
    && message.invocationId === event.invocationId
    && (message.metadata as any)?.eventId === event.eventId));
}
