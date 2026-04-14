# Dev Platform Sync, QC Profiles Fix, and Billing System Audit — 2026-04-09

## Summary

Session completed three things:
1. Repaired the CI/CD auto-sync script and got all layers synced to `dev-public.biomate.ai`
2. Fixed the `/api/qc/profiles` endpoint (was returning empty due to wrong import name)
3. Verified and fixed the AWS-hosted Lago billing system end-to-end

---

## 1. CI/CD Auto-Sync Script (`scripts/sync_to_dev.sh`)

### Bug 1: CHANGED string bug (backend/workflows never synced on force-full)

**Root cause**: Force-full CHANGED string was space-separated on one line:
```bash
CHANGED="frontend/ backend/lib/ backend/biomni_workflows/ backend/database/"
```
`grep -q "^backend/lib/"` only matches if the line STARTS with `backend/lib/`. A single-line
space-separated string always starts with `frontend/`, so backend and workflow syncs were skipped.

**Fix**:
```bash
CHANGED="$(printf 'frontend/\nbackend/lib/\nbackend/biomni_workflows/\nbackend/database/')"
```

### Bug 2: attached_assets/ missing from frontend Docker build

**Symptom**: Docker build failed with:
```
[vite:asset] Could not load /app/attached_assets/generated_images/User_avatar_placeholder_d2803d15.png
```
**Fix**: Added `frontend/attached_assets/` to the tar archive command in `deploy_frontend()`.

### Result after fixes

Full sync completed:
- **19 Python files** synced into Galaxy container including `qc_trace_monitor.py`, `ai_assistant.py`,
  `nextflow_executor.py`, `unified_workflow_search.py`, all cryo-EM knowledge files
- **62MB Nextflow workflow files** synced (all `biomni_workflows/` .nf files)
- **galaxy_ai_tools.db** (259MB) uploaded via S3 and pulled into Galaxy container
- **universe.sqlite** (3.4MB) same path
- **Frontend** rebuilt with `attached_assets/` included — Docker build succeeded

Sync watcher runs continuously (PID visible via `ps aux | grep sync_to_dev`), polling every 600s.
On each poll it diffs git commits; syncs only changed layers (smart diff). First run always does
a full sync of all layers.

---

## 2. `/api/qc/profiles` Fix

### Root cause

The endpoint `GET /api/qc/profiles` in `nextflow_executor.py` imported:
```python
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, DEFAULT_THRESHOLDS
```
But `DEFAULT_THRESHOLDS` does not exist in `qc_trace_monitor.py`. The correct name is `QC_RED_LINES`.

The `except ImportError` block silently caught this as an `ImportError` (it's actually an
`ImportError` for a name within a module, not the module itself) and returned empty:
```json
{"profiles": [], "count": 0, "defaults": {}}
```

### Fix (`nextflow_executor.py` line ~2664)
```python
# Before (broken):
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, DEFAULT_THRESHOLDS
profiles = NextflowQCGateHandler.list_profiles()
defaults = DEFAULT_THRESHOLDS

# After (fixed):
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, QC_RED_LINES
profiles = NextflowQCGateHandler.list_profiles()
defaults = QC_RED_LINES
```

### Result

`GET /api/qc/profiles` now returns all **32 named QC profiles** spanning:
- RNA-seq (polya_standard, ribodepleted, FFPE, snRNA-seq, non-model organism)
- DNA-seq/WGS/WES (germline, low-pass, somatic, clinical)
- Metagenomics (gut, soil, marine, pathogen)
- Cryo-EM (standard SPA, VPP, tomo in situ)
- Drug discovery / compound profiles
- Pharmacogenomics (PGx)

---

## 3. Billing System — AWS-hosted Lago

### Infrastructure

| Component | Location |
|-----------|----------|
| Lago API | EC2 `i-069fbdf5d2c30eb1b` (`bill`), us-west-2b |
| Lago public URL | `http://35.86.137.71:3000` (for external access) |
| Lago private URL | `http://172.31.18.185:3000` (for Lambda VPC access) |
| Lago frontend | `http://35.86.137.71:3001` |
| Lago version | v1.32.4 |
| Organization | `biomate` (lago_id: `b060e965-1acb-4878-84c6-3b0952cf49a4`) |
| API key | `01b71711-be39-49af-8d14-87a4ee827157` |
| Webhook URL | `http://172.31.18.185:8080/api/billing/webhooks/lago` |

Lago containers all up (8 days uptime): `lago-api`, `lago-worker`, `lago-clock`, `lago-db`,
`lago-redis`, `lago-front`, `billing-grafana-1`, `billing-prometheus-1`.

### Lago billable metrics configured

| Code | Name |
|------|------|
| `llm_input_tokens` | LLM Input Tokens |
| `llm_output_tokens` | LLM Output Tokens |
| `batch_vcpu_seconds` | Batch vCPU Seconds |
| `batch_memory_gb_sec` | Batch Memory GB-sec |
| `batch_gpu_seconds` | Batch GPU Seconds |
| `s3_put_requests` | S3 PUT Requests |
| `s3_get_requests` | S3 GET Requests |
| `s3_storage_gb_hours` | S3 Storage GB-hr |
| `s3_data_transfer_gb` | S3 Data Transfer GB |

### Plans

| Code | Name | Amount | Interval |
|------|------|--------|----------|
| `base` | base | $7.00 | weekly |
| `free` | free | $0 | weekly |
| `pro` | pro | $20.00 | monthly |
| `test` | Test (Unlimited) | $0 | monthly |

