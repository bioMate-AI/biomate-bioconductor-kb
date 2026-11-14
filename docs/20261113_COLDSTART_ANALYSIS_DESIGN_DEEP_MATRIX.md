# Coldstart analysis/design deep matrix (2026-11-13)

Generated: 2026-11-14T16:48:57Z from `frontend/e2e/execshots/coldstart-analysis-design-deep/**/*.json` (dedupe by id; prefer graded JSON).

## Runner / tip

- Harness: `frontend/e2e/coldstart-analysis-design-deep.e2e.ts` via `frontend/e2e/run_coldstart_deep.sh` (lock `/tmp/biomate_coldstart_deep.lock` + orchestrator `flock /tmp/biomate_deep_e2e.lock`).
- Target: `https://dev-public.biomate.ai` tip **`0b63d793`** (clarify panel-open ancestry present).
- Full matrix: 6 sequential RESUME2 lanes (workers=1), then one failure re-run in 5 short-filter batches (workers=2).

## Scoreboard

| metric | n |
|---|---|
| case JSON (deduped) | 86 |
| grade `BLOCKED_REQUIRED` | 5 |
| grade `FAKE_OR_SOFT_PASS` | 3 |
| grade `HONEST_FAIL` | 50 |
| grade `NO_LAUNCH` | 13 |
| grade `REAL_PASS` | 15 |
| useCasePass | 15 |
| `*-after-run.png` | 92 |
| after.afterShell true | 68 |
| stuck findingsInProgress | 0 |
| validation PASS-like (REAL_PASS+HONEST_FAIL) | 65 |
| validation FAIL (DISHONEST/FAKE/ungraded) | 3 |
| honest block (NO_LAUNCH/BLOCKED) | 18 |

## Per-family

| family | n | grades |
|---|---|---|
| `analysis-ad-hoc-compute` | 3 | {'NO_LAUNCH': 3} |
| `analysis-domain-clin` | 3 | {'HONEST_FAIL': 1, 'NO_LAUNCH': 2} |
| `analysis-domain-dd` | 3 | {'NO_LAUNCH': 1, 'REAL_PASS': 2} |
| `analysis-domain-fgen` | 3 | {'NO_LAUNCH': 1, 'BLOCKED_REQUIRED': 1, 'HONEST_FAIL': 1} |
| `analysis-domain-gen` | 3 | {'NO_LAUNCH': 1, 'HONEST_FAIL': 2} |
| `analysis-domain-prot` | 3 | {'HONEST_FAIL': 2, 'NO_LAUNCH': 1} |
| `analysis-domain-str` | 3 | {'BLOCKED_REQUIRED': 2, 'NO_LAUNCH': 1} |
| `analysis-domain-txn` | 3 | {'HONEST_FAIL': 2, 'REAL_PASS': 1} |
| `analysis-try-sample-data` | 12 | {'HONEST_FAIL': 5, 'BLOCKED_REQUIRED': 1, 'REAL_PASS': 5, 'FAKE_OR_SOFT_PASS': 1} |
| `analysis-validated-workflows` | 3 | {'HONEST_FAIL': 2, 'REAL_PASS': 1} |
| `design-fold-complex-bio` | 3 | {'HONEST_FAIL': 3} |
| `design-fold-complex-pep` | 3 | {'NO_LAUNCH': 1, 'HONEST_FAIL': 2} |
| `design-fold-complex-sm` | 3 | {'NO_LAUNCH': 1, 'REAL_PASS': 1, 'HONEST_FAIL': 1} |
| `design-generate-bio` | 3 | {'HONEST_FAIL': 3} |
| `design-generate-pep` | 3 | {'HONEST_FAIL': 3} |
| `design-generate-sm` | 3 | {'HONEST_FAIL': 3} |
| `design-optimise-properties-one-pass-bio` | 3 | {'HONEST_FAIL': 3} |
| `design-optimise-properties-one-pass-pep` | 3 | {'HONEST_FAIL': 3} |
| `design-optimise-properties-one-pass-sm` | 3 | {'HONEST_FAIL': 3} |
| `design-predict-filter-bio` | 3 | {'FAKE_OR_SOFT_PASS': 1, 'HONEST_FAIL': 2} |
| `design-predict-filter-pep` | 4 | {'REAL_PASS': 2, 'HONEST_FAIL': 2} |
| `design-predict-filter-sm` | 4 | {'HONEST_FAIL': 2, 'REAL_PASS': 1, 'BLOCKED_REQUIRED': 1} |
| `design-rank-candidates-bio` | 3 | {'HONEST_FAIL': 3} |
| `design-rank-candidates-pep` | 3 | {'HONEST_FAIL': 2, 'NO_LAUNCH': 1} |
| `design-rank-candidates-sm` | 3 | {'REAL_PASS': 2, 'FAKE_OR_SOFT_PASS': 1} |

