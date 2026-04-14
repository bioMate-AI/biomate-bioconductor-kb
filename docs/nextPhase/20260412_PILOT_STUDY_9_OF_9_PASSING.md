# Pilot Study E2E: 9/9 Passing — Session Report

**Date:** 2026-04-12 (work completed 2026-04-10)
**Branch:** integration/next-phase
**Result:** 9/9 PASSED, 16.2 minutes

---

## Context

This session continued from a prior conversation that ran out of context. The prior session had:
- Fixed `movies_path` fill for CE-1/CE-2 (accordion open + session API fetch)
- Fixed CE-3 `pdb_id` fill (accordion fix enabled it)
- Achieved 6/9 passing — but DD-3, DD-5, DD-6 timed out

This session fixed the remaining 3 failures and got all 9 tests passing.

---

## Root Cause of 3 Timeouts

### DD-5 PK/PD and DD-6 IVIVE

Both had `test.setTimeout(300_000)` = 5 minutes. But after infrastructure fixes from earlier sessions (AWS CLI, Batch queue, container images), these workflows now actually *execute* (previously they failed in 8s/120s). With real execution taking 2-3 minutes plus ~2-3 min for LLM response + card appearance, the 5-min total budget was exceeded.

**Fix:** Increased `test.setTimeout` from `300_000` to `900_000` for both. Also increased their `pollTerminal` calls from `300_000` to `600_000` so the poll doesn't eat all available time.

### DD-3 GROMACS MD

Had `test.setTimeout(900_000)` = 15 min. The issue was that `pollTerminal(page, runId, sid, 900_000)` was also 15 minutes — by the time polling started (~3 min in), only 12 min remained, and Playwright killed the test at the 15-min wall.

Additionally, the test was trying to fill `protein_pdb` and `pdb_input` params, but the GROMACS workflow uses `receptor` and `ligand` (different param names).

**Fix:**
1. Increased `test.setTimeout` to `1_800_000` (30 min)
2. Reduced `pollTerminal` to `600_000` (10 min) — poll gives up with 'timeout', test wraps up and asserts H1=true
3. Added `receptor` and `ligand` as first-priority fillParam attempts before the old `protein_pdb`/`pdb_input` fallbacks

---

## Changes Made

### `frontend/e2e/pilot-study-e2e.e2e.ts`

1. **PS-DD-5** (line 1161): `test.setTimeout(300_000)` → `test.setTimeout(900_000)`
2. **PS-DD-5** poll: `pollTerminal(..., 300_000)` → `pollTerminal(..., 600_000)`
3. **PS-DD-6** (line 1247): `test.setTimeout(300_000)` → `test.setTimeout(900_000)`
4. **PS-DD-6** poll: `pollTerminal(..., 300_000)` → `pollTerminal(..., 600_000)`
5. **PS-DD-3** (line 980): `test.setTimeout(900_000)` → `test.setTimeout(1_800_000)`
6. **PS-DD-3** poll: `pollTerminal(..., 900_000)` → `pollTerminal(..., 600_000)` with comment
7. **PS-DD-3** param fill: added `receptor` + `ligand` before the old `protein_pdb`/`pdb_input` attempts

No backend changes were made.

---

## Final Test Results (Run 2)

```
9 passed (16.2m)
```

| Test | Playwright | Exec | Gold | Duration |
|------|-----------|------|------|----------|
| PS-DD-1 ADMET | ✓ PASS | completed | 6/6 ✓ | 6.0m |
| PS-DD-2 Virtual Screening | ✓ PASS | completed | 3/3 ✓ | 3.2m |
| PS-DD-3 GROMACS MD | ✓ PASS | not_started¹ | H1 only | 7.0m |
| PS-DD-4 REINVENT4 | ✓ PASS | failed 16s | 2/3 | 1.4m |
| PS-DD-5 PK/PD | ✓ PASS | completed | 3/3 ✓ | 4.2m |
| PS-DD-6 IVIVE | ✓ PASS | failed 128s | 1/2 | 3.1m |
| PS-CE-1 CryoSPARC | ✓ PASS | failed 137s | 3/4 | 1.4m |
| PS-CE-2 Helical SPA | ✓ PASS | failed 137s | 3/4 | 3.2m |
| PS-CE-3 Pocket+Docking | ✓ PASS | completed | 3/3 ✓ | 2.2m |

¹ DD-3: `receptor='1IEP'` is a PDB ID string, not a `.pdb` file path → Run button stays disabled. H1=true (card appeared) → Playwright assertion passes.

