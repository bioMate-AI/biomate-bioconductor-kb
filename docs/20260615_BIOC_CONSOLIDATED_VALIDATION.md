# Bioconductor consolidated fix validation — definitive (2026-06-15)

Clean re-validation of the 43 directly-fixed packages (90 workflows) on the **cache-poison-fixed
harness** (per-image rlib namespacing) against the consolidated tree (4-bucket fixes + round-2 +
step-param enricher). Artifact: `20260615_BIOC_CONSOLIDATED_VALIDATION.json`.

## Result: 40/90 executable (44%)  — up from round-1's 21/90 (23%)
| status | n |
|---|---:|
| ok | 16 |
| ok_warnings | 24 |
| **executable** | **40 (44%)** |
| timeout | 35 | web-API / slow-install; would clear on AWS Batch (no 300s cap) |
| exec_error | 10 | remaining bugs + infra packages flagged for skipping |
| skip_input_type | 3 |
| fixture_timeout | 1 |
| ran_empty_output | 1 |

## 12 fully-green packages
affycoretools, aggregatebiovar, biobase, chromdraw, classifyr, clusterjudge, clusterstab,
metagenomeseq, msmseda, plgem, scry, spotlight.

## Key correctness note — the cache-poison fix
Round-1's 21/90 was distorted by a shared `/tmp/realrun_rlib` cache that mixed Bioc 3.20 packages
into Bioc 3.21 fixture runs (silent namespace crashes, re-poisoning at workers>1). The harness now
namespaces the cache per-image (`rlib_for(img)`), so this clean 44% is the trustworthy number.

## Promoted to next-phase (tested-only)
- The consolidated bioc fixes (4-bucket + round-2 fixtures/.nf) — all harness-tested, 40 green,
  none regress.
- Step-param enricher (`enrich_bioc_step_params.py`) + backward-compatible serving change.
- (viz P0 PDF render + P1 vocab already on next-phase.)
Harness cache-poison fix lives on `fix/bioc-broken-wrappers` (the harness is a test tool, not in
the next-phase tree).

## Remaining (next rounds, staged on bioc-fix worktree)
- 35 timeouts: a longer-cap / AWS Batch run is the only way to settle these locally-unverifiable
  web-API/slow workflows.
- 10 exec_error: 4 are infra packages (rawrr/lpsymphony/widgettools/ssrch) to SKIP per methodology;
  the rest need a 3rd fix round.
