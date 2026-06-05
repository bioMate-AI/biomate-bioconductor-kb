# 19-workflow single_cell + virtual_cell sweep — empirical result

**Date:** 2026-06-05 (UTC)
**Branch:** integration/next-phase @ d9e6984f9
**Sweep ID:** sweep19, ridfile `/tmp/sweep19_rids.txt` on dev
**Verdict:** 🔴 **0 / 19 reached `completed`. 16 / 19 hit JVM SIGABRT within 60s of fire. 3 / 19 failed at Galaxy execute (curl-timeout / hang).**

## What was fired

All 19 workflows from the 2026-06-02 gap analysis, in a single parallel sweep:

```
single_cell/      bd_rhapsody_scrna, cite_seq_preprocessing, merfish_spatial_analysis,
                  multiome_rna_atac, parse_split_seq_scrna, scrna_doublet_qc,
                  state_perturbation_prediction
virtual_cell/     cipa_cardiac_safety_ode, cpa_drug_combination_synergy, cpa_synergy_gpu,
                  gears_perturbation_gpu, gears_perturbation_prediction, metabolic_flux_fba,
                  ode_signaling_simulation, physicell_tumor_tgi, transcriptformer_cell_state,
                  transcriptformer_gpu, transcriptomic_moa_lincs, virtual_patient_cohort
```

Fired sequentially with 1.5s spacing via direct `POST /api/nextflow/execute` against the Galaxy backend (bypassing the frontend, which still has the migration crash-loop).

## Per-workflow outcome

| Workflow | RID | Outcome |
|---|---|---|
| bd_rhapsody_scrna | bc517869 | 🔴 interrupted (rc=-6, 60s) |
| cite_seq_preprocessing | 1823b318 | 🔴 interrupted |
| merfish_spatial_analysis | 13b0aefe | 🔴 interrupted |
| multiome_rna_atac | 8d9a5ef3 | 🔴 interrupted |
| parse_split_seq_scrna | 77ce44ef | 🔴 interrupted |
| scrna_doublet_qc | 1111c7b5 | 🔴 interrupted |
| state_perturbation_prediction | ad48252a | 🔴 interrupted |
| cipa_cardiac_safety_ode | cff07151 | 🔴 interrupted |
| cpa_drug_combination_synergy | 11e01f06 | 🔴 interrupted |
| cpa_synergy_gpu | — | 🔴 execute failed (empty 20s curl response) |
| gears_perturbation_gpu | — | 🔴 execute failed (empty 20s curl response) |
| gears_perturbation_prediction | a61406c0 | 🔴 interrupted |
| metabolic_flux_fba | f69aabef | 🔴 interrupted |
| ode_signaling_simulation | d026cf31 | 🔴 interrupted |
| physicell_tumor_tgi | 30062911 | 🔴 interrupted |
| transcriptformer_cell_state | ac10e13a | 🔴 interrupted |
| transcriptformer_gpu | — | 🔴 execute failed (empty 20s curl response) |
| transcriptomic_moa_lincs | 505bb090 | 🔴 interrupted |
| virtual_patient_cohort | ed27b9ff | 🔴 interrupted |

## Crash signature (representative — `bd_rhapsody_scrna`)

```
status:    interrupted
returncode: -6   (SIGABRT — JVM crashed)
duration:  60s
last log:  Jun-05 02:46:06 [main] DEBUG nextflow.util.ThreadPoolBuilder
           - Creating thread pool 'FileTransfer' minSize=10; maxSize=10; ...
```

**FileTransfer** is the Nextflow thread pool for **input file staging from S3** — the AWS CRT-based S3 client gets initialized there, hits the dlopen race on Debian trixie glibc 2.41 + OpenJDK 21.0.11, and SIGSEGVs the whole JVM. This is the same upstream bug that hits **PublishDir** when the run survives long enough; in this parallel-firing scenario it just hits earlier in the pipeline.

## Why the existing mitigations didn't help

Active mitigations on dev right now:
1. `NXF_VER=25.10.5` pin — held (verified `25.10.5` in `/tmp/nextflow_runs/*/.nextflow/framework/`)
2. Per-run `-Daws.crt.lib.dir=<run-specific-cache>` — present in JVM cmdline
3. `-Daws.crt.disable.crt.in.client=true` — present
4. `-Xss2m` (raised thread stack) — present
5. `LD_BIND_NOW=1` in env — present
6. FD-decouple subprocess (commit `41181b086`) — present
7. WARN-exclusion regex (commit `4b4f96c37`) — present

**All six mitigations are deployed AND active on dev.** The crashes still happened anyway, just at FileTransfer instead of PublishDir.

The per-run CRT cache was supposed to prevent races between concurrent extractions of the same `.so` from the shaded jar. Empirically, it doesn't — when 16 JVMs start within 30 seconds, the underlying glibc dlopen path still corrupts something across processes (probably TLS-section initialization in ld-linux that's not isolated by the per-run dir).

## What this tells us about robustness

Adds **two more incidents** to the appendix of `docs/20260604_BATCH_ROBUSTNESS_TEAM_DISCUSSION.md`:

- **Incident: parallel-fire 16 workflows → 16/16 JVM SIGABRT at FileTransfer.** Tells us the 6-mitigation stack is fragile under load. Strengthens the case for **Tier 3 item #10 — eliminate publishDir AND FileTransfer's use of the CRT-based S3 client.**
- **Incident: 3 GPU workflows' `/api/nextflow/execute` calls returned empty after 20s.** Galaxy is healthy (other 16 calls returned in <1s). Specific to GPU workflows — likely the auto-create Batch job-definition for the per-workflow GPU images takes longer than 20s on first call. Needs a longer execute timeout for first-time GPU job-defs, OR pre-register all per-image job-defs at Galaxy boot.

## Three things to do next

These are urgent given the 0/19 result:

1. **Stop the bleeding** — promote Tier 3 item #10 (eliminate publishDir / replace S3 transfer client) from "strategic" to **next sprint**. The 6-mitigation pile is genuinely not protecting users.

2. **Establish a serial-fire baseline** — fire the 19 workflows one at a time, 5-min spacing. If serial works, we have an interim throttle solution while #10 is implemented. If serial also fails, the bug is deeper than concurrency.

3. **Capture the missing-execute case** — patch `nextflow_executor.py` to:
   - Pre-register Batch job-definitions for all known images at Galaxy boot, not lazily at first run
   - Bump the per-image execute timeout to 60s (currently the auto-create path appears to time out around 20s)

## What I did NOT do

- Did not fire the 19 workflows serially. Should be next.
- Did not investigate the underlying glibc/JDK/CRT bug further; that's an upstream fix path, out of scope for this codebase.
- Did not file an upstream bug with Nextflow / AWS CRT — should be done.

## Reproduction

```bash
ssh dev "bash /tmp/sweep19.sh"
# Wait 1 minute
ssh dev "cat /tmp/sweep19_rids.txt | while IFS== read name rid; do \
  [ -z \"\$rid\" ] || [ \"\$rid\" = FAILED ] && continue; \
  st=\$(sudo docker exec biomate-galaxy-dev curl -s -m 8 \
       http://127.0.0.1:8080/api/nextflow/status/\$rid 2>/dev/null \
       | python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"status\",\"?\"))'); \
  echo \"\$name=\$st\"; \
done"
```
