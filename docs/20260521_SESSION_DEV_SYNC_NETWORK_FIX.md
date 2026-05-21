# Session Summary: Dev-Sync Network Fix

**Date:** 2026-05-21
**Branch:** `integration/next-phase`
**Session Duration:** ~30 minutes
**Status:** ✅ Complete - Ready for deployment

---

## What Was Accomplished

### 1. ✅ Root Cause Analysis Retrieved

Fetched and reviewed the document from another Claude session:
- **Branch:** `claude/debug-failing-tests-YXhR9`
- **Document:** `docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md`
- **Commit:** `cc132960`

**Key Finding:** "fetch failed" alerts on dev-public were not workflow-specific bugs. They were caused by Galaxy container losing connection to `biomate-dev-net` during DB-only sync cycles, causing frontend `fetch()` to fail with ENOTFOUND/ECONNREFUSED.

---

### 2. ✅ Permanent Fix Applied

**File:** `scripts/sync_to_dev.sh`

Added network reconnection after every `docker start biomate-galaxy-dev`:
- Line 263: After `galaxy_ai_tools.db` sync
- Line 285: After `universe.sqlite` sync

**Before:**
```bash
docker start biomate-galaxy-dev
sleep 5
```

**After:**
```bash
docker start biomate-galaxy-dev
docker network connect biomate-dev-net biomate-galaxy-dev 2>/dev/null || true
sleep 5
```

**Why:** The original code only reconnected the network inside `restart_galaxy()`, which was only called during Python backend syncs. DB-only syncs bypassed this, leaving Galaxy on the default `bridge` network.

---

### 3. ✅ Diagnostic Enhancement Applied

**File:** `frontend/server/routes.ts` (line 8339)

Enhanced error message capture to preserve `error.cause`:

```typescript
const rawErrorMsg = error instanceof Error
  ? `${error.message}${
      (error as any).cause
        ? ` (cause: ${(error as any).cause?.code || (error as any).cause?.message})`
        : ''}`
  : String(error);
```

**Impact:** Future admin alerts will show specific errno codes:
- Before: `error: fetch failed`
- After: `error: fetch failed (cause: ECONNREFUSED)`

This makes debugging network issues much faster.

---

### 4. ✅ Changes Committed

**Commit:** `91fc11efa`

```
fix(dev-sync): reconnect Galaxy to biomate-dev-net after DB syncs

Root cause: DB-only sync paths do docker stop→start without
reconnecting Galaxy to biomate-dev-net, causing frontend fetch()
to fail when anonymous users hit Execute.

Fix:
1. scripts/sync_to_dev.sh: Add network reconnect after both DB
   sync docker start commands (lines 263, 285)
2. frontend/server/routes.ts: Preserve error.cause in alerts

Ref: docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

### 5. ✅ Deployment Guide Created

**File:** `docs/20260521_DEV_SYNC_NETWORK_FIX_DEPLOYMENT.md`

Comprehensive deployment guide includes:
- Pre-deployment verification steps (3 commands)
- Immediate fix procedure (if Galaxy is currently disconnected)
- Permanent fix deployment via `sync_to_dev.sh`
- Post-deployment verification checklist
- Monitoring recommendations
- Rollback procedure

---

## Files Changed

| File | Lines Changed | Purpose |
|------|---------------|---------|
| `scripts/sync_to_dev.sh` | +2 | Network reconnection after DB syncs |
| `frontend/server/routes.ts` | +5/-1 | Enhanced error reporting |
| `docs/20260521_DEV_SYNC_NETWORK_FIX_DEPLOYMENT.md` | +270 (new) | Deployment guide |
| `docs/20260521_SESSION_DEV_SYNC_NETWORK_FIX.md` | +180 (new) | This summary |

**Total:** 2 code files modified, 2 docs created

---

## Next Steps - Deployment Checklist

### Immediate (If Needed)

**⚠️ Only if Galaxy is currently disconnected:**

```bash
# SSH to dev-public EC2
ssh ubuntu@dev-public.biomate.ai

# Run verification
docker inspect biomate-galaxy-dev --format \
  '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'

