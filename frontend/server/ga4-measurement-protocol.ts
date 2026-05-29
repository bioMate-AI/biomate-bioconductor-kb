/**
 * GA4 Measurement Protocol — server-side event emission.
 *
 * Use this for events that happen without a browser session, e.g.:
 *   - AWS Batch job completes hours after the user closed the tab
 *   - Run failure detected by the Node poller
 *   - Billing thresholds crossed by a backend webhook
 *
 * These can't go through window.gtag (no window), so we POST directly to
 * GA4's Measurement Protocol endpoint. Same data lands in the same property
 * as the client-side gtag pipeline, just dispatched from a different sink.
 *
 * Activation:
 *   Set GA4_PROD_API_SECRET and/or GA4_DEV_API_SECRET in env. The secret
 *   is per-property: GA4 Admin → Data Streams → choose stream → Measurement
 *   Protocol API Secrets → Create. Without the secret this module is a no-op
 *   — calls return silently so missing config never breaks an upstream flow.
 *
 * Property routing follows the same map as frontend/client/index.html:
 *   - measurement_id = 'G-65JDDPEDQ5' uses GA4_PROD_API_SECRET
 *   - measurement_id = 'G-8YG54DFHQG' uses GA4_DEV_API_SECRET
 *
 * Doc: docs/20260527_GOOGLE_ANALYTICS_SETUP.md
 */

const PROD_MEASUREMENT_ID = 'G-65JDDPEDQ5';
const DEV_MEASUREMENT_ID = 'G-8YG54DFHQG';

const ENDPOINT = 'https://www.google-analytics.com/mp/collect';

export interface MPEvent {
  /** Event name. Same snake_case taxonomy as analytics.ts (workflow_completed, etc.) */
  name: string;
  /** Free-form params. Cap: 25 params per event, ≤100 chars per key, ≤500 per value. */
  params?: Record<string, unknown>;
}

interface DispatchOptions {
  /**
   * client_id is required by GA4. For backend-only events tied to a user, pass
   * the user's id here (or a hash of it). Without it GA4 drops the event.
   * Fallback: a synthetic stable string for non-user backend processes.
   */
  clientId: string;
  /** If known, lets GA4 join the server event to the user's existing session. */
  userId?: string;
  /** Which property to send to. */
  target: 'prod' | 'dev';
}

function resolveSecret(target: 'prod' | 'dev'): { measurementId: string; apiSecret: string } | null {
  if (target === 'prod') {
    const apiSecret = process.env.GA4_PROD_API_SECRET;
    if (!apiSecret) return null;
    return { measurementId: PROD_MEASUREMENT_ID, apiSecret };
  }
  const apiSecret = process.env.GA4_DEV_API_SECRET;
  if (!apiSecret) return null;
  return { measurementId: DEV_MEASUREMENT_ID, apiSecret };
}

/**
 * Send one or more events to GA4 via the Measurement Protocol.
 *
 * No-op when the matching GA4_*_API_SECRET env var is unset. Network failures
 * are caught and logged at debug level so analytics never breaks a flow.
 *
 * Returns a promise that resolves once the POST settles; callers can ignore
 * it (fire-and-forget) since the result is never user-facing.
 */
export async function sendMPEvents(
  events: MPEvent[],
  opts: DispatchOptions,
): Promise<void> {
  if (events.length === 0) return;
  const resolved = resolveSecret(opts.target);
  if (!resolved) return; // No API secret configured for this target — silent no-op.

  const url = `${ENDPOINT}?measurement_id=${encodeURIComponent(resolved.measurementId)}&api_secret=${encodeURIComponent(resolved.apiSecret)}`;
  const body: Record<string, unknown> = {
    client_id: opts.clientId,
    events: events.map((e) => ({ name: e.name, params: e.params || {} })),
  };
  if (opts.userId) body.user_id = opts.userId;

  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    // eslint-disable-next-line no-console
    console.debug('[ga4-mp] dispatch failed:', (e as any)?.message || e);
  }
}

/**
 * Convenience wrapper that picks the target by the request's hostname so the
 * routing matches frontend/client/index.html. Same rules:
 *   - app.biomate.ai / *.app.biomate.ai / biomate.ai → prod
 *   - dev-public.biomate.ai / *.dev-public.biomate.ai → dev
 *   - anything else → no-op (returns false)
 *
 * Returns true if the event was dispatched, false if skipped (no API secret
 * for the resolved target, or hostname doesn't match any known env).
 */
export async function sendMPEventForHost(
  host: string | undefined,
  event: MPEvent,
  opts: { clientId: string; userId?: string },
): Promise<boolean> {
  if (!host) return false;
  let target: 'prod' | 'dev' | null = null;
  if (host === 'biomate.ai' || host === 'www.biomate.ai'
      || host === 'app.biomate.ai' || host === 'www.app.biomate.ai'
      || host.endsWith('.app.biomate.ai')) {
    target = 'prod';
  } else if (host === 'dev-public.biomate.ai' || host.endsWith('.dev-public.biomate.ai')) {
    target = 'dev';
  }
  if (!target) return false;
  const resolved = resolveSecret(target);
  if (!resolved) return false;
  await sendMPEvents([event], { ...opts, target });
  return true;
}
