# BioMate Stripe Payment Integration — Sandbox Setup Guide

**Date:** 2026-05-25  
**Status:** Code is complete. Only Stripe account configuration + env vars needed.

---

## What's Already Implemented (no code needed)

Your colleague has already written all the payment code in the `billing_system` branch, which is now merged into the main branch. Nothing below requires any code changes — only Stripe dashboard configuration and environment variables.

### Backend (`frontend/server/stripe-service.ts`)
| Method | What it does |
|---|---|
| `createTrialCheckoutSession()` | Starts a 14-day free trial, collects card but doesn't charge |
| `createCheckoutSession()` | Direct subscription checkout (no trial) |
| `createPortalSession()` | Stripe-hosted billing portal (update card, cancel, etc.) |
| `createCreditTopupSession()` | One-time credit top-up payment |
| `handleWebhook()` | Processes all Stripe events, updates DB subscription status |
| `getSubscription()` | Fetch current subscription from Stripe |
| `cancelSubscription()` | Cancel a user's subscription |

### API Routes (`frontend/server/routes.ts`)
| Route | Used for |
|---|---|
| `POST /api/payments/start-trial` | Register page "Add payment method" button |
| `POST /api/payments/create-checkout-session` | Direct checkout |
| `POST /api/payments/create-portal-session` | Billing portal link |
| `GET  /api/payments/subscription` | Fetch subscription info |
| `POST /api/payments/cancel-subscription` | Cancel subscription |
| `GET  /api/payments/pricing` | Returns active price IDs |
| `POST /api/payments/webhook` | Stripe webhook receiver |

---

## What You Need to Do

### 1 — Create Stripe Products & Prices (Sandbox)

Log in to **Stripe test mode**: https://dashboard.stripe.com/test/products

Create three products. **Copy each Price ID** — you'll need them for env vars.

**Professional** ← this is what new registrations use
```
Product name:  Biomate Professional
Monthly price: $49.00/month    → STRIPE_PRICE_PROFESSIONAL_MONTHLY
Yearly price:  $528/year ($44/mo) → STRIPE_PRICE_PROFESSIONAL_YEARLY
```

**Academic**
```
Product name:  Biomate Academic
Monthly price: $29.00/month    → STRIPE_PRICE_ACADEMIC_MONTHLY
Yearly price:  $312/year ($26/mo) → STRIPE_PRICE_ACADEMIC_YEARLY
```

**Enterprise**
```
Product name:  Biomate Enterprise
Custom pricing (set as needed)
               → STRIPE_PRICE_ENTERPRISE_MONTHLY
               → STRIPE_PRICE_ENTERPRISE_YEARLY
```

---

### 2 — Configure Webhook

Stripe Dashboard → **Developers → Webhooks → Add endpoint**:

```
URL:     https://dev-public.biomate.ai/api/payments/webhook

Events:
  ✓ checkout.session.completed
  ✓ customer.subscription.created
  ✓ customer.subscription.updated
  ✓ customer.subscription.deleted
  ✓ invoice.payment_succeeded
  ✓ invoice.payment_failed
```

Copy the **Signing secret** (`whsec_...`) → that's `STRIPE_WEBHOOK_SECRET`.

For local testing instead:
```bash
stripe listen --forward-to localhost:5000/api/payments/webhook
```

---

### 3 — Set Environment Variables on Dev Server

Add to `/home/yzhang/biomate/frontend/.env`:

```bash
# Stripe
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Price IDs from Step 1
STRIPE_PRICE_PROFESSIONAL_MONTHLY=price_...
STRIPE_PRICE_PROFESSIONAL_YEARLY=price_...
STRIPE_PRICE_ACADEMIC_MONTHLY=price_...
STRIPE_PRICE_ACADEMIC_YEARLY=price_...
STRIPE_PRICE_ENTERPRISE_MONTHLY=price_...
STRIPE_PRICE_ENTERPRISE_YEARLY=price_...

# Must match the public domain so Stripe redirects back correctly
APP_URL=https://dev-public.biomate.ai
```

Restart the Node.js server after updating.

---

### 4 — Test Checklist

Stripe test cards (use any future expiry, any CVC):

| Scenario | Card |
|---|---|
| Success | `4242 4242 4242 4242` |
| Declined | `4000 0000 0000 0002` |
| 3D Secure | `4000 0025 0000 3155` |

Test steps:
- [ ] Register at `https://dev-public.biomate.ai/register` (fill institution + role — now required)
- [ ] Click **"Add payment method & start trial"**
- [ ] Stripe Checkout opens showing Biomate Professional, $0 today
- [ ] Enter test card, complete checkout
- [ ] Redirected back to `https://dev-public.biomate.ai/`
- [ ] Stripe Dashboard → Customers: new customer created
- [ ] Stripe Dashboard → Subscriptions: 14-day trial active
- [ ] Webhook events received and processed
- [ ] DB: user's `subscriptionStatus = 'trialing'`, `subscriptionTier = 'professional'`

---

## Note on Pricing + Checkout Pages

The `/pricing` and `/checkout` pages are **currently disabled** on the website until sandbox testing is complete. To re-enable after testing passes:

1. Uncomment in `frontend/client/src/App.tsx` (search for "temporarily disabled")
2. Uncomment `Pricing` in `site-header.tsx` and `site-footer.tsx`

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `"Payment system not configured"` | `STRIPE_SECRET_KEY` not set | Set env var, restart server |
| Webhook returns 400 | Wrong `STRIPE_WEBHOOK_SECRET` | Copy secret from the exact endpoint in Stripe Dashboard |
| Subscription not updated after checkout | Webhook not reaching server | Check Stripe Dashboard → Webhooks → Recent deliveries |
| Redirected to wrong URL after checkout | `APP_URL` wrong | Verify `APP_URL=https://dev-public.biomate.ai` |
