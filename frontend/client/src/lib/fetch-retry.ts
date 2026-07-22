/**
 * fetchWithRetry — fetch() that retries transient NETWORK failures.
 *
 * A thrown fetch (vs. an HTTP error *response*) means the request never completed
 * a round-trip. dev-public sits directly on an EC2 public IP with no ALB/retry
 * layer, so brief client↔host connection drops surface to the app as
 * "TypeError: Failed to fetch" / "net::ERR_FAILED". Under sustained polling
 * (project list, chat-history sync, active-project refresh) the odds of hitting
 * one over a few minutes approach 1. Retrying masks virtually all of them.
 * See docs/20260722_PROJECT_MODULE_PERF_AND_TIER_PROPOSAL.md.
 *
 * Only network-level failures on IDEMPOTENT requests are retried — HTTP error
 * responses (4xx/5xx) are returned to the caller unchanged, and non-idempotent
 * writes (POST/PUT/PATCH/DELETE) are never retried (no double-submit risk).
 */
const DEFAULT_BACKOFF_MS = [300, 800]

export function isRetryableNetworkError(error: unknown): boolean {
  if (error instanceof TypeError) return true
  const msg = error instanceof Error ? error.message : String(error)
  return /failed to fetch|networkerror|network error|err_failed|load failed/i.test(msg)
}

function isIdempotent(options?: RequestInit): boolean {
  const method = (options?.method ?? 'GET').toUpperCase()
  return method === 'GET' || method === 'HEAD' || method === 'OPTIONS'
}

export async function fetchWithRetry(
  url: string,
  options: RequestInit = {},
  maxAttempts = 3,
  backoffMs: number[] = DEFAULT_BACKOFF_MS
): Promise<Response> {
  let lastError: unknown
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fetch(url, options)
    } catch (error) {
      lastError = error
      if (
        attempt < maxAttempts - 1 &&
        isIdempotent(options) &&
        isRetryableNetworkError(error)
      ) {
        await new Promise(r => setTimeout(r, backoffMs[attempt] ?? backoffMs[backoffMs.length - 1] ?? 800))
        continue
      }
      throw error
    }
  }
  throw lastError
}
