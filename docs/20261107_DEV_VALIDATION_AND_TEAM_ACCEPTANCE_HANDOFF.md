# Dev validation and team acceptance handoff

## Release decision

**Status: ready for the scoped teammate online UI acceptance pass described below; not full-platform or full drug-development scientific sign-off.** Dev is the first acceptance environment because prospective users will try the online platform before installation. The teammate owns final packaged on-prem installation and scientific acceptance on that installation. The wider NOT RUN scenarios remain required before making broader demonstration/readiness claims.

Target: https://dev-public.biomate.ai. Initial checks were performed on November 7, 2026, America/Chicago; evidence timestamps use UTC and may show November 8.

Do not interpret a healthy API, successful image build, catalogue entry, generated workflow card, or completed Batch process as proof of scientific correctness. Each establishes a different part of the acceptance chain.

## Current evidence

PR: https://github.com/bioMate-AI/biomate/pull/335, stacked on PR 328's deployed language/UI branch. Do not merge it onto an older baseline without preserving those changes. **Current dev application: `e06ade54e1bc8cae058fcd52c8895cc946e1b45c`**, independently verified through `/build-info.json` before and after the final test. The final consolidated preflight passed in 2.5 minutes, with all 14 recorded checks passing and no retry/skip. Evidence: `docs/qa/20261107-dev-online-readiness/run-1794113868148/preflight-results.json`; its workbench screenshot was reviewed visually. Peptide source code and output are correlated to the same tool call; molecular weight/pI agree with the reference; the full answer uses 40 rather than the invented threshold and explicitly frames the calculation as theoretical. This is a narrow interpretation regression, not general validation of biological stability predictions.

The preceding live batch on `815132435eda2036845b346d407cdf784120ac67` passed both Playwright harnesses in 4.0 minutes, including real AWS Batch execution and artifact downloads. Its manual interpretation finding was corrected in the current release and retested above. The final runtime change is guarded to basic peptide response instructions; backend, scientific workflow and diagnostics route are unchanged from that successful execution batch. The final PR may contain a later test/evidence/documentation commit; use the application identifier above when comparing dev.

The completed scientific record is `docs/qa/20261107-dev-online-readiness/scientific-1794113365310/scientific-results.json`. Ethanol run `f33302a7-9d8a-4ea9-b438-eb0d8a010697` completed; invalid-SMILES run `3a3d2640-5569-4060-9c9d-de3358c98f92` failed for the intended parsing reason, with working authenticated diagnostics. Both are terminal and their test project was deleted after evidence capture. Retained local artifacts, rather than deleted-project UI links, are the reproducible evidence.

Artifact SHA-256: ethanol CSV `9f43072887986c581d4452f85c5f62839aa21606ae7e6a355f0596f0783c08f9`; result JSON `d787871e5dffac681a83fa326a8418e384b6642e1ce11db9f9852c0b7c90e2a2`. Literal fixture hashes use UTF-8 with no trailing newline: `CCO` = `ab1de819ede91df490e6441934decfa9041b49f91d6bbadbba4df634ccff57fa`; `not-a-molecule` = `848798e7bc995a91b041ef49e196140053cbb664d1be554b4273c06a358ac7a3`; peptide `ACDEFGHIKLMNPQRSTVWY` = `5a52efc76a4a4ceb3c992ff17426b3545634646080bb6acec132c47c278c9846`.

The first live checks confirmed HTTP 200 for the online workbench, successful login with the existing shared fixture, authenticated project-list and account APIs, and `/api/health` reporting API and AI `ok` and Galaxy connected. The authenticated browser rendered the four workbench entry points: Search & evidence, Data analysis, Molecule design & generate, and Models.

The reproducible consolidated preflight is `frontend/e2e/dev-online-readiness.e2e.ts`. It uses one login, one temporary project, real APIs, and the same strict SSE response parser used by the connector. It never clicks Confirm & Run or launches Nextflow, but intentionally permits direct sandbox computation for basic peptide properties and direct public target-evidence retrieval. Its evidence is written to `docs/qa/20261107-dev-online-readiness/`:

