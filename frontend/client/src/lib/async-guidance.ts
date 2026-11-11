export interface AsyncGuidance {
  title: string;
  reason: string;
  retry: string;
  escalation: string;
  isTimeout: boolean;
  isNetworkRelated: boolean;
}

function normalizeError(rawError: string | null | undefined): string {
  return (rawError || "").trim();
}

function classifyError(error: string) {
  const lower = error.toLowerCase();
  const isTimeout =
    lower.includes("timeout") ||
    lower.includes("timed out") ||
    lower.includes("deadline exceeded") ||
    lower.includes("etimedout");

  // Only match genuine browser-side network failures.
  // Server-side errors (DB pool exhausted, Galaxy backend unreachable, POSIX codes like
  // ECONNREFUSED / ECONNRESET, PostgreSQL "connection terminated") must NOT trigger
  // "Connection error" — they are internal infrastructure problems unrelated to the
  // user's own network connection. Previously "connection" and standalone "fetch"
  // were included here, which caused DB errors to be misclassified as network errors.
  const isNetworkRelated =
    lower.includes("network") ||        // "The network connection was lost" (iOS Safari)
    lower.includes("failed to fetch") || // Chrome / Edge / Firefox standard error
    lower.includes("load failed");       // iOS Safari: "Load failed"

  return { isTimeout, isNetworkRelated };
}

// Returns a sanitized, user-friendly reason string — strips raw infrastructure details
// (POSIX codes, DB messages, stack traces) that must never be shown to users.
function sanitizeReason(error: string, fallback: string): string {
  const isRawInfraError = /econnrefused|enotfound|econnreset|epipe|pool.*drain|connection terminated|connection refused|could not connect/i.test(error);
  return isRawInfraError ? "The service encountered a temporary issue. Please try again in a moment." : (error || fallback);
}

export function getExecutionAsyncGuidance(
  rawError: string | null | undefined,
  options: { isOnline?: boolean } = {}
): AsyncGuidance {
  const error = normalizeError(rawError);
  const { isTimeout, isNetworkRelated } = classifyError(error);
  // navigator.onLine is unreliable on mobile — use only as supplementary context, not alone.
  const isOnline = options.isOnline ?? true;

  if (isNetworkRelated || (!isOnline && !error)) {
    return {
      title: "Connection issue during execution",
      reason:
        error || "The browser or API connection was interrupted while workflow execution status was being updated.",
      retry:
        "Reconnect network, then retry run actions or refresh execution status from the workflow panel.",
      escalation:
        "If this repeats, report the issue with run ID and timestamp for backend connectivity triage.",
      isTimeout,
      isNetworkRelated: true,
    };
  }

  if (isTimeout) {
    return {
      title: "Execution timed out",
      reason:
        "The workflow did not complete in the expected time window. This usually indicates heavy compute load, large inputs, or a stalled backend runner.",
      retry:
        "Retry after checking input size/parameters and backend load. If this repeats, run a smaller subset first.",
      escalation:
        "Escalate with run ID and timestamp so we can inspect backend logs and executor health.",
      isTimeout: true,
      isNetworkRelated,
    };
  }

  return {
    title: "Execution failed",
    reason: sanitizeReason(error, "The workflow could not be executed due to an unexpected issue."),
    retry:
      "Retry after confirming required inputs, file paths, and parameters are valid. You can rerun directly from the workflow card.",
    escalation:
      "If retry does not work, report confusion so context is attached automatically for triage.",
    isTimeout: false,
    isNetworkRelated,
  };
}

/**
 * Decide whether a workflow-GENERATION failure is a transient hiccup that is
 * worth an automatic client-side retry, versus a deterministic failure that
 * would just fail again (and must be surfaced immediately so the user can act).
 *
 * TRANSIENT (retry): network blip, request timeout, empty/incomplete stream,
 *   server 5xx, rate-limit / overload, generic upstream "temporary" errors.
 * DETERMINISTIC (do NOT retry): HTTP 4xx (400/401/403/404/409/422 — bad input,
 *   auth, validation), clarification/needs-input responses, aborted-by-user.
 *
 * We are deliberately conservative: only classify as transient when we have a
 * positive signal. An unrecognised error is treated as NON-transient so we
 * never retry a real bug into a hang.
 */
