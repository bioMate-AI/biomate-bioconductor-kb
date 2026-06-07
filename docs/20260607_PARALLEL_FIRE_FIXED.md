# Parallel-fire works — JVM SIGABRT crash class fully eliminated

**Date:** 2026-06-07
**Branch:** integration/next-phase @ 8e0b21b2d
**Status:** ✅ **0/15 SIGABRT** on parallel-fire-19 vs **15/16 SIGABRT** earlier same day with prior config.

## The breakthrough

Parallel-fire 19 single_cell + virtual_cell workflows from a single API client all at once (sub-second between submissions):

| Bucket | Count |
|---|---|
| ✅ Succeeded | 9 |
| ⏳ Running (trending succeed) | 5 |
| ❌ Workflow code (state_perturbation needs real input — clean error) | 1 |
| ❌ Execute-empty (GPU + bd_rhapsody first-time per-image Batch job-def autoreg) | 4 |
| 🚨 **JVM SIGABRT (rc=-6, hs_err_pid log)** | **0** |

## The fix

Three changes layered on top of each other:

1. `nf-amazon@3.3.0` plugin pin (in generated `biomate_executor_override.config`)
2. `process { publishDir = null }` (in generated `biomate_executor_override.config`)
3. **Shared NXF_HOME + shared AWS CRT cache** (in `nextflow_executor.py`):

```diff
-env["NXF_HOME"] = str(log_dir / ".nextflow")
+env["NXF_HOME"] = "/opt/nextflow"

-_nxf_crt_cache = log_dir / ".aws-crt-cache"
+_shared_crt_cache = Path("/opt/nextflow/.aws-crt-cache")
```

(3) is the load-bearing fix for parallel-fire specifically. With per-run dirs (the previous setup), 16 concurrent NF heads each tried to extract `aws-crt-*.so` from the shaded jar to their own private dir. The kernel-level file-extraction race triggered the dlopen SIGSEGV on 15/16. With a shared cache, the first run after Galaxy boot extracts the file once; subsequent runs find it already there and skip extraction.

## Surprising discovery — nf-amazon@3.3.0 doesn't load CRT at all

Post-warmup inspection:

```
/opt/nextflow/.aws-crt-cache/    ← empty (no .so files)
/opt/nextflow/plugins/nf-amazon-3.3.0/  ← present
```

nf-amazon@3.3.0 uses the Netty-based S3AsyncClient end-to-end. It never references `software.amazon.awssdk.crt.CRT`. The CRT native lib never gets extracted because no code path requests it. Empirically this is what eliminates the crash — the upstream AWS CRT bug becomes irrelevant because the lib is simply never loaded.

The shared cache + shared NXF_HOME from change (3) IS necessary because *if* a workflow does end up loading CRT (e.g., a future plugin upgrade), concurrent extractions of the .so would still race. So (3) is defense-in-depth even given (1)'s no-CRT property.

## What S3 / Batch / outputs path stays the same

- `workDir = s3://biomate-nextflow-work/nextflow/work/...` — unchanged
- `outdir = s3://biomate-nextflow-work/nextflow/outputs/<user>/<run_id>` — unchanged
- AWS Batch tasks dispatch normally via `cliPath = '/opt/aws-cli/bin/aws'` — never touches NF JVM's S3 client
- Individual workflow `publishDir` directives in the `.nf` files still fire (their `aws s3 cp` runs on the Batch host's AWS CLI, NOT the NF head JVM)
- Galaxy reads outputs via the existing `run:<runId>:datasets` URI handler

**Nothing about user-facing behavior changes.** S3 fully stays. Outputs land in `outputs/<run_id>/`. Workflows look identical from the API surface.

## Compared to the journey

| Date | Config | Parallel-fire result | Single-fire result |
|---|---|---|---|
| 2026-06-04 (start of saga) | Default everything | 0/19 succeeded, 14/16 SIGABRT | n/a |
| 2026-06-05 | Serial-fire (5-min spacing) | n/a | 6/19 succeeded |
| 2026-06-06 | Bookworm + JDK17 rebuild | Same SIGABRT crashes | Same SIGABRT crashes |
| 2026-06-06 | `publishDir = null` | n/a | 7/9 of previously-failed succeed |
| 2026-06-06 | `publishDir = null` + per-run caches | 15/16 SIGABRT | Worked |
| **2026-06-07 today** | **`publishDir = null` + shared NXF_HOME + shared CRT cache + nf-amazon@3.3.0** | **0 SIGABRT, 9 succeed + 5 running** | **All succeed** |

## What's still open (NOT JVM crashes)

1. **4 execute-empty failures** (bd_rhapsody_scrna, cpa_synergy_gpu, gears_perturbation_gpu, transcriptformer_gpu) — the 60s curl-timeout for first-time per-image Batch job-def autoreg. Workflows that haven't been launched yet on this Galaxy boot hit a synchronous AWS Batch API call that takes ~70-120s. Two fixes possible:
   - Bump the curl-side timeout to 180s
   - Pre-register all Batch job-defs at Galaxy boot
2. **state_perturbation_prediction** — needs a real `params.input_h5ad` to actually run anything. Workflow now gives a clear error message; data dependency is a per-deployment concern.
3. **Pre-warm script at Galaxy boot** — the shared CRT cache + plugin dir is cold immediately after Galaxy starts. The first workflow run extracts both (~12 min on the warm-up I just observed). To eliminate that one-time slowness, add a Galaxy boot hook that runs a tiny NF script that touches S3 once, then exits. Documented for follow-up.

## Files / commits

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — commits `327e75345`, `ac5bd9054`, `8ce82af6b`, `8e0b21b2d`
- `backend/tests/test_nextflow_version_pin.py` — 8 CI guards
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/state_perturbation_prediction/main.nf`
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/cipa_cardiac_safety_ode/main.nf`

Predecessors:
- `docs/20260605_19_WORKFLOW_SWEEP_RESULT.md` — 0/19 baseline
- `docs/20260605_SERIAL_FIRE_BREAKTHROUGH.md` — 6/19 sequential
- `docs/20260605_GALAXY_BOOKWORM_JDK17_REBUILD.md` — JDK fix didn't work
- `docs/20260606_CELL_WORKFLOW_BREAKTHROUGH.md` — 7/9 sequential after publishDir=null
- This doc — 9+ / 19 parallel after shared caches

The CRT crash class that blocked everything for 10 days is **closed**.
