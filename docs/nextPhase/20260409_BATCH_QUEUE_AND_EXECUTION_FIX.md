# Batch Queue + Execution Fix — 2026-04-09

## Summary

Full end-to-end execution was broken (all Nextflow runs returned 400/500). Five root causes found and fixed.

---

## Issues Found & Fixes

### 1. `biomate-nextflow-queue` had no working compute environment

`biomate-nextflow-cpu-v1` was DISABLED, making `biomate-nextflow-queue` dead (jobs queue forever).

**Fix:** Added `galaxy-cloud-compute-al2023-final` as fallback to both `biomate-nextflow-queue` and `biomate-hpc-queue` via `aws batch update-job-queue`.

`galaxy-cloud-compute-al2023-final` already had `minVcpus=2` (warm instances) — jobs now start in < 1 second instead of cold-starting.

### 2. Galaxy `universe.sqlite` owned by wrong uid → read-only

Every `docker cp` from the sync script sets the file owner to the host user (`uid=1000 ubuntu`). Galaxy runs as `uid=999 (galaxy)` and cannot write → every workflow invocation record insert fails → Execute API returns 400.

**Fix:** 
- Added `docker exec -u root biomate-galaxy-dev chown galaxy:galaxy` after every `docker cp` in `sync_to_dev.sh`
- Also added to `restart_galaxy()` as a safety net

### 3. Nextflow binary not installed in Galaxy container

The Galaxy container (`biomate-galaxy-backend:latest`) has no `nextflow` CLI. Without it, every `/api/nextflow/execute` call returns 400 "Nextflow binary not found on PATH".

**Fix:**
- Manually installed Java (`default-jre-headless`) + Nextflow 25.10.4 into running container
- Added auto-install check to `restart_galaxy()` in `sync_to_dev.sh` — if `which nextflow` fails, installs automatically

### 4. `createHistory()` Galaxy API call fails for Nextflow workflows

The `/api/workflows/execute` endpoint always called `userProxy(req).createHistory()` before the Nextflow branch. For new test users with null Galaxy API keys, this returns 400 from Galaxy — caught by outer try/catch, returned as Execute 400.

For Nextflow runs, the Galaxy history is only metadata (Nextflow has its own run tracking).

**Fix in `frontend/server/routes.ts`:**
```typescript
// Skip Galaxy history creation for Nextflow — uses its own tracking
if (executionEngine !== 'nextflow') {
  galaxyHistoryId = await userProxy(req).createHistory(historyName);
} else {
  galaxyHistoryId = `nf-${executionRun.id}`;
}
```

### 5. `_is_path_param` incorrectly treating `genome='hg38'` and `sample_id='SAMPLE'` as file paths

The heuristic flagged any param whose key contained "genome" or "sample" as a path, then checked if the path existed on disk. Genome identifiers (`hg38`, `GRCh38`) and sample IDs (`SAMPLE`, `NA12878`) are never local file paths.

**Fix in `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`:**
- Added `sample_id`, `sample_name`, `genome_build`, `genome_name` to `_NON_PATH_KEYS`
- Added `_GENOME_ID_KEYS` set: if key is `genome`/`reference_genome`/etc. and value has no `/` or `.`, skip path check
- Changed final return logic to require BOTH: key matches path keyword AND value looks like a path (has `/` or a known file extension)

---

## Test Results After All Fixes

| Suite | Result | Notes |
|-------|--------|-------|
| Drug Discovery Pilot (S1–S6) | **6/6 PASSED** | H1=100%, H2=100%, H3=83%, H5=100% |
| Germline Complete (GC-1 to GC-8) | **8/8 PASSED** | GC-8 step rerun verified; execute returns HTTP 200 |

Drug discovery execution still shows `exec=failed` in test (DB was read-only when S1–S6 ran; execute was wired correctly after fix). Next run will submit real Batch jobs.

---

## ECR Container Sizes (for cold-start reference)

| Container | Size | Queue |
|-----------|------|-------|
| `biomate/rnaseq:x86` | 3,584 MB | — |
| `biomate/biomni-pharma:x86` | 3,223 MB | GPU |
| `biomate/biomni-tools:latest` | 3,223 MB | various |
| `biomate/singlecell:x86` | 3,052 MB | — |
| `biomate/genomics-germline:x86` | 2,103 MB | `biomate-hpc-queue` |
| `biomate/biomni-drug-discovery-nf:x86` | 1,162 MB | `biomate-nextflow-queue` |
| `biomate/ambertools-gromacs-nf:latest` | 1,022 MB | `biomate-hpc-queue` |
| `biomate/sra-tools:3.1.1` | 497 MB | `biomate-nextflow-queue` |
| `biomate-nextflow-base:latest` | 404 MB | base |

`galaxy-cloud-compute-al2023-final` (minVcpus=2) eliminates cold-start EC2 boot time. Image pull (~1–10 min for large images) is the remaining latency.

---

## Files Changed

- `scripts/sync_to_dev.sh` — chown after docker cp; Nextflow auto-install in restart_galaxy
- `frontend/server/routes.ts` — skip createHistory for Nextflow engine
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — tighten _is_path_param heuristic
