# Dev-Sync Network Fix - Deployment Guide

**Date:** 2026-05-21
**Branch:** `integration/next-phase`
**Commit:** `91fc11efa`
**Related:** `docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md`

---

## Summary

This guide covers deploying the fix for the "fetch failed" alerts on dev-public.biomate.ai. The root cause was Galaxy container dropping off `biomate-dev-net` during DB-only sync cycles, causing frontend-to-backend connection failures.

**Fixes applied:**
1. ✅ `scripts/sync_to_dev.sh` - Network reconnection after all `docker start` commands
2. ✅ `frontend/server/routes.ts` - Enhanced error reporting with `error.cause`

---

## Pre-Deployment: Verify Current State

SSH to dev-public EC2 and run these verification commands:

```bash
# 1. Check if Galaxy is on the correct network
docker inspect biomate-galaxy-dev --format \
  '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'

# Expected output: "biomate-dev-net" present
# If only "bridge" appears, the immediate fix below is required
```

```bash
# 2. Test frontend→Galaxy connectivity
docker exec biomate-dev-frontend sh -c \
  'getent hosts biomate-galaxy-dev; \
   wget -qO- --timeout=5 http://biomate-galaxy-dev:8081/api/version \
     || echo UNREACHABLE'

# Expected: Shows IP and JSON version response
# If "UNREACHABLE", Galaxy is not reachable from frontend
```

```bash
# 3. Verify gunicorn is running
docker exec biomate-galaxy-dev sh -c \
  'ps -ef | grep -E "gunicorn|8081" | grep -v grep; \
   cat /app/database/gravity/gunicorn.pid 2>/dev/null'

# Expected: Shows gunicorn processes and PID file
```

---

## Immediate Fix (If Galaxy is Disconnected)

**⚠️ Only run this if verification #1 shows Galaxy is not on `biomate-dev-net`**

```bash
# SSH to dev-public EC2
ssh ubuntu@dev-public.biomate.ai  # or use EC2_HOST from .env

# Reconnect Galaxy to the network
docker network connect biomate-dev-net biomate-galaxy-dev

# Verify connection restored
docker exec biomate-dev-frontend sh -c \
  'wget -qO- --timeout=5 http://biomate-galaxy-dev:8081/api/version'
```

**Result:** Frontend can now reach Galaxy. Future anonymous users clicking "Run" should not trigger "fetch failed" alerts.

---

## Permanent Fix: Deploy via sync_to_dev.sh

The permanent fix is already committed to `integration/next-phase`. Deploy it to dev-public:

```bash
# From local repo root
cd /Users/kky/biomate

# Ensure you're on the correct branch
git branch --show-current
# Should output: integration/next-phase

# Run the sync script (will deploy both fixes)
./scripts/sync_to_dev.sh

# Watch the sync output
# You should see:
# [backend] Syncing Python files...
# [frontend] Building and deploying...
# [db] Syncing Galaxy databases via S3... (if DB changed)
```

**What gets deployed:**
- ✅ Updated `scripts/sync_to_dev.sh` (runs on EC2 next time DB sync triggers)
- ✅ Updated `frontend/server/routes.ts` (enhanced error alerts)

**Timeline:** ~3-5 minutes for full sync

---

## Post-Deployment Verification

### 1. Check sync script is updated on EC2

```bash
# SSH to dev EC2
ssh ubuntu@dev-public.biomate.ai

# Verify sync script has network reconnect commands
grep -A2 "docker start biomate-galaxy-dev" /opt/biomate/scripts/sync_to_dev.sh

# Expected output should show:
#   docker start biomate-galaxy-dev
#   docker network connect biomate-dev-net biomate-galaxy-dev 2>/dev/null || true
#   sleep 5
```

### 2. Trigger a DB sync to test the permanent fix

```bash
# From local machine, update a DB file timestamp
touch backend/database/galaxy_ai_tools.db

# Commit the change
git add backend/database/galaxy_ai_tools.db
git commit -m "test: trigger DB sync for network fix verification"

# Let sync_to_dev.sh detect and sync the change
# (If running in watch mode, it will auto-sync in <10 min)
# Or run manually:
./scripts/sync_to_dev.sh

# Watch EC2 logs to verify network reconnection happens
```

### 3. Verify enhanced error reporting

Next time a network error occurs, admin alerts should show:
```
error: fetch failed (cause: ECONNREFUSED)
```
Instead of just:
```
error: fetch failed
```

---

## Monitoring

### Check for "fetch failed" alerts

```bash
# On dev EC2, check recent container logs
docker logs biomate-dev-frontend --since 1h 2>&1 | grep -i "fetch failed"

# Expected: No new "fetch failed" errors after deployment
```

### Monitor Galaxy network status

```bash
# Add to cron or monitoring script (every 5 minutes):
docker inspect biomate-galaxy-dev --format \
  '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
  | grep -q biomate-dev-net || \
  (echo "WARNING: Galaxy not on biomate-dev-net" && \
   docker network connect biomate-dev-net biomate-galaxy-dev)
```

---

## Rollback Procedure

If the fix causes issues (unlikely):

```bash
# On dev EC2, revert to previous sync script version
cd /opt/biomate
git checkout HEAD~1 scripts/sync_to_dev.sh

# Or restore from git history:
git show HEAD~1:scripts/sync_to_dev.sh > scripts/sync_to_dev.sh
```

**Note:** The routes.ts change is diagnostic only (adds info, doesn't change behavior), so no rollback needed for that part.

---

## Root Cause Reference

From `docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md`:

> The script defensively re-attaches Galaxy to `biomate-dev-net` only inside
> `restart_galaxy` (line 364), and `restart_galaxy` is only called when the
> Python backend changed (line 437). The DB-only sync paths do
> `docker stop → docker start` **without** a follow-up `restart_galaxy`.

**Fix applied:** Network reconnection is now unconditional after every `docker start biomate-galaxy-dev`, not just during backend code syncs.

---

## Success Criteria

After deployment, the system should have:

- ✅ Zero "fetch failed" admin alerts for new workflow executions
- ✅ Galaxy container persistently on `biomate-dev-net` after all sync operations
- ✅ Enhanced error alerts showing specific errno codes (ECONNREFUSED, ETIMEDOUT, etc.)
- ✅ No manual container restarts required to restore frontend→backend connectivity

---

## Related Files

**Modified:**
- `scripts/sync_to_dev.sh` (lines 263, 285)
- `frontend/server/routes.ts` (line 8339)

**Documentation:**
- `docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md` (root cause analysis)
- This file (deployment guide)

**Branch:** `integration/next-phase`
**Commit:** `91fc11efa`

---

## Support

If "fetch failed" alerts continue after deployment:

1. Run verification steps above
2. Check `docker logs biomate-galaxy-dev --tail 100` for gunicorn crashes
3. Check if dev EC2 Docker daemon was restarted (container network state resets)
4. Review enhanced error message in alert - should now show specific errno

Contact: Reference commit `91fc11efa` and this deployment guide.