export function isTransientChatError(
  error: string | null | undefined,
  opts: { httpStatus?: number | null; aborted?: boolean } = {}
): boolean {
  // User pressed stop — never a retry candidate.
  if (opts.aborted) return false;

  const status = opts.httpStatus ?? null;
  if (status != null) {
    // Explicit deterministic client errors — retrying is pointless/harmful.
    // (429 is handled below as transient.)
    if (status >= 400 && status < 500 && status !== 429) return false;
    // 5xx and 429 are transient.
    if (status === 429 || (status >= 500 && status < 600)) return true;
  }

  const lower = normalizeError(error).toLowerCase();
  if (!lower) return false;

  // Deterministic / non-retryable signals take precedence.
  const isDeterministic =
    lower.includes("clarif") ||
    lower.includes("needs_input") ||
    lower.includes("needs input") ||
    lower.includes("validation") ||
    lower.includes("invalid") ||
    lower.includes("unauthorized") ||
    lower.includes("forbidden") ||
    lower.includes("not found") ||
    lower.includes("bad request") ||
    lower.includes("unprocessable");
  if (isDeterministic) return false;

  const { isTimeout, isNetworkRelated } = classifyError(lower);
  if (isTimeout || isNetworkRelated) return true;

  // Empty / incomplete stream, rate-limit / overload, and generic
  // upstream "temporary" errors are transient.
  return (
    lower.includes("no final payload") ||
    lower.includes("streaming response body unavailable") ||
    lower.includes("temporarily busy") ||
    lower.includes("ratelimit") ||
    lower.includes("rate limit") ||
    lower.includes("too many") ||
    lower.includes("overload") ||
    lower.includes("temporary") ||
    lower.includes("try again") ||
    lower.includes("econnreset") ||
    lower.includes("econnrefused") ||
    lower.includes("socket hang up") ||
    lower.includes("502") ||
    lower.includes("503") ||
    lower.includes("504") ||
    lower.includes("gateway") ||
    lower.includes("upstream") ||
    lower.includes("maintenance") // legacy '__maintenance__' sentinel from older builds
  );
}

/** HTTP 502/503/504 from the reverse proxy: the app server did not answer at all. */
export function isGatewayError(error: string | null | undefined, httpStatus?: number | null): boolean {
  if (httpStatus === 502 || httpStatus === 503 || httpStatus === 504) return true;
  return /\b(502|503|504)\b|bad gateway|service unavailable|gateway time-?out/i.test(normalizeError(error));
}

/**
 * Backoff schedule (ms) for retrying a failed chat stream; its length is the number of retries.
 * A gateway error is an app-server restart/overload window: the dev frontend was down ~5 s during a
 * container replacement (2026-11-11 04:04:19–04:04:24 UTC), and the old 0.8 s + 1.6 s schedule
 * spent both retries inside that window, so the user got a hard error for a request that would
 * have succeeded 3 s later. Retry gateway errors across ~15 s; other transient failures (which
 * include 120 s timeouts) keep the short schedule.
 */
export function chatRetryDelaysMs(error: string | null | undefined, httpStatus?: number | null): number[] {
  return isGatewayError(error, httpStatus) ? [1000, 2000, 4000, 8000] : [800, 1600];
}

export function getChatAsyncGuidance(
  rawError: string | null | undefined,
  options: { isOnline?: boolean } = {}
): AsyncGuidance {
  const error = normalizeError(rawError);
  const { isTimeout, isNetworkRelated } = classifyError(error);
  // navigator.onLine is unreliable on mobile — use only as supplementary context, not alone.
  const isOnline = options.isOnline ?? true;

  if (isNetworkRelated || (!isOnline && !error)) {
    return {
      title: "Connection error",
      reason:
        error || "Could not reach the workflow generation service because the network connection appears interrupted.",
      retry: "Reconnect and send the prompt again. If this keeps happening, wait briefly and retry.",
      escalation:
        "Use Report issue if repeated failures continue so logs and request context can be attached.",
      isTimeout,
      isNetworkRelated: true,
    };
  }

  if (isTimeout) {
    return {
      title: "Response timed out",
      reason: "Workflow generation exceeded the response time budget.",
      retry: "Retry with a narrower request or simpler input context.",
      escalation: "If timeouts persist, report issue with timestamp and prompt summary.",
      isTimeout: true,
      isNetworkRelated: false,
    };
  }

  // A gateway error (HTTP 502/503/504) means the app server was unreachable — restarting during a
  // deploy, or overloaded — so the request was never answered. It says nothing about the prompt:
  // "rephrase the request" (the generic advice below) is wrong for it (dev 2026-11-11 04:04 UTC:
  // the frontend container was replaced mid-request and the user saw "Chat API error: Bad Gateway
  // — Rephrase the request…").
  if (isGatewayError(error)) {
    return {
      title: "BioMate was briefly unavailable",
      reason: "The server did not answer (it was restarting or overloaded), so your message was not processed.",
      retry: "Send the same message again in a few seconds — no need to change it.",
      escalation: "If this keeps happening, report issue with the timestamp.",
      isTimeout: false,
      isNetworkRelated: false,
    };
  }

  const isRateLimit = /temporarily busy|wait a moment|rate.?limit|too many|overload/i.test(error);
  if (isRateLimit) {
    return {
      title: "Service temporarily busy",
      reason: "BioMate's AI service is handling many requests right now. Your request was not lost.",
      retry: "Wait 10–30 seconds and send the message again — it will process normally.",
      escalation: "If this keeps happening after a few retries, report issue with timestamp.",
      isTimeout: false,
      isNetworkRelated: false,
    };
  }

  return {
    title: "Workflow generation failed",
    reason: sanitizeReason(error, "The service returned an unexpected error while generating your workflow."),
    retry: "Rephrase the request with data type and analysis goal, then try again.",
    escalation: "If this persists, use Report issue so the backend trace can be reviewed.",
    isTimeout: false,
    isNetworkRelated: false,
  };
}
