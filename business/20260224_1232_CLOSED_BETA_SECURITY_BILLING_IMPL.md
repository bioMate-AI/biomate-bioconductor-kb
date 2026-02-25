# BioMate Closed-Beta: Security Hardening + Billing Integration
**Date**: 2026-02-24
**Branch**: `connection_formal`
**Status**: Implementation complete, awaiting prod deployment

---

## Overview

This session prepared BioMate for closed public beta by implementing three interlocking systems:

1. **P0 security fixes** — CSP, CORS, JWT/session secret validation, auth guards, XSS
2. **Invite code system** — closed-beta gate with per-code trial customisation
3. **Billing-quota rate limiting** — replaced arbitrary IP-based limits with per-user monthly quota enforcement

---

## 1. P0 Security Fixes

### 1A. CSP (Content-Security-Policy) — `server/security-config.ts`
- `unsafe-inline` / `unsafe-eval` in `script-src` are now **dev-only**
- `wss://localhost:*` in `connect-src` is now **dev-only**; production reads `WEBSOCKET_URL` env var
- Production origins restricted to `https://biomate.ai` (localhost removed)

### 1B. Production secret validation — `server/index.ts`
- Module-level synchronous check at startup (not async, so it can't silently swallow)
- Missing `JWT_SECRET`, `SESSION_SECRET`, or `BILLING_INTERNAL_KEY` → `process.exit(1)` immediately
- Both `uncaughtException` and `unhandledRejection` handlers also call `process.exit(1)`

### 1C. Route authentication — `server/routes.ts`
Added `authenticateToken` / `optionalAuth` to previously unprotected routes:
- `POST /api/datasets/upload` — requires auth
- `POST /api/datasets/import-url` — requires auth
- `DELETE /api/invocations/:id` — requires auth
- `POST/GET/PATCH /api/invocations` — optional auth (billingUserId forwarded when present)
- AI assistant + pilot routes — optional auth

### 1D. XSS sanitisation — `client/src/components/workflow-report-viewer.tsx`
Both `dangerouslySetInnerHTML` usages now wrapped with `DOMPurify.sanitize()`.

---

## 2. Invite Code System

### Schema — `shared/schema.ts`
Two new tables:

**`invite_codes`**
| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | auto-generated |
| `code` | varchar | e.g. `NEURO-A1B2-C3D4` |
| `description` | text | internal label |
| `created_by` | integer FK → users | admin who created it |
| `max_uses` | integer | null = unlimited |
| `used_count` | integer | atomic increment in transaction |
| `trial_days` | integer | override default 7-day trial |
| `quota_override_usd` | numeric | override plan quota for this code |
| `subscription_tier` | varchar | tier to assign at sign-up (default: `academic`) |
| `expires_at` | timestamp | optional hard expiry |
| `active` | boolean | soft-disable without delete |

**`invite_code_uses`**
Join table recording which user used which code, with timestamps.

**`users.invite_code_id`** FK added via migration (see below).

### Auth service — `server/auth-service.ts`
- `REQUIRE_INVITE_CODE=true` env var gates all registrations; without it, codes are optional-but-respected
- Entire flow runs in a **single `db.transaction()`**:
  1. Re-reads `usedCount` inside the transaction (TOCTOU fix)
  2. Inserts user
  3. Inserts `invite_code_uses` row
  4. Increments `usedCount` atomically with `sql\`${inviteCodes.usedCount} + 1\``
- Invite code overrides: `trialDays`, `quotaOverrideUsd`, `subscriptionTier`

### Register page — `client/src/pages/auth/register.tsx`
- Invite code field pre-filled from `?invite=CODE` URL param (shareable links)
- Input auto-uppercased, monospace font
- Friendly error messages per error code:
  `INVITE_CODE_REQUIRED` / `INVALID_INVITE_CODE` / `INVITE_CODE_EXPIRED` / `INVITE_CODE_EXHAUSTED`

### Admin API — `server/routes.ts`
Five endpoints, all behind `authenticateToken` + `requireAdmin` (tier === `'admin'`):
- `GET /api/admin/invite-codes` — list all codes with use counts
- `POST /api/admin/invite-codes` — create batch of codes
- `PATCH /api/admin/invite-codes/:id` — update active/expiry/quota
- `DELETE /api/admin/invite-codes/:id` — hard delete
- `GET /api/admin/invite-codes/:id/uses` — who used a specific code

### CLI scripts — `scripts/`
- `set-admin.ts` — promote/revoke admin, list admins
  `DATABASE_URL=... npx tsx scripts/set-admin.ts user@example.com`
- `create-invite-codes.ts` — batch create, list, deactivate
  `DATABASE_URL=... npx tsx scripts/create-invite-codes.ts --prefix BETA --count 50 --trial-days 30 --quota 25.00`

### DB migration — `migrations/0001_invite_codes.sql`
Creates both tables, adds `users.invite_code_id`, adds FK constraint and indexes.

---

## 3. Billing-Quota Rate Limiting

### Problem with the old approach
`aiGenerateLimiter` and `urlImportLimiter` were arbitrary IP-based counters
(20/hr and 10/hr respectively) with no relationship to the user's subscription tier
or the Redis-based monthly quota already defined in `billing/core/quota_enforcer.py`.

### Plan configuration — `server/plan-config.ts` (new)
Canonical tier → plan mapping mirroring `DEFAULT_PLAN_LIMITS` in `quota_enforcer.py`:

| BioMate tier | Lago plan | Monthly quota |
|---|---|---|
| `trial` | `free` | $5.00 |
| `academic` | `free` | $5.00 |
| `professional` | `basic` | $50.00 |
| `enterprise` | `pro` | $500.00 |
| `admin` | `enterprise` | unlimited |

Exported helpers: `billingPlanForTier(tier)`, `quotaUsdForTier(tier)`.

### Quota middleware — `server/quota-middleware.ts` (new)
`checkBillingQuota(resourceName)` middleware, applied per-endpoint:

| Caller | Behaviour |
|--------|-----------|
| Admin tier | Allowed unconditionally |
| Authenticated, within quota | Allowed (quota checked via `GET GALAXY_URL/api/billing/quota`) |
| Authenticated, over quota | `402 QUOTA_EXCEEDED` with `quota_usd`, `used_usd`, `resource` fields |
| Unauthenticated | IP-based fallback: 5 req/hr, prompts sign-in |
| Billing service unreachable | Fail-open — allowed through (logs nothing, avoids user disruption) |

Timeout: 3 s (`AbortSignal.timeout(3000)`) on billing quota check.

Applied to:
- `POST /api/datasets/import-url`
- `POST /api/ai_assistant/generate_workflow`

### Billing sync at registration — `server/auth-service.ts`
`syncUserToBilling()` called fire-and-forget after every successful registration:
1. `POST /internal/billing/register_user` — seeds Redis quota for the plan
2. If invite code has `quotaOverrideUsd` → `POST /internal/billing/set_quota` to override

Fail behaviour: if billing service is unreachable, `quota_enforcer.py` has no quota in Redis
and fails-open (unlimited access) until an operator calls `set_quota` manually.
Timeouts: 5 s on both calls.

---

## 4. Audit Findings and Fixes

All issues found during self-audit. Severity: Critical / High / Medium / Low / Info.

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| A1 | **Critical** | TOCTOU race: user inserted before invite code re-check | **Fixed** — full transaction with re-read |
| A2 | **High** | `SESSION_SECRET` check in async function, silently swallowed | **Fixed** — moved to synchronous module-level `process.exit(1)` |
| A3 | **High** | `unsafe-inline` / `unsafe-eval` in production CSP | **Fixed** — dev-only |
| A4 | **High** | `dangerouslySetInnerHTML` without sanitisation | **Fixed** — DOMPurify |
| A5 | **Medium** | `createdBy` not set in admin code creation | **Fixed** — `req.user?.id` |
| A6 | **Medium** | `users.invite_code_id` FK only in migration comment, not schema | **Documented** — FK in `0001_invite_codes.sql` |
| A7 | **Medium** | AI generate + URL import rate limits not tied to billing tier | **Fixed** — replaced with `checkBillingQuota` |
| A8 | **Low** | `syncUserToBilling` comment claimed login sync (nonexistent) | **Fixed** — comment corrected |
| A9 | **Low** | `resourceName` parameter silently discarded in 402 response | **Fixed** — added `resource` field to 402 JSON |
| A10 | **Info** | `workflowLimiter` exported from `rate-limit.ts` but unused in routes | Accepted — kept as reference for future use |
| A11 | **Info** | `GALAXY_URL` defined independently in `auth-service.ts` and `quota-middleware.ts` | Accepted — follows existing pattern in routes.ts |

---

## 5. Files Changed

| File | Change |
|------|--------|
| `server/security-config.ts` | CSP/CORS prod-only hardening |
| `server/index.ts` | Synchronous secret validation + process.exit |
| `server/auth-service.ts` | Invite code transaction, billing sync |
| `server/routes.ts` | Auth guards, quota middleware, admin API |
| `server/rate-limit.ts` | Removed aiGenerateLimiter / urlImportLimiter |
| `server/plan-config.ts` | **New** — tier → plan mapping |
| `server/quota-middleware.ts` | **New** — billing quota middleware |
| `shared/schema.ts` | invite_codes + invite_code_uses tables |
| `client/src/pages/auth/register.tsx` | Invite code field + URL prefill |
| `client/src/components/workflow-report-viewer.tsx` | DOMPurify sanitisation |
| `migrations/0001_invite_codes.sql` | **New** — DB migration |
| `migrations/meta/_journal.json` | Migration journal entry |
| `scripts/set-admin.ts` | **New** — CLI admin tool |
| `scripts/create-invite-codes.ts` | **New** — CLI invite code tool |
| `package.json` | Added db:migrate, db:generate, admin:set, admin:invite scripts |

---

## 6. Deployment Checklist

### Environment variables required for production
```
REQUIRE_INVITE_CODE=true         # gate registration
JWT_SECRET=<32+ random bytes>
SESSION_SECRET=<32+ random bytes>
BILLING_INTERNAL_KEY=<matching backend>
GALAXY_URL=http://<backend-private-ip>:8081
WEBSOCKET_URL=wss://biomate.ai
DATABASE_URL=postgres://...
```

### One-time operations
```bash
# 1. Run DB migration
DATABASE_URL=postgres://... npm run db:migrate

# 2. Promote yourself to admin
DATABASE_URL=postgres://... npm run admin:set -- your@email.com

# 3. Create initial beta invite codes
DATABASE_URL=postgres://... npm run admin:invite -- \
  --prefix BETA --count 100 --trial-days 14 --quota 10.00 \
  --description "Closed beta wave 1"
```

### Known remaining P1 items (not in this session)
- JWT still stored in localStorage → migrate to httpOnly cookies
- Lago billing plan codes need to be created in the Lago dashboard
  (`free`, `basic`, `pro`, `enterprise`) before `register_user` will work correctly
- `workflowLimiter` (IP-based, 10/hr) still applied to workflow execution;
  should eventually be replaced with `checkBillingQuota` like AI generation

---

## 7. Failure Modes

| Scenario | Behaviour |
|----------|-----------|
| Billing service down at registration | User registered normally; quota not seeded; fail-open (unlimited) until operator runs `set_quota` |
| Billing service down during AI generation | `checkBillingQuota` fails-open; request proceeds |
| Billing service slow (>3s) | AbortSignal fires; request proceeds (fail-open) |
| Two concurrent registrations with last invite slot | Transaction re-check catches it; second request gets `INVITE_CODE_EXHAUSTED` |
| `set_quota` override fails after `register_user` succeeds | User gets plan-default quota; warning logged; operator can fix manually |
