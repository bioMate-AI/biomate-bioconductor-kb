# BioMate hospital demonstration use case test results

Date: October 29, 2026, America/Chicago. Final run: October 30, 01:45:28–01:45:44 UTC.

## Outcome

The four proposed research cases are **not yet accepted for an end-to-end hospital demonstration**. The final suite recorded **19 passing checks, 13 failing checks and no harness exceptions**. These are software-contract checks, not a scientific accuracy percentage or a comparison with Claude/GPT. The 13 failures comprise 11 local service assertions, one live artifact-output failure and one unavailable R/PKNCA fallback execution. The indexed PKNCA workflow itself remains untested, not disproved.

The most urgent findings are a live sandbox that cannot save output files, a campaign adapter that does not use the actual observed scores, evaluation gates accepting missing/infinite metrics, and report-ingestion provenance errors. Positive results include unit normalization, a safety-driven ranking change, invalid-unit rejection and correction, persistence/isolation, real RDKit features, and a direct GP responding to changed labels.

Canonical evidence: [final raw results](qa/20261029-sysucc-usecases-live.json). Reproduction: [test runner](../scripts/test_sysucc_usecases.py). Inputs: [initial assay CSV](qa/sysucc-usecases/assays_initial.csv), [safety assay CSV](qa/sysucc-usecases/assays_safety.csv), and [study text](qa/sysucc-usecases/study_report.txt). All inputs are synthetic software fixtures, not real experimental evidence.

## Execution boundaries

Local checks invoke BioMate's actual ingestion, ranking, optimizer, retraining, evaluation-gate, knowledge-query and report-ingestion implementations. They use isolated temporary databases and the installed RDKit/scikit-learn stack without service mocks. Source and fixture hashes are included in the raw report. Local Git HEAD was `b6ca37fc8`, with substantial existing uncommitted changes; hashes identify the tested local files more precisely than HEAD alone.

Live checks use `https://dev-public.biomate.ai/api/code/run`, plus read-only health/session probes. They test sandbox calculations and output creation, not model-generated code or chat orchestration. File contents are supplied inline; actual upload, two-file citation and dataset staging have not been exercised. The dev build is not assumed identical to local source.

The existing shared fixture password is unset and its saved localhost session expired. No account was created/reset and no login bypass was attempted. Authenticated chat/UI, project handoff and indexed workflow execution remain blocked pending the fixture credential. The code-runner route accepts these dev requests without a logged-in user; this does not demonstrate authenticated access controls. No LLM calls, docking/GPU/Batch jobs, production changes or hospital-data uploads were performed.

## Case 1 Compare candidate files

Task: “Compare the potency and safety files by compound ID. Normalize concentrations; select candidates with IC50 ≤10 nM and hERG IC50 ≥10 µM. Preserve missing measurements and save a comparison table.” These are explicit test criteria, not universal clinical safety cutoffs.

The potency file contains A/B/C at 1/10/100 nM; the safety file contains hERG values of 1/50/25 µM. B alone meets both criteria.

- **Passed locally:** exact nM→µM conversion; six persisted assay rows with the correct IDs; A leads on potency alone, while B leads after safety data; another campaign sees no rows; reload preserves rankings.
- **Passed live:** sandbox computation selects B with exact normalized values.
- **Failed live:** saving `candidate_comparison.csv` raises `PermissionError`; exit code is 1 and there are no output files. Read-only inspection inside a fresh test sandbox shows runtime UID/GID 1000, output owner UID/GID 0, mode 0755 and `writable:false`. The task is incomplete even though its arithmetic is correct.
- **Failed locally:** adding D with strong potency but no safety measurement makes D rank first with `combined_score:1`, without a coverage warning. This result must not be presented as a qualified overall lead recommendation.

Source connection: `frontend/server/code-runner.ts` creates directories under the frontend identity but selects a non-root sandbox identity; no matching output-directory ownership adjustment is present. The observed dev permissions establish the mismatch independently of that source inference. Retain sandbox hardening when correcting ownership; do not run user code as root to make the test pass.

Acceptance still requires a user citing both uploaded files in chat, receiving the correct comparison, downloading a nonempty artifact and seeing incomplete candidates explicitly distinguished.

## Case 2 Perform an appropriate PK analysis

Task: “For a single-dose IV concentration–time dataset, choose NCA, state assumptions and units, calculate exposure and half-life, and save the results.” The diagnostic fixture uses `C(t)=2^(-t/4)` mg/L with a 1 mg IV dose. Expected half-life is 4 h; AUC to infinity is `4/ln(2)`, approximately 5.77078 mg·h/L.

- **Passed locally:** BioMate knowledge retrieval finds the PKNCA workflow among its top five results and explicitly labels catalogue retrieval as not execution-verified.
- **Unavailable live fallback:** the BioMate R code runner reports that PKNCA is not installed. No numerical result or NCA artifact is produced.
- **Blocked:** authenticated dataset binding and execution of the indexed PKNCA workflow. That workflow uses a separate R-NCA container; missing PKNCA in the generic sandbox is not proof that the indexed workflow cannot run.

No local Python substitute or locally installed R package was used. A source-only concern also remains for review: the indexed workflow declares dose/concentration settings and labels clearance in litres without an evident unit-conversion contract. It has not been counted as an executed numerical failure.

