# 06a · Billing & Quota

**Verified 2026-08-29.** Model: **flat-tier** — Stripe (subscription/payment) + an internal Redis cost ledger against `DEFAULT_PLAN_LIMITS`. **Lago is dropped from the critical path.**

---

## 1. The flat-tier model

- **`lago_enabled()` defaults OFF** — `ai/billing/core/lago_client.py:66`: `os.environ.get("BILLING_LAGO_ENABLED","false") == "true"`. The Batch Lambda gates the same way (`lambda/batch_event_handler.py:130`). With Lago off, cost is tracked in Redis and quota reads fall through to `DEFAULT_PLAN_LIMITS`.
- **`DEFAULT_PLAN_LIMITS`** (`ai/billing/core/quota_enforcer.py:40`, USD/month):

  | plan | limit | note |
  |------|------:|------|
  | free | 5.00 | |
  | base / basic | 25.00 | 14-day trial budget |
  | premium | 120.00 | canonical paid ($100/mo → $120 credits) |
  | pro | 500.00 | legacy, grandfathered |
  | team / test / enterprise | ∞ | custom/negotiated |

  Canonical tiers = **free · premium · team · enterprise** (`_CANONICAL_TIER` L55, `canonical_tier()` L63). Mirrored frontend-side in `plan-config.ts:59` (`CANONICAL_TIER_QUOTA_USD`) and `tier.ts`.

## 2. Endpoints (`ai/billing/api/billing_router.py`, 1,148 LOC)

**Public** (JWT HS256 via `current_user_id` L150, decodes the same `biomate_token` Bearer):
- `GET /api/billing/usage` (L187) — Redis breakdown, degrades to zeros if Redis unreachable; enriched with Java billing data when available.
- `GET /api/billing/usage/history` (L237), `/quota` (L268), `/invoices` (L293), `/jobs/running` (L308), `/usage/cohort` (L995).

**Internal** (`X-Internal-Key` via `require_internal_key` L141 — 503 if key unset [fail-closed], 403 on mismatch):
- `POST /internal/billing/job_started` (L352), `job_completed` (L369), `s3_put` (L448), `s3_delete` (L617), `llm_cost` (L494), `set_quota` (L560), `set_plan` (L576), `add-credits` (L600), `register_user` (L641).
- `POST /internal/users/provision` (L684) — Galaxy account + API-key provisioning (see [AUTH §3](AUTH_CREDENTIALS_SANDBOX.md)).
- Admin: `/admin/health`, `/admin/users`, `/admin/cohort_cost`. Lago webhook `/webhooks/lago` (L1106).

**Separate module** `billing_internal.py:77` also registers `POST /internal/billing/llm_cost` — called by the frontend Node server after each chat stream (validates `X-Internal-Key`, writes a durable file cost-log + Redis realtime cost + optional Lago). ⚠️ **Both `billing_router.py:494` and `billing_internal.py:77` register `/internal/billing/llm_cost`** — a route-conflict to be aware of. `billing_lite.py` is a fallback file-cost-log API (no Redis/Lago); `billing.py` is a discovery shim.

## 3. Quota enforcement path

- `quota_enforcer.check_and_reserve(user_id, est_cost)` (L134) reads Redis costs and raises `QuotaExceededError` (→ 402) when `total >= limit`; allows if no quota set.
- `ensure_quota_set()` (L81) tries Lago `get_plan_limit_usd()` first, else `DEFAULT_PLAN_LIMITS` — the live path since Lago is off.
- **Realtime ledger** — `realtime_cost_service.py`: `get_current_costs()` (L399) assembles llm/compute/storage + running-job estimates from Redis `cost:{uid}:month:{month}:*`; `set_quota()` writes `quota:{uid}:month:{month}:limit`. Priced by `cost_calculator.py` (`LLM_PRICING`: opus-4-6 $15/$75 per 1M, sonnet-4-6 $3/$15, haiku-4-5 $0.25/$1.25; `EC2_INSTANCE_PRICING`).

## 4. Is tier gating actually enforced?

Two axes — the project note "zero tier gating in code" is **half-true**:
- **Spend/quota IS enforced.** `frontend/server/quota-middleware.ts` proxies `GET /api/billing/quota` and returns **402** when `over_quota` (L76), **429** when the Redis check trips (L33); admin bypass (L59). Backend `check_and_reserve` also gates job submission.
- **Feature/entitlement gating is behind a disabled flag.** `frontend/server/tier.ts:57` — `tierEnforcementEnabled()` returns `process.env.TIER_ENFORCEMENT === 'on'` (default **off**). Free-project-limit (`FREE_PROJECT_LIMIT = 3`, `tier.ts:49`) and collaboration gates in `project-routes.ts:192`/`:138` only fire when the flag is on.

## 5. Event-driven Lambdas

- `lambda/batch_event_handler.py` (265 LOC) — EventBridge on Batch RUNNING/SUCCEEDED/FAILED → Redis ledger (+ optional Lago).
- `lambda/s3_event_handler.py` (180 LOC) — S3 Put/Delete → `POST {BILLING_API_URL}/internal/billing/s3_{put,delete}`.
- `BILLING_DEV_MODE` is guarded against `ENV=production`; **all billing secrets fail closed (503)** rather than crashing Galaxy boot.

## Key files

| Path | Purpose | ~LOC |
|------|---------|------|
| `ai/billing/api/billing_router.py` | Full billing router (usage/quota/jobs, internal events, provisioning, webhook) | 1148 |
| `ai/billing/core/quota_enforcer.py` | `DEFAULT_PLAN_LIMITS`, canonical tiers, `check_and_reserve` | 179 |
| `ai/billing/core/realtime_cost_service.py` | Redis realtime ledger | 644 |
| `ai/billing/core/cost_calculator.py` | LLM/EC2/S3 pricing | 357 |
| `ai/billing/core/lago_client.py` | Lago client; `lago_enabled()` OFF | 571 |
| `ai/billing/lambda/{batch,s3}_event_handler.py` | Event → Redis | 265 / 180 |
| `webapps/.../billing_internal.py` | Frontend-called `/internal/billing/llm_cost` | 178 |
| `frontend/server/quota-middleware.ts` / `tier.ts` / `plan-config.ts` | Spend gate + tier config | — |
