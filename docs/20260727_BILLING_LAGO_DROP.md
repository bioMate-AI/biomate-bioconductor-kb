# Billing: Lago Dropped from the Critical Path (Flat-Tier Billing)

**Date:** 2026-07-27
**Author:** Engineering (with Claude)
**Commit:** `0e0ff9d82` on `integration/next-phase`
**Status:** ✅ Shipped to `integration/next-phase` (not yet synced to dev)
**Related:** `docs/20260727_TIER_MODEL_DECISION.md` (the tier model this implements)

---

## TL;DR for the team

We **removed Lago from the billing critical path.** Billing now runs on two things:

1. **Stripe** — subscriptions & payment. Sets a user's `subscriptionTier`.
2. **Internal quota** — `DEFAULT_PLAN_LIMITS` (in `quota_enforcer.py`) + the Redis realtime cost ledger.

Lago is still in the codebase but **turned off by default** behind a feature flag
(`BILLING_LAGO_ENABLED`, default `false`). When off, every Lago call is a safe no-op and the system
gets its quota from `DEFAULT_PLAN_LIMITS` instead of asking Lago.

**Nothing about how much users are charged changed.** This is an architecture simplification, not a
pricing change. No live quota value was modified.

---

## Why we did this

Lago is a **usage-metering** service. It earns its keep when you bill customers for *how much they
used* — metered/overage billing (per vCPU-second, per GB-hour, per token above an included amount).

Our billing model is now **flat-tier** (decided 2026-07-27, see `20260727_TIER_MODEL_DECISION.md`):

| Tier | Price | Billing motion |
|---|---|---|
| Free | $0 | self-serve, capped (3 projects) |
| Premium | $100/mo | self-serve, flat |
| Team | custom | sales-led |
| Enterprise | custom | sales-led |

A flat monthly price does **not** need per-unit metered billing. What it needs is:
- **Subscription state** (is this user paying? what plan?) → **Stripe** already does this.
- **A spend/quota guardrail** (stop runaway compute cost within a plan) → **internal `DEFAULT_PLAN_LIMITS` + Redis** already does this.

So Lago sat in the critical path adding: a second source of truth for quota, a network dependency
(a hosted EC2 box + circuit breaker), and operational surface (customers/subscriptions to keep in
sync with our DB) — for a capability (metered/overage billing) the product doesn't currently sell.
Dropping it removes a dependency and a class of "Lago is down / out of sync" failure modes.

We kept the Lago code (dormant, flag-gated) rather than deleting it, because if we ever add
usage-based or overage billing, flipping one env var brings it back.

---

## Architecture: before vs. after

### Before (Lago on the critical path)

```
                    ┌─────────────────────────────────────────────┐
   LLM chat  ─────► │  file cost log  ─►  Redis realtime ledger    │
   Batch job ─────► │                                              │
                    └───────────────┬──────────────┬──────────────┘
                                    │              │
                          quota read│              │emit usage events
                                    ▼              ▼
                            ┌──────────────┐  ┌──────────┐
                            │ Java billing │  │   Lago   │  ◄── hosted EC2, metering,
                            │  (:8080)     │  │ (metering)│     circuit breaker, customer sync
                            └──────────────┘  └──────────┘
```

### After (flat-tier: Stripe + internal quota)

```
   Stripe  ──► subscriptionTier (entitlement: free/premium/team/enterprise)

                    ┌─────────────────────────────────────────────┐
   LLM chat  ─────► │  file cost log  ─►  Redis realtime ledger    │  ◄── real-time spend
   Batch job ─────► │                                              │
                    └───────────────────────┬─────────────────────┘
                                            │ quota check
                                            ▼
                            ┌──────────────────────────────┐
                            │  DEFAULT_PLAN_LIMITS          │  ◄── quota_enforcer.py
                            │  (quota_enforcer.py)          │      the single quota source
                            └──────────────────────────────┘

          Lago  ──►  DORMANT (BILLING_LAGO_ENABLED=false); all calls no-op
```

**Key point:** the Redis realtime ledger and the file cost log are unchanged — we still track every
dollar of LLM and compute spend. What changed is *where quota limits come from* (now always
`DEFAULT_PLAN_LIMITS`, never Lago) and *whether we emit usage events to Lago* (now no).