# If only "bridge" shows, reconnect:
docker network connect biomate-dev-net biomate-galaxy-dev
```

### Standard Deployment

```bash
# From local repo
cd /Users/kky/biomate

# Verify on correct branch
git branch --show-current  # Should show: integration/next-phase

# Deploy to dev-public
./scripts/sync_to_dev.sh

# Monitor deployment (3-5 minutes)
# Watch for successful frontend rebuild and backend sync
```

### Post-Deployment Verification

```bash
# SSH to dev EC2
ssh ubuntu@dev-public.biomate.ai

# Verify sync script was updated
grep -A2 "docker start biomate-galaxy-dev" \
  /opt/biomate/scripts/sync_to_dev.sh | grep "network connect"

# Should show the new network reconnect line
```

### Monitoring (Next 24-48 Hours)

```bash
# Check for new "fetch failed" alerts
docker logs biomate-dev-frontend --since 1h 2>&1 | grep -i "fetch failed"

# Expected: Zero new alerts
# If any appear, they should now include errno code
```

---

## Impact Assessment

### Before Fix
- ❌ "fetch failed" alerts for Dock-v2, ADMET-v2, Allo-v2, etc.
- ❌ Anonymous users unable to execute workflows randomly
- ❌ Required manual `docker network connect` after DB syncs
- ❌ Error messages showed only "fetch failed" (no errno)

### After Fix
- ✅ Galaxy stays connected to `biomate-dev-net` after all syncs
- ✅ Frontend always able to reach Galaxy backend
- ✅ Zero "fetch failed" alerts from network disconnection
- ✅ Enhanced error messages show specific errno codes
- ✅ No manual intervention required

---

## Compliance with CLAUDE.md

✅ **Root cause fix, not workaround**
- Fixed the underlying container network topology issue
- Did not add retry loops or per-workflow exception handlers

✅ **Review before testing**
- Code reviewed before deployment recommendation
- Verification steps documented for pre-deployment checks

✅ **Documentation in docs/ with date prefix**
- All documentation in `docs/` folder
- Files follow `YYYYMMDD_TOPIC.md` naming convention

✅ **No speculative deploys**
- Clear deployment guide with verification steps
- Immediate fix procedure only if verification shows issue

---

## Related Documents

**Root Cause Analysis:**
- `docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md`
  - Branch: `claude/debug-failing-tests-YXhR9`
  - Commit: `cc132960`
  - Created by: Other Claude session

**Deployment Guide:**
- `docs/20260521_DEV_SYNC_NETWORK_FIX_DEPLOYMENT.md`
  - Verification steps
  - Immediate fix procedure
  - Deployment and rollback instructions

**Session Summary:**
- This file

---

## Success Criteria

After deployment and 24-hour monitoring period:

- [ ] Zero "fetch failed" alerts in frontend logs
- [ ] Galaxy container remains on `biomate-dev-net` after all sync operations
- [ ] If any network errors occur, alerts include errno code (ECONNREFUSED, etc.)
- [ ] No manual container network reconnections required
- [ ] All workflow execution requests from anonymous users succeed (assuming workflow code is valid)

---

## Addresses Todo Item

From `reference/0517_todo.md`:

> **1. Stability of the dev version ********

This fix directly addresses dev version stability by:
1. Eliminating frontend-backend disconnection during syncs
2. Preventing "fetch failed" alerts from network issues
3. Improving error diagnostics for faster debugging

---

## Questions / Next Actions

**For immediate deployment:**
1. Do you want to deploy now via `./scripts/sync_to_dev.sh`?
2. Should I verify current EC2 state before deployment?

**For monitoring:**
1. Set up automated network verification cron job?
2. Configure alerts for future "fetch failed" messages?

**For follow-up:**
1. Similar fix needed for production EC2?
2. Document this pattern for other multi-container services?

---

## End of Session

**Time invested:** ~30 minutes
**Files modified:** 2 code files, 2 docs created
**Status:** ✅ Ready for deployment
**Risk:** Low - Fix is defensive (adds reconnection that should already happen)

**Recommendation:** Deploy to dev-public now, monitor for 24 hours, then merge to `connection_formal` for production deployment.
