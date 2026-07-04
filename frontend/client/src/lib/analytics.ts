/**
 * BioMate Analytics — dual-sink telemetry
 *
 * Every track() call fans out to two sinks:
 *   1. BioMate's own backend (POST /api/telemetry/event) — full event payload,
 *      durable in our own database, available for analyses we own end-to-end.
 *   2. Google Analytics 4 (window.gtag, see frontend/client/index.html) — for
 *      funnel + acquisition reports in the GA4 console. Skipped automatically
 *      on hosts that don't have gtag loaded (localhost, E2E, dev without GA),
 *      so this never adds risk in non-prod environments.
 *
 * GA4 event names share BioMate's snake_case taxonomy verbatim (workflow_started,
 * qc_failed, etc.). When adding a new event, the AnalyticsEvent union below is
 * the single source of truth — type-checked at every call site.
 *
 * Usage:
 *   import { analytics } from '@/lib/analytics';
 *   analytics.track('workflow_started', { domain: 'rnaseq', steps: 8 });
 */

declare global {
  interface Window {
    gtag?: (command: string, ...args: unknown[]) => void;
    dataLayer?: unknown[];
  }
}

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
  | 'workflow_chain_started'
  | 'workflow_chain_failed'
  | 'workflow_pipeline_started'
  | 'workflow_pipeline_failed'
  | 'workflow_pipeline_step_approved'
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
  | 'api_key_configured'
  | 'pipeline_started'
  // Gap 2 — chat-driven workflow edits
  | 'workflow_edit_applied'
  | 'workflow_edit_undone'
  | 'workflow_edit_confirm_required'
  // Gap 3 / Gap 4 — run reuse
  | 'run_again_clicked'
  | 'reset_to_defaults_clicked'
  | 'workflows_sidebar_opened'
  | 'import_workflow_opened'
  | 'personal_workflow_opened'
  | 'workflow_imported';

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
  // Gap 2 / 3 / 4 properties
  op?: 'set_param' | 'add_step' | 'remove_step' | 'reorder';
  via?: 'rule_extractor' | 'llm_extractor' | 'assistant_emit';
  source?: 'panel' | 'sidebar_history';
  workflow_name?: string;
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

  // Sink 1: fire-and-forget POST to BioMate backend
  fetch('/api/telemetry/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    // keepalive ensures the request completes even if the page navigates away
    keepalive: true,
  }).catch(() => {
    // Silently ignore — analytics must never affect UX
  });

  // Sink 2: GA4 via gtag (only fires on hosts where the static loader in
  // frontend/client/index.html called gtag('config', …) — i.e. prod app +
  // dev-public + marketing site, NOT localhost / E2E).
  try {
    if (typeof window !== 'undefined' && typeof window.gtag === 'function') {
      // GA4 caps custom event names + param keys: snake_case, ≤40 chars,
      // no leading underscore. BioMate's existing names already comply.
      window.gtag('event', event, properties || {});
    }
  } catch {
    // gtag failures must never affect UX
  }
}

function identify(userId: string, traits?: { plan?: string; email?: string; name?: string }): void {
  _userId = userId;
  _userTraits = {
    plan: traits?.plan,
  };
  // GA4 user attribution: gtag('set') merges into the global config so every
  // subsequent event is attributed to this user_id. We don't pass email/name
  // — those are PII and GA4 rejects unhashed PII in user_id anyway. The
  // BioMate backend has the full traits already via the sink-1 POST below.
  try {
    if (typeof window !== 'undefined' && typeof window.gtag === 'function') {
      window.gtag('set', { user_id: userId });
      if (traits?.plan) {
        // Custom user property for GA4 segmentation by plan tier.
        window.gtag('set', 'user_properties', { plan: traits.plan });
      }
    }
  } catch {
    // gtag failures must never affect UX
  }
  // Record the identify event itself
  track('user_logged_in', { userId });
}

function reset(): void {
  _userId = undefined;
  _userTraits = {};
  // Clear the GA4 user binding so post-logout events aren't attributed to
  // the previous user. Sending user_id: undefined clears it server-side.
  try {
    if (typeof window !== 'undefined' && typeof window.gtag === 'function') {
      window.gtag('set', { user_id: undefined });
    }
  } catch {
    // gtag failures must never affect UX
  }
}

export const analytics = { track, identify, reset };
