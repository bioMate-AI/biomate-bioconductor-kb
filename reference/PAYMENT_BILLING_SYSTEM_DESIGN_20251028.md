# BioMate Payment & Billing System Design

**Document Created:** 2025-10-28
**Priority:** P2 - Platform Maturity (Month 2-4)
**Status:** Architecture Specification
**Estimated Implementation:** 6-8 weeks

---

## Executive Summary

This document defines the payment and billing system architecture for BioMate platform, enabling commercial viability through automated subscription management, usage tracking, and cost control. The system must support multiple pricing tiers, trial periods, and flexible billing (compute, storage, per-workflow).

**Key Requirements:**
- Subscription management (trials, paid tiers, upgrades/downgrades)
- Usage metering (compute, storage, API calls)
- Cost calculation per workflow
- Payment processing (Stripe integration)
- Invoice generation
- Credit/quota management
- Cost control and alerts

**Business Context:** From 90-Day Strategy, target pricing is:
- Academic: $10K-30K/year
- Biotech: $100K-500K/year
- Clinical: $50-200/report

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Pricing Model](#pricing-model)
3. [Subscription Management](#subscription-management)
4. [Usage Metering](#usage-metering)
5. [Payment Processing](#payment-processing)
6. [Invoice Generation](#invoice-generation)
7. [Cost Control](#cost-control)
8. [Database Schema](#database-schema)
9. [API Design](#api-design)
10. [Implementation Plan](#implementation-plan)

---

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    BioMate Platform Usage                        │
├─────────────────────────────────────────────────────────────────┤
│  • Workflow Executions                                          │
│  • Data Storage (S3)                                            │
│  • API Calls                                                    │
│  • Compute Time (Galaxy)                                        │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Usage Metering Service                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │  Workflow    │   │   Storage    │   │   Compute    │       │
│  │   Tracker    │   │   Tracker    │   │   Tracker    │       │
│  └──────────────┘   └──────────────┘   └──────────────┘       │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                            ↓                                     │
│                  ┌──────────────────┐                           │
│                  │  Usage Events    │                           │
│                  │   (Queue)        │                           │
│                  └──────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                   Billing Aggregation Service                    │
├─────────────────────────────────────────────────────────────────┤
│  • Aggregate usage per customer per billing cycle               │
│  • Apply pricing rules (tier pricing, overage)                  │
│  • Calculate invoice line items                                 │
│  • Check quotas and limits                                      │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Subscription Management                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │    Plans     │   │ Subscriptions│   │    Trials    │       │
│  │  (Catalog)   │   │  (Customer)  │   │  (7-day)     │       │
│  └──────────────┘   └──────────────┘   └──────────────┘       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Payment Processing                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐      │
│  │              Stripe (Payment Gateway)                │      │
│  ├──────────────────────────────────────────────────────┤      │
│  │  • Card processing                                    │      │
│  │  • ACH/Wire transfers (enterprise)                    │      │
│  │  • Subscription billing                               │      │
│  │  • Invoice generation                                 │      │
│  │  • Payment retries                                    │      │
│  │  • PCI compliance                                     │      │
│  └──────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Customer Notifications                      │
├─────────────────────────────────────────────────────────────────┤
│  • Invoice emails                                               │
│  • Payment success/failure alerts                              │
│  • Quota warnings (90% usage)                                  │
│  • Subscription changes                                         │
│  • Trial expiration reminders                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pricing Model

### Pricing Strategy

**Hybrid Model:** Base subscription + usage-based billing

**Why Hybrid:**
- Predictable revenue (base subscription)
- Scales with customer value (usage billing)
- Handles edge cases (light vs heavy users)

---

### Pricing Tiers

#### 1. Free Trial (7 Days)

**Limits:**
- 5 workflow executions
- 10GB storage
- 10 compute hours
- Email support only

**Purpose:** Evaluate platform, prove value

**Auto-Upgrade Prompt:** At 80% of any quota, prompt upgrade

---

#### 2. Academic Tier ($10K-30K/year)

**Target:** Universities, non-profit research labs

**Included:**
- 100 workflow executions/month
- 500GB storage
- 200 compute hours/month
- 3 user seats
- Email + chat support

**Overage:**
- Workflows: $50/execution
- Storage: $0.10/GB/month
- Compute: $5/hour

**Annual Discount:** 20% (pay yearly vs monthly)

---

#### 3. Biotech Tier ($100K-500K/year)

**Target:** Biotech companies, pharma R&D

**Included:**
- Unlimited workflows
- 5TB storage
- 1000 compute hours/month
- 10 user seats
- Priority support (24/7)
- Dedicated account manager
- Custom integrations

**Overage:**
- Storage: $0.08/GB/month (discounted)
- Compute: $4/hour (discounted)

**Annual Discount:** 25%

**Enterprise Add-ons:**
- SSO (SAML): +$10K/year
- Compliance package (SOC 2, HIPAA BAA): +$20K/year
- Instrument integrations: +$5K per instrument/year

---

#### 4. Clinical Tier (Per-Report Pricing)

**Target:** Clinical labs (post-validation)

**Pricing:** $50-200 per report (based on complexity)

**Report Types:**
- Simple variant report: $50
- Cancer panel: $100
- Whole genome analysis: $200

**Minimum:** $10K/month (committed reports)

**Compliance Included:**
- CAP/CLIA validation support
- HIPAA BAA
- SOC 2 Type II certification
- Audit trail

---

### Compute Markup

**AWS Cost Multiplier:** 1.5-2.5x

**Examples:**

| AWS Instance | AWS Cost/hour | BioMate Price/hour |
|--------------|---------------|---------------------|
| m5.xlarge (4 CPU, 16GB RAM) | $0.192 | $0.40 |
| m5.4xlarge (16 CPU, 64GB RAM) | $0.768 | $1.50 |
| c5.9xlarge (36 CPU, 72GB RAM) | $1.530 | $3.00 |
| p3.2xlarge (GPU, 8 vCPU, 61GB RAM) | $3.06 | $6.00 |

**Rationale:** Covers overhead (Galaxy, monitoring, support), industry standard margin

---

### Storage Markup

**S3 Cost Multiplier:** 2.0-3.0x

| Storage Tier | AWS Cost/GB/month | BioMate Price/GB/month |
|--------------|-------------------|-------------------------|
| S3 Standard | $0.023 | $0.05-0.07 |
| S3 Intelligent-Tiering | $0.018 | $0.04-0.06 |
| S3 Glacier | $0.004 | $0.01 |

---

## Subscription Management

### Subscription Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    Subscription States                           │
└─────────────────────────────────────────────────────────────────┘

[New User] → [Trial (7 days)] → [Active] → [Past Due] → [Canceled]
                    │                │            │           │
                    │                │            ↓           ↓
                    │                └──────→ [Paused]    [Deleted]
                    │                            │
                    └────────────────────────────┘
                              (trial expired, no payment)

State Transitions:
• Trial → Active: Payment method added, paid
• Active → Past Due: Payment failed
• Past Due → Active: Payment succeeded (retry)
• Past Due → Canceled: After 3 failed attempts (30 days)
• Active → Paused: User requests pause (enterprise only)
• Canceled → Deleted: After 90 days (data purge)
```

### Trial Management

**Trial Creation:**

```typescript
async function createTrial(userId: string, email: string) {
  const trial = await db.subscriptions.create({
    userId,
    status: 'trial',
    planId: 'free_trial',
    trialStartDate: new Date(),
    trialEndDate: addDays(new Date(), 7),
    quotas: {
      workflows: 5,
      storageGB: 10,
      computeHours: 10,
    },
  });

  // Schedule trial expiration reminder (Day 5)
  await scheduleEmail({
    to: email,
    template: 'trial_expiring',
    sendAt: addDays(new Date(), 5),
    data: { daysLeft: 2 },
  });

  return trial;
}
```

**Trial Expiration:**

```typescript
// Cron job: Check for expired trials (runs daily)
async function handleExpiredTrials() {
  const expired = await db.subscriptions.findMany({
    where: {
      status: 'trial',
      trialEndDate: { lte: new Date() },
    },
  });

  for (const sub of expired) {
    // Send expiration email
    await sendEmail({
      to: sub.user.email,
      template: 'trial_expired',
      data: {
        upgradeUrl: `${BASE_URL}/upgrade?userId=${sub.userId}`,
      },
    });

    // Update status
    await db.subscriptions.update({
      where: { id: sub.id },
      data: { status: 'trial_expired' },
    });

    // Disable workflow execution (but keep data)
    await disableWorkflowExecution(sub.userId);
  }
}
```

---

### Subscription Upgrades/Downgrades

**Upgrade (Trial → Paid):**

```typescript
async function upgradeToPaid(userId: string, planId: string, paymentMethodId: string) {
  // 1. Create Stripe subscription
  const stripeSubscription = await stripe.subscriptions.create({
    customer: user.stripeCustomerId,
    items: [{ price: plans[planId].stripePriceId }],
    default_payment_method: paymentMethodId,
    trial_end: 'now',  // End trial immediately
    expand: ['latest_invoice.payment_intent'],
  });

  // 2. Update BioMate subscription
  await db.subscriptions.update({
    where: { userId },
    data: {
      status: 'active',
      planId,
      stripeSubscriptionId: stripeSubscription.id,
      currentPeriodStart: new Date(stripeSubscription.current_period_start * 1000),
      currentPeriodEnd: new Date(stripeSubscription.current_period_end * 1000),
      quotas: plans[planId].quotas,
    },
  });

  // 3. Enable full platform access
  await enableFullAccess(userId);

  return stripeSubscription;
}
```

**Downgrade (e.g., Biotech → Academic):**

```typescript
async function downgradePlan(userId: string, newPlanId: string) {
  const subscription = await db.subscriptions.findUnique({ where: { userId } });

  // Downgrade at end of current billing period (prorated refund)
  await stripe.subscriptions.update(subscription.stripeSubscriptionId, {
    items: [{
      id: subscription.stripeItemId,
      price: plans[newPlanId].stripePriceId,
    }],
    proration_behavior: 'always_invoice',  // Stripe handles refund
  });

  // Update in DB (effective at period end)
  await db.subscriptions.update({
    where: { userId },
    data: {
      pendingPlanId: newPlanId,
      pendingPlanEffectiveDate: subscription.currentPeriodEnd,
    },
  });

  // Send confirmation email
  await sendEmail({
    to: user.email,
    template: 'plan_downgrade_scheduled',
    data: {
      currentPlan: subscription.planId,
      newPlan: newPlanId,
      effectiveDate: subscription.currentPeriodEnd,
    },
  });
}
```

---

## Usage Metering

### Event Tracking

**Usage Events:**

```typescript
interface UsageEvent {
  id: string;
  userId: string;
  organizationId?: string;
  eventType: 'workflow_execution' | 'compute_time' | 'storage_usage' | 'api_call';
  resourceId: string;  // workflow_id, job_id, etc.
  quantity: number;
  unit: 'count' | 'hours' | 'gb' | 'calls';
  cost?: number;  // AWS cost (for compute/storage)
  metadata: {
    workflowName?: string;
    instanceType?: string;
    storageClass?: string;
  };
  timestamp: Date;
}

// Example: Workflow execution
{
  id: 'evt_abc123',
  userId: 'user_123',
  eventType: 'workflow_execution',
  resourceId: 'workflow_xyz',
  quantity: 1,
  unit: 'count',
  metadata: {
    workflowName: 'RNA-seq Pipeline',
  },
  timestamp: '2025-10-28T10:00:00Z'
}

// Example: Compute time
{
  id: 'evt_def456',
  userId: 'user_123',
  eventType: 'compute_time',
  resourceId: 'job_789',
  quantity: 2.5,  // 2.5 hours
  unit: 'hours',
  cost: 0.48,  // AWS cost (m5.xlarge * 2.5h)
  metadata: {
    instanceType: 'm5.xlarge',
  },
  timestamp: '2025-10-28T12:30:00Z'
}

// Example: Storage (daily snapshot)
{
  id: 'evt_ghi789',
  userId: 'user_123',
  eventType: 'storage_usage',
  resourceId: 's3_bucket',
  quantity: 150,  // 150GB
  unit: 'gb',
  cost: 3.45,  // AWS cost (150GB * $0.023)
  metadata: {
    storageClass: 'S3_STANDARD',
  },
  timestamp: '2025-10-28T00:00:00Z'
}
```

---

### Event Collection

**Workflow Execution Tracking:**

```typescript
// In Galaxy workflow service
async function executeWorkflow(workflowId: string, userId: string) {
  const startTime = Date.now();

  try {
    // Execute workflow
    const result = await galaxyClient.runWorkflow(workflowId);

    // Track usage event
    await trackUsageEvent({
      userId,
      eventType: 'workflow_execution',
      resourceId: workflowId,
      quantity: 1,
      unit: 'count',
      metadata: {
        workflowName: result.name,
      },
    });

    return result;
  } finally {
    const duration = (Date.now() - startTime) / 1000 / 3600;  // hours

    // Track compute time
    await trackUsageEvent({
      userId,
      eventType: 'compute_time',
      resourceId: result.jobId,
      quantity: duration,
      unit: 'hours',
      cost: calculateComputeCost(duration, instanceType),
      metadata: {
        instanceType,
      },
    });
  }
}
```

**Storage Tracking (Daily Cron):**

```typescript
// Runs daily at midnight
async function trackStorageUsage() {
  const users = await db.users.findMany({ where: { status: 'active' } });

  for (const user of users) {
    // Get S3 usage from AWS API
    const usage = await s3Client.getBucketSize(`biomate-${user.id}`);

    // Track event
    await trackUsageEvent({
      userId: user.id,
      eventType: 'storage_usage',
      resourceId: `s3_${user.id}`,
      quantity: usage.sizeGB,
      unit: 'gb',
      cost: usage.costUSD,
      metadata: {
        storageClass: usage.storageClass,
      },
    });
  }
}
```

---

### Quota Enforcement

**Check Quota Before Action:**

```typescript
async function checkWorkflowQuota(userId: string): Promise<boolean> {
  const subscription = await db.subscriptions.findUnique({ where: { userId } });
  const usage = await getUsageThisMonth(userId, 'workflow_execution');

  const quota = subscription.quotas.workflows;
  const used = usage.total;

  // Check if over quota
  if (used >= quota) {
    // Send warning email (if not sent already)
    if (used === quota) {
      await sendEmail({
        to: user.email,
        template: 'quota_exceeded',
        data: {
          quotaType: 'workflow executions',
          quota,
          used,
          upgradeUrl: `${BASE_URL}/upgrade`,
        },
      });
    }

    return false;  // Block execution
  }

  // Warn at 90%
  if (used / quota >= 0.9 && !user.quotaWarningSent) {
    await sendEmail({
      to: user.email,
      template: 'quota_warning',
      data: {
        quotaType: 'workflow executions',
        quota,
        used,
        remaining: quota - used,
      },
    });

    await db.users.update({
      where: { id: userId },
      data: { quotaWarningSent: true },
    });
  }

  return true;  // Allow execution
}
```

---

## Payment Processing

### Stripe Integration

**Why Stripe:**
- Industry standard (PCI DSS Level 1 compliant)
- Handles subscriptions, invoicing, retries
- Supports ACH, wire transfers (enterprise)
- Excellent API, webhooks
- Global support (multi-currency)

**Setup:**

```typescript
import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: '2023-10-16',
});

// Create customer (on signup)
async function createStripeCustomer(user: User) {
  const customer = await stripe.customers.create({
    email: user.email,
    name: user.name,
    metadata: {
      biomate_user_id: user.id,
    },
  });

  await db.users.update({
    where: { id: user.id },
    data: { stripeCustomerId: customer.id },
  });

  return customer;
}
```

---

### Payment Methods

**Card (Default):**

```typescript
// Add payment method
async function addPaymentMethod(userId: string, paymentMethodId: string) {
  const user = await db.users.findUnique({ where: { id: userId } });

  // Attach to customer
  await stripe.paymentMethods.attach(paymentMethodId, {
    customer: user.stripeCustomerId,
  });

  // Set as default
  await stripe.customers.update(user.stripeCustomerId, {
    invoice_settings: {
      default_payment_method: paymentMethodId,
    },
  });
}
```

**ACH/Wire (Enterprise):**

```typescript
// For large annual contracts (>$100K)
async function setupACH(userId: string, bankAccountToken: string) {
  const user = await db.users.findUnique({ where: { id: userId } });

  const bankAccount = await stripe.customers.createSource(
    user.stripeCustomerId,
    { source: bankAccountToken }
  );

  // Verify bank account (micro-deposits)
  await stripe.customers.verifySource(
    user.stripeCustomerId,
    bankAccount.id,
    { amounts: [32, 45] }  // User provides amounts
  );
}
```

---

### Webhooks

**Handle Stripe Events:**

```typescript
// Webhook endpoint: POST /webhooks/stripe
async function handleStripeWebhook(req: Request) {
  const sig = req.headers['stripe-signature'];
  const event = stripe.webhooks.constructEvent(
    req.body,
    sig,
    process.env.STRIPE_WEBHOOK_SECRET
  );

  switch (event.type) {
    case 'invoice.payment_succeeded':
      await handlePaymentSucceeded(event.data.object);
      break;

    case 'invoice.payment_failed':
      await handlePaymentFailed(event.data.object);
      break;

    case 'customer.subscription.updated':
      await handleSubscriptionUpdated(event.data.object);
      break;

    case 'customer.subscription.deleted':
      await handleSubscriptionCanceled(event.data.object);
      break;
  }
}

async function handlePaymentSucceeded(invoice: Stripe.Invoice) {
  const userId = invoice.metadata.biomate_user_id;

  // Update subscription status
  await db.subscriptions.update({
    where: { userId },
    data: {
      status: 'active',
      lastPaymentDate: new Date(),
      lastPaymentAmount: invoice.amount_paid / 100,
    },
  });

  // Send receipt email
  await sendEmail({
    to: invoice.customer_email,
    template: 'payment_success',
    data: {
      amount: invoice.amount_paid / 100,
      receiptUrl: invoice.hosted_invoice_url,
    },
  });
}

async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const userId = invoice.metadata.biomate_user_id;

  // Update subscription status
  await db.subscriptions.update({
    where: { userId },
    data: {
      status: 'past_due',
      paymentFailureCount: { increment: 1 },
    },
  });

  // Send failure email
  await sendEmail({
    to: invoice.customer_email,
    template: 'payment_failed',
    data: {
      amount: invoice.amount_due / 100,
      retryDate: new Date(invoice.next_payment_attempt * 1000),
      updatePaymentUrl: `${BASE_URL}/billing/update-payment`,
    },
  });

  // Cancel after 3 failures (30 days)
  const sub = await db.subscriptions.findUnique({ where: { userId } });
  if (sub.paymentFailureCount >= 3) {
    await cancelSubscription(userId);
  }
}
```

---

## Invoice Generation

### Monthly Invoices

**Invoice Structure:**

```typescript
interface Invoice {
  id: string;
  userId: string;
  billingPeriodStart: Date;
  billingPeriodEnd: Date;
  lineItems: LineItem[];
  subtotal: number;
  tax: number;
  total: number;
  status: 'draft' | 'open' | 'paid' | 'void';
  dueDate: Date;
  paidDate?: Date;
}

interface LineItem {
  description: string;
  quantity: number;
  unit: string;
  unitPrice: number;
  total: number;
  metadata: any;
}

// Example invoice
{
  id: 'inv_202510',
  userId: 'user_123',
  billingPeriodStart: '2025-10-01',
  billingPeriodEnd: '2025-10-31',
  lineItems: [
    {
      description: 'Academic Plan (Base)',
      quantity: 1,
      unit: 'month',
      unitPrice: 1000,
      total: 1000,
    },
    {
      description: 'Workflow Executions (100 included, 25 overage)',
      quantity: 25,
      unit: 'execution',
      unitPrice: 50,
      total: 1250,
    },
    {
      description: 'Storage (500GB included, 150GB overage)',
      quantity: 150,
      unit: 'GB',
      unitPrice: 0.10,
      total: 15,
    },
    {
      description: 'Compute (200 hours included, 50 overage)',
      quantity: 50,
      unit: 'hour',
      unitPrice: 5,
      total: 250,
    },
  ],
  subtotal: 2515,
  tax: 0,  // Tax calculated based on location
  total: 2515,
  status: 'paid',
  dueDate: '2025-11-07',
  paidDate: '2025-11-01',
}
```

**Generate Monthly Invoice (Cron):**

```typescript
// Runs on 1st of each month
async function generateMonthlyInvoices() {
  const subscriptions = await db.subscriptions.findMany({
    where: { status: 'active' },
  });

  for (const sub of subscriptions) {
    // Get usage for last month
    const usage = await getUsageLastMonth(sub.userId);

    // Calculate line items
    const lineItems = calculateLineItems(sub, usage);

    // Create invoice
    const invoice = await db.invoices.create({
      data: {
        userId: sub.userId,
        billingPeriodStart: startOfLastMonth(),
        billingPeriodEnd: endOfLastMonth(),
        lineItems,
        subtotal: sumLineItems(lineItems),
        total: sumLineItems(lineItems),
        status: 'open',
        dueDate: addDays(new Date(), 7),
      },
    });

    // Create Stripe invoice (for payment)
    const stripeInvoice = await stripe.invoices.create({
      customer: sub.user.stripeCustomerId,
      auto_advance: true,  // Automatically finalize and pay
      collection_method: 'charge_automatically',
      description: `BioMate Usage - ${formatMonth(endOfLastMonth())}`,
      metadata: {
        biomate_invoice_id: invoice.id,
      },
    });

    // Add line items to Stripe invoice
    for (const item of lineItems) {
      await stripe.invoiceItems.create({
        customer: sub.user.stripeCustomerId,
        invoice: stripeInvoice.id,
        amount: Math.round(item.total * 100),  // cents
        currency: 'usd',
        description: item.description,
      });
    }

    // Finalize and charge
    await stripe.invoices.finalizeInvoice(stripeInvoice.id);

    // Send invoice email
    await sendEmail({
      to: sub.user.email,
      template: 'invoice_generated',
      data: {
        invoiceUrl: stripeInvoice.hosted_invoice_url,
        amount: invoice.total,
        dueDate: invoice.dueDate,
      },
    });
  }
}
```

---

## Cost Control

### Spending Alerts

```typescript
// Check spending vs budget (runs daily)
async function checkSpendingAlerts() {
  const subscriptions = await db.subscriptions.findMany({
    where: { status: 'active' },
  });

  for (const sub of subscriptions) {
    const usage = await getUsageThisMonth(sub.userId);
    const projected = projectMonthlySpend(usage);

    const budget = sub.quotas.monthlyBudget || Infinity;

    // Alert at 80%, 90%, 100%
    if (projected >= budget * 0.8) {
      await sendEmail({
        to: sub.user.email,
        template: 'spending_alert',
        data: {
          projected,
          budget,
          percentage: Math.round((projected / budget) * 100),
        },
      });
    }

    // Block at 110% (soft limit)
    if (projected >= budget * 1.1) {
      await db.subscriptions.update({
        where: { id: sub.id },
        data: { status: 'paused', pauseReason: 'budget_exceeded' },
      });

      await sendEmail({
        to: sub.user.email,
        template: 'budget_exceeded',
        data: {
          projected,
          budget,
          resumeUrl: `${BASE_URL}/billing/increase-budget`,
        },
      });
    }
  }
}
```

---

## Database Schema

```sql
-- Subscription plans (catalog)
CREATE TABLE plans (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price_monthly DECIMAL(10, 2),
    price_annual DECIMAL(10, 2),
    quotas JSONB,  -- {workflows: 100, storageGB: 500, computeHours: 200}
    features JSONB,  -- {sso: false, priority_support: false}
    stripe_price_id VARCHAR(255),
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Customer subscriptions
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) REFERENCES users(id),
    organization_id VARCHAR(255) REFERENCES organizations(id),
    status VARCHAR(50),  -- trial, active, past_due, canceled, paused
    plan_id VARCHAR(50) REFERENCES plans(id),
    stripe_subscription_id VARCHAR(255),
    trial_start_date TIMESTAMP,
    trial_end_date TIMESTAMP,
    current_period_start TIMESTAMP,
    current_period_end TIMESTAMP,
    quotas JSONB,
    last_payment_date TIMESTAMP,
    last_payment_amount DECIMAL(10, 2),
    payment_failure_count INT DEFAULT 0,
    pending_plan_id VARCHAR(50),  -- For scheduled upgrades/downgrades
    pending_plan_effective_date TIMESTAMP,
    pause_reason TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);

-- Usage events
CREATE TABLE usage_events (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) REFERENCES users(id),
    organization_id VARCHAR(255) REFERENCES organizations(id),
    event_type VARCHAR(50),  -- workflow_execution, compute_time, storage_usage, api_call
    resource_id VARCHAR(255),
    quantity DECIMAL(10, 4),
    unit VARCHAR(20),  -- count, hours, gb, calls
    cost DECIMAL(10, 4),  -- AWS cost
    metadata JSONB,
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_usage_events_user ON usage_events(user_id);
CREATE INDEX idx_usage_events_timestamp ON usage_events(timestamp);
CREATE INDEX idx_usage_events_type ON usage_events(event_type);

-- Aggregated usage (for fast queries)
CREATE TABLE usage_aggregates (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) REFERENCES users(id),
    period_start TIMESTAMP,
    period_end TIMESTAMP,
    workflows INT DEFAULT 0,
    compute_hours DECIMAL(10, 2) DEFAULT 0,
    storage_gb DECIMAL(10, 2) DEFAULT 0,
    api_calls INT DEFAULT 0,
    total_cost DECIMAL(10, 2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, period_start, period_end)
);

CREATE INDEX idx_usage_aggregates_user ON usage_aggregates(user_id);

-- Invoices
CREATE TABLE invoices (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) REFERENCES users(id),
    stripe_invoice_id VARCHAR(255),
    billing_period_start TIMESTAMP,
    billing_period_end TIMESTAMP,
    line_items JSONB,
    subtotal DECIMAL(10, 2),
    tax DECIMAL(10, 2),
    total DECIMAL(10, 2),
    status VARCHAR(50),  -- draft, open, paid, void
    due_date TIMESTAMP,
    paid_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_invoices_user ON invoices(user_id);
CREATE INDEX idx_invoices_status ON invoices(status);
```

---

## API Design

```typescript
// Get current subscription
GET /api/billing/subscription
Response: {
  status: "active",
  plan: {
    id: "academic",
    name: "Academic Tier",
    price: 1000,
  },
  quotas: {
    workflows: 100,
    storageGB: 500,
    computeHours: 200,
  },
  usage: {
    workflows: 75,
    storageGB: 350,
    computeHours: 150,
  },
  nextBillingDate: "2025-11-01",
}

// Get usage this month
GET /api/billing/usage?period=current

// Get invoice history
GET /api/billing/invoices

// Upgrade/downgrade plan
POST /api/billing/subscription/change
Body: {
  planId: "biotech",
  prorated: true,
}

// Add payment method
POST /api/billing/payment-method
Body: {
  paymentMethodId: "pm_xxx",  // From Stripe.js
}

// Cancel subscription
POST /api/billing/subscription/cancel
Body: {
  reason: "Too expensive",
  cancelAt: "period_end",  // or "immediate"
}
```

---

## Implementation Plan

### Phase 1: MVP (Weeks 1-3)

**Week 1:**
- [ ] Set up Stripe account
- [ ] Database schema (plans, subscriptions, usage_events)
- [ ] Trial creation on signup
- [ ] Basic usage tracking (workflow executions)

**Week 2:**
- [ ] Subscription upgrade (trial → paid)
- [ ] Payment method management
- [ ] Quota enforcement
- [ ] Billing API endpoints

**Week 3:**
- [ ] Stripe webhook integration
- [ ] Usage aggregation (daily cron)
- [ ] Spending alerts
- [ ] Testing

**Deliverable:** Trial + basic paid subscriptions working

---

### Phase 2: Invoicing (Weeks 4-5)

**Week 4:**
- [ ] Invoice generation (monthly cron)
- [ ] Line item calculation
- [ ] Overage pricing
- [ ] Invoice email templates

**Week 5:**
- [ ] Payment retries (Stripe handles, but monitoring)
- [ ] Past due handling
- [ ] Subscription cancellation flow
- [ ] Testing

**Deliverable:** Automated monthly invoicing

---

### Phase 3: Enterprise Features (Weeks 6-8)

**Week 6:**
- [ ] ACH/wire payment support
- [ ] Annual billing discount
- [ ] Organization/team billing
- [ ] Multi-user seat management

**Week 7:**
- [ ] Usage dashboards (UI)
- [ ] Cost breakdown reports
- [ ] Budget management
- [ ] Spending forecasts

**Week 8:**
- [ ] Tax calculation (Stripe Tax)
- [ ] Custom contracts (manual invoicing)
- [ ] Compliance (PCI DSS audit)
- [ ] Production deployment

**Deliverable:** Enterprise-ready billing

---

## Success Metrics

### Launch (Week 3)
- ✅ Trial signups converting to paid >10%
- ✅ Payment success rate >95%
- ✅ Zero billing errors
- ✅ Quota enforcement working

### Month 2
- ✅ 50+ paid subscriptions
- ✅ Automated invoicing working
- ✅ $50K+ MRR (Monthly Recurring Revenue)
- ✅ <1% payment failure rate

### Month 4
- ✅ 100+ paid subscriptions
- ✅ Enterprise features operational
- ✅ $200K+ MRR
- ✅ Net Revenue Retention >100%

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Next Review:** Before Phase 1 implementation
**Owner:** BioMate Billing Team
