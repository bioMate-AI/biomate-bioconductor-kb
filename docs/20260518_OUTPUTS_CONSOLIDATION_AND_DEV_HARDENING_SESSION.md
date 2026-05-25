# Outputs Consolidation + Dev-public Hardening — Session Doc (2026-05-18)

**Branch:** `integration/next-phase`
**Status:** PR 1 + PR 2 of outputs consolidation shipped to dev-public. PR 3 pending. Atomic-swap deploy fix shipped. v17 super-test running to validate end-to-end.

---

## 1. What this session resolved

The same end-user failure ("workflow ran, where are my outputs?") had been patched across 4 endpoints, 4 storage places, 3 ID flavors, and 3 UI surfaces over multiple sessions. Each patch was real but only closed one symptom because there was no canonical outputs path. This session:

1. Catalogued every fragmented path that contributes to outputs rendering (doc: `20260518_OUTPUTS_SERVICE_CONSOLIDATION_SPEC.md`).
2. Built `RunsOutputsService` as the single source of truth (PR 1).
3. Migrated the UI to consume the canonical endpoint (PR 2).
4. Fixed the dev-public `sync_to_dev.sh` race that caused multi-minute 502 windows every deploy.
5. Closed 5 unrelated dev-public bugs along the way.

---

## 2. Commits today (in order)

| commit | summary | layer |
|---|---|---|
| `12cd4ea3f` | L4 lint: `git rm -r --cached backend/work/` (432MB / 1801 files), `BIOMNI_FUNCTIONS_ANALYSIS_*` in `.dockerignore`, portability for `fix_biomni_tools.py` + `test_dd_modules.py` | release / GHA |
| `25ce01131` | `run_code` pluggable sandbox backend (`RUN_CODE_BACKEND_URL` env). Production deploy can drop the docker socket mount from the frontend container | security |
| `f13b15b02` | Portability fixes for 3 first-party files with `/home/yzhang/` literals | release / GHA |
| `15cc97f72` | 5-test smoke for the run_code dispatch (docker spawn + sidecar HTTP) | tests |
| `a270e223b` | MRC parser: cell dimensions at offsets 40/44/48 (was 96/100/104, the `extra` region — read zeros). Verified against live MRC bytes, voxel size 1.77 Å | viewer |
| `25a00b76d` | PostgreSQL `execution_runs` schema drift fix — 11 missing columns. Fire-and-forget `.catch` was silently swallowing the column-not-found error, so 0 rows persisted | storage |
| `3765ef87c` | `/api/workflows/runs/:id/output_files` S3 client uses NF creds + us-east-1 (was default us-west-2 → "must be addressed using the specified endpoint" redirect spam) | storage |
| `1abc2840f` | Workflow viewer's Output Results gate now accepts `invocationId` OR `runId` | UI |
| `16db6415e` | Consolidation spec for review | docs |
| `1b184feab` | **PR 1**: `RunsOutputsService` + `GET /api/runs/:anyId/outputs` + `GET /api/runs/:anyId/meta` | outputs core |
| `bc923b1a0` | **PR 2**: ChatOutputAttachments consumes the canonical endpoint (~50 lines → ~15 lines); DensityMapViewer prefers `downloadUrl` | outputs core |
| `01fd07a2d` | `sync_to_dev.sh`: atomic image swap (build `:next` → tag `:latest` → swap container). Dev no longer goes 502 mid-build | infra |

---

## 3. Outputs consolidation

### Why it was needed

| Layer | Code path | Independent failure I hit this session |
|---|---|---|
| API | `/api/invocations/:id/outputs` | needed S3 fallback (`f8cd7affc`), wrong region (`1298a9ff5`) |
| API | `/api/workflows/runs/:id/outputs` | proxied to `/output_files` but returned empty (`6dd35a6ac` switched component to it) |
| API | `/api/workflows/runs/:id/output_files` | wrong region + missing creds (`3765ef87c`) |
| API | `/step-file` proxy | constructed wrong S3 path when outdir suffix was wrong |
| Storage | MemStorage | wiped on every container restart |
| Storage | PostgreSQL | 11-column schema drift, silent `.catch` (`25a00b76d`) |
| Storage | `nextflowStatus.s3_output_files` | populated only during live run |
| Storage | `_findingsCache` | in-memory only |
| UI gate | `invocationId && showResults` | fragile to `currentRun` being null (`1abc2840f`) |
| UI state | `showResults` | useState+useEffect race (`974b86b87`) |
| UI fetch | useQuery key | runId vs invocationId vs galaxyInvocationId — 3 different ids identifying the same run |
| Parser | MRC header | wrong offsets (`a270e223b`) |
| Renderer | classifyFileType | missing density_map/structure cases (earlier fix) |

Each fix was real, but each only closed one symptom.

### The single path now