Acceptance requires the indexed workflow to run on explicitly normalized units, match independently specified reference values, preserve dose/route/subject identity, and produce an inspectable artifact and faithful final answer.

## Case 3 Learn from a new assay batch

Task: “Import potency data, create a proposal, add new safety measurements, refit and show how the observed data affect the next proposal. Keep evaluation data separate.”

- **Passed:** real RDKit features; two nonempty persisted campaign proposals; a direct BioMate GP changes held-out predictions when its label distribution changes. The latter is a synthetic sensitivity check, not improved biological accuracy.
- **Failed:** campaign scores stay `[0,0]` before and after the safety batch, despite changed observed rankings. `AssayIngestionService.get_ranked_compounds()` emits `combined_score`; `auto_retrain.refit_and_propose()` reads `composite_score` with a default of 0.5. Constant fallback labels normalize to zero. A successful proposal response therefore does not establish that new assay values were learned.
- **Failed:** both persisted proposals have round number 1. The optimizer initializes its round from `bo_proposals`, while this adapter persists to `auto_proposals` without the corresponding optimizer save.
- **Failed:** a configured AUC gate of 0.7 accepts both an absent metric and positive infinity. Valid 0.8 passes and poor 0.6 fails as expected.

Sources: `drug_discovery/assay_ingestion.py`, `auto_retrain.py`, `bayesian_optimizer.py`, and `ml_training/training_job.py` under `backend/lib/galaxy/ai/`.

No claim of immutable model versions, checkpoint promotion, restart-safe model reload, rollback, generator continued training or biological improvement is accepted from these tests. The campaign path persists proposals; that alone is not durable model versioning. Acceptance requires actual label sensitivity through the public campaign path, stable round identities, fail-closed metrics, protected holdouts and the exact demonstrated model artifact.

## Case 4 Build a source faithful evidence package

Task: “Extract measured PK and safety findings from the supplied study, preserving values, units, species and source. Keep predictions separate and do not invent GLP status.”

These checks exercise `WetLabReportIngester`, which also participates in the IND assembly's structured wet-lab override path. They do **not** exercise the separate PDF upload extractor, `study_report_ingester.extract_from_pdf`, or validate a rendered IND document.

- **Passed:** half-life of 8 h; hERG conversion from 5000 nM to 5 µM; source-reference retention.
- **Failed:** the rat half-life is labelled human by default.
- **Failed:** explicitly supplied Cmax 250 ng/mL and AUCinf 1500 ng·h/mL are absent from text-ingestion output. Patterns exist, but `ingest_text` does not wire those extractions.
- **Failed:** text explicitly marked “Computational prediction only” with no measurements becomes `source:measured_wetlab`, confidence HIGH.
- **Failed:** structured input without evidence of GLP compliance yields `glp_certified:true` by default.

Acceptance requires testing the actual chosen upload/extraction/assembly route, human review of extracted fields, source/species fidelity, prediction/measured separation and a rendered report checked against its inputs. Success on one parser must not be generalized to every report-ingestion path.

## Deliberate data errors and recovery

Unsupported `mg/mL`, NaN, an invalid date and negative Kd are rejected with explanations. Correcting an invalid unit then ingests exactly one valid row without retaining the rejected row.

Two safeguards fail: negative IC50 is accepted, and the same compound ID mapped to ethanol and benzene is ingested without an identity conflict. These need endpoint-specific physical validation and structure-identity checks, not generic text filtering. Censoring, replicates/batches, missing receptor recovery and restart/reviewer journeys remain outside this run.

## Test audit and reproduction

The initial exploratory report `qa/20261029-sysucc-usecases.json` is superseded. Reviewing the harness found two important test issues: an unseen-structure GP can legitimately revert to a shared prior mean when labels are merely permuted, and checking only for predictions equal to 0.5 misses fallback labels normalized to zero. The final fixture changes the normalized label distribution and tests before/after campaign predictions; it no longer treats that valid GP behavior as a product defect.

The live comparison prints numerical results before attempting its artifact write, so calculation correctness is scored separately from task completion. Every assertion records expected and actual values, and the runner exits nonzero on failures. No failing case was skipped or converted into a pass.

```sh
python3 scripts/test_sysucc_usecases.py
python3 scripts/test_sysucc_usecases.py --live --output docs/qa/20261029-sysucc-usecases-live.json
```

The live flag is restricted to the named dev server. Local dependencies are NumPy, scikit-learn and RDKit; none were installed during this run. Compile and whitespace checks passed for the new runner/fixtures. These tests add no production fixes or deployment changes.

## Required order before the hospital comparison

1. Correct sandbox output ownership and prove real artifact download while retaining non-root isolation.
2. Correct campaign score binding/round persistence and reject missing/nonfinite configured gate metrics.
3. Correct measured/predicted, species and GLP provenance in the relevant report paths.
4. Add endpoint/identity/coverage safeguards and test complete versus incomplete candidates.
5. Restore authenticated fixture access; run uploaded-file chat, indexed NCA, campaign and evidence-package journeys against the exact deployed build, including visible final answers and downloads.
6. Only then run the frozen Claude/GPT comparison protocol. This run establishes actionable BioMate findings, not competitor wins.
