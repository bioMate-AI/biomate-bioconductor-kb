/**
 * Single source of truth for E2E / Playwright target URL resolution.
 *
 * Precedence: BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > fallback
 * (shell BASE_URL must win — a0d9191c17 closed the fixture-only bug; this
 * module closes the class for every helper / config / bypasser).
 *
 * Import `BASE_URL` or `resolveE2eBaseUrl` — do not re-read env vars ad hoc.
 */
export function resolveE2eBaseUrl(fallback = "http://localhost:5000"): string {
  return (
    process.env.BASE_URL ||
    process.env.PLAYWRIGHT_BASE_URL ||
    process.env.BIOMATE_URL ||
    fallback
  ).replace(/\/+$/, "");
}

/** Specs and helpers: same precedence; localhost when no env is set. */
export const BASE_URL = resolveE2eBaseUrl();
