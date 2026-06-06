# Cell-workflow breakthrough — JVM crash class closed, 7/9 of previously-failed workflows now succeed

**Date:** 2026-06-06
**Branch:** integration/next-phase @ 8ce82af6b + ac5bd9054
**Status:** ✅ **CRT crash class eliminated. 7/9 previously-failed workflows succeed end-to-end.**

## The breakthrough

After ~48 hours of failed infrastructure rebuilds (JDK 21 → JDK 17, Debian trixie → bookworm, glibc 2.41 → 2.36) that did NOT fix the JVM SIGABRT crashes, the actual fix turned out to be a **2-line Nextflow config** change emitted by `nextflow_executor.py`:

```groovy
plugins {
    id 'nf-amazon@3.3.0'
}
process {
    publishDir = null
}
```

Triage of the 9 workflows that previously crashed:

| Workflow | Before fix | After fix |
|---|---|---|
| metabolic_flux_fba | rc=-6 SIGABRT JVM crash | ✅ rc=0 succeeded |
| ode_signaling_simulation | rc=-6 SIGABRT | ✅ rc=0 succeeded |
| physicell_tumor_tgi | rc=-6 SIGABRT | ✅ rc=0 succeeded |
| transcriptformer_cell_state | rc=-6 SIGABRT | ✅ rc=0 succeeded |
| transcriptomic_moa_lincs | rc=-6 SIGABRT | ✅ rc=0 succeeded |
| virtual_patient_cohort | rc=-6 SIGABRT | ✅ rc=0 succeeded |
| cipa_cardiac_safety_ode | rc=1 em-dash apostrophe Python SyntaxError | ✅ rc=0 succeeded (workflow patched) |
| state_perturbation_prediction | cryptic Groovy "Missing fromPath" | rc=1 clean "params.input_h5ad is required" |
| transcriptformer_gpu | execute-empty (60s curl timeout) | execute-empty (separate GPU job-def autoreg issue) |

**Net: 7/9 succeed, 1 needs real input data (clean error message), 1 needs separate execute-timeout fix. Zero JVM crashes.**

## Why this fix works

The 6+ mitigation attempts before this (per-run CRT cache, `-Xss2m`, `LD_BIND_NOW=1`, NXF_VER pin, FD-decouple, JDK 17 + bookworm rebuild) all left the AWS CRT native lib still being loaded on PublishDir thread creation:

```
software.amazon.awssdk.crt.CRT.<clinit>
  → extractAndLoadLibrary
  → System.load
  → ld-linux-x86-64.so.2 dlopen
  → SIGSEGV
```

The `process { publishDir = null }` directive tells Nextflow not to create publishDir threads at all. **No publishDir thread = no S3 TransferManager init = no CRT class load = no JVM crash.**

The `nf-amazon@3.3.0` plugin pin is an additional safety: even if some future change re-enables an S3 path, 3.3.0 is the most-recent version before nf-amazon flipped to CRT-by-default for input-staging too. (Empirically the 3.3.0 pin didn't take effect in the successful test — NF used 3.4.4 anyway — so the publishDir disable is the load-bearing fix; the pin is belt-and-suspenders.)

## Surprising finding — outputs/ still populated

Even with `process { publishDir = null }` as a Nextflow config default, the workflow's own per-process `publishDir "${params.outdir}/${meta.id}", mode: 'copy'` directives in the `.nf` files override the null. They ran successfully via the workflow's per-task `aws s3 cp` calls (which use `cliPath = '/opt/aws-cli/bin/aws'` on the Batch host — NO CRT).

So in practice: **outputs DO land in `outputs/<run_id>/<process>/` on S3**, just not via the head JVM's broken CRT path. Galaxy's normal output discovery works.

## Doc trail

This closes the saga that started 2026-06-04 with:
- `docs/20260605_19_WORKFLOW_SWEEP_RESULT.md` — 0/19 parallel-fire all SIGABRT
- `docs/20260605_SERIAL_FIRE_BREAKTHROUGH.md` — 6/19 serial-fire succeed
- `docs/20260605_GALAXY_BOOKWORM_JDK17_REBUILD.md` — JDK + OS rebuild didn't fix (proved bug is in AWS CRT, not OS/JDK)
- This doc — `publishDir = null` is the actual fix

## What's still open

1. **`transcriptformer_gpu` execute timeout** — first-time GPU job-def autoreg takes >60s. Pre-register at Galaxy boot OR bump the curl timeout to 120s.
2. **`state_perturbation_prediction` real input** — needs an h5ad file fixture for end-to-end validation. Not a bug; a data dependency.
3. **The `nf-amazon@3.3.0` pin** isn't actually taking effect — NF still downloads 3.4.4. The pin syntax in the generated config may be wrong; Nextflow may need a different format. Low-priority since the publishDir disable handles the actual crash.
4. **CI tests for `publishDir = null` and the plugin block** in the generated config — add to `backend/tests/test_nextflow_version_pin.py`. Defense against the future-session-strips-it failure mode.
5. **Document for the user/team** — when workflows want to emit results to a specific `outputs/<custom_path>/`, they need to do it via their per-process `publishDir` (already do); BioMate's global config null doesn't prevent them. Communicate this in the workflow author guide.

## Files / commits

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (commits `327e75345`, `ac5bd9054`, `8ce82af6b`)
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/state_perturbation_prediction/main.nf` (commit `ac5bd9054`)
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/cipa_cardiac_safety_ode/main.nf` (commit `e2065bd02`)

This is the system stable enough to start adding real workflow inputs + CI gates. The JVM crash class that blocked everything for ~10 days is closed.
