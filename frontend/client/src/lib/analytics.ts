/**
 * BioMate Analytics — self-hosted telemetry
 *
 * Sends events to BioMate's own backend (POST /api/telemetry/event).
 * No third-party dependency. All data stays in the platform's database.
 *
 * Usage:
 *   import { analytics } from '@/lib/analytics';
 *   analytics.track('workflow_started', { domain: 'rnaseq', steps: 8 });
 */

const IS_DEV = import.meta.env.DEV;

// ── Event type definitions ────────────────────────────────────
export type AnalyticsEvent =
  | 'page_viewed'
  | 'user_registered'
  | 'user_logged_in'
  | 'user_logged_out'
  | 'query_sent'
  | 'clarification_answered'
  | 'workflow_suggested'
  | 'workflow_started'
  | 'pilot_run_started'
  | 'pilot_run_skipped'
  | 'workflow_completed'
  | 'workflow_failed'
  | 'workflow_cancelled'
  | 'qc_passed'
  | 'qc_failed'
  | 'qc_warning'
  | 'qc_report_exported'
  | 'compute_settings_changed'
  | 'subscription_page_viewed'
  | 'checkout_started'
  | 'subscription_upgraded'
  | 'tool_searched'
  | 'dataset_uploaded'
  | 'settings_opened'
  | 'api_key_configured';

export interface AnalyticsProperties {
  userId?: string;
  plan?: string;
  domain?: string;
  workflow_steps?: number;
  execution_engine?: 'galaxy' | 'nextflow';
  qc_profile?: string;
  total_samples?: number;
  invocation_id?: string;
  gates_failed?: number;
  gates_advisory?: number;
  failing_step?: string;
  query_length?: number;
  page?: string;
  error?: string;
  [key: string]: string | number | boolean | undefined;
}

// Current user identity (set by identify(), included in all subsequent events)
let _userId: string | undefined;
let _userTraits: Record<string, string | undefined> = {};

function track(event: AnalyticsEvent, properties?: AnalyticsProperties): void {
  const payload = {
    event,
    properties: {
      ...properties,
      ..._userTraits,
      userId: properties?.userId ?? _userId,
      timestamp: new Date().toISOString(),
      platform: 'web',
    },
  };

  if (IS_DEV) {
    console.debug('[analytics]', event, payload.properties);
  }

  // Fire-and-forget POST to backend — never await, never throw
  fetch('/api/telemetry/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    // keepalive ensures the request completes even if the page navigates away
    keepalive: true,
  }).catch(() => {
    // Silently ignore — analytics must never affect UX
  });
}

function identify(userId: string, traits?: { plan?: string; email?: string; name?: string }): void {
  _userId = userId;
  _userTraits = {
    plan: traits?.plan,
  };
  // Record the identify event itself
  track('user_logged_in', { userId });
}

function reset(): void {
  _userId = undefined;
  _userTraits = {};
}

export const analytics = { track, identify, reset };
