# Billing, quotas & the two-lane cost model

> One-line promise: after this page you know what's free vs billed, where to read your usage and quota,
> and why BioMate deliberately does **not** quote you a per-run price before you run. For everyone —
> especially the person paying the bill.

<!-- Every claim here is code-verified (tier C); see coverage-ledger.md "## I.13 Billing & quotas". -->

## What this is for

Cost in BioMate follows the **two lanes** from the front door (I.1). Understanding which lane a request
falls in tells you, up front, whether it's a light in-chat answer or a metered cloud pipeline — and
that, not a dollar estimate, is the consequence you decide on before you commit.

## The two-lane cost model

| Lane | What runs | Where | Time | Cost character |
|---|---|---|---|---|
| **Instant** | A cited answer, an ad-hoc calculation, short code | In the conversation | Seconds | Light — LLM tokens (and any ad-hoc compute), metered but small |
| **Cloud** | A validated pipeline on **AWS Batch** | The run panel beside the chat | Minutes to hours | Billed — vCPU-hours, memory-hours, GPU-hours, plus storage of outputs |

The lane is chosen by routing (`laneForText`, `lane-preview.tsx`; see I.1) and you can override it. The
cost model tracks three components regardless of lane: **LLM tokens**, **compute** (Batch job time),
and **S3 storage** — the exact fields the usage API returns (`billing_router.py:214-216`:
`llm_cost_usd`, `compute_cost_usd`, `storage_cost_usd`, `total_usd`).

> **Tip — the lane is your cost signal.** Instant = cheap and immediate; Cloud = a real Batch job with
> real infrastructure cost. Knowing the lane before you send is the point of the front door.

## Where billing lives

The **billing page** is at **`/billing`** (`App.tsx:614-618`, `BillingPage` from `pages/billing.tsx`),
reachable from the sidebar. It reads two endpoints:

- **`GET /api/billing/usage`** — the current-month breakdown: LLM input/output tokens and cost,
  compute cost, storage cost, total, and quota % (`billing.tsx:173`; `billing_router.py:187-234`). It
  degrades gracefully to **zeros** (not a 500) if Redis is unreachable (`billing_router.py:211-219`).
- **`GET /api/billing/quota`** — your plan limit, used amount, quota %, and an `over_quota` flag
  (`billing_router.py:268-290`).

The page also shows usage history (`/api/billing/usage/history`, `billing.tsx:196`) and offers credit
top-ups via the payments/subscription path (`/api/payments/subscription`, `billing.tsx:221`).

![The /billing page: current-month usage broken into LLM / compute / storage, the quota bar, and credit-pack top-ups.](../assets/i13-1-billing-page.png)
<!-- CAPTURE route=/billing ; state=logged in ; focus=billing usage + quota bar ; note=LLM/compute/storage breakdown, quota %, credit packs -->

## The plan model — flat tiers + internal quota

BioMate bills on a **flat-tier subscription model**, not usage-based metering. Two systems run
together (per CLAUDE.md "Billing System"):

1. **Stripe** — subscriptions and payment. Your `subscriptionTier` is set from the Stripe price ID.
2. **Internal quota** — a monthly spend cap per tier, enforced from `DEFAULT_PLAN_LIMITS` in
   `quota_enforcer.py:40-49` plus a Redis realtime ledger. When you approach the cap, the quota %
   climbs; at 100% `over_quota` trips (`billing_router.py:281`).

The canonical tiers are **free / premium / team / enterprise** (`quota_enforcer.py:35-49`), with a
14-day trial budget as a separate axis. Concrete limits live in code — free is a small monthly cap,
premium a larger monthly credit, and team/enterprise are negotiated (effectively unbounded in the
default table). Treat exact dollar values as subject to change; the shape is: **a flat monthly
allowance per tier, tracked in real time, with top-up credits available.**

> **Note — Lago is dropped from the critical path.** Usage-metering via Lago (`lago_client.py`) is
> **off by default** (`BILLING_LAGO_ENABLED`); quota reads fall back to `DEFAULT_PLAN_LIMITS` and emits
> are no-ops (CLAUDE.md billing update 2026-07-27). The billing smoke test verifies the **internal**
> pipeline (`/api/billing/usage` + `/api/billing/quota`), not Lago.

## The pre-run panel shows NO per-run cost or runtime estimate

This is deliberate and worth stating plainly.

When you open a workflow's run panel before confirming (I.6), you will **not** see an estimated dollar
cost or estimated runtime for that run. The component that would render it — **`CostEstimateBadge`** —
is **commented out** in `nextflow-workflow-viewer.tsx:449-476`, with the reason in the source:

> *"Commented out — static lookup table values are not accurate enough to show users. Actual
> infrastructure cost should appear on the per-user billing page sourced from real billing events."*
> (`nextflow-workflow-viewer.tsx:445-448`)

So the honest position is: **BioMate does not quote a speculative per-run price.** Instead:

- **Before** you run, the **lane** (Instant vs Cloud) is your cost signal — not a number.
- **After** you run, **real** cost lands on the **`/billing` page**, sourced from actual usage events
  (LLM tokens + Batch compute + storage), not an estimate.

> **Pitfall — don't wait for a price tag on the run panel.** There isn't one, by design. If you need
> to reason about spend before a large Cloud run, use the domain chapter's expected-timing guidance and
> your remaining quota on `/billing`, not a per-run estimate the product intentionally withholds.

## What's free vs billed (practical read)

- **Instant answers and short ad-hoc compute** — light; they consume LLM tokens (and small compute)
  against your monthly quota.
- **Cloud workflows (AWS Batch)** — the billed lane: vCPU/memory/GPU-hours plus output storage.
- **Reading results, opening panels, browsing the catalogue** — not a metered run.

## Pitfalls & tips

> **Tip — check quota before a big run.** `/billing` shows quota % live (`GET /api/billing/quota`). A
> long cryo-EM or WGS Cloud run draws real compute; make sure you have headroom.

> **Pitfall — usage may read zero if Redis is down.** The usage endpoint returns zeros rather than
> erroring when the realtime ledger is unreachable (`billing_router.py:211-219`); a zero reading during
> an outage is a degradation signal, not proof you spent nothing.

## What's not covered

- **Per-run cost/runtime estimate before Confirm & Run** — intentionally disabled (`CostEstimateBadge`
  commented out, `nextflow-workflow-viewer.tsx:449-476`). → Appendix E.
- **Usage-based / overage billing (Lago metering)** — dropped from the critical path; off by default.
  Re-enabling it is a roadmap decision (`BILLING_LAGO_ENABLED`). → Appendix E.
- **A published price sheet in-app** — exact tier dollar amounts live in code/Stripe config and are not
  documented as fixed here. → Appendix E.

---
_Verification: coverage-ledger.md "## I.13 Billing & quotas" — all tier C (source-read); no Batch runs
fired; no live billing events emitted._
