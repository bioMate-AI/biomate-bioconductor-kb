/**
 * BioMate Analytics
 * Thin wrapper around Mixpanel. No-ops gracefully when VITE_MIXPANEL_TOKEN is absent.
 *
 * Usage:
 *   import { analytics } from '@/lib/analytics';
 *   analytics.track('workflow_started', { domain: 'rnaseq', steps: 8 });
 */
import mixpanel from 'mixpanel-browser';

const TOKEN = import.meta.env.VITE_MIXPANEL_TOKEN as string | undefined;
const IS_DEV = import.meta.env.DEV;
const ENABLED = !!TOKEN;

if (ENABLED) {
  mixpanel.init(TOKEN!, {
    debug: IS_DEV,
    track_pageview: true,
    persistence: 'localStorage',
    ignore_dnt: false,
  });
}

// ── Event type definitions ────────────────────────────────────
export type AnalyticsEvent =
  // Onboarding
  | 'page_viewed'
  | 'user_registered'
  | 'user_logged_in'
  | 'user_logged_out'
  // Chat / queries
  | 'query_sent'
  | 'clarification_answered'
  | 'workflow_suggested'
  // Workflow lifecycle
  | 'workflow_started'
  | 'pilot_run_started'
  | 'pilot_run_skipped'
  | 'workflow_completed'
  | 'workflow_failed'
  | 'workflow_cancelled'
  // QC
  | 'qc_passed'
  | 'qc_failed'
  | 'qc_warning'
  | 'qc_report_exported'
  // Compute
  | 'compute_settings_changed'
  // Billing
  | 'subscription_page_viewed'
  | 'checkout_started'
  | 'subscription_upgraded'
  // Tools
  | 'tool_searched'
  | 'dataset_uploaded'
  // Settings
  | 'settings_opened'
  | 'api_key_configured';

export interface AnalyticsProperties {
  // Common
  userId?: string;
  plan?: string;
  // Workflow props
  domain?: string;
  workflow_steps?: number;
  execution_engine?: 'galaxy' | 'nextflow';
  qc_profile?: string;
  total_samples?: number;
  invocation_id?: string;
  // QC props
  gates_failed?: number;
  gates_advisory?: number;
  failing_step?: string;
  // Query props
  query_length?: number;
  // Generic
  [key: string]: string | number | boolean | undefined;
}

function track(event: AnalyticsEvent, properties?: AnalyticsProperties): void {
  if (!ENABLED) {
    if (IS_DEV) console.debug('[analytics]', event, properties);
    return;
  }
  try {
    mixpanel.track(event, properties);
  } catch (e) {
    // Never let analytics crash the app
  }
}

function identify(userId: string, traits?: { plan?: string; email?: string; name?: string }): void {
  if (!ENABLED) return;
  try {
    mixpanel.identify(userId);
    if (traits) {
      mixpanel.people.set({
        $email: traits.email,
        $name: traits.name,
        plan: traits.plan,
      });
    }
  } catch (e) {}
}

function reset(): void {
  if (!ENABLED) return;
  try { mixpanel.reset(); } catch (e) {}
}

export const analytics = { track, identify, reset };
