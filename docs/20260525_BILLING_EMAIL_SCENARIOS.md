# BioMate Billing Email Scenarios

**Date:** 2026-05-25  
**Scope:** All automated emails related to billing, subscriptions, quotas, and payments  
**Primary files:** `frontend/server/email-service.ts`, `frontend/server/stripe-service.ts`

---

## Overview

BioMate sends automated emails in two categories:

| Category | Trigger source |
|---|---|
| **Auth & onboarding** | Node.js auth routes (registration, verification, password reset) |
| **Billing & subscription** | Stripe webhooks → `stripe-service.ts` → `email-service.ts` |
| **Quota & compute** | Galaxy billing API → Node.js billing routes → `email-service.ts` |
| **Workflow events** | `workflow-notification-service.ts` (not billing-specific) |

---

## Current Status: What Is Already Implemented

### 1. Email Verification
- **Trigger:** User registers → `POST /api/auth/register`
- **Template:** `sendVerificationEmail(email, token, userName)`
- **Subject:** `Verify Your BioMate Account`
- **Contains:** Verification link (expires 24 hours)
- **Status:** Implemented and wired

### 2. Password Reset
- **Trigger:** User submits forgot-password form → `POST /api/auth/forgot-password`
- **Template:** `sendPasswordResetEmail(email, token, userName)`
- **Subject:** `Reset Your BioMate Password`
- **Contains:** Reset link (expires 1 hour), security notice
- **Status:** Implemented and wired

### 3. Welcome / Account Activated
- **Trigger:** Email verification confirmed → `auth-service.ts:547`
- **Template:** `sendWelcomeEmail(email, userName)`
- **Subject:** `Welcome to BioMate - Your Account is Active!`
- **Contains:** 14-day trial summary, feature list, "Get Started" button → `${appUrl}/`
- **Status:** Implemented and wired

### 4. Payment Failed
- **Trigger:** Stripe webhook `invoice.payment_failed`
- **Template:** `sendPaymentFailedEmail(email, userName, amountDue, nextAttemptDate, updateUrl)`
- **Subject:** `Action Required: BioMate Payment Failed`
- **Contains:** Amount due, next retry date, "Update Payment Method" button → `/billing`
- **What happens in DB:** `subscriptionStatus` set to `past_due`
- **Status:** Implemented and wired

