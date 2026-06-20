# Bioconductor runs on dev: the full dispatch-failure fix chain — 2026-06-20

## TL;DR
Bioconductor workflows with file inputs (e.g. DESeq2) **queued but never dispatched to
AWS Batch** on dev — empty work dir, status `interrupted`, zero Batch jobs, while the
Batch CEs were healthy. Root-caused from the actual galaxy/head/task logs to a chain of
**five distinct issues**, each fixed and merged. The dispatch is now **fixed and proven
on dev**: a real DESeq2 run staged its inputs, launched the head, parsed the wrapper,
**submitted the `BIOC_DESEQ2` task to AWS Batch, and executed the full DESeq2 analysis**.

| PR | Layer | Fix | How found |
|----|-------|-----|-----------|
| #42 | galaxy executor | `_stage_declared_input`: boto3 + bucket-region (not the absent `aws` CLI) | `galaxy.log`: `staging failed for 'cts': [Errno 2] ... 'aws'` |
| #43 | frontend | `_uploadFileToS3` → SDK; both staging paths resolve the bucket region (us-east-1) | dev log: `aws s3 cp` fail + "specified endpoint" |
| #44 | galaxy executor | **revert** my own LD_PRELOAD libmanagement.so (it broke `/usr/bin/env`) | head `nextflow.log`: `libjvm.so: cannot open shared object file` |
| #45 | galaxy executor | exclude `/bioconductor/` from `process { publishDir = null }` injection | head log: `Could not find method publishDir()` (NF 25.10.5) |
| #46 | deseq2 `.nf` | declare `apeglm` in `.bm_deps` (used by `lfcShrink`) | task `.command.err`: `type='apeglm' requires ... 'apeglm'` |

## The chain, in the order the run hits it

1. **Input staging used the `aws` CLI, which isn't in the Galaxy container** (#42). For any
   bioc workflow with an `s3://` declared input, `_stage_declared_input` shelled out to
   `aws s3 cp` → `FileNotFoundError('aws')` → `_build_bioc_entry_wrapper` returned `None`
   → fell back to `nextflow run … -entry <…>_WORKFLOW`, which **cannot bind the `take:`
   channel** (the exact thing the wrapper exists to avoid) → head exited in ~10 s →
   `interrupted`, empty work dir, no Batch job. Non-bioc workflows have no declared file
   inputs, so they skip this path and succeed — which is why it looked intermittent.
   Fix: boto3 `download_file` + `GetBucketLocation` region resolution.

2. **Frontend S3 also used the `aws` CLI + wrong region** (#43). `_uploadFileToS3` (the
   upload→S3 mirror) used `execFile('aws', …)` → always failed → `s3_uri` came back null;
   and both staging paths built the S3 client with the us-west-2 default against the
   **us-east-1** work bucket → "must be addressed using the specified endpoint". Fix: AWS
   SDK + a shared `_s3ClientForBucket()` that resolves the bucket's real region.

3. **My own LD_PRELOAD broke the launch** (#44). An earlier PR (#41) added
   `LD_PRELOAD=libmanagement.so` to "fix" an intermittent JVM crash — a **misdiagnosis**
   (there was never an `hs_err`; the JVM never crashed). Once #42 let runs reach the head,
   every run died with `/usr/bin/env: error while loading shared libraries: libjvm.so` —
   LD_PRELOADing libmanagement.so into *every* exec'd process broke `/usr/bin/env` (it
   needs libjvm.so, absent for non-JVM processes). Reverted entirely. **Lesson: read the
   log before shipping a mitigation.**

4. **`publishDir = null` is rejected by dev's Nextflow 25.10.5** (#45). The executor
   injects `process { publishDir = null }`; NF 25.10.5 rejects that property for the bioc
   wrapper's process shape → `Could not find method publishDir() to invoke` at
   `biomate_entry.nf`. The identical failure was already documented + excluded for
   `structural_biology/boltz_*`. The spot tests passed only because the spot ran NF
   **26.04.4**. Bioc `.nf` carry no publishDir directives (outputs come from the Batch task
   work-dir copy) and the nf-amazon@3.3.0 pin already covers CRT, so excluding
   `/bioconductor/` is safe. After this, the head **submitted `BIOC_DESEQ2` to AWS Batch**.

5. **`apeglm` undeclared** (#46). The Batch task ran the full DESeq2 pipeline
   (DESeqDataSet → size factors → dispersions → model fit → testing) and failed only at
   `lfcShrink(dds, type="apeglm")` — `apeglm` is used (line 130) but absent from `.bm_deps`
   (line 50), so the slim image (which doesn't bake it) never lazy-installed it. Added it.

## Proof on dev (head `.nextflow.log`, run ec2a55ab)
```
Workflow process names [dsl2]: BIOMATE_RDS_INTROSPECT, BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX
[AWS BATCH] Process `BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX (sample)` submitted > job=f2a5d54b…
  container=…/biomate/bioc-domain-transcriptomics:3.20-slim
Task completed > … status: COMPLETED; exit: 1; error: Essential container in task exited
```
…and the task `.command.err` showed the analysis completing through model fit + testing,
failing only on the missing `apeglm` (now fixed).

## Separate infra finding (not fixed here)
**Dev's `preload: true` + `kill -HUP` deploy does NOT reliably load backend Python
changes** — gunicorn workers fork from the old preloaded master, so a HUP keeps running
the previous code until workers happen to cycle (or a full restart). This is why backend
fixes appeared not to take effect immediately and required retries. It affects every
backend deploy on dev. Recommend `restart_galaxy` use a full container restart or
`SIGUSR2` master re-exec instead of HUP for code changes.

## Process notes / contention
The dev box was running **many concurrent agent sessions**, each committing to next-phase
and running `sync_to_dev.sh` from different (sometimes stale) checkouts — repeatedly
clobbering each other's deploys (e.g. re-introducing the reverted LD_PRELOAD). Landing a
clean deploy required catching a lock-free window. A single coordinated deploy from
current next-phase HEAD is the clean way to apply all of #42–#46 together.

## Status
- Dispatch: **fixed + proven on dev** (real Batch run executed the analysis).
- All five fixes merged to `integration/next-phase` (#42–#46).
- Final fully-green run (apeglm → `lfcShrink` → `dds.rds` + `.rds.json` sidecar + CSV
  tables + findings) was queued behind the deploy contention at time of writing; the
  apeglm fix is a `.nf` (read at run time), so any sync from current next-phase completes it.
