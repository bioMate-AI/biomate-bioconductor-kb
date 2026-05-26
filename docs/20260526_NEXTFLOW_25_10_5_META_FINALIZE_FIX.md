# Nextflow 25.10.0 → 25.10.5: meta-finalize bug fixed via upstream PR #6550

**Date:** 2026-05-26
**Branch:** `integration/next-phase`
**Key commits:** `caf04eb1d` (profile-in-override), `32aab65bd` (version pin bump)

## TL;DR

- Nextflow 25.10.0 (our pin since 2026-05-21) shipped with a regression: `No such property: meta for class: nextflow.script.dsl.ProcessDslV1` at task finalize, firing on every workflow that uses `tuple val(meta), path(...)` outputs (~200+ drug-dev workflows including ADMET).
- Root cause is upstream Nextflow [issue #6512](https://github.com/nextflow-io/nextflow/issues/6512) / [#6600](https://github.com/nextflow-io/nextflow/issues/6600) — `publishDir` closures referencing process inputs lose scope at finalize.
- Fix is upstream [PR #6550](https://github.com/nextflow-io/nextflow/pull/6550), merged 2025-11-12 with `backport/25.10` label.
- First patched release: 25.10.1 (2025-11-28). Latest patch: **25.10.5** (2026-05-05).
- **Bumping the pin 25.10.0 → 25.10.5 resolves the bug.** Validated with `predict_admet_properties` on dev (run `6f4d6662…`, completed in 3m 22s, 6 outputs including `pk_summary.json`, `predict_admet_properties_results.json`, interactive `report.html`).

## What was broken

ADMET (`predict_admet_properties`), IVIVE, POCKET, PHARMA, PBPK, and most of the 209 drug-dev workflows failed at task finalize on dev with:

```
ERROR ~ Unexpected error while finalizing task 'PREDICT_ADMET_PROPERTIES_WORKFLOW:PREDICT_ADMET_PROPERTIES (run)'
       - cause: No such property: meta for class: nextflow.script.dsl.ProcessDslV1
```

The task body executed fine. The closure passed to `publishDir { "${params.outdir}/${meta.id}" }` — re-evaluated at finalize for output placement — could not see `meta` because the `ProcessDslV1` instance backing finalize had lost its input-variable scope. This is a known 25.10.0 regression from 25.04.3 (where the same workflows ran cleanly).

## Why naive workarounds were wrong

Through earlier sessions I tried (and rejected, with user pushback) several false fixes:

| Attempt | Why it was wrong |
|---|---|
| Mass-rewrite 297 files from `publishDir { ... }` closure to bare string | Closure form is the **correct** Nextflow idiom for input-dependent paths; reverted in commits `51450928d` / `1884f027f`. |
| Remove `.view` calls / pipe operators | User: *"I refuse to do so. keep the function and fix the grammar."* The workflows are correct; the runtime was broken. |
| Set `NXF_SYNTAX_PARSER=v2` | Speculation; user: *"you learn more about nextflow first."* Investigation showed `NXF_SYNTAX_PARSER` is parser-level, not the runtime DSL selector. |
| Remove `-with-trace` | The trace observer triggers the finalize path. But `-with-trace` feeds 5+ BioMate subsystems (autofix, monitor, runner, pilot client, study_run_logger). Not viable. |

Each of these would have shipped behavior changes without addressing the upstream regression.

## The actual fix path

1. **Read the upstream issue/PR threads.** GitHub issues #6512 and #6600 both pinpointed `publishDir`/`accelerator`/`arch` closures referencing process inputs at finalize.
2. **Locate the fix.** PR #6550 was merged 2025-11-12 with `backport/25.10` label.
3. **Pick the smallest patch that carries it.** PR #6550 merged before 25.10.1 (2025-11-28), so any 25.10.x patch ≥ .1 should carry it. Latest stable patch: 25.10.5.
4. **Bump the pin** in both sites:
   - `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — `NXF_VER` env default
   - `scripts/sync_to_dev.sh` — `EXPECTED_NF_VER` launcher-reinstall guard
5. **Reinstall the launcher on dev.** Force-reinstall to 25.10.5.12056 via `NXF_VER=25.10.5 curl -fsSL https://get.nextflow.io | bash`.
6. **Validate with the failing canary.** Fire ADMET on dev. Expect: completes, no meta-finalize error in log, real S3 outputs.

## Validation result

Run `6f4d6662-53ac-486e-b824-c27ec03e8834`, `predict_admet_properties` on dev (Nextflow 25.10.5.12056):

```
status=completed nfs=succeeded dur=221s outs=5
last 5 lines:
  Completed at: 26-May-2026 13:29:35
  Duration    : 3m 22s
  CPU hours   : (a few seconds)
  Succeeded   : 1
```

Outputs (`/api/runs/:id/outputs`):

| File | Size | Type |
|---|---|---|
| `dag.dot` | 961 B | binary |
| `report.html` | 2.96 MB | interactive |
| `timeline.html` | 252 KB | interactive |
| `pk_summary.json` | 1153 B | text |
| `predict_admet_properties_output.txt` | 651 B | table |
| `predict_admet_properties_results.json` | 677 B | text |

Zero `No such property: meta` in the log.

## Related fix this session: profile-in-override

Many no-config workflows under `nextflow_nfcore/subworkflows/**/*.nf` lack their own `nextflow.config`, so when our executor passes `-profile aws` they fail with `Unknown configuration profile: 'aws'`.

Commit `caf04eb1d` declares an empty `profiles { aws { } }` block in the executor-generated `-c` override config (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`, `_generate_executor_config`). All real AWS Batch settings remain top-level; the empty profile block just satisfies the `-profile aws` reference. Verified: `transporter_ddi` (no own config) completed in 223 s after the fix.

## Lessons captured

- **Pin to the latest patch of a minor**, not the `.0` release. 25.10.0 was untested in our load.
- **Read upstream issues before rewriting code.** I spent multiple sessions exploring local workarounds before researching whether this was a known upstream regression.
- **The user's "I refuse to do so. keep the function and fix the grammar" was correct.** When workflows ran on 25.04.3 and broke on 25.10.0, the right move was always to fix the runtime, not the workflows.

## What's still pending

- Sweep the broader drug-dev workflow set (transporter_ddi ✓, predict_admet ✓; IVIVE, POCKET, PHARMA, PBPK pending re-fire) — Task #12.
- Validate output visualization on all completed runs and flag any low-confidence outputs for knowledge augmentation, per CLAUDE.md UX completeness rule.
- Generate `nextflow.config` for the 3-5 flagship demo workflows (bispecific_antibody_design, simcyp_pbpk, virtual_patient_cohort, survival_analysis_km) — deferred until full sweep is green.
- Test colleague's biomni-tools split images (rna/molecular/full-optimized) for cold-start speedup.

## File touch list

```
backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py  (NXF_VER 25.10.0 → 25.10.5; profiles { aws { } } block)
scripts/sync_to_dev.sh                                       (EXPECTED_NF_VER 25.10.0 → 25.10.5)
```

No workflow files were modified in this fix — that was the whole point.
