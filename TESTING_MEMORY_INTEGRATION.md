# Testing Memory Integration — Quick Start Guide
## 2026-05-18

## 🎯 Quick Test (5 minutes)

### Option 1: Automated Script
```bash
./scripts/test_memory_integration.sh
```

This will:
1. Check if backend/frontend are running
2. Offer to start them if not
3. Run all E2E tests (MM-0 through MM-4)
4. Generate audit JSON and screenshots

### Option 2: Manual Testing

**Step 1: Start Services** (if not already running)
```bash
# Terminal 1: Backend
cd backend
bash start_backend.sh

# Terminal 2: Frontend
cd frontend
npm run dev
```

**Step 2: Run Individual Tests**
```bash
cd frontend

# MM-0: API Preflight (~30 seconds) - SAFE, NO WORKFLOW EXECUTION
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-0"

# MM-1: Session Init (~5 min) - SAFE
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-1"

# MM-2: Episode Recording (~5 min) - SAFE
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-2"

# MM-3: Outcome Tracking (~10 min) - RUNS WORKFLOW
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-3"

# MM-4: Cross-Session (~15 min) - RUNS WORKFLOW
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-4"

# ALL TESTS (~45 min)
npm run test:e2e -- memory-integration.e2e.ts
```

---

## 📊 What Each Test Does

### MM-0: API Preflight ⚡ FASTEST
**Runtime**: ~30 seconds
**Safe**: Yes (API-only, no UI, no workflows)

**Tests**:
- `/api/health` returns 200
- Database connectivity confirmed
- `/api/memory/user` accessible (200 or 404 OK)
- `/api/memory/projects` accessible
- `/api/memory/projects/:id/episodes` accessible

**Expected**: All 4-5 assertions pass

**Why run this first**: Validates memory infrastructure without running workflows

---

### MM-1: Session Initialization
**Runtime**: ~5 minutes
**Safe**: Yes (creates project, no workflows)

**Tests**:
- User registration/login
- Project creation via `/api/memory/projects`
- Project knowledge addition
- Chat message with memory context loaded
- Response references past knowledge (e.g., "STAR aligner", "GRCh38")

**Expected**: 4-5 assertions pass

**Pass criteria**: Response text mentions past project knowledge

---

### MM-2: Episode Recording
**Runtime**: ~5 minutes
**Safe**: Yes (workflow card appears, not run)

**Tests**:
- User requests nf-core/rnaseq workflow
- Workflow card appears
- Episode recorded in database
- Episode contains user query, intent, workflow_generated=true

**Expected**: 4-5 assertions pass

**Pass criteria**: Episode fetched via API has all required fields

---

### MM-3: Episode Outcome Tracking 🔑 KEY TEST
**Runtime**: ~10 minutes
**Safe**: ⚠️ Runs test workflow

**Tests**:
- Test workflow requested and runs
- Workflow completes (or fails)
- Episode outcome recorded within 5 seconds
- Episode has `outcome_success`, `what_worked`, `lessons_learned`

**Expected**: 6-8 assertions pass

**Pass criteria**: Episode updated with outcome data after workflow completion

**Why important**: This validates the integration between workflow execution and memory system

---

### MM-4: Cross-Session Reference 🎯 USER-FACING
**Runtime**: ~15 minutes
**Safe**: ⚠️ Runs workflow

**Tests**:
- **Session A**: Run nf-core/rnaseq with STAR + GRCh38
- Episode recorded
- User logs out
- **Session B**: Same user logs in, says "use same workflow as yesterday"
- Memory retrieves past episode
- Response mentions previous workflow
- Workflow card appears with params pre-filled

**Expected**: 8-10 assertions pass

**Pass criteria**:
- Session B response mentions "previous" or "recall" or "nf-core/rnaseq"
- Workflow params show aligner=STAR, genome=GRCh38

**Why important**: This is the main use case — validates cross-session memory works

---

## 📁 Test Outputs

### Audit JSON
```bash
cat frontend/e2e/screenshots/memory-integration/audit_*.json
```

Structure:
```json
{
  "testId": "MM-4",
  "finalStatus": "done",
  "assertions": [
    {"name": "MM-4 Session A: Project created", "passed": true},
    {"name": "MM-4 Session B: Memory retrieved", "passed": true},
    ...
  ],
  "screenshots": ["MM4_01_sessionA_home.png", ...],
  "metadata": {"projectId": "...", "episodeId": 123}
}
```

