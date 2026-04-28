# BioMate Real User Audit — 2026-04-16

Conducted by: Playwright-driven first-time-user simulation
Test account: `audit_test_[timestamp]@test.com`
Screenshots: `frontend/e2e/screenshots/user-audit/`

---

## Summary

Navigated the full first-time-user journey: landing → register → onboarding → chat → workflow → dashboard → billing. Found 2 P0 blockers, 4 P1 friction points, and 4 P2 issues.

---

## Findings

### P0 — Blocks Usage

---

#### P0-1: `/app` is a 404 — the entry URL everyone will type doesn't work

**Screenshot:** `02_app_direct_nav.png`

The page shows a blank "404 Page Not Found" card. The app's actual entry point is `/` (no path), but any user who types `yoursite.com/app` — the conventional SaaS pattern — hits a 404. The landing page CTA links go to `/register`, not `/app`, but any bookmark, shared URL, or documentation reference using `/app/anything` silently fails with no redirect.

Affected routes confirmed as 404:
- `/app` → 404
- `/app/dashboard` → 404
- `/app/settings` → 404

**Fix:** Add catch-all redirects for `/app`, `/app/*` → `/`.

---

#### P0-2: /billing page crashes the entire React app with a white error screen

**Screenshot:** `13_billing.png`

Navigating to `/billing` triggers a React render crash (caught by AppErrorBoundary). The error message fills the entire screen in red text:

```
Application Error
A <Select.Item /> must have a value prop that is not an empty string.
```

Source: `/home/yzhang/biomate/frontend/client/src/pages/billing.tsx` line 906:
```tsx
<SelectItem value="">All months</SelectItem>
```

Radix UI's `<Select.Item>` throws when `value=""`. The whole `/billing` route becomes unrenderable. A user trying to check their subscription or invoices sees a full application crash with a raw stack trace.

**Fix:** Change `value=""` to `value="all"` (and update the filter logic to match).

---

### P1 — Major Friction

---

#### P1-1: Registration form requires an Invite Code, but no code is shown, explained, or obtainable

**Screenshot:** `03_register_page.png`

The registration form has a visible "Invite Code (required during closed beta)" field with placeholder "BETA-XXXX-XXXX". The landing page "Start Free Trial" button goes to `/register` with no invite code pre-filled. A new user who fills out their name, email, and password and clicks "Create Account" sees the "Full Name" native browser validation fire first (the test missed filling name, and the form submits with HTML5 `required` errors). Even after fixing that, with no invite code the backend returns `INVITE_CODE_REQUIRED`.

There is no link on the registration page explaining how to get an invite code. There is no "request access" form. The form says "Start your 7-day free trial of BioMate" above, implying open registration, while requiring a closed-beta invite code below. This messaging contradiction will confuse every new user.

Note: The API (`POST /api/auth/register`) does NOT actually enforce the invite code requirement — registration succeeds without one when called directly. The invite code check only lives in the frontend validation, meaning the frontend is more restrictive than the backend.

**Fix:** Either (a) remove the invite code field and match frontend to backend behavior, or (b) add a "Request invite" link / waitlist flow to the registration page.

---

#### P1-2: After successful registration, the email-sent screen blocks the user and the "Continue setup" button goes nowhere useful

**Screenshot:** `04_email_sent_screen.png`

After a successful registration via the form, the user sees a "Check your email" screen with the message "We sent a verification link to [email]. Click the link in your email to verify your account, then come back to log in."

Two problems:
1. The email is sent via `smtp.ethereal.email` (a fake SMTP dev service) — the user will never actually receive a verification email in production unless real SMTP is configured.
2. The "Continue setup" button exists, which bypasses the email verification gate and goes to the domain profile step — but this is not explained. The primary instruction ("click the link in your email") will send users on a dead-end hunt for an email that will not arrive.

In production with real email configured, users who click "Continue setup" before verifying will proceed but remain unverified, which may cause issues downstream.

---

#### P1-3: Welcome screen (main chat app) is completely blank — no onboarding content or example prompts

**Screenshots:** `06_main_app_after_login.png`, `07_welcome_screen.png`

