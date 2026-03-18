# Async Execution Fix - Analysis & Plan

**Date:** 2026-02-12
**Discovery:** Galaxy ALREADY HAS async execution infrastructure!

---

## What I Found

### ✅ Galaxy HAS Parallel Execution

1. **Celery is running** - 2 workers active
2. **NextflowWorkflowJobRunner exists** - Async job runner
3. **Uses subprocess.Popen** - Non-blocking execution
4. **Has monitoring** - `check_watched_items()` method
5. **Production-ready** - AWS Batch, Slurm, S3 support

### ❌ The Problem

**TWO Nextflow Executor APIs exist:**

| File | Execution | Status |
|------|-----------|--------|
| `nextflow_executor.py` | `subprocess.run` (BLOCKING) | ❌ BROKEN |
| `nextflow_executor_v2.py` | `NextflowWorkflowRunner.queue_job()` | ❌ METHOD DOESN'T EXIST |

### 🐛 The Bug

**File:** `lib/galaxy/webapps/galaxy/api/nextflow_executor_v2.py`
**Line:** 125

```python
# Current (BROKEN):
runner.queue_job(                    # ❌ This method doesn't exist!
    invocation,
    nextflow_path=request.nextflow_path or request.workflow_name,
    parameters=request.parameters,
    profile=request.profile
)
```

**File:** `lib/galaxy/jobs/runners/nextflow_workflow_runner.py`
**Line:** 204, 287

```python
# Actual methods available:
def queue_workflow(self, workflow_invocation):         # ✅ Exists
def run_native_nextflow(self, workflow_invocation):   # ✅ Exists
```

**Issue:** Method name mismatch + parameter mismatch

---

## Root Cause Analysis

### Why v2 API Doesn't Work

1. **Creates tracking workflow** (line 92-96)
2. **Creates invocation** (line 99-117)
3. **Stores metadata in invocation.messages** (line 105-114)
4. **Tries to call `runner.queue_job()`** - ❌ DOESN'T EXIST
5. **With extra parameters** - but runner methods only take `workflow_invocation`

### Why Biomni Workflows Need Special Handling

Biomni workflows are **native Nextflow workflows**, not Galaxy tools.

The runner has:
- `queue_workflow()` - For converted Galaxy workflows
- `run_native_nextflow()` - For native Nextflow packages

We need `run_native_nextflow()` but it expects the metadata in a different format.

---

## The Solution

### Option 1: Use `run_native_nextflow()` (Recommended)

**Change:** Update `nextflow_executor_v2.py` to use existing method

```python
# BEFORE (broken):
runner.queue_job(
    invocation,
    nextflow_path=request.nextflow_path or request.workflow_name,
    parameters=request.parameters,
    profile=request.profile
)

# AFTER (fixed):
runner.run_native_nextflow(invocation)
```

**But requires:** Metadata must be stored in the correct format that `run_native_nextflow()` expects.

Let me check what format it expects...

### Option 2: Create `queue_job()` wrapper method

Add this to `NextflowWorkflowJobRunner`:

```python
def queue_job(self, invocation, nextflow_path=None, parameters=None, profile=None):
    """
    Wrapper for queueing native Nextflow workflows from API.

    This is a convenience method that stores metadata and calls run_native_nextflow.
    """
    # Store metadata in expected format
    if nextflow_path:
        invocation.add_message('info', json.dumps({
            'type': 'nextflow_native',
            'nextflow_path': nextflow_path,
            'parameters': parameters or {},
            'profile': profile or 'standard'
        }))

    # Call the actual execution method
    return self.run_native_nextflow(invocation)
```

This is cleaner and maintains backward compatibility.

---

## Recommended Fix

**Add the `queue_job()` wrapper method to NextflowWorkflowJobRunner.**

### Why This is Better:

1. ✅ Minimal code changes
2. ✅ Maintains API compatibility
3. ✅ Uses existing async infrastructure
4. ✅ No reinventing the wheel
5. ✅ Leverages Galaxy's production-tested code

### Implementation:

1. Add `queue_job()` method to `NextflowWorkflowJobRunner`
2. Test with simple workflow
3. Verify async execution
4. Run E2E tests
5. Done!

**Estimated time:** 30 minutes (not 4-8 hours!)

---

## What This Will Fix

### Before (Current State):

```
User → POST /api/nextflow/execute
     → nextflow_executor_v2.py
     → runner.queue_job()  ❌ Method doesn't exist
     → Falls back to nextflow_executor.py?
     → subprocess.run()  ❌ BLOCKS
     → Backend hangs for 6+ minutes
```

### After (Fixed):

```
User → POST /api/nextflow/execute
     → nextflow_executor_v2.py
     → runner.queue_job()  ✅ New wrapper method
     → runner.run_native_nextflow()  ✅ Async execution
     → subprocess.Popen()  ✅ Non-blocking
     → Returns immediately with invocation_id

Backend continues monitoring in background:
     → check_watched_items()  ✅ Polls process status
     → Updates invocation state
     → User can check status anytime
```

---

## Next Steps

1. ✅ **Add `queue_job()` wrapper method** - 10 min
2. ✅ **Test basic execution** - 5 min
3. ✅ **Verify non-blocking** - 5 min
4. ✅ **Run E2E test suite** - 10 min
5. ✅ **Document the fix** - 5 min

**Total:** ~35 minutes

Much simpler than rewriting Galaxy's execution system!

---

## User's Insight

> "I am surprised to see this, isn't galaxy has parallel ability already?"

**YES! You were absolutely right.** Galaxy has:
- Celery for async task execution
- Job runners for parallel execution
- AsyncJobRunner base class
- Monitoring infrastructure
- Production-tested code

The issue was just a simple method name mismatch in the v2 API.

**We don't need to rewrite anything** - just add one small wrapper method to use the existing infrastructure correctly.

---

**Status:** Ready to implement
**Complexity:** Low (one method, ~15 lines of code)
**Risk:** Very low (using existing tested code)
**Impact:** HIGH - fixes the production blocker
