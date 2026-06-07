# Email + Quota + Billing — Implementation Guide

**Date:** 2026-06-06
**Audience:** Engineer picking up the unfinished email/quota/billing work before public trial launch.
**Status:** Single source of truth for what to build, in what order, and where each piece lands in the codebase. Supersedes scattered guidance in `20260525_BILLING_EMAIL_SCENARIOS.md` (priority calls), `20260518_TRIAL_QUOTA_CONFIGURATION.md` (number is stale — see §1), and the trial-quota reduction note.

---

## 1. Settled facts you can rely on

| Fact | Value | Authoritative source |
|---|---|---|
| Trial duration | **14 days** | `frontend/server/auth-service.ts:126` (`trialDays = … ?? 14`) |
| Trial budget | **$25 USD** | `backend/lib/galaxy/ai/billing/core/quota_enforcer.py` → `DEFAULT_PLAN_LIMITS["base"] = 25.00` / `"basic": 25.00` |
| Default paid plan tier code | `professional` (do not rename) | DB schema + Java mapping depend on it |
| Default paid plan label | "Premium" | Register page UI string |
| Email transport | **nodemailer / SMTP** | `frontend/server/email-service.ts:1` |
| Email config env vars | `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USER`, `EMAIL_PASS`, `EMAIL_SECURE`, `EMAIL_FROM`, `APP_URL` | same file, lines 27–60 |
| When SMTP is unconfigured | Logs `[EmailService] Email not configured…` and **silently no-ops every send** (no crash) | `email-service.ts` `isConfigured()` |
| Stripe webhook entry | `POST /api/billing/stripe/webhook` | `frontend/server/routes.ts:2641` → `stripe-service.ts` |
| Quota enforcement | Galaxy backend, per-job | `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py` |
| Realtime cost accumulator | Redis (`REDIS_URL`) | `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py` |

If anything in your task disagrees with this table, the table wins — flag the disagreement back to the team rather than coding around it.

---

## 2. What is already done (do not rebuild)

These have both a working template **and** a wired trigger in production. Treat them as reference patterns for the work below.

| Scenario | Email function | Trigger |
|---|---|---|
| Email verification on register | `sendVerificationEmail` | `routes.ts` register handler |
| Password reset | `sendPasswordResetEmail` | `POST /api/auth/forgot-password` |
| Welcome / account activated | `sendWelcomeEmail` | `auth-service.ts:547` after email verified |
| Workflow complete | `sendWorkflowCompleteEmail` | Nextflow executor callback |
| Workflow failed | `sendWorkflowErrorEmail` | Nextflow executor callback |
| Payment failed | `sendPaymentFailedEmail` | Stripe `invoice.payment_failed` webhook |

The patterns to copy when adding new senders:
- Use the existing nodemailer transporter; do not introduce a new mailer library.
- Match the inline-CSS HTML style of the existing templates so brand looks consistent.
- Always set `text` fallback (every existing template does this).
- Wrap the send in `try/catch` and log on failure; never let a transient SMTP error fail a webhook handler or block a user-facing action.

---

## 3. Sprint 1 — must ship before public trial launch

### 3.1 Quota warning at 80% and 100% (Gap #1)

**Why this is must-ship.** Trial budget is $25. 80% is $20 — a few medium jobs and the user is there with zero warning. Hitting the 100% wall without an inbound email feels like a bug; that drives 1-star reviews and pre-activation churn.

**Template — already exists.**
```ts
emailService.sendQuotaWarningEmail(email, userName, pct, usedUsd, quotaUsd, addCreditsUrl)
```
Location: `frontend/server/email-service.ts:547`.
Subjects already vary by `pct` ("80% used" vs "exhausted — jobs paused"); no template change required.

**Where to wire it.**
1. In `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py`, after the existing `job_completed` recording, compute:
   ```python
   pct = (total_used_usd / quota_limit_usd) * 100.0
   ```
2. For each threshold in `(100, 80)` (check 100 first so the exhausted path wins over the warning path):
   - Build the Redis dedup key (see below). If `SET key 1 NX EX <ttl>` returns `OK`, fire the alert; if it returns `nil`, skip — we already sent this threshold this period.
3. To fire the alert, `POST` to a new Node.js internal endpoint with the existing `BILLING_INTERNAL_KEY` header pattern (same scheme as `/internal/billing/llm_cost`):
   ```
   POST /internal/billing/quota-alert
   Headers: X-Internal-Key: <BILLING_INTERNAL_KEY>
   Body: { user_id, email, name, pct, used_usd, quota_usd, period_start_iso }
   ```