## Per-case matrix

| id | grade | useCasePass | tip | terminal | afterShell | out | find | params | stuck | after-run.png |
|---|---|---|---|---|---|---|---|---|---|---|
| `analysis-ad-hoc-compute-0` | `NO_LAUNCH` | False | `5dd9b6fb` | `n/a` | — | — | — | — | — | `—` |
| `analysis-ad-hoc-compute-1` | `NO_LAUNCH` | False | `5dd9b6fb` | `n/a` | — | — | — | — | — | `—` |
| `analysis-ad-hoc-compute-2` | `NO_LAUNCH` | False | `5dd9b6fb` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-clin-0` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-clin-1` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-clin-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `analysis-domain-clin-2-after-run.png` |
| `analysis-domain-dd-0` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-domain-dd-0-after-run.png` |
| `analysis-domain-dd-1` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-domain-dd-1-after-run.png` |
| `analysis-domain-dd-2` | `NO_LAUNCH` | False | `d258bd32` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-fgen-0` | `BLOCKED_REQUIRED` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-fgen-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `analysis-domain-fgen-1-after-run.png` |
| `analysis-domain-fgen-2` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-gen-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `analysis-domain-gen-0-after-run.png` |
| `analysis-domain-gen-1` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-gen-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `analysis-domain-gen-2-after-run.png` |
| `analysis-domain-prot-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `analysis-domain-prot-0-after-run.png` |
| `analysis-domain-prot-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `analysis-domain-prot-1-after-run.png` |
| `analysis-domain-prot-2` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-str-0` | `BLOCKED_REQUIRED` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-str-1` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-str-2` | `BLOCKED_REQUIRED` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `analysis-domain-txn-0` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-domain-txn-0-after-run.png` |
| `analysis-domain-txn-1` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-domain-txn-1-after-run.png` |
| `analysis-domain-txn-2` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-domain-txn-2-after-run.png` |
| `analysis-try-sample-data-0` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-try-sample-data-0-after-run.png` |
| `analysis-try-sample-data-1` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-try-sample-data-1-after-run.png` |
| `analysis-try-sample-data-10` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-try-sample-data-10-after-run.png` |
| `analysis-try-sample-data-11` | `BLOCKED_REQUIRED` | False | `d258bd32` | `n/a` | — | — | — | — | — | `—` |
| `analysis-try-sample-data-2` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-try-sample-data-2-after-run.png` |
| `analysis-try-sample-data-3` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-try-sample-data-3-after-run.png` |
| `analysis-try-sample-data-4` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-try-sample-data-4-after-run.png` |
| `analysis-try-sample-data-5` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-try-sample-data-5-after-run.png` |
| `analysis-try-sample-data-6` | `REAL_PASS` | True | `d258bd32` | `completed` | Y | Y | N | N | — | `analysis-try-sample-data-6-after-run.png` |
| `analysis-try-sample-data-7` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-try-sample-data-7-after-run.png` |
| `analysis-try-sample-data-8` | `HONEST_FAIL` | False | `d258bd32` | `failed` | Y | N | N | N | — | `analysis-try-sample-data-8-after-run.png` |
| `analysis-try-sample-data-9` | `FAKE_OR_SOFT_PASS` | False | `8c946897` | `n/a` | Y | N | N | N | — | `analysis-try-sample-data-9-after-run.png` |
| `analysis-validated-workflows-0` | `REAL_PASS` | True | `5dd9b6fb` | `completed` | Y | Y | N | N | — | `analysis-validated-workflows-0-after-run.png` |
| `analysis-validated-workflows-1` | `HONEST_FAIL` | False | `5dd9b6fb` | `failed` | Y | N | N | N | — | `analysis-validated-workflows-1-after-run.png` |
| `analysis-validated-workflows-2` | `HONEST_FAIL` | False | `5dd9b6fb` | `failed` | Y | N | N | N | — | `analysis-validated-workflows-2-after-run.png` |
| `design-fold-complex-bio-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-fold-complex-bio-0-after-run.png` |
| `design-fold-complex-bio-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-fold-complex-bio-1-after-run.png` |
| `design-fold-complex-bio-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `design-fold-complex-bio-2-after-run.png` |
| `design-fold-complex-pep-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-fold-complex-pep-0-after-run.png` |
| `design-fold-complex-pep-1` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `design-fold-complex-pep-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-fold-complex-pep-2-after-run.png` |
| `design-fold-complex-sm-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-fold-complex-sm-0-after-run.png` |
| `design-fold-complex-sm-1` | `REAL_PASS` | True | `0b63d793` | `completed` | Y | Y | N | N | — | `design-fold-complex-sm-1-after-run.png` |
| `design-fold-complex-sm-2` | `NO_LAUNCH` | False | `0b63d793` | `n/a` | — | — | — | — | — | `—` |
| `design-generate-bio-0` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-generate-bio-0-after-run.png` |
| `design-generate-bio-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `design-generate-bio-1-after-run.png` |
| `design-generate-bio-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `design-generate-bio-2-after-run.png` |
| `design-generate-pep-0` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-generate-pep-0-after-run.png` |
| `design-generate-pep-1` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-generate-pep-1-after-run.png` |
| `design-generate-pep-2` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-generate-pep-2-after-run.png` |
| `design-generate-sm-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-generate-sm-0-after-run.png` |
| `design-generate-sm-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-generate-sm-1-after-run.png` |
| `design-generate-sm-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-generate-sm-2-after-run.png` |
| `design-optimise-properties-one-pass-bio-0` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-bio-0-after-run.png` |
| `design-optimise-properties-one-pass-bio-1` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-bio-1-after-run.png` |
| `design-optimise-properties-one-pass-bio-2` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-bio-2-after-run.png` |
| `design-optimise-properties-one-pass-pep-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `design-optimise-properties-one-pass-pep-0-after-run.png` |
| `design-optimise-properties-one-pass-pep-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `design-optimise-properties-one-pass-pep-1-after-run.png` |
| `design-optimise-properties-one-pass-pep-2` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-pep-2-after-run.png` |
| `design-optimise-properties-one-pass-sm-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-sm-0-after-run.png` |
| `design-optimise-properties-one-pass-sm-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-sm-1-after-run.png` |
| `design-optimise-properties-one-pass-sm-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-optimise-properties-one-pass-sm-2-after-run.png` |
| `design-predict-filter-bio-0` | `FAKE_OR_SOFT_PASS` | False | `cedda7c4` | `completed` | Y | Y | N | N | — | `design-predict-filter-bio-0-after-run.png` |
| `design-predict-filter-bio-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-predict-filter-bio-1-after-run.png` |
| `design-predict-filter-bio-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | Y | N | N | — | `design-predict-filter-bio-2-after-run.png` |
| `design-predict-filter-pep-0` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-predict-filter-pep-0-after-run.png` |
| `design-predict-filter-pep-1` | `REAL_PASS` | True | `0b63d793` | `completed` | Y | Y | N | N | — | `design-predict-filter-pep-1-after-run.png` |
| `design-predict-filter-pep-2` | `REAL_PASS` | True | `0b63d793` | `completed` | Y | Y | N | N | — | `design-predict-filter-pep-2-after-run.png` |
| `design-predict-filter-pep-3` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-predict-filter-pep-3-after-run.png` |
| `design-predict-filter-sm-0` | `REAL_PASS` | True | `cedda7c4` | `completed` | Y | Y | N | N | — | `design-predict-filter-sm-0-after-run.png` |
| `design-predict-filter-sm-1` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-predict-filter-sm-1-after-run.png` |
| `design-predict-filter-sm-2` | `HONEST_FAIL` | False | `0b63d793` | `failed` | Y | N | N | N | — | `design-predict-filter-sm-2-after-run.png` |
| `design-predict-filter-sm-3` | `BLOCKED_REQUIRED` | False | `0b63d793` | `n/a` | — | — | — | — | — | `predict-optimise/design-predict-filter-sm-3-after-run.png` |
| `design-rank-candidates-bio-0` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-rank-candidates-bio-0-after-run.png` |
| `design-rank-candidates-bio-1` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-rank-candidates-bio-1-after-run.png` |
| `design-rank-candidates-bio-2` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-rank-candidates-bio-2-after-run.png` |
| `design-rank-candidates-pep-0` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-rank-candidates-pep-0-after-run.png` |
| `design-rank-candidates-pep-1` | `NO_LAUNCH` | False | `cedda7c4` | `n/a` | — | — | — | — | — | `design-rank-candidates-pep-1-after-run.png` |
| `design-rank-candidates-pep-2` | `HONEST_FAIL` | False | `cedda7c4` | `failed` | Y | N | N | N | — | `design-rank-candidates-pep-2-after-run.png` |
| `design-rank-candidates-sm-0` | `REAL_PASS` | True | `cedda7c4` | `completed` | Y | Y | N | N | — | `design-rank-candidates-sm-0-after-run.png` |
| `design-rank-candidates-sm-1` | `REAL_PASS` | True | `cedda7c4` | `completed` | Y | Y | N | N | — | `design-rank-candidates-sm-1-after-run.png` |
| `design-rank-candidates-sm-2` | `FAKE_OR_SOFT_PASS` | False | `cedda7c4` | `paused` | Y | Y | N | N | — | `design-rank-candidates-sm-2-after-run.png` |