### Bug: Missing LAGO_* env vars on dev EC2 Galaxy container

Dev Galaxy container was launched with:
- `LAGO_API_URL` pointing to `localhost:3010` (local dev Lago, not the AWS one)
- No `LAGO_API_KEY` set

**Fix**: Updated `/opt/biomate/.env` on dev EC2:
```
LAGO_API_URL=http://35.86.137.71:3000
LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
```

### Bug: Lambda `biomate-batch-billing` — Lago code never deployed

The user updated `batch_event_handler.py` locally to add `_emit_to_lago()` and `_parse_container()`
memory extraction, but the Lambda was still running the old code (194 lines, no Lago references).

**Investigation**:
- Lambda invoked, returned 200, Redis writes succeeded
- No Lago emit log appeared because `_emit_to_lago` didn't exist in deployed code
- Confirmed by downloading Lambda zip and checking for `_emit_to_lago`

**Fix**: Built new deployment zip and updated Lambda:
```bash
mkdir lambda_build
cp backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py lambda_build/lambda_function.py
pip install redis==5.0.3 -t lambda_build/
cd lambda_build && zip -r /tmp/lambda_billing_new.zip .
aws lambda update-function-code --function-name biomate-batch-billing --zip-file fileb:///tmp/lambda_billing_new.zip
```

**Fix**: Also set Lambda env vars (were missing LAGO_*):
```bash
aws lambda update-function-configuration --function-name biomate-batch-billing \
  --environment "Variables={
    BILLING_API_KEY=...,
    BILLING_API_URL=http://172.31.8.116:8081,
    REDIS_URL=redis://biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379,
    LAGO_API_URL=http://172.31.18.185:3000,   # private IP (Lambda can't reach public IP — no NAT)
    LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
  }"
```

**Key**: Lambda uses Lago private IP `172.31.18.185:3000` (same VPC, no NAT gateway needed).
Dev Galaxy uses Lago public IP `35.86.137.71:3000` (Galaxy is outside the VPC).

### Billing System End-to-End Verification

#### LLM billing (Galaxy → cost_log → Lago)

```bash
# POST /internal/billing/llm_cost on dev Galaxy
curl -X POST http://localhost:8080/internal/billing/llm_cost \
  -H "X-Internal-Key: 031b06b827bdfd5a8fdbd314645577eff95c28a436a2571f" \
  -d '{"user_id":"e2e_test_user","model":"claude-sonnet-4-6","input_tokens":500,"output_tokens":200}'
# → {"status":"recorded","user_id":"e2e_test_user",...}
# Galaxy log: [CostLog→Lago] Event accepted for user=e2e_test_user ✅
```

Lago confirmed: `bm_e2e_test_user_base` subscription received `llm_input_tokens` event.

#### Batch compute billing (Lambda → Redis + Lago)

```
Lambda log: Lago batch emit accepted for job=lago-verify-1775732659 user=billing_e2e_user vcpus=4.0 duration=30.0s ✅
```

Lago confirmed:
- `batch_vcpu_seconds`: transaction_id=batch-vcpu-lago-verify-1775732659, seconds=120.0 (4 vcpu × 30s)
- `batch_memory_gb_sec`: transaction_id=batch-mem-lago-verify-1775732659, gb_seconds=240.0 (8GiB × 30s)

### Outstanding: Full billing router (Redis-backed) not running on dev EC2 Galaxy

The full `billing_router.py` requires `redis` package. The Galaxy Docker image (built Mar 31)
doesn't have `redis` installed, so it falls back to no-op router. This means:
- `/api/billing/usage` — not available on dev Galaxy
- `/internal/billing/admin/health` — not available on dev Galaxy  
- `/api/billing/quota` — not available on dev Galaxy

**Impact**: Low for pilot — pilot accounts bypass quota anyway (`PILOT_ACCOUNT_EMAILS`).
Real-time billing dashboard (`/api/billing/usage`) requires Redis.

**To fix permanently**: Add `redis` to the Galaxy Docker image build and rebuild.

### Frontend health check (cosmetic issue)

`biomate-dev-frontend` shows "unhealthy" in `docker ps` because the Dockerfile uses
`curl` in the health check but `curl` is not installed in the Alpine-based frontend image.

**Impact**: None — container is actually working (nginx → `http://52.42.49.175:3000` → 200).
Status shows "unhealthy" but the container serves traffic normally.

**Fix**: Change health check in Dockerfile to use `wget -q -O- ...` or `node -e "require('http').get(...)"`.

---

## Dev Platform Status Summary (2026-04-09)

| Component | Status | Notes |
|-----------|--------|-------|
| Frontend (dev-public.biomate.ai) | ✅ Working | CORS, compression, nginx all fixed |
| Galaxy backend | ✅ Working | qc_trace_monitor.py + 18 other Python files synced |
| `/api/qc/profiles` | ✅ 32 profiles | Fixed DEFAULT_THRESHOLDS → QC_RED_LINES |
| galaxy_ai_tools.db | ✅ Synced | 259MB, current as of Apr 9 |
| Nextflow workflows | ✅ Synced | 62MB, all biomni_workflows/ |
| LLM billing → Lago | ✅ Verified | Galaxy cost_log → Lago events accepted |
| Batch billing → Lago | ✅ Verified | Lambda emit accepted, events in Lago DB |
| Full billing router | ❌ No redis | Falls back to billing_internal.py |
| Frontend health check | ⚠️ Unhealthy | curl missing; container works fine |
| CI/CD sync watcher | ✅ Running | PID on dev machine; syncs all layers every 10 min |
