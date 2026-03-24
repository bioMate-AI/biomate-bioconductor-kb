# E2E Test Debugging Session — 2026-03-22

**Branch**: `bioconductor_skill`
**Goal**: Get all 8 tests in `frontend/e2e/full-workflow-e2e.e2e.ts` passing.

---

## Starting State (from previous session)

- ADMET-Full ✓ PASS (confirmed runs 7-11)
- Review-UX ✓ PASS (confirmed runs 7-11)
- UC-3 through UC-7, UC-2: FAILING

---

## Root Causes Fixed This Session

### 1. Nextflow Path Resolution (500 on Execute)

**File**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
**Fix**: Added `backend_root / "biomni_workflows"` to `_candidate_bases()` search roots.

Before: `nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf` → 404 "Could not resolve Nextflow script"
After: Path correctly resolved from `backend/biomni_workflows/nextflow_nfcore/...`

### 2. DeepPurpose Module Check Blocks mock_mode Runs

**File**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
**Fix**: Skip `_choose_container_strategy()` check when `mock_mode=True` OR executor=awsbatch.

```python
_executor_for_container = (compute or {}).get("executor", "")
_will_mock = bool(params.get("mock_mode", False))
strategy: Dict[str, Any] = {  # safe defaults
    "mode": "host", "image": None, "docker_opts": "",
    "required_modules": [], "missing_modules": [], ...
}
if _executor_for_container != "awsbatch" and not _will_mock:
    strategy = _choose_container_strategy(nf_path, request.nextflow_path)
    if strategy["mode"] == "docker" and strategy["image"]:
        cmd += ["-with-docker", strategy["image"]]
    elif strategy["missing_modules"]:
        raise HTTPException(status_code=503, detail=("Missing..."))
```

Also resolved a git merge conflict in the same section (conflicting upstream change about awsbatch skip).

### 3. Preflight Endpoint Missing

**File**: `frontend/server/routes.ts`
**Fix**: Added `POST /api/workflows/preflight` endpoint (3-phase fast validation: parameters, S3 inputs, structure).

Returns `{phases: [{id, status, message}], ready: bool}`. Used by `PilotRunPanel` UC-2 test.

### 4. AI Over-Clarification (Multiple Clarification Rounds)

**File**: `frontend/server/galaxy-assistant.ts`
**Fix**: Added 3 rules to system prompt (line 1853-1855):

1. Added SMILES/InChI/sequences to recognized input data types (so AI doesn't ask for data when SMILES is in the query)
2. "Ask at most ONE clarification question per conversation. Once user replied, generate the workflow immediately."

Result: ADMET queries dropped from 2-3 clarification rounds to 1.

---

## Infrastructure Issues

### Galaxy Backend Crashes

The Galaxy gunicorn backend (port 8081) crashed multiple times during test runs:
- **Cause**: Unknown — possibly memory pressure or boot failures after code changes
- **Workaround**: Restart with `BILLING_DEV_MODE=true NEXTFLOW_USE_AWS=false` env vars
- **Symptom in tests**: `ECONNREFUSED 127.0.0.1:8081` → Execute API 500

### Frontend Server Stability (inotify ENOSPC)

VS Code (33k) + Cursor (28k) = 61k/65k inotify file watches → frontend server crashes.
**Fix**: Start with `CHOKIDAR_USEPOLLING=1` env var.

**Server start command**:
```bash
cd /home/yzhang/biomate/frontend
CHOKIDAR_USEPOLLING=1 SESSION_SECRET=dev-secret-biomate-local \
ANTHROPIC_API_KEY=$(grep ANTHROPIC_API_KEY /home/yzhang/biomate/.env | cut -d= -f2-) \
nohup ./node_modules/.bin/tsx server/index.ts > /tmp/frontend-server.log 2>&1 &
```

**Galaxy start command**:
```bash
cd /home/yzhang/biomate/backend
BILLING_DEV_MODE=true NEXTFLOW_USE_AWS=false SESSION_SECRET=dev-secret-biomate-local \
ANTHROPIC_API_KEY=$(grep ANTHROPIC_API_KEY /home/yzhang/biomate/.env | cut -d= -f2-) \
nohup .venv/bin/gunicorn "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 --pythonpath lib -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 --workers 4 --log-level info > /tmp/galaxy-server.log 2>&1 &
```

### Registration Rate Limit (429)

Tests register ~8 users in sequence. The rate limiter fires at ~UC-4 onwards.
- **Symptom**: `registerAndGoHome` catch block runs, uses previous session or anonymous
- **Impact**: Later tests may share sessions or run as anonymous

---

## Test Run Summary

| Run | Result | Key Issues |
|-----|--------|------------|
| Run 9 | 3/8 pass | Execute 500 (biomni_workflows path not in roots) |
| Run 10 | 2/8 pass | UC-3 execute 500 (merge conflict in executor), server crash later |
| Run 11 | ≥2/8 | UC-3 execute 500 (Galaxy was briefly down), UC-4+ still running |

---

## Remaining Issues

### UC-4/5/6 Over-Clarification
Despite system prompt fix (1 clarification → generate), UC-4 and later tests still ask 3 clarifications.
Likely due to:
1. `_detectWorkflowAmbiguity` in intent classifier firing based on conversation context
2. OR registration rate limit causing later tests to run without proper auth

### UC-6: Detach/Reconnect Labels
The `execution-control-panel.tsx` still has hardcoded "Pause"/"Resume" buttons without `executionEngine` prop or `data-testid` attributes. UC-6 test checks for `[data-testid="button-pause-workflow-panel"]` with text "Detach".

### UC-7: Download Commands Panel
UC-7 test requires the workflow to complete (status=completed) to see the DownloadCommandsPanel. Local mock runs fail immediately (status=failed), so the panel never renders.

### UC-2: Pilot Run / Preflight
Preflight endpoint ✓ works. Test might fail if registration rate limit fires.

---

## P1.6 Fixes Applied (from previous session requests)

1. **Reranker window**: `limit=5 → limit=20` in `search_nextflow_workflow` endpoint
2. **Remove 'de' keyword**: Removed `'de': 2.0` from `unified_workflow_search.py` keyword_weights
3. **`_nextflow_workflow_key()` fix**: Added `nextflow_nfcore/` path format support in `ai_assistant.py`

---

## Files Modified

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | biomni_workflows path root, mock_mode module check skip, merge conflict resolution |
| `frontend/server/routes.ts` | POST /api/workflows/preflight endpoint |
| `frontend/server/galaxy-assistant.ts` | System prompt: SMILES as data type, max-1-clarification rule |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Remove 'de' keyword |
| `backend/lib/galaxy/ai/ai_assistant.py` | _nextflow_workflow_key() fix, limit=20 |