- `preflight-results.json`: individual verdicts, timestamps, routing metadata and cleanup results.
- `authenticated-workbench.png`: browser capture, reviewed visually.

This preflight checks authentication boundaries, an ADMET draft, a numerical peptide-property result and public target evidence. Real Nextflow execution and output downloads are checked separately by `frontend/e2e/dev-scientific-properties.e2e.ts`. Neither harness qualifies predictive ADMET accuracy, binding affinity or a complete drug-development chain.

The local checkout contains extensive changes from several work streams. The active branch name or local HEAD must not be presented as the deployed version. The first scoped release, `4dde598fd1d78fd77e0833e0da5f0ea4c084f1b9`, was deployed successfully. Its first live retest found further defects; the follow-up release and final verdict are recorded in the deployment log and must be checked before acceptance.

### Historical first dev run and corrective work

The public `/build-info.json` identified frontend commit `7c030334b439df2ecc7d384e7c2812c1a59c843f`. A read-only backend import in the dev container succeeded when run with the application's `/app/lib` module path; the deployed `ai_assistant.py` SHA-256 was `0f1b2666558967be580eae3f3311c6722c5af9801f17c992416afaf0df4e2e03`.

| Check | Observed result | Status |
| --- | --- | --- |
| Login, workbench, Galaxy API, anonymous 401 and nonexistent project 404 | Expected behavior; browser screenshot reviewed | PASS |
| Small-molecule ADMET draft | Structured card selects `nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`; no dispatch | PASS for routing only |
| Peptide molecular weight and pI request | Answer describes `peptide_properties`, but structured card selects `nfcore/proteinfold/main.nf` | FAIL |
| EGFR/NSCLC target evidence | Direct tool returns only `llm_reasoned`; Open Targets and STRING are in `channel_errors`; reply nevertheless starts “completed successfully” | FAIL |
| No automatic run launch | Zero execution runs in the isolated project after drafts/direct analysis | PASS |
| Cleanup | Every test-created session and project removed successfully | PASS |

The target case was repeated with structured `identify_targets` tool-result inspection, allowing a direct chat result instead of requiring a workflow card. It still failed because the requested Open Targets channel was unavailable. That second record is `docs/qa/20261107-dev-online-readiness/run-1794109823145/preflight-results.json`. A source diagnostic is still required to determine why the channels failed; the missing evidence must not be blamed on credentials without that diagnosis.

Corrective changes at the time of the initial run (subsequently included in the first scoped deployment):

- The protein-folding fast path now requires explicit structure/folding intent or a bare sequence. Property calculations, annotation, alignment, immunogenicity and fold-change requests no longer select folding solely because a sequence is present. English and Chinese controls are covered. All 21 focused routing tests pass; restoring the old method makes all eight new nonstructural cases fail.
- Target result headings distinguish incomplete evidence, reasoning-only hypotheses and missing provenance. Failed channels are not listed as successful, and a failed primary channel cannot be claimed as the ordering source. The reply offers a source-retrieval/retry step without printing internal exception details. The scientific-tool and strict SSE parser suites pass all 23 tests.
- Review of the canonical physicochemical workflow found mislabeled molar refractivity, unsupported logD7.4 substitution, invalid SMILES marked successful and an undeclared scientific CSV output. The local patch labels molar refractivity correctly, supplies named QED separately, removes unsupported ionization claims, fails invalid inputs at the wrapper boundary and exposes the CSV output. Four tests execute the exact embedded Python body with RDKit, including ethanol reference values and invalid/empty inputs. These pass locally. Restoring the old workflow makes all four test methods fail (five assertion failures across subcases and one missing-QED error), confirming that the tests reject the previous output. Nextflow execution and online artifact delivery are still NOT RUN.

