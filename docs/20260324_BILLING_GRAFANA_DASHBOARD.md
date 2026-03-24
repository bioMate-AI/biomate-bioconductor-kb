# BioMate Billing — Grafana Dashboard Reference

**Date**: 2026-03-24
**Dashboard**: Billing System Overview (`uid: billing-overview`)
**Grafana URL**: http://localhost:3000 — login: `admin` / `admin123`
**Prometheus URL**: http://localhost:9090
**Java billing service**: http://35.86.137.71:8080

### Local Lago Instance (NEW 2026-03-24)

| Service | URL | Credentials |
|---------|-----|-------------|
| Lago UI | http://localhost:8088 | `admin@biomate.dev` / `BioMate2026!` |
| Lago API | http://localhost:3010 | API key: `ba049ead-f0da-494a-b0ec-b76bdc26fc96` |
| Lago Sidekiq | http://localhost:3010/sidekiq | (no auth in dev mode) |
| Remote Lago UI | http://35.86.137.71 | (colleague's instance) |

Start/stop:
```bash
cd /home/yzhang/biomate/billing_system/lago
docker compose --env-file .env up -d     # start
docker compose --env-file .env down      # stop (keeps data)
docker compose --env-file .env down -v   # stop + wipe all data
```

---

## Quick Start for Colleagues

Everything auto-starts when you run the normal backend startup command.
No extra steps needed.

```bash
# 1. Start the backend (also starts Prometheus + Grafana automatically)
cd /home/yzhang/biomate/backend
./start_backend.sh

# 2. Start the frontend (in a separate terminal)
cd /home/yzhang/biomate/frontend
npm run dev
```

After about 10 seconds, open Grafana at **http://localhost:3000** (admin / admin123)
and navigate to **Dashboards → Billing → Billing System Overview**.

> **Note**: If you started the frontend server before today (2026-03-24), restart it once
> so it picks up `JAVA_BILLING_SERVICE_URL` from `.env`.

### What happens automatically

| On backend start | What starts |
|-----------------|-------------|
| `start_backend.sh` | Python Galaxy backend on :8081 |
| `start_backend.sh` | `docker compose up -d` → Prometheus :9090 + Grafana :3000 |
| Frontend `.env` | `JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080` is loaded by `dotenv` |

Prometheus scrapes the Java billing service every **10 seconds**.
Grafana dashboard auto-refreshes every **10 seconds**.

### Verify everything is connected

```bash
# Java billing service is reachable
curl http://35.86.137.71:8080/actuator/prometheus | grep billing_event_total | head -3

# Prometheus is scraping it
curl http://localhost:9090/api/v1/targets | python3 -c "
import json,sys; ts=json.load(sys.stdin)['data']['activeTargets']
[print(t['labels']['job'], t['health']) for t in ts]
"

# Grafana is up
curl -s http://localhost:3000/api/health | python3 -c "import json,sys; print(json.load(sys.stdin)['database'])"
```

Expected output: `billing-sys up`, `prometheus up`, `database ok`.

---

## How BioMate sends billing events

Every user action that costs money emits an event to the Java service automatically.
There is nothing to configure — it works as long as `JAVA_BILLING_ENABLED=true`.

| User action | Event code | Emitted from |
|-------------|-----------|-------------|
| Chat message (any model) | `llm` | `frontend/server/routes.ts` → `/api/chat` and `/api/chat/stream` |
| Nextflow workflow completes | `ec2_instance` | `backend/.../nextflow_executor.py` → `_stream_logs()` at terminal state |
| File uploaded to S3 | `ebs_storage` | `backend/.../billing_router.py` → `s3_put` endpoint |
| New user registers | *(customer registration)* | `frontend/server/auth-service.ts` → `syncUserToBilling()` |

All events carry `externalCustomerId: bm_{userId}` so they appear per-user in Grafana.

### Feature flag

Set in `backend/start_backend.sh` and `frontend/.env`:

