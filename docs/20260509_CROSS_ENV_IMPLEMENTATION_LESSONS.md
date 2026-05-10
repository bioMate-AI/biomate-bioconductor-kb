# Cross-Environment Implementation Lessons — 2026-05-09

## Context
This document captures lessons from the CryoEM E2E dev deployment session. The session involved making the CS-3 test pass on `https://dev-public.biomate.ai` with a real CryoSPARC pipeline run. Most failures were not bugs in the workflow logic — they were cross-environment gaps.

---

## Lesson 1: Galaxy user provisioning is async — credentials must wait for it

**Problem:** E2E test stored CryoSPARC credentials immediately after registration. Galaxy account provisioning is fire-and-forget (takes ~1–3s). The credential was stored under the admin Galaxy user instead of the test user, causing a `source: 'none'` response from the LicenseGate check.

**Fix in test code:**
```typescript
// Wait for Galaxy provisioning to complete before storing credentials
await page.waitForFunction(async () => {
  const r = await fetch('/api/auth/me', { credentials: 'include' });
  const d = await r.json();
  return !!(d.user?.galaxyUserId);
}, { timeout: 15_000, polling: 1000 }).catch(() => {});
// Then store credential
await page.evaluate(async ({ url, license }) => {
  await fetch(`${url}/api/users/credentials`, { method: 'POST', credentials: 'include', ... });
}, { url: BASE_URL, license: CRYOSPARC_LICENSE });
```

**Deeper fix (code):** Store credentials in BioMate's PostgreSQL (`users` table as JSON), not Galaxy's vault. This eliminates the async provisioning dependency entirely.

---

## Lesson 2: Galaxy route conflicts — custom endpoints must not collide with framework routes

**Problem:** `GET /api/workflows/license-requirements` was registered as a custom endpoint, but Galaxy's framework has `GET /api/workflows/{workflow_id}` which matched first. Every call returned 400 with `"Invalid id length"`.

**Fix:**
- Moved the endpoint to `/api/nextflow/license-requirements` (no collision with framework routes)
- Updated Node.js proxy to forward to the new path

**Rule:** When adding custom Galaxy endpoints under `/api/workflows/`, always verify there's no existing `{param}` route that would catch the path. Safe namespaces: `/api/nextflow/`, `/api/biomate/`, `/api/ai_assistant/`.

---

## Lesson 3: Galaxy billing router fails silently — missing env vars block entire router

**Problem:** `billing_router.py` imported `redis` at module level. Dev Galaxy container had no `redis` package → `ImportError` → billing router failed to load → `/internal/users/provision` returned 404 → no user got a Galaxy account → all API calls fell back to admin key.

**Fix 1 (code):** Guard the redis import:
```python
try:
    import redis
    _REDIS_AVAILABLE = True
except ImportError:
    redis = None
    _REDIS_AVAILABLE = False
```

**Fix 2 (env):** `LAGO_WEBHOOK_SECRET` was missing from dev `.env` → add it.

**Rule:** Every module-level import of optional dependencies (redis, psycopg2, boto3) must be guarded with try/except. Required env vars must be validated at startup with clear error messages, not silently disabled at import time.

---

## Lesson 4: localStorage persistence across E2E test runs causes phantom passes

**Problem:** Previous test runs populated `movies_path` in the browser's `localStorage`. New test runs on the same domain inherited that state. Tests "passed" because the workflow card had stale params, not real extracted ones.

**Fix in test code:**
```typescript
// Before navigating, inject init script to clear localStorage
await page.addInitScript(() => {
  try { localStorage.clear(); sessionStorage.clear(); } catch {}
});
```

**Key insight:** `page.evaluate(() => localStorage.clear())` runs AFTER React has already initialized from localStorage. `addInitScript` runs BEFORE any page JavaScript, so React starts with a clean state.

**Rule:** E2E tests must always start with clean browser state. Use `page.addInitScript` to clear localStorage/sessionStorage before navigation.

---

## Lesson 5: Multiple background sync processes destroy container stability

**Problem:** Each Claude Code session started `sync_to_dev.sh` without `--once` flag. After several sessions, there were 8+ background sync processes each running every 10 minutes, all competing to stop/rm/run the frontend container. The container was replaced every ~10 minutes, wiping the volume mount and all hot-patched code.

**Fix (operations):**
- Always run `bash scripts/sync_to_dev.sh --once` (not without the flag)
- Before running, kill existing sync processes: `pkill -f sync_to_dev.sh`
- Added persistent volume mount to the sync script's `docker run` command

