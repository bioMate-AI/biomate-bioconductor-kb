# Bioconductor validation wave — 340-workflow sample (2026-06-14)

Spot box `i-02fd076fea65d8ec2` (m5.4xlarge), `realrun_test_bioc_workflows.py --workers 8`,
domain `:3.20`/`:3.20-deps` images. Raw audit: `20260614_BIOC_VALIDATION_340_AUDIT.json` (340 records).
Box terminated after collection.

## Status tally (340)
| status | n | |
|---|---:|---|
| **ok** | 29 | clean |
| **ok_warnings** | 80 | runs + produces output, R warnings only |
| **→ executable** | **109 (32%)** | ok + ok_warnings |
| exec_error | 144 | ran but R/nextflow error, 0 output |
| skip_input_type | 33 | harness skips (input type not yet synthesizable) |
| timeout | 22 | exceeded wall clock |
| fixture_failed | 17 | fixture build/install failed |
| fixture_timeout | 10 | fixture install > budget |
| harness_error | 3 | |
| ran_empty_output | 2 | ran, no declared output produced |

## Failure signatures (164 hard failures: exec_error + fixture_failed + harness_error)
| n | signature | next-wave fix | examples |
|---:|---|---|---|
| 91 | **other** (long tail) | per-workflow triage | assessorf, matter, acgh |
| 18 | **fixture: wrong binary/rds format** | fixture writes a real S4 `.rds`/binary the wf can `readRDS` | tximeta, nanomethviz, wpm |
| 14 | **input-contract: fixture filename mismatch** | fixture must emit the exact `// Input:` filename the wf reads | aspli, affycoretools, cnordt |
| 12 | **nextflow: null path** (`Path value cannot be null`) | B-2 entry-wrapper / input-staging gap — wrapper not binding the declared input | clusterjudge, msbackendsql, biobase |
| 9 | analysis / API bug | per-workflow (real R logic) | sampleclassifier, branchpointer |
| 7 | R: package not installed/loadable | dep bootstrap / bake into domain image | methylkit, geodiff |
| 7 | dep skew / native lib load | image rebuild (upstream CRAN drift) | ancombc (`object 'solve' not exported`) |
| 6 | **generator bug: doubled `library` token** (`unexpected symbol in "librar library"`) | cheap regex fix in generator + regen the 6 | variantannotation, scry |

## Highest-leverage, lowest-risk next steps (data/codegen, not per-workflow)
1. **6× doubled-`library` generator bug** — deterministic escape bug; fix in the generator, regen those `.nf`. Pure win.
2. **12× null-path** — the B-2 entry wrapper isn't binding a declared input for these; trace `_build_bioc_entry_wrapper` against the 12. Likely one structural cause.
3. **32× fixture-contract** (18 binary + 14 filename) — the "fix the data, not the workflow" class the user called out: fixture must emit the exact declared filename and a real S4 object. Batchable in `generate_bioc_fixtures.py`.
4. **7× dep-skew / native-lib** — the known upstream miaverse-style drift; image-level, not pipeline-fixable (see domain-images README).

These four cover ~57 of 164 hard failures with structural (non-per-workflow) fixes; the 91 "other"
tail + 9 analysis bugs need per-workflow triage. The `skip_input_type` (33) are not failures —
the harness can't yet synthesize those input types.