After logging in, the user lands on the main chat interface with:
- A left sidebar showing "PROJECTS", "RECENT CHATS" (with stale example entries from previous test runs), "TOOL CATEGORIES", and "QUICK ACTIONS"
- A completely empty main content area — no greeting, no welcome message, no suggested prompts, no capability showcase
- A text input at the bottom: "Type your message here..."

A first-time scientist has no idea what to type. The sidebar shows example chat sessions from a different user's local storage (e.g., "RNA-seq Analysis Pipeline", "Variant Calling Workflow") which are stored in `localStorage` and never cleared, creating a confusing experience where a brand new account appears to have prior chat history belonging to nobody.

The landing page (`/home`) promises "Real-World Applications" cards for Proteomics, RNA-Seq, etc. — none of this appears in the chat welcome state.

**Fix:** Add example prompts/capability chips to the empty chat state. Clear stale localStorage sessions on new account creation.

---

#### P1-4: Chat AI response never arrives — SSE stream fails silently, user sees "BioMate is thinking..." indefinitely

**Screenshots:** `08d_response_received.png`, `08e_response_scrolled.png`

After sending "I want to run RNA-seq differential expression analysis on mouse samples comparing treatment vs control", the chat shows "BioMate is thinking..." and never progresses. The console shows:

```
[ChatInterface] SSE read error: TypeError network error
[ChatInterface] API Error: TypeError: network error
```

The SSE stream endpoint is failing. The user sees a perpetual loading indicator with no timeout, no error message, and no retry button. The status bar at the bottom says "Analyzing request... response will stream in as soon as it's ready." — this message never clears.

The user has no way to know whether the system is working, broken, or just slow. There is no timeout fallback.

Note: This may be environment-specific (test account without a Galaxy provisioned user), but the UX failure (no error feedback after >30s) is unconditional.

---

### P2 — Minor Issues

---

#### P2-1: Dashboard shows hardcoded fake data for every user

**Screenshot:** `11_dashboard.png`

The `/dashboard` page always shows:
- "Welcome back, Dr. Smith" (hardcoded name, ignores logged-in user)
- "Workflows Run: 127 (+12%)"
- "Storage Used: 24.3 GB / 50 GB limit"
- "Team Members: 5 / 10 max"
- "API Calls: 8.2K (+23%)"
- Recent Workflows: "DIA-LCMS Proteomics Analysis (completed)", "RNA-Seq Differential Expression (running, 65%)", "Genomic Variant Calling (completed)"

All data is hardcoded in `client/src/pages/dashboard.tsx` lines 20–70. A new user who navigates to `/dashboard` sees activity they didn't create. The subscription panel shows "Pro Plan — November 17, 2025 — $49.00/month" — a past billing date, signaling the data is placeholder.

This is confusing: a scientist who just registered sees someone else's workflow history.

**Fix:** Connect dashboard to real API data; show empty state for new users.

---

#### P2-2: Chat history sync creates 50+ console errors on every page load

The frontend `chat-history.ts` is configured with `VITE_BACKEND_URL=http://localhost:8081` (Galaxy backend) but the session sync API (`/api/sessions`) does not exist on port 8081. This generates a waterfall of CORS and fetch errors on every navigation:

```
Access to fetch at 'http://localhost:8081/api/sessions' from origin 'http://localhost:5000' 
has been blocked by CORS policy
[ChatHistory] Pull from backend failed: TypeError: Failed to fetch
[ChatHistory] Failed to sync session ...: TypeError: Failed to fetch
```

These errors are silently swallowed by the app (`// Silently ignore — billing is non-critical`) but clutter the console continuously. This indicates `VITE_BACKEND_URL` is misconfigured — it should point to the main Express server (port 5000), not Galaxy (port 8081), or the session sync endpoint should exist on port 8081.

---

#### P2-3: "Settings" sidebar link opens a dialog (not a page), but "Billing & Invoices" navigates to a crash

The sidebar has two seemingly equivalent links:
- "Settings" → opens an in-app dialog (correct behavior)
- "Billing & Invoices" → navigates to `/billing` which crashes (P0-2 above)

The inconsistency is confusing: some sidebar items open modals, others navigate pages. There's no visual distinction between them.

---

