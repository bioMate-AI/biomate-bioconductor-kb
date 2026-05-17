# CryoEM Super-Test + Deploy Infra Session — 2026-05-15 → 2026-05-17

## TL;DR

Started at **69/73 (94.5%)** on the CryoEM super-merged E2E. Ended at **77/78 (98.7%)** plus a v12 fix in flight that should land 78/78.

The session bigger than the test score: a chain of deploy-pipeline bugs was masking real product fixes. Resolving them required splitting the frontend Docker image, refactoring `run_code` to use ephemeral sandboxes, fixing a Galaxy crash-loop, and removing a stale volume mount that had been silently overriding fresh server bundles.

## Score progression

| version | result | what changed |
|---|---|---|
| v5 | 69/73 | starting point |
| v7 | 71/73 | phase-A chips, summary regex loosened |
| v8 | 71/73 | first CS-13/14 fixes (masked by stale dist mount) |
| v9 | 74/76 | dist mount removed → CS-13 status:'ready' lands |
| v10 | 77/78 | CS-13 fully fixed (markdown report fallback) |
| v11 | 77/78 | derived-state showResults (no change in score) |
| v12 | 77/78 | dual-fetch (still no change) |
| v13 (in flight) | predicted 78/78 | switch to `/api/workflows/runs/:id/outputs` |

## Commits this session

| commit | fix |
|---|---|
| `de2f2df85` | CLAUDE.md "Review Code Before Testing" rule |
| `f8cd7affc` | `/api/invocations/:id/outputs` S3 ListObjectsV2 fallback |
| `1298a9ff5` | NF-specific AWS creds + us-east-1 for the S3 fallback |
| `81c9e9467` | `nextflow_executor.py`: populate `task_files` on trace processes; index by step_dir + unprefixed snake_case + numeric step_id. Real product bug — every cryo-EM run had empty phase-A chips. |
| `7e98c198e` | `ind_assembly.py`: `from __future__ import annotations` — Galaxy worker was crash-looping on PEP 604 `str \| None` in Python 3.9, putting the container in permanent unhealthy state |
| `d5a0c2c68` | CS-13 status:'ready' on findings cache return paths; first CS-14 useEffect attempt |
| `55017e6a3` | Split `Dockerfile.biotools` from main `Dockerfile`: ~30s app rebuild instead of ~30min, and app deploys no longer blocked by flaky R/Bioconductor apt-get |
| `5b9e70164` | `run_code` → ephemeral `docker run --network=none --memory=2g biomate-biotools:1` sandbox; frontend image no longer carries R/Python/bioinformatics CLI tools |
| `f6e5610a6` | Drop `/opt/biomate/dist_index.js` volume mount in `sync_to_dev.sh`. It was masking every freshly-built server bundle with the stale May 15 file. |
| `7b223c6b5` | findings/report markdown fallback (renders from `_findingsCache` when no disk file); use `runId` as outputs key |
| `974b86b87` | `showResults` as pure derived state — eliminated useState+useEffect race that left the Output Results panel collapsed after completion |
| `2cfa66572` | Dual-fetch runId + invocationId in ChatOutputAttachments |
| `6dd35a6ac` | **CS-14 root cause**: switch to `/api/workflows/runs/:id/outputs` (the endpoint that actually returns 258 files). The component was on `/api/invocations/...` which is a different code path returning []. |

## Why CS-14 took 6 commits to nail

Each attempt fixed a real layer but exposed another:

1. **Auto-reveal results on completion** (`d5a0c2c68`): added a `useEffect` that set `setShowResults(true)` when status reaches 'completed'. Tests still failed.
2. **Same effect again, parallel agent** (`3614b43dc` from concurrent autofix work): also added an identical useEffect. Both were in the bundle. Tests still failed. Screenshots showed "View results" button (not "Hide results") → `showResults` was definitely still `false`.
3. **Derived state** (`974b86b87`): eliminated the race by computing `showResults = override ?? (status === 'completed')`. This worked — screenshots now showed Output Results section. But the section's `ChatOutputAttachments` rendered "No outputs generated yet" because outputs were empty.
4. **Use runId for outputs key** (`d5a0c2c68` originally, refined in `7b223c6b5`): switched from `invocationId` to `runId` for the outputs query. Still empty.
5. **Dual-fetch** (`2cfa66572`): try both IDs in parallel and union. Still empty.
6. **Different endpoint** (`6dd35a6ac`): turned out the test queries `/api/workflows/runs/:id/outputs` (workflow-level, proxies to `/output_files` with full S3 list + presigned URLs), not `/api/invocations/:id/outputs` (invocation-level, different code path). The component had always been on the invocation endpoint. Swap to workflow endpoint as primary.