### 5. Quota Warning (Template Exists — NOT Wired)
- **Trigger:** Should fire at 80% and 100% of monthly compute quota
- **Template:** `sendQuotaWarningEmail(email, userName, pct, usedUsd, quotaUsd, addCreditsUrl)`
- **Subject (80%):** `BioMate: you've used 80% of your monthly quota`
- **Subject (100%):** `Your BioMate quota is exhausted — jobs paused`
- **Contains:** Progress bar graphic, used/limit amounts, "Add Credits Now" button → `/billing`
- **Status:** Template implemented, **never called** — needs wiring (see Gap #1 below)

---

## Gaps: What Needs to Be Implemented

### Gap 1 — Quota Warning Trigger (HIGH PRIORITY)

**What:** The quota warning email template exists but is never invoked.

**Where to wire it:** In `billing_internal.py` (Galaxy backend), after each compute job completes, the backend already checks quota usage to enforce limits. The 80% and 100% thresholds should trigger a `POST` to an internal Node.js endpoint (e.g. `POST /internal/billing/quota-alert`) which then calls `emailService.sendQuotaWarningEmail(...)`.

**Logic:**
```
after job_completed recorded:
  pct = total_used_usd / quota_limit_usd * 100
  if pct >= 100 and not already_sent_100pct_alert:
    → send "quota exhausted" email (red, jobs paused)
  elif pct >= 80 and not already_sent_80pct_alert:
    → send "80% used" email (amber, warning)
```

**De-duplication:** Track `quota_alert_80_sent` and `quota_alert_100_sent` boolean flags per billing period (reset at period start) — either in Redis or in the users DB. Do not send the same threshold email more than once per billing period.

---

### Gap 2 — Trial Ending Reminder (HIGH PRIORITY)

**What:** When a user's trial ends in 3 days, Stripe fires `customer.subscription.trial_will_end`. BioMate currently has no handler for this event and no email template.

**Stripe webhook to add:** `customer.subscription.trial_will_end`

**New email template to add:** `sendTrialEndingEmail(email, userName, trialEndDate, planName, price, upgradeUrl)`

**Subject:** `Your BioMate trial ends in 3 days`

**Contains:**
- Trial end date
- What happens after: subscription starts at $X/month (or jobs paused if they don't convert)
- "Continue with BioMate" button → `/billing`
- "Cancel before trial ends" link → Stripe customer portal

**Where to add the handler in stripe-service.ts:**
```typescript
case 'customer.subscription.trial_will_end':
  await this.handleTrialWillEnd(event.data.object as Stripe.Subscription);
  break;
```

---

### Gap 3 — Invoice / Payment Receipt (MEDIUM PRIORITY)

**What:** When a subscription renews successfully, Stripe fires `invoice.payment_succeeded`. The current handler logs only — no receipt is sent to the user.

**New email template to add:** `sendInvoiceReceiptEmail(email, userName, invoiceId, amountPaid, periodStart, periodEnd, planName, invoicePdfUrl)`

**Subject:** `BioMate receipt — $X charged`

**Contains:**
- Invoice number (Stripe `invoice.number`)
- Amount charged
- Billing period (e.g. "June 1 – June 30, 2026")
- Plan name
- "View Invoice" button → Stripe-hosted invoice PDF URL
- "Manage billing" link → `/billing`

**Where to wire:** In `handlePaymentSucceeded()` in `stripe-service.ts` (currently just logs).

---

### Gap 4 — Subscription Activated After Trial (MEDIUM PRIORITY)

**What:** When a trial converts to a paid subscription (either because the user paid, or trial ended naturally and auto-renewed), no email confirms this to the user. The `customer.subscription.updated` webhook fires (status changes from `trialing` → `active`) but the current handler only updates the DB.

**New email template to add:** `sendSubscriptionActivatedEmail(email, userName, planName, price, interval, nextBillingDate, manageUrl)`

**Subject:** `Your BioMate subscription is now active`

**Contains:**
- Plan name and price confirmation
- Next billing date
- "Manage subscription" link → `/billing`

**Where to wire:** In `handleSubscriptionUpdate()` — detect the `trialing → active` status transition.

---

### Gap 5 — Subscription Canceled (MEDIUM PRIORITY)

**What:** When a subscription is canceled (either by the user via the portal, or by Stripe due to failed payments), `customer.subscription.deleted` fires and the DB is updated, but no email is sent.

**New email template to add:** `sendSubscriptionCanceledEmail(email, userName, planName, accessExpiresDate, resubscribeUrl)`

**Subject:** `Your BioMate subscription has been canceled`

**Contains:**
- Confirmation that cancellation was received
- Date their access expires (end of current billing period)
- "Reactivate subscription" button → `/billing`
- Note about data retention

**Where to wire:** In `handleSubscriptionDeleted()` in `stripe-service.ts`.

---

### Gap 6 — Credit Top-Up Confirmation (LOW PRIORITY)

**What:** When a user purchases a credit top-up (one-time Stripe Checkout, `checkout.session.completed` with `metadata.credit_topup = true`), the quota is credited in Redis but no confirmation email is sent.

**New email template to add:** `sendCreditTopupEmail(email, userName, amountUsd, newBalanceUsd, billingUrl)`

**Subject:** `BioMate credits added — $X`

**Contains:**
- Amount added
- New available balance
- "View billing" link

**Where to wire:** In `handleCheckoutCompleted()` in `stripe-service.ts`, after `_creditBillingQuota()` returns.

---

### Gap 7 — Monthly Usage Summary (LOW PRIORITY / FUTURE)

**What:** A monthly digest email showing usage breakdown (LLM tokens, compute hours, storage) sent on the 1st of each month for the previous month.

**Trigger:** Cron job on the 1st of each month (or Lago webhook `invoice.finalized`)

**New email template to add:** `sendMonthlyUsageSummaryEmail(email, userName, month, usageBreakdown[], totalUsd, quotaUsd, billingUrl)`

**Contains:**
- Line-item usage table: LLM tokens, vCPU-hours, GPU-hours, S3 storage
- Total vs. plan quota bar
- "View full report" → `/billing`

---

## Full Email Scenario Map

| # | Scenario | Trigger | Template | Status |
|---|---|---|---|---|
| 1 | New user registration | POST /api/auth/register | `sendVerificationEmail` | Done |
| 2 | Password reset | POST /api/auth/forgot-password | `sendPasswordResetEmail` | Done |
| 3 | Account activated | Email verified | `sendWelcomeEmail` | Done |
| 4 | Payment failed | `invoice.payment_failed` webhook | `sendPaymentFailedEmail` | Done |
| 5 | Quota at 80% | Compute job completed | `sendQuotaWarningEmail` | Template only — **not wired** |
| 6 | Quota at 100% (exhausted) | Compute job completed | `sendQuotaWarningEmail` | Template only — **not wired** |
| 7 | Trial ending in 3 days | `trial_will_end` webhook | `sendTrialEndingEmail` | **Not implemented** |
| 8 | Invoice / renewal receipt | `invoice.payment_succeeded` webhook | `sendInvoiceReceiptEmail` | **Not implemented** |
| 9 | Trial converted to paid | `subscription.updated` (trialing→active) | `sendSubscriptionActivatedEmail` | **Not implemented** |
| 10 | Subscription canceled | `subscription.deleted` webhook | `sendSubscriptionCanceledEmail` | **Not implemented** |
| 11 | Credit top-up purchased | `checkout.session.completed` (topup) | `sendCreditTopupEmail` | **Not implemented** |
| 12 | Monthly usage digest | Cron / invoice.finalized | `sendMonthlyUsageSummaryEmail` | **Future** |
| 13 | Workflow completed | Nextflow executor callback | `sendWorkflowCompleteEmail` | Done |
| 14 | Workflow failed | Nextflow executor callback | `sendWorkflowErrorEmail` | Done |

---

## Implementation Priority

**Sprint 1 (before launch):**
- Gap 1: Wire quota warning (template exists, just needs the trigger)
- Gap 2: Trial ending reminder (most important retention email)

**Sprint 2 (shortly after launch):**
- Gap 3: Invoice receipt (users expect a receipt)
- Gap 4: Subscription activated (confirms billing started)
- Gap 5: Subscription canceled (confirm + offer to reactivate)

**Sprint 3 (polish):**
- Gap 6: Credit top-up confirmation
- Gap 7: Monthly usage digest

---

## Stripe Webhooks to Register

When setting up the Stripe dashboard (see `docs/20260525_STRIPE_SANDBOX_SETUP.md`), the following webhook events must all be selected:

| Event | Purpose |
|---|---|
| `checkout.session.completed` | Handle subscription start and credit top-ups |
| `customer.subscription.created` | Update user tier in DB |
| `customer.subscription.updated` | Detect trial→active conversion |
| `customer.subscription.deleted` | Mark subscription canceled in DB + send email |
| `customer.subscription.trial_will_end` | Send 3-day trial reminder **(add to handler)** |
| `invoice.payment_succeeded` | Send receipt email **(add to handler)** |
| `invoice.payment_failed` | Send payment failure email (already handled) |

---

## Key Code Locations

| File | Purpose |
|---|---|
| `frontend/server/email-service.ts` | All email templates |
| `frontend/server/stripe-service.ts` | Stripe webhook handlers |
| `frontend/server/routes.ts:2641` | Stripe webhook endpoint |
| `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py` | Where quota check lives (Gap 1 trigger) |
| `frontend/server/routes.ts` | Internal billing endpoints |
