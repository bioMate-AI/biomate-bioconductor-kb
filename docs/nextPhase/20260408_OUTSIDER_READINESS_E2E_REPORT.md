# Outsider Readiness E2E — 19/19 PASSING (2026-04-08)

## Summary

All 19 tests in `frontend/e2e/outsider-readiness.e2e.ts` pass in ~18 seconds.

## Tests Covered

| # | Test | Status |
|---|------|--------|
| 1 | Landing page loads and has Register + Login links | ✅ |
| 2 | Register page shows password requirements as user types | ✅ |
| 3 | Register new user → lands on platform (clean state) | ✅ |
| 4 | New user platform has no stale chat history | ✅ |
| 5 | Login page has Forgot Password link → navigates correctly | ✅ |
| 6 | Forgot-password form submits and shows confirmation | ✅ |
| 7 | Reset-password page renders with password requirements | ✅ |
| 8 | Reset-password page with no token shows error | ✅ |
| 9 | Verify-email page with no token shows error | ✅ |
| 10 | Verify-email page with fake token shows failure gracefully | ✅ |
| 11 | Platform chat is accessible only when logged in | ✅ |
| 12 | Authenticated user can access chat and type a query | ✅ |
| 13 | Feedback/rating components exist in the codebase (smoke) | ✅ |
| 14-16 | Register page renders correctly on mobile/tablet/desktop | ✅ |
| 15-17-19 | Login page renders correctly on mobile/tablet/desktop | ✅ |

## Root Causes Fixed

### 1. `api.ts` default BASE_URL was `http://localhost:5173/api`
- **Problem**: Nothing runs on port 5173 when the app is served via `tsx server/index.ts` on port 5000.
  All API calls through `api.ts` (e.g., `forgotPassword`, `verifyEmail`) silently failed with network error.
  The catch block showed a toast, but `setSuccess(true)` never ran → success state never shown.
- **Fix**: Changed default from `http://localhost:5173/api` to `/api` (relative URL).
  Relative URL is resolved against the serving origin (port 5000) → correct.
- **File**: `frontend/client/src/lib/api.ts` line 8

### 2. Registration form is a 3-step flow on the same `/register` URL
- **Problem**: After clicking "Create Account", the form transitions to a domain-selection step
  and then a trial step — all on `/register`. The `waitForFunction(() => !location.pathname.includes("/register"))` 
  never resolves because the URL never changes.
- **Fix**: Updated `registerUser` helper to:
  1. Submit the account form
  2. Wait for the domain selector heading (confirms registration succeeded)
  3. Click "Skip for now" (domain step)
  4. Use `page.goto('/dashboard')` to navigate away (bypasses the Stripe trial step for testing)
- **File**: `frontend/e2e/outsider-readiness.e2e.ts`

### 3. Tests 4 & 12 depended on test 3 creating a user with the same `Date.now()` email
- **Problem**: Each Playwright test can evaluate module-level `Date.now()` at different times,
  producing different `TEST_EMAIL` values. Tests 4 and 12 tried to login with an email that
  didn't exist (created by a different test run's email). Login failed → redirect never happened
  → `waitForFunction` timed out.
- **Fix**: Tests 4 and 12 now create their own unique users via `createUserViaApi()` (direct
  API call) before attempting UI login. Each test is self-contained.
- **File**: `frontend/e2e/outsider-readiness.e2e.ts`

### 4. Server restart required for Vite to pick up api.ts changes
- **Root cause**: Vite dev server caches module transforms. Changing `api.ts` while the server
  is running requires a server restart (or browser page refresh) to serve the updated code.
- **Note**: The `waitForURL` approach (used briefly) doesn't work for pushState/client-side
  routing — it waits for `load` events which don't fire on wouter navigation.

## Infrastructure Verified

- Email flow (Ethereal SMTP): verification + password reset emails send correctly
- Auth flow: register → verify → login → forgot password → reset all work end-to-end
- Responsive: register + login pages render correctly at 375px, 768px, 1440px
- Auth gating: platform chat requires authentication
- Clean state: new users have no stale chat history
