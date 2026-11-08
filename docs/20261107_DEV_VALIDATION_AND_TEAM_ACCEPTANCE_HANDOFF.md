# Dev validation and team acceptance handoff

## Release decision

**Status: validation in progress; not yet ready for teammate acceptance.** Dev is the first acceptance environment because prospective users will try the online platform before installation. The teammate owns final packaged on-prem installation and scientific acceptance on that installation. Dev validation must establish a working user journey before that handoff.

Target: https://dev-public.biomate.ai. Initial checks were performed on November 7, 2026, America/Chicago; evidence timestamps use UTC and may show November 8.

Do not interpret a healthy API, successful image build, catalogue entry, generated workflow card, or completed Batch process as proof of scientific correctness. Each establishes a different part of the acceptance chain.

## Current evidence

The first live checks confirmed HTTP 200 for the online workbench, successful login with the existing shared fixture, authenticated project-list and account APIs, and `/api/health` reporting API and AI `ok` and Galaxy connected. The authenticated browser rendered the four workbench entry points: Search & evidence, Data analysis, Molecule design & generate, and Models.

The reproducible consolidated preflight is `frontend/e2e/dev-online-readiness.e2e.ts`. It uses one login, one temporary project, real APIs, and the same strict SSE response parser used by the connector. It never clicks Confirm & Run and does not dispatch compute. Its evidence is written to `docs/qa/20261107-dev-online-readiness/`:

- `preflight-results.json`: individual verdicts, timestamps, routing metadata and cleanup results.
- `authenticated-workbench.png`: browser capture, reviewed visually.

This preflight checks authentication boundaries and three drug-development draft requests. Execution, output downloads, QC and scientific accuracy require the additional tests below. The final readiness decision remains withheld until those tests are recorded.

The local checkout contains extensive changes from several work streams. The active branch name or local HEAD must not be presented as the deployed version. Before a code fix is synced, record the actual deployed commit or artifact identifier and the exact changed files. No application deployment has been performed as part of this dev preflight.

### First dev run and corrective work

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

Local corrective changes, **not deployed**:

- The protein-folding fast path now requires explicit structure/folding intent or a bare sequence. Property calculations, annotation, alignment, immunogenicity and fold-change requests no longer select folding solely because a sequence is present. English and Chinese controls are covered. All 21 focused routing tests pass; restoring the old method makes all eight new nonstructural cases fail.
- Target result headings distinguish incomplete evidence, reasoning-only hypotheses and missing provenance. Failed channels are not listed as successful, and a failed primary channel cannot be claimed as the ordering source. The reply offers a source-retrieval/retry step without printing internal exception details. The scientific-tool and strict SSE parser suites pass all 23 tests.
- Review of the canonical physicochemical workflow found mislabeled molar refractivity, unsupported logD7.4 substitution, invalid SMILES marked successful and an undeclared scientific CSV output. The local patch labels molar refractivity correctly, supplies named QED separately, removes unsupported ionization claims, fails invalid inputs at the wrapper boundary and exposes the CSV output. Four tests execute the exact embedded Python body with RDKit, including ethanol reference values and invalid/empty inputs. These pass locally. Restoring the old workflow makes all four test methods fail (five assertion failures across subcases and one missing-QED error), confirming that the tests reject the previous output. Nextflow execution and online artifact delivery are still NOT RUN.

The full frontend regression suite passed **2,287 tests**, with **32 skipped** across 206 passing and three skipped files. TypeScript checking passed. The first restricted suite attempt could not bind loopback HTTP servers (`EPERM`); the complete passing rerun had loopback permission. The local Anaconda Python 3.9 import failed inside its installed SciPy stack (`scipy.interpolate._fitpack_impl`, `TypeError`), before application import completed.

To test compatibility without altering dev, the reviewed method was substituted into the deployed module **in memory**. Its complete candidate source hash matched the local file exactly (`d786878b46ed588710f7c63e228954074133a96141a1956c9de0b957e6208a9d`). The full candidate module imported successfully under dev's **Python 3.9.25**, and seven nonstructural/design controls plus five folding controls passed. SSM command: `17dc951b-cee0-4c6f-8501-905a34f386c3`. No deployed file, worker or service changed. This closes the Python compatibility check, not deployment or live chat retesting.

