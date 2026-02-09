# E2E Test Execution Plan - Nextflow Integration

**Date**: 2026-02-09
**Status**: In Progress
**Branch**: connection_formal
**Task**: #2 - Run E2E tests for Nextflow execution flow

## Prerequisites

### Environment
- ✅ Branch: `connection_formal`
- ✅ Backend code: Updated with workflow tags
- ✅ Frontend code: Updated with helper function
- ⏳ Backend service: Not running (needs start)
- ⏳ Frontend service: Not running (needs start)

### Required Services
1. **Backend Galaxy** - Port 8081
   - Script: `/home/yzhang/biomate/backend/start_galaxy_simple.sh`
   - Healthcheck: `curl http://localhost:8081/api/version`

2. **Frontend Server** - Port 5000
   - Command: `cd /home/yzhang/biomate/frontend && npm run dev`
   - Healthcheck: `curl http://localhost:5000/`

### Required Environment Variables
```bash
export GALAXY_URL="http://localhost:8081"
export GALAXY_API_KEY="<your-key>"  # Check ~/.galaxy_api_key or config
export BIOMATE_URL="http://localhost:5000"
```

## Test Plan

### Phase 1: Service Health Checks

| Test | Command | Expected Result |
|------|---------|-----------------|
| 1.1 Backend alive | `curl http://localhost:8081/api/version` | HTTP 200, JSON with version |
| 1.2 Frontend alive | `curl http://localhost:5000/` | HTTP 200, HTML with root div |
| 1.3 AutoFix status | `curl http://localhost:5000/api/galaxy/autofix3/status` | HTTP 200, JSON with enabled:true |

### Phase 2: Workflow Generation & Tagging

| Test | Action | Expected Result |
|------|--------|-----------------|
| 2.1 Generate Galaxy reuse workflow | POST /api/chat with known query | Tags: `['galaxy-reuse', 'ai-generated']` |
| 2.2 Generate Nextflow workflow | POST /api/chat with new query | Tags: `['nextflow', 'ai-generated']` |
| 2.3 Verify execution engine | Check workflow response | `execution_engine` field present |
| 2.4 Verify workflow tags | Check workflow response | `workflow_tags` field present |

### Phase 3: Workflow Execution

| Test | Action | Expected Result |
|------|--------|-----------------|
| 3.1 Execute Nextflow workflow | POST /api/workflows/execute | Returns runId, galaxyInvocationId |
| 3.2 Verify engine in response | Check execute response | `executionEngine: 'nextflow'` |
| 3.3 History created | Check Galaxy API | History exists with name containing [Nextflow] |
| 3.4 Invocation started | Check Galaxy API | Invocation state = scheduled/running |

### Phase 4: Status Synchronization

| Test | Action | Expected Result |
|------|--------|-----------------|
| 4.1 Initial status | GET /api/workflows/runs/:id/status | Status = queued/running |
| 4.2 Status updates | Poll every 2s | Status progresses |
| 4.3 **Completion sync** | When Galaxy = ok | **Frontend status = ok** |
| 4.4 Nextflow status | Check nextflowStatus field | Contains Nextflow-specific data |

### Phase 5: Output Verification

| Test | Action | Expected Result |
|------|--------|-----------------|
| 5.1 Outputs exist | GET /api/invocations/:id/outputs | Array of output datasets |
| 5.2 Outputs not empty | Check output file sizes | All > 0 bytes |
| 5.3 Download works | GET /api/datasets/:id/download | File downloads successfully |

### Phase 6: AutoFix Integration

| Test | Action | Expected Result |
|------|--------|-----------------|
| 6.1 AutoFix button visible | Check workflow artifact UI | AutoFix button present for failed runs |
| 6.2 Trigger AutoFix | POST /api/workflows/runs/:id/ai/autofix | Returns fix result |
| 6.3 AutoFix sessions | GET /api/galaxy/workflows/.../autofix3/sessions | Lists sessions |

## Automated Test Scripts

### Script 1: Python E2E Test
**Location**: `/home/yzhang/biomate/codex_work/run_nextflow_tests.py`

**Usage**:
```bash
cd /home/yzhang/biomate/codex_work

# Set environment
export BIOMATE_URL="http://localhost:5000"
export GALAXY_URL="http://localhost:8081"
export GALAXY_API_KEY="your-key"
export WORKFLOW_JSON="/path/to/workflow.ga"
export AUTO_FIX="false"

# Run test
python3 run_nextflow_tests.py
```

**What it tests**:
- Health checks (frontend + backend)
- Workflow execution
- Status polling
- Output fetching
- AutoFix (if enabled)

### Script 2: Playwright E2E Tests
**Location**: `/home/yzhang/biomate/frontend/e2e/`