```
GET /api/runs/:anyId/outputs
  → resolve(anyId)        — accepts runId / galaxyInvocationId / nextflowRunId
  → list S3               — one client (us-east-1, NF creds, follow-redirects)
  → presign + normalize   — returns CanonicalOutput[] with always-set downloadUrl

Client: useQuery(['outputs', id]) → fetch above → cast → render
```

`CanonicalOutput` is shaped like `OutputDataset` (`metadata.s3Uri`, `fileType`, etc.) so the React renderer needs no translation.

### Smoke-test results (live on dev-public)

```
$ curl https://dev-public.biomate.ai/api/runs/a6607614-…/meta
{
  "runId": "a6607614-…",
  "galaxyInvocationId": "301b552f-…",
  "nextflowRunId": "301b552f-…",
  "s3Outdir": "s3://biomate-nextflow-work/nextflow/outputs/f6cda6a5-…/28a51d90",
  "status": "completed",
  "workflowName": "CryoSPARC Standard Single-Particle Analysis"
}

$ curl https://dev-public.biomate.ai/api/runs/a6607614-…/outputs
count: 258
mrc count: 3
  fileType: density_map
  downloadUrl: <presigned 515-char>
  step: 21_non_uniform_refinement
```

### What PR 3 still owes (not in this session)

- Make the 4 legacy endpoints (`/api/invocations/:id/outputs`, `/api/workflows/runs/:id/outputs`, `/api/workflows/runs/:id/output_files`, `/step-file`) thin wrappers around the service or 301 redirects.
- Update remaining `OutputRenderer` cases (StructureViewer for `.pdb/.cif`) to prefer `downloadUrl` like DensityMapViewer now does.
- Remove `OutputRenderer`'s fallback to step-file proxy once all consumers are on canonical.

---

## 4. Dev-public hardening

### `sync_to_dev.sh` atomic-swap

Old pattern caused multi-minute 502 windows every deploy:
```
docker stop && docker rm OLD     # immediate downtime
docker build new                  # 1–5 minutes
docker run new
```

New pattern (commit `01fd07a2d`):
```
docker build -t biomate-dev-frontend:next ...   # old container still serving
docker tag :next :latest                         # promote
docker rm -f OLD                                 # ~2 seconds
docker run NEW
```

Downtime now bounded by `docker run` (seconds), not the build. Failure path no longer touches the old container at all.

### PostgreSQL schema drift fix

PG `execution_runs` table was missing 11 columns the drizzle schema defined. `storage.createExecutionRun().catch()` was silently logging `column "error_message" does not exist` and dropping the write. Net effect: 0 rows persisted, so every container restart wiped user run history.

Fix (commit `25a00b76d`):
- `frontend/migrations/0010_execution_runs_schema_catchup.sql` — idempotent ALTER TABLE … IF NOT EXISTS for all 11 columns
- `scripts/sync_to_dev.sh` new `apply_postgres_migrations()` step runs all `frontend/migrations/*.sql` against `biomate-dev-postgres` before deploying the frontend

Verified end-to-end: create run → row in PG → docker restart frontend → fetch by ID → still found (via DB fallback). User run history now durable.

---

## 5. Test state

| version | result | what was tested |
|---|---|---|
| v14 | 83/84 | viewer mounted, only voxel-dims failed |
| v15b | 77/78 | regression: viewer didn't mount (currentRun=null edge case) |
| v17 (running) | TBD | full consolidation path |

The MRC fix is mathematically verified against live bytes (1.77 Å vs the prior 0 → "N/A"). Voxel-dims should pass when the run completes.

---

## 6. Open items (post-session)

### Outputs consolidation
- [ ] PR 3 — legacy endpoint redirects, OutputRenderer downloadUrl preference, step-file proxy removal
- [ ] StructureViewer canonical migration (same pattern as DensityMapViewer)

### Tracked from CI/CD P1.2 doc (parallel agent)
- [ ] P1.3 — `scripts/deploy.sh <env> <release-tag>` via AWS SSM
- [ ] P1.4 — CloudWatch idle alarm (Terraform)

### Production-grade run_code (this session abstracted the seam)
- [ ] Build the reference sidecar service per `docs/20260518_RUN_CODE_SANDBOX_PRODUCTION_PATH.md`
- [ ] Set `RUN_CODE_BACKEND_URL` + remove docker.sock mount in prod env

### Backlog
- [ ] 62 remaining `/home/.../` literals in production-code defaults (need careful audit, not bulk replace)
- [ ] OutputRenderer + step-file consolidation in PR 3
- [ ] Galaxy backend `nextflow_executor.py` task_files emission could move to the canonical service (currently independent)

---

## 7. Net headline

Before this session, every deploy caused a multi-minute dev outage AND the user run history was silently being wiped AND the outputs panel could fail for any of 8 different reasons. After this session:

- Deploys don't break dev-public.
- Runs persist.
- Outputs have ONE source of truth that's shaped right for every consumer.

The remaining work (PR 3, sidecar, deploy.sh) is incremental hardening rather than firefighting.