---

## The feature flag

Single environment variable controls everything:

```bash
BILLING_LAGO_ENABLED=false   # default — Lago off, flat-tier billing
BILLING_LAGO_ENABLED=true    # re-enable Lago (only if metered/overage billing returns)
```

`lago_enabled()` in `lago_client.py`:

```python
def lago_enabled() -> bool:
    return os.environ.get("BILLING_LAGO_ENABLED", "false").lower() == "true"
```

**Default-off** is the safe posture: a fresh environment with no env var set gets flat-tier billing
automatically, with no chance of a half-configured Lago silently swallowing events.

---

## What changed, file by file

### 1. `backend/lib/galaxy/ai/billing/core/lago_client.py`
Added `lago_enabled()` and gated every outbound Lago method so that **when Lago is off the caller
sees a benign result and never makes a network call**:

| Method | Behavior when disabled | Why that value |
|---|---|---|
| `send_event` | returns `True` | "event recorded" — success, so callers don't log/retry |
| `send_batch_events` | returns `len(events)` | "all N accepted" |
| `get_plan_limit_usd` | returns `None` | `None` → `quota_enforcer` falls back to `DEFAULT_PLAN_LIMITS` |
| `get_current_usage` | returns `None` | usage comes from the Redis ledger, not Lago |
| `upsert_customer` | returns `True` | provisioning no-op success |
| `assign_plan` | returns `True` | provisioning no-op success |

The critical one is `get_plan_limit_usd` → `None`: the quota enforcer is **already written** to fall
back to `DEFAULT_PLAN_LIMITS` when Lago returns no limit, so quota "just works" with Lago off.

### 2. `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py`
The AWS Batch billing Lambda's `_emit_to_lago()` now early-returns when the flag is off:

```python
def _emit_to_lago(...):
    if os.environ.get("BILLING_LAGO_ENABLED", "false").lower() != "true":
        return  # Lago dropped — cost is tracked in Redis by _record_completed
```

**Compute cost is still recorded** — `_record_completed()` writes it to Redis
(`cost:{user_id}:month:{YYYY-MM}:total`) *before* the Lago emit, so dropping the emit loses nothing
for internal accounting.

### 3. `frontend/e2e/billing-smoke.e2e.ts`
Rewritten to be **Lago-free**. The post-sync smoke test now verifies the *internal* pipeline (no
mocks, live backend):
- `GET /api/billing/usage` → structured breakdown present; LLM usage is **monotonic** after a real
  chat (proves the internal ledger recorded the cost).
- `GET /api/billing/quota` → returns a plan limit sourced from `DEFAULT_PLAN_LIMITS` (a number, or
  `null` = unlimited).

### 4. `backend/lib/galaxy/ai/billing/tests/test_lago_gate.py` (new)
5 unit tests locking in the gate:
- `lago_enabled()` defaults `False`; flips on `BILLING_LAGO_ENABLED=true`.
- `send_event`/`send_batch_events` no-op to success when disabled (no HTTP call).
- `get_plan_limit_usd`/`get_current_usage` return `None` when disabled.
- `upsert_customer`/`assign_plan` no-op to success when disabled.

### 5. `CLAUDE.md`
Added a note at the top of the **Billing System** section marking Lago as dropped from the critical
path and pointing to `BILLING_LAGO_ENABLED=true` for re-enablement. The detailed 4-layer Lago
architecture below that note is **retained for context / re-enablement** but is now historical, not
current guidance.

---

### 6. `backend/lib/galaxy/ai/cost_log.py` (found during live testing)
A **second, ungated** direct-Lago emit surfaced on dev: `cost_log._forward_to_lago()` POSTed every
LLM usage event to Lago because dev still has a stale `LAGO_API_URL`/`LAGO_API_KEY` set — so each
Galaxy-backend LLM call spawned a daemon thread that blocked on a 5s timeout (`[CostLog→Lago]
Forward failed (non-fatal): urlopen error timed out`). Gated with the same single source of truth
(`lago_client.lago_enabled()`): skip spawning the thread in `record()` and early-return in
`_forward_to_lago()`. Local JSONL cost log + Redis ledger unchanged — only the Lago forward stops.
(commit `d72900b09`)

