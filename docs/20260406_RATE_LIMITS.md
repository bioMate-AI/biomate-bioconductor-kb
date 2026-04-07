# BioMate Rate Limits

*Last updated: 2026-04-06*

All rate limiters live in the Node.js BFF layer (`frontend/server/`).  
Source files: `rate-limit.ts`, `security-config.ts`, `quota-middleware.ts`.

---

## Rate Limit Table

| Endpoint(s) | Limit | Window | Error code | Source |
|---|---|---|---|---|
| All `/api/*` (global) | **1 000 req / IP** | 15 min | 429 `RATE_LIMIT_EXCEEDED` | `security-config.ts → globalRateLimiter` |
| `POST /api/auth/login` | **5 attempts / IP** | 15 min | 429 `TOO_MANY_ATTEMPTS` | `rate-limit.ts → authLimiter` |
| `POST /api/auth/register` | **3 registrations / IP** | 1 hour | 429 `REGISTRATION_LIMIT_EXCEEDED` | `rate-limit.ts → registerLimiter` |
| `POST /api/auth/forgot-password` | **3 attempts / IP** | 1 hour | 429 `PASSWORD_RESET_LIMIT_EXCEEDED` | `rate-limit.ts → passwordResetLimiter` |
| `POST /api/auth/resend-verification` | **5 attempts / IP** | 1 hour | 429 `VERIFICATION_LIMIT_EXCEEDED` | `rate-limit.ts → emailVerificationLimiter` |
| File upload | **20 uploads / IP** | 1 hour | 429 `UPLOAD_LIMIT_EXCEEDED` | `rate-limit.ts → uploadLimiter` |
| Compute endpoints (unauthenticated) | **5 req / IP** | 1 hour | 429 `UNAUTHENTICATED_LIMIT_EXCEEDED` | `quota-middleware.ts → unauthLimiter` |
| Compute endpoints (authenticated, over monthly quota) | billing cap | monthly | 402 `QUOTA_EXCEEDED` | `quota-middleware.ts → checkBillingQuota` |

> **Note:** `authLimiter` has `skipSuccessfulRequests: false` — every login attempt counts whether it succeeds or fails. With 11 E2E tests each calling login, the 6th–11th would be rate-limited if not bypassed.

---

## Compute / Workflow Execute

`POST /api/workflows/execute` uses `optionalAuth` only — no dedicated rate limiter at the route level.

The **429 seen in E2E tests** (`[DA1_NCA] http=429`) is caused by the **global rate limiter** (1 000 req / 15 min per IP) being hit when multiple rapid E2E runs fire in the same 15-minute window.

---

## E2E Bypass

All limiters except `globalRateLimiter` and `unauthLimiter` have an explicit `skip` hook:

```typescript
// rate-limit.ts / security-config.ts
function isE2EBypass(req: Request): boolean {
  if (!_E2E_TOKEN) return false;
  return req.headers['x-e2e-test-token'] === _E2E_TOKEN;
}
```

Pass `X-E2E-Test-Token: <E2E_TEST_TOKEN>` on any `page.request.*` call to bypass
`authLimiter`, `registerLimiter`, `passwordResetLimiter`, `emailVerificationLimiter`, and `globalRateLimiter`.

**Important:** browser-level page actions (form submits, Playwright `page.click()` triggering fetch) do **not** carry this header unless you call:

```typescript
await page.setExtraHTTPHeaders({ 'X-E2E-Test-Token': E2E_TEST_TOKEN });
```

The current `drug-discovery-full-e2e.e2e.ts` sets the header only on `page.request.post()` calls (auth/register), **not** on the page context itself.  This means the `POST /api/workflows/execute` UI-triggered request is not bypassed, and can still hit the global 1 000/15 min limiter under heavy test load.

### Fix for execute 429s

Add `setExtraHTTPHeaders` to each test page so all browser-level requests carry the bypass token:

```typescript
// inside each test:
await page.setExtraHTTPHeaders({ 'X-E2E-Test-Token': E2E_TEST_TOKEN });
```

Or set it once on the shared browser context in `beforeAll`:

```typescript
// drug-discovery-full-e2e.e2e.ts → setupSharedAccount
const ctx = await browser.newContext({
  extraHTTPHeaders: { 'X-E2E-Test-Token': E2E_TEST_TOKEN },
});
```

---

## Billing Quota (402, not 429)

Authenticated users who exceed their monthly compute quota receive **HTTP 402** (not 429).

```json
{
  "error": "QUOTA_EXCEEDED",
  "message": "Monthly compute quota exceeded ($50.00/month). Add credits or wait for your billing cycle to reset.",
  "quota_usd": 50.00,
  "used_usd": 51.23
}
```

Admin-tier accounts bypass quota checks entirely.

---

## Response Headers

All rate-limited responses include standard `RateLimit-*` headers
(`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`) from `express-rate-limit`
(`standardHeaders: true`).

---

## Summary for E2E Operators

| Scenario | Root cause | Fix |
|---|---|---|
| `[Setup] JWT: not found` (tests 2–11) | `beforeAll` without `describe` → no shared state | Wrap all tests in `test.describe` ✅ done |
| `POST /api/auth/login` → 429 | authLimiter: 5/15 min, no skip-on-success | Use shared JWT cookie, call login once in `beforeAll` ✅ done |
| `POST /api/workflows/execute` → 429 | global 1 000/15 min; browser page has no bypass header | Set `extraHTTPHeaders` on browser context in `beforeAll` |
| `POST /api/auth/register` → 429 | registerLimiter: 3/hr, but E2E bypass set on `page.request` | Already bypassed via `X-E2E-Test-Token` header ✅ |