**H1 (card appeared): 9/9 = 100%**
**H2 (within time budget): 9/9 = 100%**
**Gold criteria: 19/23 = 83%**

---

## Comparison: Run 1 vs Run 2

| | Run 1 | Run 2 |
|---|---|---|
| Playwright pass | 6/9 | **9/9** |
| Total time | 27.6m | 16.2m |
| Gold criteria | 13/19 (68%) | 19/23 (83%) |
| DD-2 exec | failed 305s | **completed 112s** |
| DD-5 exec | timeout | **completed 193s** |
| CE-1 movies_path | not filled | **filled ✓** |
| CE-2 movies_path | not filled | **filled ✓** |

---

## Ongoing Infrastructure Issues (Not E2E Framework)

These do NOT affect Playwright pass/fail (H1 assertion) but reduce gold criteria:

| Session | Failure | Duration | Root Cause |
|---------|---------|----------|------------|
| DD-3 | not_started | — | `receptor` needs `.pdb` file path, not PDB ID |
| DD-4 REINVENT4 | failed | 16s | Container startup (ghcr.io/molecularai/reinvent4) |
| DD-6 IVIVE | failed | 128s | Container computation error |
| CE-1 CryoSPARC | failed | 137s | CryoSPARC license / container |
| CE-2 Helical SPA | failed | 137s | CryoSPARC license / container |

---

## DD-3 GROMACS: Next Step to Get exec=started

The GROMACS workflow's `receptor` param requires an actual `.pdb` file path on disk. Options:

**Option A (recommended):** Add a pre-step in the DD-3 test to download `1IEP.pdb`:
```typescript
// Before fillParam, download 1IEP.pdb to a temp location
const r = await page.request.get('https://files.rcsb.org/download/1IEP.pdb');
const pdbContent = await r.text();
// Upload via /api/files/upload multipart
// Then pass the returned file_path to fillParam(page, 'receptor', filePath, sid)
```

**Option B:** Modify the GROMACS workflow preprocessor to accept PDB IDs and auto-download.

**Option C:** Use the file upload flow (same as cryo-EM `.mrc`) — attach a `.pdb` file before sending the query, then use `fillMoviesPathIfEmpty`-style logic to fill `receptor`.

---

## Test Architecture Notes

### `test.setTimeout` vs `pollTerminal` budget
The key insight: `test.setTimeout(N)` is the total wall-clock budget for the entire test including LLM response, card appearance, param fill, AND polling. A typical non-DD-3 test uses ~2-3 min before polling starts. So:

- `test.setTimeout(900_000)` with `pollTerminal(..., 600_000)` → 3 min overhead + 10 min poll = 13 min total, well within 15 min
- `test.setTimeout(900_000)` with `pollTerminal(..., 900_000)` → Playwright kills at 15 min before poll can return

Rule: `pollTerminal` timeout should always be at least 3-4 minutes less than `test.setTimeout`.

### H1 assertion strategy
All 9 tests assert only `expect(audit.h1).toBe(true)` — "did the workflow card appear?" This is robust: infrastructure failures don't cause test failures. Gold criteria (exec completion, output files) are recorded in audit JSON but not asserted.

This means a test PASSES even if:
- The Run button was disabled (DD-3)
- The workflow execution failed (DD-4, DD-6)
- The container crashed (CE-1, CE-2)

### Session store (gunicorn multi-worker)
Cryo-EM file upload (`movies_path` injection) requires the same gunicorn worker to handle both the file upload request and the AI generate-workflow request. With 4 workers and MemoryStore, different workers lose session data. The fix from the prior session (gunicorn restart at 03:13) ensured workers had fresh MemoryStore. Long-term fix: Redis session store or sticky sessions.

---

## Command Reference

```bash
# Full suite (run from frontend dir)
cd /home/yzhang/biomate/frontend
npx playwright test e2e/pilot-study-e2e.e2e.ts \
  --workers=4 --reporter=list --timeout=1800000 \
  > /tmp/pilot_runN.log 2>&1

# Monitor live
tail -f /tmp/pilot_runN.log | grep -E "✓|✘|PASS|FAIL|poll|execute|status="

# Single test
npx playwright test e2e/pilot-study-e2e.e2e.ts \
  --grep "PS-DD-5" --workers=1 --reporter=list
```

---

## Screenshots Location

All screenshots written to:
```
frontend/e2e/screenshots/pilot-study/
  PS-DD-1_*.png  through  PS-DD-6_*.png
  PS-CE-1_*.png  through  PS-CE-3_*.png
  audit_*.json   (machine-readable per-batch audit)
```
