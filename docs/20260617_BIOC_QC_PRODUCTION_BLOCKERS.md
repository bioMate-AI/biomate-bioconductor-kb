# Bioc QC Harness — Production-Path Blockers

Date: 2026-06-17
Branch: `qc/coverage-and-rebuilds`

The BIOC_QC_HARNESS Phase 3c adoption is complete locally (430 / 430 workflows, all 7 audit dimensions clean, 429 / 429 R blocks execute under Rscript, reader-side roundtrip pytest passes). **But the production end-to-end path is blocked by two pre-existing infrastructure constraints** that have nothing to do with QC harness correctness.

## Blocker 1 — `publishDir = null` is force-injected for BioMate workflows

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:1931-1936`:

```python
*(
    ["process {", "    publishDir = null", "}"]
    if "/nf-core-workflows/" not in nf_path
       and "structural_biology/" not in nf_path
    else []
),
```

Every Bioconductor workflow under `nextflow_nfcore/subworkflows/bioconductor/` is a BioMate (not nf-core) workflow, so the executor injects `publishDir = null` into the on-the-fly nextflow.config. Any `publishDir` directive in the patched `.nf` source — including the one I might add — is overridden to null at config-parse time.

**Why this directive exists** (lines 1893-1912 in `nextflow_executor.py`):

> publishDir is what spawns S3 TransferManager which constructs S3CrtAsyncClient which loads the AWS CRT native lib. That lib's dlopen randomly SIGSEGVs the JVM via `software.amazon.awssdk.crt.CRT.extractAndLoadLibrary`. Empirically reproduced on JDK 17 / 21 + Debian bookworm / trixie, nf-amazon 3.3.0 AND 3.4.4. The bug is in AWS CRT native lib, not OS/JDK.

So the publishDir disable is a guard against a real JVM crash bug in AWS CRT. Removing it requires either:
- Upgrading to an nf-amazon version with a CRT-free fallback (none exists), or
- Patching the CRT lib (upstream AWS issue), or
- Replacing the publishDir flow with a Galaxy-side post-task `aws s3 sync` (the comment at lines 1908-1911 notes this is the planned fix).

## Blocker 2 — `qc_metrics.json` lands in `work/<hash>/`, not `outdir/<process>/`

Without publishDir, every output file (including `qc_metrics.json`) stays in the Nextflow work directory at `s3://<work-bucket>/nextflow/work/<task-hash>/`. The Galaxy backend reads the outdir at `s3://<work-bucket>/nextflow/outputs/<user>/<run>/` (see `qc_trace_monitor._S3_REPORT_PATHS[\"BIOC_\"] = (\"*\", \"qc_metrics.json\")` — the `*` wildcard means "scan anywhere under outdir").

`qc_trace_monitor._read_s3_report_metrics()` paginates `list_objects_v2` under `<outdir>/`. Because `qc_metrics.json` is in `<workdir>/` (different prefix entirely), it's invisible to the listing. The trace monitor logs `[QC-S3] No report found for BIOC_<NAME> at s3://...` and returns None.

## What still works end-to-end LOCALLY

Despite the two blockers, the full harness chain is verified locally:

| Step | Tool | Status |
|---|---|---|
| Static audit (7 dimensions) | `bioc_qc_harness_audit.py` | ✓ 430 / 430 |
| Dynamic R-block execution | `bioc_qc_harness_verify_all.py` | ✓ 429 / 429 |
| End-to-end roundtrip (Nextflow→R→JSON→reader→tuples) | `backend/tests/test_bioc_qc_harness_roundtrip.py` | ✓ 4 / 4 |
| S3 registry coverage | `bioc_qc_harness_audit.py` (dim 7) | ✓ all matched by `BIOC_` substring |

## What needs to land before any Phase 3c gate fires in production

**Option A (preferred) — Galaxy-side `aws s3 sync work → outdir/qc_metrics_collection/`**

After each Nextflow process completes (Batch SUCCEEDED event), the Galaxy backend runs:

```bash
aws s3 cp \
  s3://<work-bucket>/nextflow/work/<task-hash>/qc_metrics.json \
  s3://<work-bucket>/nextflow/outputs/<user_id>/<run_id>/<process>/qc_metrics.json
```

This is exactly the post-task sync the executor comment (lines 1908-1911) anticipates. The Galaxy side already has work-dir reading via `routes.ts:2898` for the `run:<runId>:datasets` URI handler, so the infrastructure exists.

Implementation: add the sync to the Batch state-change handler (EventBridge → `biomate-batch-billing` Lambda already exists; could extend it OR add a separate `biomate-qc-sync` Lambda).

**Option B (workaround) — patcher injects an inline `aws s3 cp` call**

Each patched `.nf` could append after `cat(jsonlite::toJSON(...), file = qc_metrics.json)`:

```bash
if [ -n "$BIOMATE_OUTDIR" ]; then
  aws s3 cp qc_metrics.json $BIOMATE_OUTDIR/${task.process}/qc_metrics.json || true
fi
```

But: requires extending the executor's `env_lines` to inject `BIOMATE_OUTDIR` (currently only `BIOMATE_USER_ID` + `BIOMATE_RUN_ID`), and per-task `aws s3 cp` is more fragile than a Galaxy-side post-task event-driven sync.

**Option C (blocker — high effort) — fix the AWS CRT JVM SIGSEGV**

Upstream issue. Outside scope.

## Recommendation

Land **Option A** as the next infrastructure work item. The QC harness work is correct and complete on the workflow side; the production gate-firing path is gated on this single sync mechanism. Until it lands, every Bioc `qc_metrics.json` emits to S3 work dir but is invisible to `qc_trace_monitor`.

## Cross-references

- Full Phase 3c coverage writeup: `docs/20260617_BIOC_QC_HARNESS_FULL_COVERAGE.md`
- Adoption recipe: `docs/20260616_BIOC_PHASE_3C_ADOPTION_RECIPE.md`
- AWS CRT crash analysis (prior session): `MEMORY.md` → `project_jvm_libmanagement_crash.md`
- nextflow_executor publishDir architecture: comments at `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:1893-1936`