The full frontend regression suite passed **2,287 tests**, with **32 skipped** across 206 passing and three skipped files. TypeScript checking passed. The first restricted suite attempt could not bind loopback HTTP servers (`EPERM`); the complete passing rerun had loopback permission. The local Anaconda Python 3.9 import failed inside its installed SciPy stack (`scipy.interpolate._fitpack_impl`, `TypeError`), before application import completed.

To test compatibility without altering dev, the reviewed method was substituted into the deployed module **in memory**. Its complete candidate source hash matched the local file exactly (`d786878b46ed588710f7c63e228954074133a96141a1956c9de0b957e6208a9d`). The full candidate module imported successfully under dev's **Python 3.9.25**, and seven nonstructural/design controls plus five folding controls passed. SSM command: `17dc951b-cee0-4c6f-8501-905a34f386c3`. No deployed file, worker or service changed. This closes the Python compatibility check, not deployment or live chat retesting.

A direct source diagnostic also established that dev can retrieve real Open Targets disease associations with the platform's existing association query. A separate exploratory name-search diagnostic initially used the wrong GraphQL argument (`query` rather than `queryString`); the full HTTP 400 body identified that diagnostic mistake. It is not evidence of a broken association-query implementation. The EGFR/NSCLC chat source failures remain a separate issue until their input and complete channel errors are diagnosed.

The corrected public name lookup resolved non-small cell lung carcinoma to `MONDO_0005233`. Calling the existing dev target handler with that verified ID, EGFR and `use_llm=False` returned both `genetics_ot` and `ppi_string`, no channel errors, primary-channel Open Targets ordering, and EGFR score **0.8884** with two-channel corroboration. Its source links resolve to the Open Targets EGFR/NSCLC evidence page and STRING network. SSM command: `18a64a2f-11b7-4104-b3eb-47f4204b37df`. This establishes that the underlying evidence channels can work from dev; it does **not** repair or pass the failed online chat journey. The score is an association score, not a clinical probability.

The focused chat diagnosis subsequently captured the actual tool request and complete channel errors in `run-1794110341921/preflight-results.json`. The model supplied **`EFO_0003838`**, which Open Targets reported did not resolve. STRING then reported **`no seed_genes in context`**. This is an identifier/routing failure with a downstream consequence, not a demonstrated credentials failure.

The corrective path accepts the user's full disease name in `identify_targets`, resolves it against Open Targets and retains resolution provenance. The initial resolver accepted only an exact canonical name; the follow-up also accepts ontology-verified `hasExactSynonym` terms. It rejects ambiguity, conflicting name/ID inputs and unverified fuzzy matches. Offline mode never makes a name-lookup network call. The frontend boundary rejects unresolved-ID results with a retry instruction instead of treating AI-only fallback as a successful evidence-backed answer. The latest routing/resolver suite passes 28 tests, and all 12 target-handler regression tests pass in an isolated Python 3.12 environment. Earlier handler regressions also passed against the exact reviewed functions in dev's Python 3.9.25 process, in memory, without changing services (SSM `24c5fbab-94ec-40b9-9fcc-da0b4a9c49d2`). The route-test event-loop helper uses `asyncio.run` to close loops after each case.

An initial full frontend rerun terminated with SIGSEGV rather than a test verdict; the log contained no failed assertion. The macOS diagnostic report identifies `npm exec vitest run` terminating with that signal. This attempt is not a pass. The subsequent bounded-worker rerun passed 2,288 tests with 32 skipped. After the additional fixes, the shared-source full suite passed **2,304 tests, 32 skipped**, 207 passing files and three skipped files, in 72.82 seconds. Exact release-source TypeScript checking and 83 focused tests passed; the final peptide instruction follow-up also passed its TypeScript check and all 14 sequence tests. These are local regressions, distinct from the successful live evidence at the top of this document; skipped tests are not live qualification.

### First post-deployment scientific execution

