# Trial Quota Reduced: $50 → $25

**Date:** 2026-05-18
**Branch:** `integration/next-phase`
**Deployed to:** `dev-public.biomate.ai`
**Supersedes the $50 figure in:** `docs/20260518_BILLING_TRIAL_CONFIGURATION_HANDOFF.md`, `docs/20260518_TRIAL_LAUNCH_FINAL_HANDOFF.md`

---

## What changed

Per-user 14-day trial budget is now **$25** (was $50). Everything else from the prior trial-launch handoff is unchanged: 14-day duration, full Premium feature access, no payment required, converts to Academic on expiry.

## Why

Lower per-user blast radius at launch. Worst-case spend caps shift from $5,000/100-users to $2,500/100-users; conservative (30 % active) projection drops from ~$600 to ~$300/mo. We can raise it back to $50 after the first cohort if usage data shows the cap is constraining real workflows.

## Where it's set

Authoritative server-side enforcement (only source that matters for actual blocking):

```python
# backend/lib/galaxy/ai/billing/core/quota_enforcer.py
DEFAULT_PLAN_LIMITS = {
    "free":  5.00,
    "base":  25.00,   # 14-day trial budget
    "basic": 25.00,   # 14-day trial budget (was $50 — reduced 2026-05-18)
    "pro":   500.00,
    ...
}
```

Frontend mirror (for messaging only — tree-shaken from the runtime bundle today, kept in source for consistency):

```ts
// frontend/server/plan-config.ts
TIER_QUOTA_USD = { professional: 25.00, ... }
```

Schema preserved exactly as prior session designed it:

```
subscriptionTier = 'professional'   (code identifier — DO NOT rename)
        ↓
"Premium"                            (user-facing UI label)
        ↓
Lago plan 'basic'                    (billing plan code)
        ↓
$25 monthly cap                      (DEFAULT_PLAN_LIMITS['basic'])
```

The code identifier stays `professional` — every billing test, the Java service mapping, and `TIER_TO_BILLING_PLAN` key on it. Only the UI string says "Premium".

## Commits

- `54ecb5393` — billing(trial): reduce per-user trial quota $50 → $25
- `dbb5ea89b` — Revert professional→premium rename (intermediate over-edit; reverted)

## Deployment

Synced via `scripts/sync_to_dev.sh frontend backend` at 2026-05-18 11:13 UTC. Verified live on dev:

```
$ docker exec biomate-galaxy-dev grep '"basic"' /app/lib/galaxy/ai/billing/core/quota_enforcer.py
35:    "basic":     25.00,    # 14-day trial budget (was $50 — reduced 2026-05-18)
```

## What remains before public-trial launch

Same checklist as `20260518_BILLING_TRIAL_CONFIGURATION_HANDOFF.md` §"Configuration Checklist", with current dev-public status:

| Item | Status on dev-public |
|---|---|
| Env vars (`BILLING_INTERNAL_KEY`, `REDIS_URL`, `LAGO_*`, `JWT_SECRET`, `GALAXY_URL`) | ✅ set in both containers |
| Redis (ElastiCache) reachable | ✅ `PING` OK over TLS |
| Lago API reachable | ✅ `/billable_metrics` returns 200 |
| Java billing service `35.86.137.71:8080` | ❌ `503 DOWN` — fix is uncommitted in the `billing_system/` repo (Redis loopback + disabled Redis health check in `application.yml`). For trial this is OK: `JAVA_BILLING_ENABLED` is unset → already bypassed; cost tracking continues in layers 1–3 (file log, Redis, Lago) per the handoff doc |
| Batch billing Lambda (`biomate-batch-billing`) | ✅ deployed |
| S3 billing Lambda | ❌ not deployed. Deploy script creates IAM role + SQS + DLQ; not blocking trial launch |
| `backfill_billing_customers.py` for existing users | ⏸ blocked on Java service being up |
| `e2e/billing-smoke.e2e.ts` against AWS Lago | not yet run on dev |

## Open decisions for the team

1. Bring Java billing service up (other session's `billing_system` branch has the uncommitted config fix — needs to land + redeploy the jar).
2. Deploy S3 billing Lambda before or after public-trial launch? Not strictly required for the first cohort; Layer 1–3 tracking covers cost.
3. Run `backfill_billing_customers.py` after Java service is up — registers existing users in the billing DB so they get quota records.
4. Hook up Grafana billing dashboard + 80 % quota Slack/email alert + CloudWatch Lambda-error alarms before launch.

## Reminders

- The code identifier is **`professional`**, not `premium`. Don't rename — the schema, Java mapping, and prior tests all depend on the legacy name.
- The user-facing label is **"Premium"**. The register page already says "Start your 14-day Premium trial".
- Quota source of truth is `DEFAULT_PLAN_LIMITS` in `quota_enforcer.py`. The frontend `TIER_QUOTA_USD` is informational only.

## Known inconsistency (flagged for follow-up, not yet fixed)

`frontend/shared/schema.ts:17` declares the `users.trial_ends_at` column
with a Postgres-level default of `NOW() + INTERVAL '7 days'`. The actual
registration path in `frontend/server/auth-service.ts:126` overrides this
to **14 days** (`trialDays = resolvedCode?.trialDays ?? 14`), so every
real registration produces the correct 14-day trial.

The mismatch only bites if a row is ever inserted via the column default
(e.g., a backfill script, a test fixture, or a future API route that
forgets to set `trialEndsAt`). To prevent silent 7-day trials from
leaking in, change the schema default to `INTERVAL '14 days'` and add a
migration. Tracked as a small code task — not blocking trial launch.