4. In Node.js (`frontend/server/routes.ts`), implement the route. Resolve `email` and `name` from `users` table if not passed, then call `emailService.sendQuotaWarningEmail(...)`. Return `{ sent: true }` or `{ sent: false, reason }`.

**Dedup — concrete proposal.** Reuse the existing billing Redis; no new infrastructure.

```
key:    quota_alert_sent:{user_id}:{period_start_iso}:{threshold}
value:  1
TTL:    seconds_until_period_end + 86400   # auto-expires; no cleanup job
```

`threshold ∈ {80, 100}`. Use `SET key 1 NX EX ttl` for an atomic "first writer wins" check — only the call that actually set the key sends the email. The keys expire naturally at period rollover. To audit which alerts were sent: `SCAN 0 MATCH quota_alert_sent:*`.

**Edge cases to test before merging.**
- 100% hit on the same `job_completed` that crosses 80%: send only the 100% email.
- Quota cap raised mid-period (e.g. trial → paid): the existing 80%/100% keys remain set, so no re-alert. Correct.
- Quota lowered mid-period (e.g. downgrade): user may already be above the new 80%. Acceptable — they'll hit 100% next job and get the exhausted email.
- Redis unavailable: log and fall through to sending the email. A duplicate email is much better than a silent ceiling.

### 3.2 Trial ending reminder (Gap #2)

**Why must-ship.** Highest-impact retention email — users who are about to lose access need to know.

