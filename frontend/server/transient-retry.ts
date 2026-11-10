/**
 * Shared bounded-retry helpers for transient Node→backend connection blips.
 *
 * WHY: a request from the Node frontend to the Galaxy backend (:8081) or to the
 * run_code sandbox sidecar node (e.g. 172.19.0.2:8080) can land in the few-second
 * window where that process is recycling/restarting. The TCP connect is then
 * REFUSED/RESET, times out, or fails DNS — surfacing to the user as
 * "ECONNREFUSED", "fetch failed", or a 502/503/504 from a front proxy. These are
 * TRANSIENT infra blips, not real failures.
 *
 * The workflow-EXECUTE handler (routes.ts /api/workflows/execute) and the
 * generate_workflow proxy (galaxy-api-proxy.ts) already bounded-retry exactly this
 * class. This module factors the SAME classification so the run_code path can use
 * it too, keeping one definition of "transient".
 *
 * Error classes treated as transient (mirrors the execute handler):
 *   - ECONNREFUSED / ECONNRESET / ETIMEDOUT / EAI_AGAIN (DNS) / ENOTFOUND / EPIPE
 *   - undici's generic "fetch failed" TypeError (its wrapper for the above)
 *   - "socket hang up" / "getaddrinfo" / "network error"
 *   - HTTP 502 / 503 / 504 from a front proxy
 *
 * NOT transient (never retried — surfaced to the caller UNCHANGED so a real,
 * persistent outage or a genuine failure is never hidden):
 *   - an execution timeout / explicit AbortController abort (the user's code was
 *     too slow, or the caller cancelled) — a real failure, not a connection blip
 *   - any 4xx / validation / genuine runtime error
 */

/** True when a string (an Error.message, a detail, or captured stderr) looks like
 *  a transient connection-level blip worth a bounded retry. Abort/execution-timeout
 *  is explicitly excluded — that is a real failure, not a connection blip. */
export function isTransientConnMessage(raw: string | undefined | null): boolean {
  const s = String(raw ?? '');
  if (!s) return false;
  // An execution timeout / explicit cancel is a REAL failure, never a blip.
  if (/operation was aborted|AbortError\b|\baborted\b/i.test(s)) return false;
  return (
    /\b(ECONNREFUSED|ECONNRESET|ETIMEDOUT|EAI_AGAIN|ENOTFOUND|EPIPE)\b/i.test(s) ||
    /fetch failed|socket hang up|getaddrinfo|network error|connection (refused|reset)/i.test(s) ||
    /\bHTTP (502|503|504)\b/i.test(s)
  );
}

/** True when an Error/Axios-style error object is a transient connection blip. */
export function isTransientError(err: any): boolean {
  if (!err) return false;
  const code = String(err.code || err.cause?.code || '').toUpperCase();
  if (['ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT', 'EAI_AGAIN', 'ENOTFOUND', 'EPIPE'].includes(code)) {
    return true;
  }
  const status = Number(err.status ?? err.status_code ?? err.response?.status);
  if ([502, 503, 504].includes(status)) return true;
  return isTransientConnMessage(err.message || err.detail || err.cause?.message);
}

/**
 * True when a run_code / code-runner RESULT (which never throws — it returns
 * exit_code + captured stderr) carries a transient SIDECAR connection failure.
 *
 * code-runner.ts surfaces sidecar infra failures with a stable prefix:
 *   - "[sidecar fetch error: <msg>]"       → the TCP connect to the sidecar failed
 *   - "[sidecar error: HTTP 502|503|504 …]" → a front proxy returned 5xx
 * Both are produced ONLY by the sidecar transport, never by user code, so matching
 * that prefix is precise. An abort inside the fetch (execution timeout) is excluded
 * by isTransientConnMessage.
 */
export function isTransientSidecarStderr(stderr: string | undefined | null): boolean {
  const s = String(stderr ?? '');
  if (/\[sidecar error: HTTP (502|503|504)\b/i.test(s)) return true;
  if (/\[sidecar fetch error:/i.test(s)) return isTransientConnMessage(s);
  return false;
}

const DEFAULT_DELAYS_MS = [0, 1500, 3000]; // 3 attempts, ≤4.5s added latency

/**
 * Bounded retry for a run_code-style thunk that RETURNS a result (never throws)
 * whose transient failures live in `stderr`. Retries only on a transient sidecar
 * connection blip; a genuine code error or an execution timeout returns on the
 * first attempt. When retries are exhausted the LAST result is returned UNCHANGED,
 * so a persistent sandbox outage still surfaces its real error to the user.
 */
export async function retryTransientRunCode<T extends { exit_code?: number; stderr?: string }>(
  fn: () => Promise<T>,
  opts: { delaysMs?: number[]; label?: string } = {},
): Promise<T> {
  const delays = opts.delaysMs ?? DEFAULT_DELAYS_MS;
  const tag = opts.label ? ` ${opts.label}` : '';
  let result!: T;
  for (let attempt = 0; attempt < delays.length; attempt++) {
    if (delays[attempt] > 0) {
      await new Promise((r) => setTimeout(r, delays[attempt]));
    }
    result = await fn();
    const failed = (result?.exit_code ?? 0) !== 0;
    const transient = failed && isTransientSidecarStderr(result?.stderr);
    if (!transient || attempt === delays.length - 1) {
      return result; // success, non-transient failure, or retries exhausted → honest result
    }
    console.warn(
      `[retryTransientRunCode${tag}] transient sandbox error (attempt ${attempt + 1}/${delays.length}), retrying:`,
      String(result?.stderr || '').slice(0, 160),
    );
  }
  return result;
}
