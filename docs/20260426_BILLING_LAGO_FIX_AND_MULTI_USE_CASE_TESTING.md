# 20260426 — Billing Lago Fix + Multi-Use-Case Testing

## Session Summary

Continued from previous session. Primary goals:
1. Restart Galaxy backend with correct Lago URL
2. Fix LLM billing events not reaching Lago
3. Run full multi-use-case test suite (ADMET, CRO, Billing, CryoEM)
4. Commit and sync to dev

---

## Issues Fixed

### 1. Execution Runs Lost on Server Restart (Previous Session)
**Root cause**: `MemStorage` kept execution runs in-memory only.  
**Fix** (already committed): Added PostgreSQL write-through in `storage.ts`:
- `createExecutionRun()` fires `db.insert()` after setting in-memory map
- `getExecutionRun()`, `getExecutionRunByGalaxyId()`, `updateExecutionRun()` all fall back to DB
- New schema columns in `shared/schema.ts` + migration `0007_execution_runs_persistence.sql`

### 2. Galaxy Backend Running with Wrong Lago URL
**Root cause**: `start_backend.sh` had `LAGO_API_URL=http://localhost:3010` pointing to local Docker container.  
**Fix**: Updated `start_backend.sh`:
```bash
export LAGO_API_URL=http://35.86.137.71:3000
export LAGO_API_KEY=01b71711-be39-49af-8d14-87a4ee827157
export JAVA_BILLING_ENABLED=true
```
**Note**: `kill -HUP <master>` does NOT update environment variables — must do full restart to pick up new env vars.

### 3. Billing Events Not Reaching Lago (Primary Root Cause)
**Root cause**: Two `/internal/billing/llm_cost` endpoints existed:
- `billing_router.py`: emits to Lago ✓ but was overridden by...
- `billing_internal.py`: only records to file/Redis, no Lago emission

`billing_internal.py` was the one actually responding. **Fix**: Added Lago emission to `billing_internal.py`:
```python
lago = _lago_client()
if lago is not None:
    plan_code = _get_user_plan_code(user_id)
    lago.emit_llm(user_id=user_id, session_id=session_id, ...)
```

### 4. Missing Aggregate `llm` Event
**Root cause**: `lago_client.py emit_llm()` only sent `llm_input_tokens` + `llm_output_tokens` (2 events).  
Billing smoke test expected 3 events including aggregate `llm`.  
**Fix**: Added `EventCode.LLM = "llm"` and emitted aggregate event in `emit_llm()` batch.

### 5. Billing Smoke Test User UUID Mismatch
**Root cause**: Test expected fixed UUID `bsmoke-0000-0000-0000-000000000001` but DB had different UUID.  
**Fix**: Recreated user with correct UUID and bcrypt password hash (app uses bcrypt, not scrypt).

### 6. Billing Page Empty
**Root cause**: `billing.tsx` used `localStorage.getItem("auth_token")` but app uses HTTP-only cookies.  
**Fix** (previous session): Replaced with `authFetch()` using `credentials: 'include'`.

---

## Test Results

| Test Suite | Status |
|------------|--------|
| Full Workflow E2E (8 use cases) | **8/8 ✓** |
| Billing Smoke | **4/4 ✓** |
| CRO Compliance | **10/10 ✓** |
| Pilot Study E2E | Running... |
| CryoEM Real E2E | Running... |

---

## Lago Infrastructure Status

- Lago UI: `http://35.86.137.71/subscriptions`
- API: `http://35.86.137.71:3000`
- All 2432 users backfilled into Lago with `register_user`
- LLM events now flowing correctly (verified in Lago events API)
- Event format: `llm_input_tokens`, `llm_output_tokens`, `llm` (aggregate with `value` field)

---

## Files Changed This Session

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/billing_internal.py` | Added Lago emit + aggregate event |
| `backend/lib/galaxy/ai/billing/core/lago_client.py` | Added `EventCode.LLM` + aggregate event in `emit_llm()` |
| `backend/start_backend.sh` | AWS Lago URL + JAVA_BILLING_ENABLED=true |
| `CLAUDE.md` | Cross-environment iterative loop + document periodically requirements |
| `frontend/migrations/0007_execution_runs_persistence.sql` | Execution run persistence columns |
| `frontend/server/storage.ts` | DB write-through for execution runs |
| `frontend/shared/schema.ts` | New execution_json/nextflow_run_id/nextflow_output_dir columns |
| `frontend/client/src/pages/billing.tsx` | Cookie-based auth for billing API calls |
| `frontend/server/routes.ts` | S3 path fix for findings, maxTokens 2048, Lago registration on signup |

---

## Known Open Issues

1. **Redis**: `start_backend.sh` uses `REDIS_URL=redis://localhost:6379` — should be AWS ElastiCache for real quota enforcement. Quota enforcement won't work correctly until this is fixed.

2. **AI Findings**: Fixed maxTokens=2048 and Gemini double-JSON unwrap in routes.ts. Needs verification that findings now populate correctly in completed runs.

3. **Pilot + CryoEM tests**: Still running at time of doc creation.

---

## Next Steps

1. Fix Redis URL in start_backend.sh to AWS ElastiCache
2. Verify AI findings work end-to-end
3. Run `sync_to_dev.sh` and retest on dev EC2
4. Test intermediate output visualization for all use cases
5. Verify quota enforcement with real AWS Redis
