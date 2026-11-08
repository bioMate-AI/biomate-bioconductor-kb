# Real-run E2E harness was stale (pointed at deleted test files) — fixed

**Date:** 2026-10-05. **Severity:** the real-workflow-execution E2E harness could not run at all.

## Symptom
`DOMAINS="admet rnaseq wgs" scripts/run_real_workflows.sh` against dev returned, for **every** domain:
```
Error: No tests found.
→ FAIL(rc=1)  run_id=—
```
No AWS Batch run was ever launched (so no wasted spend), but the harness reported all domains failed.

## Root cause
`scripts/run_real_workflows.sh` `spec_for()` mapped each domain to an e2e file that **no longer exists** —
the four target files were removed in the "clean up 161 stale E2E files" commit (`1a12b4e8c`, 2026-07-06),
the same cleanup that broke the `ind-pi-suite` CI workflow (see `docs/20261005_CI_ACTIONS_FAILURES_TRIAGE.md`).
This is a recurring class: a bulk test-file deletion that left referencing harnesses/workflows dangling.

| domain | old (deleted) spec | corrected spec (verified present) |
|---|---|---|
| admet  | `drug-discovery-full-e2e.e2e.ts` | `realrun-admet.e2e.ts` (real ADMET auto-loop run) |
| rnaseq | `complete-workflow.e2e.ts` | `project-real-run-capstone.e2e.ts` (GSE227835 → nf-core/differentialabundance, DESeq2) |
| wgs    | `germline-complete-e2e.e2e.ts` | `wgs-capstone.e2e.ts` (real germline variant calling) |
| cryoem | `cryoem-real-e2e.e2e.ts` | `cryoem-capstone.e2e.ts` (real cryo-EM, GPU) |

## Fix
Remapped `spec_for()` to the real-execution suites that exist (all four confirmed present on disk).
No change to the harness's real-run semantics (real AWS Batch, real data, poll-to-terminal).

## Related stale-reference cleanups still open
The 2026-07-06 bulk deletion also left `ind-pi-suite.yml` pointing at deleted files (CI red) — tracked
separately in `docs/20261005_CI_ACTIONS_FAILURES_TRIAGE.md`. A sweep for any other harness/workflow that
references a non-existent `e2e/*.ts` would be worthwhile to catch the rest of this class in one pass.