Ethanol completed through the real platform/AWS Batch path: frontend run `9a559a44-1ef0-40e0-bba7-01d842436f3d`, Nextflow run `074e47dc-3a0d-4682-affc-754c31ddf8be`. Downloaded CSV/JSON are in `docs/qa/20261107-dev-online-readiness/scientific-1794112344365/`. Checked values include molecular weight 46.07, TPSA 20.23, three heavy atoms and QED 0.4068. This is a deterministic physicochemical fixture, not a predictive ADMET benchmark.

Invalid SMILES correctly produced a failed run (`d5ff7047-0a85-4cb7-9239-2efd7f5af952`) but its diagnostic endpoint returned HTTP 500, so the negative acceptance test failed. The endpoint already had an ownership guard. The follow-up preserves it and selects the correct Nextflow status API instead of an invalid Galaxy invocation URL. It does not expose raw logs automatically in the user interface.

The peptide follow-up uses the existing BioPython sandbox for explicitly requested basic unmodified linear sequence properties, not an unrelated antibody workflow. Expected values for `ACDEFGHIKLMNPQRSTVWY` are molecular weight 2395.7134 Da (tolerance 0.02) and theoretical pI 6.78455 (tolerance 0.01). These values do not describe cyclic, modified or folded peptides.

**Current gate:** the scoped automated retests have passed. Perform the teammate's online UI pass below, then qualify the wider NOT RUN scientific journeys before approving the complete demonstration chain. See `docs/20261107_DEV_PR_SYNC_TEST_LOG.md` for chronological deployment/test evidence, including the original failures. Do not reinterpret those failed runs as passes.

## Test ownership and order

1. Development owner: test dev through the real online entry point, diagnose failures, implement scoped fixes, run local regression checks, then retest the deployed fix.
2. Scientific reviewer: compare downloaded results against the declared controls and method-specific expectations. Sign off on the interpretation separately from execution success.
3. Installation teammate: test the identified package after the dev handoff is marked ready. Repeat the same scientific inputs to distinguish installation/configuration failures from algorithmic differences.

Use public or synthetic data until hospital data governance and access are agreed. Do not place patient records, credentials, cookies, signed URLs or raw provider traces in the evidence repository.

## Dev acceptance scenarios

| ID | User journey | Required evidence and pass condition |
| --- | --- | --- |
| DEV-01 | Sign in, open workbench, create a project, return after refresh | Real browser screenshots; project persists; no console failure prevents interaction; no other user's resources appear. |
| DEV-02 | Upload two result files, cite both in chat, compare them | Both stable dataset IDs remain bound; comparison uses actual rows from both files; missing columns are explained; no substituted demonstration data. |
| DEV-03 | Small-molecule property calculation and ADMET | Named input molecules map to downloaded rows; deterministic descriptors match references; model endpoint names, units and versions are explicit; predictions are not described as measurements. |
| DEV-04 | Peptide analysis, followed by cyclic-peptide design where configured | Sequence, modifications and cyclization are explicit; results retain candidate identity; ordinary peptide properties are not presented as validation of cyclic structure, binding or permeability. |
| DEV-05 | Oncology target identification from public evidence and an uploaded analysis result | Disease and target identifiers resolve; source evidence and input-run provenance are accessible; contribution of the uploaded evidence is identifiable; unknown evidence is not a negative association. |
| DEV-06 | Adapt a model using an internal-data-shaped public/synthetic fixture | Declared trainer actually executes; split prevents group/scaffold/patient leakage; held-out evaluation, model artifact and reload inference are available. A descriptor baseline is not described as Chemprop or continued neural training. |
| DEV-07 | Observe a real run and inspect results | Chat, workflow panel and Run Manager agree on status; outputs are associated with the correct run and step; refresh preserves state; report download resolves and includes actual values and methods. |
| DEV-08 | Invalid input, missing input, unavailable service and QC halt | No false green completion; clear actionable user message; no stack trace or literal internal log dump; retry does not silently duplicate compute; no automatic acceptance of a safety halt. |
| DEV-09 | Evidence search and cited research answer | Real external calls; relevant sources; titles and identifiers resolve; unavailable channels are identified; no invented accessions or citations. |
| DEV-10 | Representative non-drug regression | One existing RNA expression analysis with correct assay-specific method; one other supported domain; real outputs and no regressions in shared binding, execution and report paths. |