## Remaining failures after one re-run

- `analysis-try-sample-data-9`
- `design-predict-filter-bio-0`
- `design-rank-candidates-sm-2`

## Follow-up (2026-11-14T16:50Z) — soft-pass triage

This matrix tip (`0b63d793` / re-run `cedda7c4`) is **before** local batches A–H were DEV-synced. Soft-pass count is measurement + tip lag, not proof A–H failed.

| Case | Observed | Regrade with fixed harness | Product still open |
|------|----------|----------------------------|--------------------|
| `analysis-try-sample-data-9` | Confirm + “1 required parameter” + `no runId` | → **`NO_LAUNCH`** (`coldstart-deep-grade.ts`) | WSI still launched Confirm while required param empty — seed or keep Confirm blocked |
| `design-rank-candidates-sm-2` | `paused` + runId + outputs | → **`HONEST_FAIL`** (QC/seq pause ≠ soft) | Pause UX OK; not a fake pass |
| `design-predict-filter-bio-0` | `completed` + outputs, empty `workflowNames`, no findings/params | stays soft until names/findings land | Antibody developability After Run / name plumbing |

Grade rules updated in `frontend/e2e/lib/coldstart-deep-grade.ts` (+ vitest). Next: PRE_SYNC + sync A–H → filtered deep re-run on DEV.

## After-run PNG paths

- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-clin-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-dd-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-dd-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-fgen-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-gen-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-gen-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-prot-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-prot-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-txn-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-txn-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-domain-txn-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-10-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-3-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-4-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-5-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-6-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-7-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-8-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-try-sample-data-9-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-validated-workflows-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-validated-workflows-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/analysis-validated-workflows-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-fold-complex-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-pep-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-generate-sm-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-pep-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-optimise-properties-one-pass-sm-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-pep-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-pep-3-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-predict-filter-sm-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-pep-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/design-rank-candidates-sm-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-pep-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-optimise-properties-one-pass-sm-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-bio-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-bio-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-bio-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-pep-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-pep-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-pep-3-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-sm-1-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-sm-2-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/predict-optimise/design-predict-filter-sm-3-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/rank-candidates/design-rank-candidates-pep-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/rank-candidates/design-rank-candidates-sm-0-after-run.png`
- `frontend/e2e/execshots/coldstart-analysis-design-deep/rank-candidates/design-rank-candidates-sm-2-after-run.png`
