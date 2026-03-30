/**
 * UX Feedback API and types
 * Submits feedback to POST /api/feedback
 * Reason tags aligned with backend canonical taxonomy in shared/schema.ts
 */

import { emitUxEvent } from '@/lib/ux-telemetry';
import { UX_FEEDBACK_ENABLED } from '@/lib/feature-flags';

/** Canonical reason tags from backend schema - submit these values to API */
export const FEEDBACK_REASON_TAGS = [
  'unclear_output',
  'wrong_tool',
  'slow',
  'confusing_ui',
  'missing_feature',
  'error_not_helpful',
  'workflow_failed',
  'other',
] as const;

export type FeedbackReasonTag = (typeof FEEDBACK_REASON_TAGS)[number];

/** User-friendly display labels for reason tags */
export const FEEDBACK_REASON_LABELS: Record<FeedbackReasonTag, string> = {
  unclear_output: 'Unclear output',
  wrong_tool: 'Wrong tool suggested',
  slow: 'Too slow',
  confusing_ui: 'Confusing UI',
  missing_feature: 'Missing feature',
  error_not_helpful: 'Error message not helpful',
  workflow_failed: 'Workflow failed',
  other: 'Other',
};

export type FeedbackType =
  | 'inline'
  | 'post_run'
  | 'confusion_report'
  | 'download_check'
  | 'session_pulse';

export interface FeedbackPayload {
  feedback_type: FeedbackType;
  /** Thumbs up/down for inline feedback */
  rating?: 'up' | 'down';
  /** Required for downvote inline feedback */
  reason_tags?: FeedbackReasonTag[];
  comment?: string;
  /** Context for correlation */
  message_id?: string;
  session_id?: string;
  run_id?: string;
  invocation_id?: string;
  workflow_id?: string;
  output_id?: string;
  /** Post-run: run outcome state */
  run_status?: 'completed' | 'failed' | 'cancelled';
  /** Workflow name for display context */
  workflow_name?: string;
  /** Post-run: micro-survey answers */
  execution_clear?: boolean;
  outputs_match_expectation?: boolean;
  download_visualization_easy?: boolean;
  /** Pilot evaluation KPI fields */
  qc_publication_rating?: number;
  ran_without_manual_correction?: boolean;
  prior_time_hours?: number;
  pricing_response?: string;
  submitted_at?: string;
  /** Download check: did user get expected file(s)? */
  download_success?: boolean;
  /** UI context snapshot */
  ui_context?: Record<string, unknown>;
}

export interface FeedbackResponse {
  success: boolean;
  id?: string;
  error?: string;
}

export async function submitFeedback(payload: FeedbackPayload): Promise<FeedbackResponse> {
  if (!UX_FEEDBACK_ENABLED) {
    return { success: true };
  }

  const response = await fetch('/api/feedback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ message: response.statusText }));
    return { success: false, error: err.message || err.error || 'Failed to submit feedback' };
  }

  const result = await response.json();
  emitUxEvent('feedback.submitted', {
    sessionId: payload.session_id,
    runId: payload.run_id,
    workflowId: payload.workflow_id,
    invocationId: payload.invocation_id,
    feedbackType: payload.feedback_type,
    rating: payload.rating,
  });
  return result;
}