Record each scenario as PASS, FAIL, BLOCKED or NOT RUN. A safe clarification can pass a negative-input scenario but does not pass a positive scenario requiring a runnable plan. A skipped test is not a passed capability.

### Scope of this PR's evidence

The automated tests authenticate in a real browser and render the workbench, then submit scientific requests through the real chat/execution APIs with that authenticated context. They do not yet exercise every click, panel transition, report-editing interaction or restart/persistence case. The teammate's online UI pass must therefore include those interactions, rather than treating API success as full UX acceptance.

The current evidence covers an ADMET **draft**, basic linear peptide properties, public EGFR/NSCLC evidence, a deterministic small-molecule descriptor execution/download, invalid-SMILES rejection and the corrected diagnostics API. Uploaded hospital-like evidence, full ADMET predictions, docking/redocking, cyclic-peptide design, model training/reload, multi-file comparison, report editing and representative non-drug end-to-end cases remain **NOT RUN in this scoped PR qualification**. That status is a test-coverage statement, not a claim that the platform lacks those capabilities.

For the teammate's online pass, verify the final `/build-info.json` identifier first, then:

1. Sign in with the existing test account and create a fresh synthetic-data project. Refresh it and verify the project survives.
2. Submit the exact ADMET, peptide and target prompts from the preflight source through the chat UI. Compare the visible answer and workflow card against the machine-readable results. Do not launch the ADMET prediction merely to reproduce a routing check.
3. Confirm peptide output is explicitly theoretical/unmodified/linear, with units for molecular weight. Inspect all added interpretations, not just the two expected numbers. The observed instability-index threshold defect is part of the regression checklist.
4. Follow the EGFR Open Targets evidence link and verify the disease/target identity. The score 0.8884 is an association score; public-source evidence and model judgment must remain distinguishable.
5. Run ethanol through the workflow UI, watch Run Manager, refresh during execution and download CSV/JSON through the displayed result links. Check the exact reference values above. The automated source requests AWS Batch, one CPU and 2 GB memory; actual assigned resources must be confirmed from the scheduler if comparing performance.
6. Submit invalid SMILES once. Verify a failed status, a useful user-facing explanation and no fake scientific table. Internal diagnostics may support engineering investigation, but must not appear as an unsolicited raw log dump in the chat answer.
7. Record screenshots, the deployed commit, project/run IDs, artifact hashes and any UI/API discrepancy. Clean up only the synthetic resources created for this pass. Do not use patient data or change scientific thresholds to obtain a pass.

## Scientific fixtures and interpretation

### Small molecules

Use ethanol (`CCO`) for deterministic descriptor checks: molecular weight approximately 46.07 g/mol, three heavy atoms and one hydrogen-bond donor. Include an invalid SMILES string and verify rejection without a plausible-looking result row. Download the table and check numeric types, units and molecule identity rather than checking only the success badge.

For ADMET, use a small named panel with caffeine, aspirin and terfenadine. Verify exact SMILES and molecular identity before running. Terfenadine is a useful cardiotoxicity challenge; the model's declared endpoint and threshold determine its expected gate behavior. Do not require every other compound to pass all models, and do not convert an unexpected prediction into a passing run by overriding a gate. A completed prediction is not an accuracy benchmark. Assess accuracy separately on a held-out labeled panel using the appropriate metric.

Keep endpoint types separate: an hERG classification probability, a derived heuristic IC50 estimate and an experimentally measured IC50 are not interchangeable. Check the deployed model and any transformation before approving units or accuracy claims in the answer/report. The current routing-only ADMET pass does not validate those scientific claims.