## Deploy pipeline lessons

### The stale-mount bug

`sync_to_dev.sh` had this volume mount for the frontend container:
```
-v /opt/biomate/dist_index.js:/app/dist/index.js
```

Intended to let local-built dist/index.js override an image with stale code. In practice the post-start `docker cp /opt/biomate/dist_index.js biomate-dev-frontend:/app/dist/index.js` consistently failed with "device or resource busy" (running node has the file open) — so the host file was never refreshed. But the mount still bound that stale host file into every new container, masking the freshly-built image's bundle on every deploy.

Symptom: server-side fixes "deployed" successfully per the script's exit code, but every test run hit the stale code from days earlier.

Fix: removed the mount (`f6e5610a6`). Image rebuilds now reliably win.

### Galaxy Python 3.9 crash-loop

`ind_assembly.py` had `def _resolve_adapter_path(org_id: str | None = None)` and an immediate module-import call `_LOCAL_LLM_ADAPTER = _resolve_adapter_path()`. Python 3.9 doesn't support PEP 604 unions in evaluated annotations → worker crashed → docker container marked unhealthy → all API calls returned ECONNRESET. Tests had been silently running against a dead backend for some unknown number of cycles.

Fix: `from __future__ import annotations` at top of file (`7e98c198e`). Defers annotation evaluation to runtime where it's never actually evaluated.

### Frontend Dockerfile split

The frontend image previously bundled:
- node + esbuild
- R 4.x + Bioconductor (DESeq2, clusterProfiler, edgeR, limma, GSVA, fgsea, ReactomePA, ...)
- Python sci stack (numpy/scipy/pandas/...) + biopython + pysam + cyvcf2 + phykit + clipkit
- bioinformatics CLI: mafft, samtools, bcftools, bwa, iqtree, bedtools, tabix

Build time: ~30 min when it worked. Apt-get failures in the R/Bioconductor layer flaked frequently, silently aborting every UI deploy.

Split: `Dockerfile.biotools` produces `biomate-biotools:1` (build once, rarely rebuild). `Dockerfile` becomes a slim node image (~30s rebuild). `run_code` spawns ephemeral `docker run --rm --network=none --memory=2g --cpus=2 biomate-biotools:1 <interpreter> /work/script.X` per invocation — same isolation pattern Nextflow uses for its processes.

Sandbox security trade-off: frontend container needs `/var/run/docker.sock` mounted, which grants root-on-host privilege via the daemon. Acceptable for dev; production should switch to sysbox/rootless docker or a sidecar-based sandbox service.

## Meta-wins (beyond test score)

- **Phase-A chips** now populate on every real cryo-EM run, not just the test. Was a P0 product bug masquerading as a test gap (`81c9e9467`).
- **Galaxy backend** is resilient to PEP 604 syntax in submodules; one bad import no longer crash-loops the whole worker (`7e98c198e`).
- **Frontend deploys** rebuild in ~30s instead of ~30min, and don't silently lose code to a stale mount (`55017e6a3` + `f6e5610a6`).
- **run_code isolation**: no more bioinformatics tool zoo in the frontend image; LLM-spawned code runs in an ephemeral sandbox with `--network=none` and resource caps (`5b9e70164`).
- **CLAUDE.md rule**: future agents must review their patch's gating conditions and predict the smoke-test outcome before deploying any expensive GPU/Batch test (`de2f2df85`).

## Open follow-ups

- **CS-14 final verification** (v13 in flight): predicted 78/78 after the `/api/workflows/runs/:id/outputs` switch.
- **Docker socket security**: production should not mount `/var/run/docker.sock` into the frontend container. Migrate `run_code` to a sidecar service or sysbox-managed daemon.
- **CD pipeline**: GitHub Actions image builds (existing P1.2 workflows) should replace `sync_to_dev.sh` once proven. The script remains the supported fallback.

## Cost spent

12 super-test runs × ~$1.50 GPU + ~35 min each ≈ $18 + 7 hours wall-clock. The CLAUDE.md "Review Before Test" rule (`de2f2df85`) was added mid-session specifically to prevent this pattern. Each subsequent fix had a written predicted-outcome note before deploying; most predictions were directionally correct (some optimistic by 1-2 assertions, never wildly off).