**Usage**:
```bash
cd /home/yzhang/biomate/frontend

# Run all E2E tests
npm run e2e

# Run specific test
npm run e2e -- workflow-execution-e2e.e2e.ts

# Run with UI
npm run e2e:ui

# Run headed (visible browser)
npm run e2e:headed
```

**What it tests**:
- Complete UI workflow (chat → generate → execute → outputs)
- Workflow execution from My Workflows
- Real API integration
- AutoFix UI

## Manual Test Procedure

### Step 1: Start Services

```bash
# Terminal 1: Start Backend
cd /home/yzhang/biomate/backend
./start_galaxy_simple.sh

# Wait for startup (check logs)
# Look for: "Galaxy started successfully"

# Terminal 2: Start Frontend
cd /home/yzhang/biomate/frontend
npm run dev

# Wait for startup
# Look for: "Server running on http://localhost:5000"
```

### Step 2: Verify Health

```bash
# Check backend
curl http://localhost:8081/api/version | jq

# Check frontend
curl http://localhost:5000/ | grep "root"

# Check AutoFix
curl http://localhost:5000/api/galaxy/autofix3/status | jq
```

### Step 3: Run Automated Tests

```bash
# Python E2E test
cd /home/yzhang/biomate/codex_work
export GALAXY_API_KEY="your-key"
export WORKFLOW_JSON="/path/to/test-workflow.ga"
python3 run_nextflow_tests.py

# Playwright E2E tests
cd /home/yzhang/biomate/frontend
npm run e2e
```

### Step 4: Manual UI Testing

1. Open http://localhost:5000 in browser
2. Send chat: "Run quality control on my FASTQ files"
3. Verify workflow generated with tags
4. Click "Execute"
5. Verify:
   - Engine badge shows "Nextflow"
   - Status updates in real-time
   - Completion shows "ok"
   - Outputs are downloadable
6. If failed, verify AutoFix button appears

## Test Data Requirements

### Sample Workflow
Need a simple Galaxy .ga workflow for testing:
- Location: TBD
- Requirements:
  - 1-2 tool steps
  - Fast execution (< 2 min)
  - Known good output

### Sample Inputs
Need test datasets:
- Small FASTQ file (< 1MB)
- Uploaded to Galaxy
- Dataset IDs documented

## Expected Results

### Success Criteria (All Must Pass)

- [ ] Phase 1: Both services running and communicating
- [ ] Phase 2: Workflows generated with correct tags
- [ ] Phase 3: Workflows execute with correct engine
- [ ] Phase 4: Status synchronization works (NO DESYNC!)
- [ ] Phase 5: Outputs are valid and downloadable
- [ ] Phase 6: AutoFix integration works

### Performance Benchmarks

- Workflow generation: < 30s
- Workflow execution: < 5 min (for simple workflows)
- Status polling: Updates every 2s
- Output retrieval: < 5s

## Known Issues to Monitor

1. **Status Desync** - Frontend stuck at "queued" when backend is "ok"
   - **Root cause**: Galaxy invocation state doesn't update
   - **Mitigation**: History-based fallback (already implemented)
   - **Test**: Verify fallback works

2. **Tool ID Format** - `Repository_Actions_*` prefix
   - **Root cause**: Crawling artifact
   - **Mitigation**: Postprocessing in ai_assistant.py
   - **Test**: Verify tool IDs are clean

3. **Container Architecture** - linux/amd64 vs linux/arm64
   - **Root cause**: Default images not arm64
   - **Mitigation**: Custom container resolvers
   - **Test**: Verify tools execute on arm64

## Failure Recovery

If tests fail:

1. **Check logs**:
   - Backend: `tail -f /home/yzhang/biomate/backend/galaxy.log`
   - Frontend: Terminal output from `npm run dev`

2. **Common fixes**:
   - Restart services
   - Clear browser cache
   - Check environment variables
   - Verify database connectivity

3. **Debug endpoints**:
   - `/api/workflows/runs/:id/status` - Run status
   - `/api/galaxy/workflows/:wfId/invocations/:invId/autofix3/status` - AutoFix status
   - `/api/invocations/:id/outputs` - Output datasets

## Documentation

Results will be documented in:
- `/home/yzhang/biomate/codex_work/20260209_e2e_test_results.md`

## Timeline

**Estimated Duration**: 2-3 hours
- Service startup: 10 min
- Automated tests: 30 min
- Manual UI tests: 30 min
- Documentation: 30 min
- Buffer: 30 min

## Next Steps After Testing

1. Document all test results
2. Create bug reports for any failures
3. Update integration progress document
4. Move to Task #3: Documentation