For docking, use a real receptor and known ligand with a reference pose. Record receptor preparation, protonation, search box, seed and scoring version. Report redocking pose RMSD only after atom mapping and alignment are defined. A negative docking score alone cannot establish binding affinity or a valid pose.

### Peptides

Use `ACDEFGHIKLMNPQRSTVWY` for a basic sequence-property test. Record terminal groups and any modifications. For cyclic-peptide testing, supply an explicitly defined cyclization chemistry and candidate/reference structure. Check ring closure, stereochemistry, clashes, candidate uniqueness and the score's meaning. Linear-sequence calculations do not qualify the cyclic-peptide modeling chain.

### Target identification

Start with a public EGFR/non-small-cell lung carcinoma evidence query. Separately provide a small synthetic differential-expression or target-score table with declared identifiers and scores. Compare the public-evidence-only result against the combined result, retaining source attribution and weights. Validate identifier mapping, duplicate handling and ranking behavior; do not assert that every familiar oncogene must rank highly irrespective of the supplied evidence.

### Training and adaptation

Use a labeled public/synthetic CSV with a declared feature schema, task, seed and split. For molecular tasks, use scaffold grouping; for patient-like tabular data, keep all rows from a patient/group on one side of the split. Fit preprocessing on training folds only. Save training configuration, data hash, per-fold or held-out metrics and model artifact. Reload the saved artifact and compare inference on a fixed input with the original inference.

Inspect the selected trainer before making a demonstration claim. The current local `chemprop_trainer._train_chemprop` and `chemprop_wrapper._make_chemprop_predict` still raise `NotImplementedError`; that path is not qualified for a Chemprop training demonstration. Other implemented trainers must be tested independently rather than treated as equivalent neural adaptation.

## Reproduce the initial preflight

Run from the frontend directory with the existing shared fixture credentials supplied through the team's secret mechanism:

```bash
BIOMATE_URL=https://dev-public.biomate.ai \
  npx playwright test e2e/dev-online-readiness.e2e.ts \
  --project=chromium --workers=1 --retries=0 --reporter=line --trace=off \
  --output=/private/tmp/biomate-dev-readiness-playwright
```

Use `E2E_FIXTURE_EMAIL`, `E2E_FIXTURE_PASSWORD` and `E2E_TEST_TOKEN` when an override is needed. Never create another test account or register the shared fixture again. Do not store authentication-bearing Playwright traces in the shared evidence folder.

The test asserts exact HTTP/authentication behavior and requires `workflow_ready` plus relevant structured workflow metadata for the ADMET draft. Peptide properties require a successful actual `run_code` result with the declared sequence, molecular weight and pI within tolerance, and no unrelated workflow card. Target identification may return a direct tool result, but must contain EGFR and a successful Open Targets channel to pass the requested public-evidence scenario. Merely mentioning the requested capability in response text cannot satisfy it. It verifies that the isolated project has zero Nextflow execution runs, then removes only the test-created sessions and project. New runs use separate timestamped evidence directories; `DEV_READINESS_CASES` can select named cases for a focused retest. The narrow peptide interpretation regression rejects the observed invented threshold and retains the full response for scientific review; it is not a comprehensive natural-language truth validator.

Repeat actual execution/download/failure checks separately:

```bash
BIOMATE_URL=https://dev-public.biomate.ai \
  node node_modules/@playwright/test/cli.js test e2e/dev-scientific-properties.e2e.ts \
  --project=chromium --workers=1 --retries=0 --reporter=line --trace=off \
  --output=/private/tmp/biomate-dev-scientific-playwright
```

This creates exactly two bounded CPU scientific runs through the existing AWS Batch path, without safety overrides. Each run has an eight-minute polling bound. It downloads real outputs, rejects false green invalid-input completion and requires the diagnostics API to succeed. It cancels only its own active run on timeout and retains the cleanup outcome. Do not restart Galaxy or sync application services while these owned tests are active.

## Configuration checks before execution

Check configuration in the running processes, not only a developer's shell or an example env file. Report presence and effective non-secret settings; never copy secret values into this document.