---

## How this was verified

**Pre-sync (laptop):**
- **Gate behavior:** standalone-loaded `lago_client.py` (bypassing the heavy Galaxy import) —
  disabled → `send_event`=`True`, `get_plan_limit_usd`=`None`, `upsert_customer`=`True`. All pass.
- **Python 3.9 compat:** `py_compile` clean on `lago_client.py`, `batch_event_handler.py`, `cost_log.py`.
- **Frontend:** `tsc` clean; `vitest run` = **942 passed / 6 skipped**; `tier.test.ts` 12/12.
- **Unit tests:** `test_lago_gate.py` (5 tests) for the proper billing-test env / CI.

**On dev (live, read-only SSM):**
- **Deployed gate is live:** on the box, `lago_enabled()` = `False`, `get_plan_limit_usd('premium')`
  = `None` (→ `DEFAULT_PLAN_LIMITS`). Galaxy restarted healthy on py3.9 with all gates loaded.
- **UI end-to-end (`frontend/e2e/chat-costlog-verify.e2e.ts`, passed):** logged in as the canonical
  fixture in a real browser and sent an ADMET prompt → Galaxy generated the `predict_admet_properties`
  workflow → `cost_log.record()` fired. Correlating `galaxy.log` before/after:

  | Signal | Before | After the UI chat |
  |---|---|---|
  | `[CostLog]` internal-ledger writes | last `02:12` | **new `02:48:48`, `02:48:57`** (cost recorded) |
  | `[CostLog→Lago]` forward attempts | `28153`, last `23:43:30` | **`28153`, last `23:43:30` (unchanged)** |

  → A real cost event was recorded through the UI **with zero Lago forwards** — the gate holds on a
  freshly-triggered event, and the internal ledger still captures the cost.

> **Note — billing has no UI surface today:** the `/billing` route is intentionally commented out in
> `client/src/App.tsx` (SB-9: "not yet wired to the backend"), so the Lago drop is a backend-only
> change with no billing page to test. Separately, the Node→Galaxy billing proxy returns 401 on dev
> (a pre-existing `GALAXY_JWT_SECRET` mismatch, unrelated to this change) — fix that before enabling
> the billing page.

---

## Impact & risk

- **User-facing pricing:** none. No live quota value changed. All edits are additive/gating.
- **Data:** none lost. LLM + compute cost still flows to the file log and Redis ledger.
- **Rollback:** set `BILLING_LAGO_ENABLED=true` — every gated method resumes calling Lago exactly as
  before. No code revert needed.
- **Ops:** one fewer live dependency (hosted Lago) in the critical billing path.

---

## Re-enabling Lago (if metered/overage billing returns)

1. Set `BILLING_LAGO_ENABLED=true` on the relevant service(s) (Galaxy backend + the Batch billing
   Lambda's env).
2. Ensure `LAGO_API_URL` / `LAGO_API_KEY` point at the production Lago instance and customers are
   provisioned.
3. The gated methods resume real behavior automatically — no code change.

---

## Deployment status & next steps

- **Landed:** commit `0e0ff9d82`, pushed to `origin/integration/next-phase` (clean fast-forward).
- **Not yet on dev:** run `scripts/sync_to_dev.sh` (after the pre-sync checklist) to deploy. The dev
  env should have `BILLING_LAGO_ENABLED` unset or `false` — confirm with
  `docker exec biomate-galaxy-dev printenv BILLING_LAGO_ENABLED`.

### Deferred (not blocking this change)
- **Turn on tier enforcement** — the flat-tier gates (Free 3-project cap, collaboration=Team) and the
  tier↔quota reconciliation are already in code behind `TIER_ENFORCEMENT` (default off). Turning them
  on needs: provision real `team`/`premium` plans, set `subscriptionTier` on paying accounts, add the
  upgrade-CTA UI, then flip `TIER_ENFORCEMENT=on`. See `20260727_TIER_MODEL_DECISION.md`.
- **Billing email notifications** (quota warnings, trial-ending) — the #1 pre-launch billing gap.