A direct source diagnostic also established that dev can retrieve real Open Targets disease associations with the platform's existing association query. A separate exploratory name-search diagnostic initially used the wrong GraphQL argument (`query` rather than `queryString`); the full HTTP 400 body identified that diagnostic mistake. It is not evidence of a broken association-query implementation. The EGFR/NSCLC chat source failures remain a separate issue until their input and complete channel errors are diagnosed.

The corrected public name lookup resolved non-small cell lung carcinoma to `MONDO_0005233`. Calling the existing dev target handler with that verified ID, EGFR and `use_llm=False` returned both `genetics_ot` and `ppi_string`, no channel errors, primary-channel Open Targets ordering, and EGFR score **0.8884** with two-channel corroboration. Its source links resolve to the Open Targets EGFR/NSCLC evidence page and STRING network. SSM command: `18a64a2f-11b7-4104-b3eb-47f4204b37df`. This establishes that the underlying evidence channels can work from dev; it does **not** repair or pass the failed online chat journey. The score is an association score, not a clinical probability.

The focused chat diagnosis subsequently captured the actual tool request and complete channel errors in `run-1794110341921/preflight-results.json`. The model supplied **`EFO_0003838`**, which Open Targets reported did not resolve. STRING then reported **`no seed_genes in context`**. This is an identifier/routing failure with a downstream consequence, not a demonstrated credentials failure.

The local corrective path now accepts the user's full disease name in `identify_targets`, resolves it against Open Targets and retains resolution provenance. Only one exact normalized name match is accepted; the first loosely matching search hit is never selected automatically. Conflicting name/ID inputs require correction. Offline mode never makes a name-lookup network call. The frontend boundary rejects unresolved-ID results with a retry instruction instead of treating AI-only fallback as a successful evidence-backed answer. Five resolver tests and the 21 routing tests pass together; the scientific-tool/parser suites now pass 24 tests. All 12 target-handler regression tests also pass in an isolated Python 3.12 test environment. The two new handler regressions separately pass against the exact reviewed functions in dev's Python 3.9.25 process, in memory, without changing services (SSM `24c5fbab-94ec-40b9-9fcc-da0b4a9c49d2`). The route-test event-loop helper was changed to `asyncio.run` so its loops are closed after each case.

The latest-code full frontend rerun initially terminated with SIGSEGV rather than a test verdict; the log contained no failed assertion. The macOS diagnostic report identifies `npm exec vitest run` terminating with that signal. This attempt is not a pass. The subsequent direct Vitest run with bounded workers completed successfully: **2,288 passed, 32 skipped**, 206 passing files and three skipped files, in 73.68 seconds. TypeScript checking also passed. This is local regression evidence; deployment and live verification remain outstanding.

**Next gate:** diagnose the source failures, deploy only reviewed fixes, repeat the failed online cases, then execute and download the selected scientific fixtures. Do not hand the package to the teammate as scientifically qualified at this stage.

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

## Scientific fixtures and interpretation

### Small molecules

Use ethanol (`CCO`) for deterministic descriptor checks: molecular weight approximately 46.07 g/mol, three heavy atoms and one hydrogen-bond donor. Include an invalid SMILES string and verify rejection without a plausible-looking result row. Download the table and check numeric types, units and molecule identity rather than checking only the success badge.

For ADMET, use a small named panel with caffeine, aspirin and terfenadine. Verify exact SMILES and molecular identity before running. Terfenadine is a useful cardiotoxicity challenge; the model's declared endpoint and threshold determine its expected gate behavior. Do not require every other compound to pass all models, and do not convert an unexpected prediction into a passing run by overriding a gate. A completed prediction is not an accuracy benchmark. Assess accuracy separately on a held-out labeled panel using the appropriate metric.

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

The test asserts exact HTTP/authentication behavior and requires `workflow_ready` plus relevant structured workflow metadata for positive draft cases. Target identification may return a direct tool result, but must contain EGFR and a successful Open Targets channel to pass the requested public-evidence scenario. Merely mentioning ADMET, peptide or target identification in response text cannot satisfy it. It verifies that the isolated project has zero execution runs after draft generation, then removes only the test-created sessions and project. New runs use separate timestamped evidence directories; `DEV_READINESS_CASES` can select named cases for a focused retest.

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