Use the existing inventory and configuration review rather than building another incompatible env list:

- `docs/20261107_ONPREM_DOCUMENT_CONFIGURATION_REVIEW.md`
- `docs/qa/20261107-onprem-configuration/ENVIRONMENT_PARAMETERS.md`
- `docs/qa/20261107-onprem-configuration/ONPREM_CONFIGURATION_MATRIX.md`
- `docs/qa/20261107-onprem-configuration/environment-inventory.json`

The inventory includes optional and dynamic settings, not a requirement to configure every entry. Record the effective subset for each accepted scenario and map it to the teammate's execution/storage/provider choices.

- Frontend-to-Galaxy connection and authenticated user provisioning.
- Workflow catalogue database, canonical workflow search roots and resolvable file paths.
- Selected executor and queue, region, output bucket/prefix and worker identity.
- Exact image digest and native architecture for each selected workflow.
- Output write access, result read access and presigned download access through the online user path.
- AI provider availability and external evidence-channel authentication where required.
- Effective feature flags for the specific path being demonstrated, including `ML_TRAINING_ROUTING` or composer flags only if that path actually uses them.
- QC profile, endpoint mappings, threshold units and behavior when evaluation is unavailable.
- Persistence for projects, datasets, runs, reports and model artifacts across process restarts.

An `export` run in a one-off `docker exec` shell does not update the environment of existing application workers or persist across container recreation. Change the supported persistent configuration and recreate/reload through the deployment procedure, then verify the application process's effective setting. Do not copy that obsolete activation pattern from older runbooks.

## Fix and retest rules

Read the complete error and trace the selected catalogue record, resolved workflow file, executor and image. Do not diagnose an active workflow by inspecting a similarly named legacy wrapper. Use the user's input and actual run record to reproduce the defect.

Before syncing a fix, review its full diff and complete `docs/PRE_SYNC_CHECKLIST.md`. `scripts/sync_to_dev.sh` synchronizes multiple layers and can change databases and services; it must not be run indiscriminately from this heavily modified shared checkout. Use a reviewed, scoped release state and retain rollback evidence. Do not replace dev's live Galaxy database as part of routine validation.

After deployment, repeat the failed case and its nearest positive/negative regressions. Preserve the original failed evidence and add a new result for the corrected build. Do not edit old test output into a pass.

## Teammate handoff requirements

Mark this document **ready for teammate acceptance** only when the selected release's required dev scenarios pass and remaining exclusions are explicitly named. Supply:

1. Package/release identifier, source commit, image digests and architecture, with the corresponding dev-deployed version.
2. Exact public/synthetic fixtures, hashes, prompts, parameters, QC settings and expected outputs for each accepted scenario.
3. Dev run IDs, final statuses, downloaded scientific artifacts, findings and report links or local evidence paths.
4. Scientific comparisons with tolerances, units and interpretation limits; model metrics must identify their evaluation split.
5. Configuration mapping from dev to on-prem: storage, execution, identity, network/egress, evidence providers, AI providers and feature flags. Values containing secrets go through the team's secret channel, not this handoff.
6. Known failures, unsupported combinations and explicit stop conditions.
7. Rollback and recovery instructions for the identified package, plus the scope of any migrations.

The teammate should first install without customer data, verify health and effective configuration, then repeat the same accepted fixtures through the UI. He should test persistence after restart, output/report downloads, missing credentials, unavailable dependencies, denied access, invalid inputs and a safety halt. Record environmental differences rather than silently changing scientific thresholds or accepting different algorithms to obtain a pass.

## Issue record format

For every failed scenario record: environment and deployed build, timestamp, test ID, project/session/run IDs, input fixture hash, exact reproduction steps, expected result, observed result, severity, root cause, changed files/commit, regression tests, deployed-fix identifier and retest evidence. Include a screenshot when the failure is visible to users. Keep internal diagnostic detail in the restricted engineering record; the user-facing error should describe what failed and the next useful action.