### Screenshots
```bash
ls frontend/e2e/screenshots/memory-integration/
```

Examples:
- `MM1_01_home.png` - Home page after login
- `MM4_08_sessionB_params_prefilled.png` - Params pre-filled from memory

### View Results Summary
```bash
cat frontend/e2e/screenshots/memory-integration/audit_*.json | \
  jq '.[] | {testId, finalStatus, passed: [.assertions[] | select(.passed)] | length, total: [.assertions[]] | length}'
```

---

## 🐛 Troubleshooting

### MM-0 Fails: "Memory endpoints not accessible"
**Cause**: Memory API endpoints don't exist or return 404

**Fix**:
```bash
# Check if memory routes are registered
curl http://localhost:5000/api/memory/projects

# If 404, check frontend/server/routes.ts has memory routes
grep -n "api/memory" frontend/server/routes.ts
```

### MM-1 Fails: "Memory context not loaded"
**Cause**: Memory integration not wired into chat flow

**Fix**: Check if `memoryIntegration.processWithMemory()` is called in `/api/chat/stream`
```bash
grep -A5 "memoryIntegration" frontend/server/routes.ts | grep processWithMemory
```

### MM-2 Fails: "Episode not recorded"
**Cause**: Episode recording not triggered after workflow suggestion

**Fix**: Check memory-integration.ts is called in galaxy-assistant.ts

### MM-3 Fails: "Episode outcome not updated"
**Cause**: Integration patch not applied to nextflow_executor.py

**Fix**: Apply patches from `backend/lib/galaxy/ai/memory/INTEGRATION_PATCH.md`
```bash
grep -n "record_workflow_outcome" backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py
```

### MM-4 Fails: "Memory not retrieved in Session B"
**Cause**: Episode retrieval not working, or project ID mismatch

**Fix**:
1. Check episodes exist: `curl http://localhost:5000/api/memory/projects/:id/episodes`
2. Check same user in both sessions
3. Check projectId consistency

---

## ✅ Success Criteria

### Minimum Viable (Ready for Production)
- ✅ MM-0: All API endpoints accessible
- ✅ MM-1: Memory context loads
- ✅ MM-2: Episodes recorded
- ✅ MM-3: Outcomes updated (80%+ assertions pass)
- ✅ MM-4: Cross-session reference works (80%+ assertions pass)

### Full Success
- ✅ All tests pass 95%+ assertions
- ✅ Screenshots show correct UI states
- ✅ Audit JSON has no errors
- ✅ Tests run consistently (3 runs, all pass)

---

## 🚀 Next Steps After Testing

### If All Tests Pass ✅
1. Commit integration patches
2. Run tests on dev environment
3. Document any edge cases found
4. Implement MM-5 through MM-12 (advanced features)

### If Tests Fail ❌
1. Review audit JSON for specific assertion failures
2. Check screenshots for UI state issues
3. Review logs: `tail -f backend/logs/galaxy.log`
4. Apply fixes from troubleshooting section
5. Re-run failed tests

---

## 📖 Additional Resources

- **Architecture Docs**: `docs/20260518_CONTEXT_MEMORY_ARCHITECTURE_GAPS_AND_SOLUTIONS.md`
- **Implementation Guide**: `docs/20260518_MEMORY_INTEGRATION_STATUS_AND_IMPLEMENTATION.md`
- **E2E Test Plan**: `docs/20260518_MEMORY_INTEGRATION_E2E_TEST_PLAN.md`
- **Integration Patches**: `backend/lib/galaxy/ai/memory/INTEGRATION_PATCH.md`

---

## 🎬 Ready to Test!

**Recommended first test** (fastest, safest):
```bash
cd frontend
npm run test:e2e -- memory-integration.e2e.ts --grep "MM-0"
```

**Expected output**:
```
════ MM-0 Preflight Results ════
  ✓ MM-0: Health endpoint returns 200
  ✓ MM-0: Database connectivity confirmed
  ✓ MM-0: Memory user endpoint accessible  (HTTP 200)
  ✓ MM-0: Memory projects endpoint accessible  (HTTP 200)
  ✓ MM-0: Memory episodes endpoint accessible  (HTTP 200)
```

Good luck! 🚀