**New work.**
- **Template:** add `sendTrialEndingEmail(email, userName, trialEndDate, planName, price, upgradeUrl)` to `email-service.ts`. Subject: `Your BioMate trial ends in 3 days`. Mirror the visual style of `sendWelcomeEmail`. Include:
  - Trial end date (formatted in user's locale if available, otherwise UTC).
  - What happens after: subscription starts at $X/month, or jobs paused if no conversion.
  - Primary CTA "Continue with BioMate" → `${appUrl}/billing`.
  - Secondary link "Cancel before trial ends" → Stripe customer portal URL.
- **Stripe webhook handler:** in `frontend/server/stripe-service.ts` `handleEvent` switch, add:
  ```ts
  case 'customer.subscription.trial_will_end':
    await this.handleTrialWillEnd(event.data.object as Stripe.Subscription);
    break;
  ```
  In `handleTrialWillEnd`, look up the user by `subscription.customer`, fetch `email` and `fullName`, then call `emailService.sendTrialEndingEmail(...)`.
- **Stripe dashboard:** ensure `customer.subscription.trial_will_end` is enabled on the webhook endpoint (see §6).

**Idempotency.** Stripe will send `trial_will_end` exactly once per trial under normal operation, so no dedup is needed. Don't add one — it just hides bugs.

### 3.3 Subscription canceled confirmation (Gap #5, promoted)

**Why must-ship.** Silent cancellation looks broken; users expect a confirmation receipt by GDPR/CCPA convention.

**New work.**
- **Template:** `sendSubscriptionCanceledEmail(email, userName, planName, accessExpiresDate, resubscribeUrl)`. Subject: `Your BioMate subscription has been canceled`. Contents:
  - Confirmation that cancellation was received.
  - Date access expires (end of current billing period from `subscription.cancel_at` or `current_period_end`).
  - CTA "Reactivate subscription" → `${appUrl}/billing`.
  - One-sentence note on data retention (defer to existing privacy doc).
- **Wire:** in `handleSubscriptionDeleted` (already exists at `stripe-service.ts:225`), after the existing DB update call the new template.

---

## 4. Sprint 2 — shortly after launch

### 4.1 Invoice / renewal receipt (Gap #3)

- Template: `sendInvoiceReceiptEmail(email, userName, invoiceId, amountPaid, periodStart, periodEnd, planName, invoicePdfUrl)`. Subject: `BioMate receipt — $X charged`.
- Wire: Stripe `invoice.payment_succeeded` already has a handler that logs only. Add the send call there. Use `invoice.hosted_invoice_url` for the PDF link.
- Skip on the trial-period-start invoice ($0) — easy filter on `amountPaid === 0`.

### 4.2 Subscription activated (Gap #4)

- Template: `sendSubscriptionActivatedEmail(email, userName, planName, monthlyPrice, billingDate, manageUrl)`.
- Trigger: in `handleSubscriptionUpdate`, detect the `previous_attributes.status === 'trialing'` AND `subscription.status === 'active'` transition (Stripe sends `previous_attributes` on the event).

---

## 5. Sprint 3 — polish

- **Gap #6 (credit top-up confirmation).** Template `sendCreditTopupEmail(email, userName, amountUsd, newBalanceUsd, billingUrl)`. Wire in `handleCheckoutCompleted` after `_creditBillingQuota()` for sessions with `metadata.credit_topup === 'true'`.
- **Gap #7 (monthly usage digest).** Template `sendMonthlyUsageSummaryEmail(...)`. Trigger via cron on the 1st of each month, or driven by Lago `invoice.finalized`. Decision deferred until we have one full billing cycle of real data.

---

## 6. Stripe webhook events to enable

The Stripe dashboard webhook endpoint must have ALL of these enabled. If you add a new handler in `stripe-service.ts` but forget to enable the event, the email never fires and you'll waste an hour wondering why.

| Event | Sprint | Handler |
|---|---|---|
| `checkout.session.completed` | 1 (live) | `handleCheckoutCompleted` (existing) |
| `customer.subscription.created` | 1 (live) | `handleSubscriptionUpdate` (existing) |
| `customer.subscription.updated` | 1 (live) | `handleSubscriptionUpdate` (existing) |
| `customer.subscription.deleted` | 1 | `handleSubscriptionDeleted` (extend to send email — Gap 5) |
| `customer.subscription.trial_will_end` | 1 | **NEW** `handleTrialWillEnd` (Gap 2) |
| `invoice.payment_succeeded` | 2 | extend (Gap 3) |
| `invoice.payment_failed` | 1 (live) | `handlePaymentFailed` (existing) |

---

## 7. SMTP credentials — needed before any of this works

Today the test EC2's frontend container has **no `EMAIL_*` env vars set**, so every `send*` call silently no-ops. Before merging Sprint 1, set the following keys in AWS Secrets Manager (`test/biomate/galaxy-env` for test, equivalent for dev/prod) so they land in `/opt/biomate/.env` on the next deploy:

```
EMAIL_HOST
EMAIL_PORT          # 587 unless using implicit-TLS 465
EMAIL_USER
EMAIL_PASS
EMAIL_SECURE        # "true" only for port 465
EMAIL_FROM          # e.g. noreply@biomate.ai
APP_URL             # e.g. https://test.stage-public.biomate.ai
```

Choice of provider isn't decided — Postmark, AWS SES, and SendGrid all work with nodemailer SMTP. Whichever you pick, verify the FROM domain (`biomate.ai` or `biomate.dev`) and configure SPF + DKIM before the first send to a real user, or every email will land in spam.

---

## 8. Known inconsistencies (flag these, don't silently work around)

1. **Schema vs code: trial duration.** `frontend/shared/schema.ts:17` declares `users.trial_ends_at` default `NOW() + INTERVAL '7 days'`. The actual register path overrides to 14 days. Real users get 14 days. The mismatch only matters if a row is inserted via the column default — backfill scripts, fixtures, or a future API route that forgets to set the column. **Fix:** change the schema default to `INTERVAL '14 days'` and add a migration. Tracked separately; not blocking trial launch.
2. **Frontend mirror is informational only.** `frontend/server/plan-config.ts` `TIER_QUOTA_USD = { professional: 25.00, ... }` is for UI messaging. The server-side enforcement number that actually blocks is `quota_enforcer.py` `DEFAULT_PLAN_LIMITS`. If you change one, change both — and re-deploy both.
3. **`20260518_TRIAL_QUOTA_CONFIGURATION.md`** says trial is `$55/month`. That number was never adopted. The doc now carries a SUPERSEDED banner pointing at the $25 doc; don't quote the $55 number anywhere.

---

## 9. Where to look in the code

| What | File |
|---|---|
| All email templates | `frontend/server/email-service.ts` |
| Stripe webhook handlers | `frontend/server/stripe-service.ts` |
| Stripe webhook endpoint | `frontend/server/routes.ts:2641` |
| Auth + register + verify | `frontend/server/auth-service.ts` |
| User schema (Drizzle) | `frontend/shared/schema.ts` |
| Plan + quota mirror (informational) | `frontend/server/plan-config.ts` |
| Quota enforcement (authoritative) | `backend/lib/galaxy/ai/billing/core/quota_enforcer.py` |
| Realtime cost accumulator | `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py` |
| Galaxy billing API (internal endpoints) | `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py` |
| Billing router (user-facing endpoints) | `backend/lib/galaxy/ai/billing/api/billing_router.py` |

---

## 10. Suggested PR ordering

Each item is independently shippable and testable. Don't bundle.

1. **SMTP secret + env wire-up.** Lowest risk; lets every send call start working without code change.
2. **Quota warning wiring (Gap 1).** Highest user-visible impact for trial users.
3. **Trial ending reminder (Gap 2).** Highest retention impact.
4. **Subscription canceled email (Gap 5).** Lowest-effort of the Sprint 1 items.
5. **Schema-default fix migration.** Safe, small, addresses Inconsistency 1.
6. **Sprint 2 + 3 work** in any order — they're polish.