**Fix (infrastructure):** The `sync_to_dev.sh` `deploy_frontend` function now mounts the pre-compiled index.js as a volume:
```bash
VOLUME_MOUNT=""
[ -f /opt/biomate/dist_index.js ] && VOLUME_MOUNT="-v /opt/biomate/dist_index.js:/app/dist/index.js"
docker run -d ... $VOLUME_MOUNT biomate-dev-frontend:latest
```

**Rule:** Never run background sync scripts without `--once` in dev sessions. Check for existing sync processes before starting a new one.

---

## Lesson 6: Nextflow DSL2 forbids top-level variable assignments after declarations

**Problem:** `cryosparc_standard_spa/main.nf` had:
```groovy
def get_sample_recommendations(...) { ... }  // function declaration
CS_IMAGE = "..."                             // assignment AFTER declaration → ERROR
```

Nextflow DSL2 forbids mixing statements (assignments) with declarations (function/process/workflow) at the script level.

**Fix:** Move variable assignments to BEFORE all function declarations, OR convert to `params`:
```groovy
params.cs_image = "399683337364..."  // valid at any position as params
params.cs_helper = '''...'''
```
Also removed `workflow.onComplete { ... }` which is not allowed at script level in Nextflow 26.04+.

**Rule:** In Nextflow DSL2, use `params.xxx = value` for script-level variables. Never use bare `VARNAME = value` or `def VARNAME = value` at the script level alongside function/process/workflow declarations.

---

## Lesson 7: Docker volume mounts persist code through container restarts; docker cp does not

**Problem:** `docker cp /tmp/patched.js container:/app/dist/index.js` replaces the file on disk AFTER Node.js has already loaded the old code into memory. Container restart with `--restart unless-stopped` starts from the base image file, not the copied file.

**Fix:** Use a bind mount:
```bash
docker run -d ... -v /opt/biomate/dist_index.js:/app/dist/index.js biomate-dev-frontend:latest
```
The volume mount takes precedence over the image file at startup.

**Rule:** Never use `docker cp` to hot-patch production code that needs to survive restarts. Use volume mounts for files that change between deployments but shouldn't be baked into the image.

---

## Lesson 8: SQLite write fails when database files are owned by the wrong user

**Problem:** After `sync_to_dev.sh` replaced `universe.sqlite` on dev (uploaded from local, owned by `ubuntu`), Galaxy's gunicorn process (running as `galaxy` user) couldn't write to it. All DB operations silently failed.

**Fix:**
```bash
docker exec -u root biomate-galaxy-dev chown -R galaxy:galaxy /app/database/
```

**Rule:** Always set correct ownership after copying files into containers. Add `chown` to the sync script after any database file replacement.

---

## Lesson 9: E2E tests must never rely on stale state from previous runs

**Root principle** (per CLAUDE.md): Passing a test by bypassing the system it tests is worthless. The previous CS-3 tests were passing because:
- localStorage had stale `movies_path` from old runs
- The run button appeared enabled because old params were restored from cache
- The test was measuring localStorage restoration, not AI param extraction

After fixing with `addInitScript`, the test correctly exposed that the Galaxy AI WAS extracting `movies_path` properly — but the CryoSPARC credential check was blocking the run due to provisioning timing.

**Diagnostic approach when a test unexpectedly passes:**
1. Check if the test relies on localStorage/sessionStorage from previous runs
2. Add `addInitScript` to clear storage before each test
3. Re-run — if it fails, the original pass was from stale state

---

## Pending Code Changes (all in this session)

| File | Change |
|------|--------|
| `frontend/e2e/cryoem-stepwise-and-output.e2e.ts` | `addInitScript` for localStorage clear; wait for Galaxy provisioning before credential storage; cookie domain uses `BASE_DOMAIN` not hardcoded "localhost" |
| `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py` | Redis import made optional with `_REDIS_AVAILABLE` guard |
| `backend/lib/galaxy/webapps/galaxy/api/credentials_api.py` | License-requirements endpoint moved to `/api/nextflow/license-requirements` |
| `frontend/server/routes.ts` | Proxy license-requirements to new Galaxy path; CryoSPARC execute reads license from params/env fallback |
| `frontend/server/galaxy-assistant.ts` | Debug log for `required_params` |
| `frontend/scripts/sync_to_dev.sh` | Volume mount for patched index.js in `docker run` |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` | DSL2 fixes: `CS_IMAGE`/`CS_HELPER` → `params.cs_image`/`params.cs_helper`; removed `workflow.onComplete` |
| `CLAUDE.md` | Root-cause resolution rule added |

## Current CS-3 Status
- ✅ `ai-response-received`
- ✅ `workflow-card-appeared`
- ⏳ `execute-returned-runId` — pending provisioning fix in test
- Pipeline fails with Nextflow DSL2 error (fixed in main.nf, needs re-run to verify)