#### P2-4: Stale "Recent Chats" in sidebar persist across accounts via localStorage

**Screenshot:** `06_main_app_after_login.png`

The sidebar shows chat sessions ("RNA-seq Analysis Pipeline", "Variant Calling Workflow", "ChIP-seq Data Processing", "Genome Assembly Help") that belong to a different account, stored in `localStorage`. When a new user registers and logs in on a shared machine or after a previous test run, they see another user's chat history in their sidebar.

This is a data isolation issue: `chatHistoryService` reads from `localStorage` without scoping by user ID. If two users share a browser, the second user sees the first user's sessions.

**Fix:** Scope localStorage keys by user ID, and clear on login of a different account.

---

## Console Errors Summary

| Category | Count | Root Cause |
|---|---|---|
| `Failed to load resource: net::ERR_FAILED` | ~10 | Google Fonts CORS blocked by `X-E2E-Test-Token` header (test-only) |
| `ChatHistory Pull from backend failed` | ~8 | `VITE_BACKEND_URL=http://localhost:8081` wrong port |
| `ChatHistory Failed to sync session` | ~4 | Same wrong backend URL |
| `SSE read error: TypeError network error` | 1 | AI response stream failure |
| `Select.Item value must not be empty string` | 2 | Billing page crash (P0-2) |
| `[AppErrorBoundary] React render crash` | 1 | Billing page crash consequence |

Total filtered errors (excluding Google Fonts CORS from test header): **50 errors** across a single user session.

---

## Navigation Map

| Route | Status | Observation |
|---|---|---|
| `/home` | OK | Full landing page, well designed |
| `/register` | Partial | Invite code field creates friction; form works without code at API level |
| `/login` | OK | Standard login form |
| `/` (chat app) | OK (empty) | App loads but welcome state is blank |
| `/dashboard` | OK (fake) | Loads but all data is hardcoded |
| `/billing` | CRASH | React crash — `<SelectItem value="">` |
| `/app` | 404 | Should redirect to `/` |
| `/app/dashboard` | 404 | Should redirect to `/dashboard` |
| `/app/settings` | 404 | Should redirect to settings dialog |
| `/pricing` | Not tested | |
| `/blog` | Not tested | |

---

## Prioritized Fix List

1. **[P0]** Fix `<SelectItem value="">` in `billing.tsx` line 906 → change to `value="all"`
2. **[P0]** Add redirects: `/app` → `/`, `/app/*` → appropriate route
3. **[P1]** Fix `VITE_BACKEND_URL` misconfiguration (should be `http://localhost:5000` or remove backend sync)
4. **[P1]** Add onboarding content / example prompts to empty chat state
5. **[P1]** Fix email verification flow (use real SMTP or make the dev bypass link visible/explicit)
6. **[P1]** Resolve registration invite code contradiction (frontend requires it, backend does not)
7. **[P2]** Scope `localStorage` chat sessions by user ID
8. **[P2]** Connect dashboard to real user data or show meaningful empty state

---

## Screenshots Index

All screenshots in `frontend/e2e/screenshots/user-audit/`:

| File | What it shows |
|---|---|
| `01_landing_page_home.png` | Full `/home` landing page — well-designed, all sections load |
| `02_app_direct_nav.png` | `/app` → 404 blank card (P0-1) |
| `03_register_page.png` | Registration form with Invite Code field |
| `03b_register_form_filled.png` | Filled form — shows password requirements working |
| `03c_after_register_submit.png` | After submit — stays on /register (Full Name validation error) |
| `04_email_sent_screen.png` | "Check your email" post-registration screen |
| `06_main_app_after_login.png` | Main chat app — blank center, stale sidebar sessions |
| `07_welcome_screen.png` | Welcome state — blank, no prompts |
| `08d_response_received.png` | Chat showing "BioMate is thinking..." — never resolves |
| `08e_response_scrolled.png` | Same stuck state after scrolling |
| `11_dashboard.png` | Dashboard with hardcoded "Dr. Smith" + fake workflow data |
| `13_billing.png` | Billing page full React crash — red stack trace |
| `12_app_navigation.png` | Sidebar navigation items |
| `14_final_app_state.png` | Final state — blank chat, working sidebar |
