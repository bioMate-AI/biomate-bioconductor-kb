/**
 * UX Telemetry - Minimal event emission for funnel analytics.
 *
 * Emits structured events with correlation IDs (sessionId, runId, workflowId).
 * Events are sent to /api/telemetry/events when available; otherwise logged in dev.
 */

export type UxEventName =
  | 'chat.prompt_submitted'
  | 'chat.suggestion_clicked'
  | 'workflow.generated'
  | 'workflow.run_clicked'
  | 'workflow.run_switched'
  | 'workflow.background_action_selected'
  | 'workflow.prereq_recovery_requested'
  | 'workflow.low_confidence_override_clicked'
  | 'workflow.low_confidence_auto_proceeded'
  | 'workflow.status_changed'
  | 'workflow.error_shown'
  | 'workflow.confusion_signal'
  | 'workflow.pause_clicked'
  | 'workflow.resume_clicked'
  | 'async.retry_clicked'
  | 'async.report_issue_clicked'
  | 'output.panel_opened'
  | 'output.download_clicked'
  | 'output.visualization_opened'
  | 'feedback.submitted';

export interface UxEventPayload {
  /** Chat/session correlation */
  sessionId?: string;
  /** Execution run ID */
  runId?: string;
  /** Workflow or invocation ID */
  workflowId?: string;
  /** Invocation ID (Galaxy) */
  invocationId?: string;
  /** Correlation ID for request tracing */
  correlationId?: string;
  /** Event-specific payload */
  [key: string]: unknown;
}

export interface UxEventEnvelope {
  event: UxEventName;
  timestamp: string;
  payload: UxEventPayload;
}

let sessionIdStorage: string | null = null;

/** Get or create a persistent session ID for the browser tab */
export function getOrCreateSessionId(): string {
  if (typeof window === 'undefined') return '';
  if (sessionIdStorage) return sessionIdStorage;
  const key = 'biomate_ux_session_id';
  let id = sessionStorage.getItem(key);
  if (!id) {
    id = `sess_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;
    sessionStorage.setItem(key, id);
  }
  sessionIdStorage = id;
  return id;
}

/**
 * Emit a UX telemetry event. Fire-and-forget; never throws.
 */
export function emitUxEvent(event: UxEventName, payload: UxEventPayload = {}): void {
  const envelope: UxEventEnvelope = {
    event,
    timestamp: new Date().toISOString(),
    payload: {
      ...payload,
      sessionId: payload.sessionId ?? getOrCreateSessionId(),
    },
  };

  if (typeof window === 'undefined') return;

  // Fire-and-forget to backend
  fetch('/api/telemetry/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(envelope),
    keepalive: true,
  }).catch(() => {
    // Silently ignore network errors; dev fallback below
  });

  if (import.meta.env?.DEV) {
    console.debug('[UX Telemetry]', event, envelope.payload);
  }
}