```
JAVA_BILLING_SERVICE_URL=http://35.86.137.71:8080
JAVA_BILLING_ENABLED=true      # set to false to disable all Java billing calls
```

Disabling the flag does NOT break BioMate — events are simply not forwarded.
The existing Lago integration continues to work independently.

---

## Dashboard panels (12 panels, 4 sections)

### Section 1 — System Health

Three panels across the top. Check these first when something seems wrong.

---

#### Panel 1: Event QPS

**PromQL**: `rate(billing_event_total{code!="none"}[5m])`

What it shows: Rate of billing events per second broken down by resource type
(`llm`, `ec2_instance`, `ebs_storage`) and status (`success`, `failed`).

How to read it:
- Healthy system shows `llm - success` spikes whenever users chat
- `ec2_instance - success` spikes when Nextflow workflows finish
- A flat zero line means BioMate stopped sending events — check `JAVA_BILLING_ENABLED`

---

#### Panel 2: Event Error Rate

**PromQL**: `rate(billing_event_total{status="failed"}[5m]) / rate(billing_event_total[5m])`

What it shows: Fraction of events that failed, as a percentage.

How to read it:
- Should be 0% at all times
- Above 1% means usage is not being recorded — billing accuracy degrades
- Events are fire-and-forget so user experience is unaffected, but users may be under-billed

---

#### Panel 3: Credits Consumption Rate (by resource)

**PromQL**: `sum by (code) (rate(billing_credits_consumed_total{code!=""}[5m]))`

What it shows: Credits burned per second for each of the three resource types.

How to read it:
- `llm` typically dominates — Claude API calls are frequent
- `ec2_instance` spikes = active Nextflow runs on AWS Batch
- `ebs_storage` is low and steady
- A sudden large `ec2_instance` spike = user ran an expensive workflow

---

### Section 2 — Usage by Resource

---

#### Panel 4: EC2 Credits (by instance type)

**PromQL**: `sum by (instance_type) (rate(billing_credits_consumed_total{code="ec2_instance",instance_type!=""}[5m]))`

What it shows: Credits from Nextflow runs broken down by AWS instance type
(e.g. `m5.2xlarge`, `g4dn.xlarge`).

How to read it:
- GPU instances (`g4dn`, `p3`) cost far more than CPU instances
- `m5.large` dominating = most workflows running locally (non-Batch)

---

#### Panel 5: LLM Credits (by model)

**PromQL**: `sum by (model) (rate(billing_credits_consumed_total{code="llm",model!=""}[5m]))`

What it shows: Credits from Claude API calls broken down by model.

How to read it:
- Opus costs ~5× more than Haiku per token
- If Opus dominates after a code change, check model selection logic for regressions

---

#### Panel 6: LLM Model Share (last 1h)

**PromQL**: `sum by (model) (increase(billing_event_total{code="llm",model!=""}[1h]))`

What it shows: Proportion of LLM calls by model over the last hour (pie chart).

How to read it:
- Complements Panel 5 — this shows call *count*, not credit cost
- A model with small call share but large credit share = long/expensive requests

---

### Section 3 — LLM Details

---

#### Panel 7: LLM Request Rate (by model)

**PromQL**: `sum by (model) (rate(billing_event_total{code="llm",model!=""}[5m]))`

What it shows: Number of Claude API calls per second by model.

How to read it:
- Spikes = peak user activity (many simultaneous chat sessions)
- Correlate with Panel 2 — if rate spikes and error rate also spikes, API may be rate-limited

---

#### Panel 8: LLM Usage by Customer

**PromQL**: `sum by (model, customer_id) (rate(billing_event_total{code="llm",model!=""}[5m]))`

What it shows: LLM request rate broken down by both customer (`bm_userId`) and model.

How to read it:
- One `customer_id` dominating all traffic may indicate automation or a loop bug
- Useful for debugging a specific user's billing issue
- During testing, your test user's `customer_id` will appear here in real time

---

### Section 4 — Per-User Billing

The most important section for cost attribution. All `customer_id` values are `bm_{userId}`.

---

#### Panel 9: Events per User (last 1h)

**PromQL**: `sum by (customer_id) (increase(billing_event_total{status="success"}[1h]))`

What it shows: Total successful billing events per user in the last hour.

How to read it:
- Each chat message = 1 event; each completed Nextflow run = 1 event
- A user with 0 events may not be logged in, or their events are failing
- After running a test, your test user should appear here within 10 seconds

---

#### Panel 10: LLM Tokens per User (last 1h)

**PromQL**: `sum by (customer_id) (increase(billing_raw_usage_total{code="llm"}[1h]))`

What it shows: Total LLM tokens (input + output) consumed per user in the last hour.

How to read it:
- Multiply by the model's per-token price for approximate USD cost
- Few events + many tokens = long conversations or large document uploads

---

#### Panel 11: Per-User Activity Rate (5m)

**PromQL**: `sum by (customer_id) (rate(billing_event_total{status="success"}[5m]))`

What it shows: Real-time event rate per user over the last 5 minutes (time series).

How to read it:
- Non-zero right now = user is actively using BioMate
- Best panel to watch during a live test or demo

---

#### Panel 12: Compute Credits per User (last 1h)

**PromQL**: `sum by (customer_id) (increase(billing_credits_consumed_total{code="ec2_instance"}[1h]))`

What it shows: Credits consumed by Nextflow runs per user in the last hour.

How to read it:
- Zero = user only used chat (no workflow runs)
- Very large values = user ran a long or resource-intensive workflow

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| All panels show "No data" | Prometheus not scraping | Run `curl localhost:9090/api/v1/targets` — check `billing-sys` state |
| Panels show "No data" for one code | That event type not being emitted | Check `JAVA_BILLING_ENABLED=true` in both backend and frontend env |
| Per-user panels show 0 | Less than 1h of scrape history | Wait — `increase([1h])` needs 1h of data. Raw totals work immediately |
| `customer_id` missing from events | User not registered in Java service | Run the backfill script (see below) |
| Frontend sends no events | `JAVA_BILLING_SERVICE_URL` not in env | Restart the frontend server after confirming `.env` has the variable |

### Backfill existing users

If users already existed before the Java billing integration was added, register them:

```bash
cd /home/yzhang/biomate
python3 backend/scripts/backfill_billing_customers.py --dry-run   # preview
python3 backend/scripts/backfill_billing_customers.py             # run for real
```

### Look up a specific user's billing data

```bash
# Replace 42 with the user's integer ID from the BioMate users table
curl "http://35.86.137.71:8080/api/billing/usage/current?externalCustomerId=bm_42"
```

---

## Architecture

```
BioMate Frontend (TypeScript, :5000)
  ├─ /api/chat, /api/chat/stream  ──► POST /api/billing/usage/events (code=llm)
  └─ auth-service.ts              ──► POST /api/billing/customers

BioMate Backend (Python, :8081)
  ├─ billing_router.py → llm_cost ──► POST /api/billing/usage/events (code=llm)
  ├─ billing_router.py → job_completed ► POST /api/billing/usage/events (code=ec2_instance)
  ├─ billing_router.py → s3_put   ──► POST /api/billing/usage/events (code=ebs_storage)
  └─ nextflow_executor.py         ──► emit_ec2() at workflow terminal state

                                         │
                                         ▼
                              Java Billing Service (:8080)
                              ├─ Lago (subscription billing)
                              ├─ Stripe (payments)
                              ├─ PostgreSQL (event log)
                              └─ /actuator/prometheus ◄── Prometheus scrapes every 10s
                                                               │
                                                               ▼
                                                        Prometheus (:9090)
                                                               │
                                                               ▼
                                                        Grafana (:3000)
                                                        Billing System Overview
```
