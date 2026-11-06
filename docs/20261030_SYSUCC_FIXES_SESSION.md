# 2026-10-30 — SYSUCC demo fixes: sandbox outputs, assay/report fidelity, learning loop, model versioning

Follows `docs/20261029_SYSUCC_USECASE_TEST_RESULTS.md` and
`docs/20261029_SYSUCC_DRUG_DEVELOPMENT_DEMO_PLAN.md`. Three agents worked in the
same tree: (A) sandbox output ownership, (B) assay/report fidelity, (C) the
experimental learning loop plus durable model versioning. Nothing is committed,
pushed or synced to dev. Unrelated uncommitted changes in the tree (manuscript
docs, e2e reports, skill loader, …) are not part of this work.

## Files changed (from `git diff --stat` + untracked)

Modified:

| File | Area |
|---|---|
| `frontend/server/code-runner.ts` | A |
| `backend/lib/galaxy/ai/drug_discovery/assay_schema.py` | B |
| `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py` | B, C (score/coverage contract constants) |
| `backend/lib/galaxy/ai/drug_discovery/wetlab_report_ingester.py` | B |
| `backend/lib/galaxy/ai/drug_discovery/study_report_ingester.py` | B |
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | B |
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | B (ingest warnings, `glp` optional), C (propose/retrain/models/versions) |
| `backend/lib/galaxy/ai/drug_discovery/auto_retrain.py` | C |
| `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py` | C |
| `backend/lib/galaxy/ai/drug_discovery/custom_model_registry.py` | C (rewritten: versioned registry) |
| `backend/lib/galaxy/ai/drug_discovery/custom_model_wrapper.py` | C (Docker `command`) |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_training_worker.py` | C |
| `backend/lib/galaxy/ai/ml_training/{training_job,chemprop_trainer,config,ludwig_adapter,ludwig_trainer,llm_trainer,trl_trainer}.py` | C |
| `backend/lib/galaxy/webapps/galaxy/api/models_inference.py` | C (shared registry, active-version dispatch) |
| Tests: `drug_discovery/tests/test_training_worker.py`, `test_regulatory_pair_recorder.py`, `ml_training/tests/test_ludwig_adapter.py`, `test_training_job.py`, `test_real_sklearn_e2e.py` | C |

New:

| File | Area |
|---|---|
| `frontend/server/code-runner-output-dir.test.ts` | A |
| `backend/lib/galaxy/ai/drug_discovery/evidence_provenance.py` | B |
| `backend/lib/galaxy/ai/drug_discovery/tests/test_assay_report_fidelity.py` | B |
| `backend/lib/galaxy/ai/ml_training/splits.py` | C |
| `backend/lib/galaxy/ai/drug_discovery/tests/test_campaign_learning_loop.py` | C |
| `backend/lib/galaxy/ai/drug_discovery/tests/test_model_versioning.py` | C |
| `backend/lib/galaxy/ai/drug_discovery/tests/test_model_versions_api.py` | C |
| `backend/lib/galaxy/ai/ml_training/tests/test_gate_and_split_contracts.py` | C |

## A. Sandbox output ownership (`code-runner.ts`)

- The run's `output/` directory is created by `prepareSandboxOutputDir` and
  chowned to the sandbox identity, so non-root sandbox code can write the
  artifacts users download. Inputs and the script stay owned by the server.
  If the server cannot hand the directory over, the run fails early with an
  actionable error instead of a `PermissionError` inside the sandbox.
- `resolveSandboxIdentity` keeps the rule that user code never runs as root.
- Output scanning uses `lstat` and previews with `O_NOFOLLOW`, so symlinks
  planted by sandbox code are not followed.
- Tests: `code-runner-output-dir.test.ts` → 9 passed, 1 skipped (root-only case).

## B. Assay and report fidelity

- `assay_schema.py`:
  - Each endpoint has a physical-range rule, so negative IC50/Kd and other
    impossible values are rejected.
  - RDKit canonical-structure identity checks reject a compound ID that maps
    to different structures, both within one file and against previously
    ingested rows in the same campaign. Unparseable SMILES are rejected.
- `assay_ingestion.py`:
  - Every ranked compound carries `coverage_status`, `measured_objectives` and
    `missing_objectives`.
  - Incomplete compounds rank after complete ones, and `ingest()` returns a
    warning for each.
- `evidence_provenance.py` is a new shared module that detects species,
  tri-state GLP status and "prediction only" text.
  - `wetlab_report_ingester.py`:
    - Species is extracted rather than defaulted to human.
    - Cmax and AUCinf are wired through text ingestion.
    - Prediction-only text is not recorded as measured.
    - GLP status is not assumed.
  - `study_report_ingester.py`:
    - The PDF extractor rejects prediction-only documents.
    - GLP status is tri-state.
- `ind_assembly.py`:
  - Structured wet-lab input keeps its provenance.
  - Ames/DILI are reported only when they were measured.
  - Narrative text states "not stated in the report" instead of inventing a
    species, route or GLP status.
- `api_router.py`: ingest responses carry `warnings`, and `glp` is `Optional[bool]`.
- Tests: `test_assay_report_fidelity.py` → 38 passed.

## C. Experimental learning loop (agent C)

1. **Score binding.** `auto_retrain.refit_and_propose()` read `composite_score`
   with a 0.5 default, but ranking emits `combined_score`. The constant labels
   normalized to zero, so the surrogate learned nothing. `api_router` propose
   had the same bug.
   - `RANKED_SCORE_KEY` and the coverage constants are now exported by
     `assay_ingestion.py` and imported by `auto_retrain`.
   - `build_training_rows()` is the single mapper. It skips rows that are
     not fully evaluated (`coverage_status != complete`, missing objectives
     listed) or that lack SMILES or a finite score. Skipped rows are listed in
     a `training_report`, which is persisted with every proposal and returned
     by the API. Fewer than 2 usable rows raises `CampaignDataError` (HTTP 422).
   - Partial scores are never used as labels.
   - `_format_proposal` reads objective-keyed scores; before this, the UI
     showed 0.0 for every score.
2. **Round numbers.**
   - `bo_proposals` is the single ledger. `save_proposal` allocates
     MAX+1 inside a `BEGIN IMMEDIATE` transaction.
   - `persist_round()` writes `bo_proposals` and `auto_proposals` in the same
     transaction.
   - Legacy rounds are backfilled without renumbering history, and the propose
     endpoint now persists its rounds.
3. **Fail-closed gates.**
   - `_evaluate_gate` fails with a stated reason when a configured metric is
     missing, non-numeric, NaN or infinite.
   - A non-finite threshold is a config error.
   - The gate payload sent to the UI never carries `inf`.
4. **Split contract.**
   - `splits.py` implements a real Bemis–Murcko scaffold split: group-wise,
     seeded, sizes approximated (Chemprop-balanced scheme). The sklearn
     baseline uses it and records the method and partition sizes.
   - Ludwig tabular uses a precomputed `fixed` partition column.
   - LLM configs reject scaffold split, and TRL records `none_all_rows_train`.
5. **Stubbed training.**
   - `_train_chemprop` raises `NotImplementedError` whether or not
     chemprop is installed.
   - `post_train_lora` jobs end `failed` with a `not_implemented` message and
     no adapter path. Research cyclic-peptide paths are untouched.

## C. Durable model versioning (`custom_model_registry.py`)

**Immutable versions** (table `custom_model_versions` in the campaign SQLite DB):
- Every registration of (campaign, name) creates version N+1. Each version
  records:
  - status
  - artifact directory, keyed by version (`<root>/<campaign>/<model>/v0003-<id>/`,
    which must not already exist)
  - artifact SHA-256 over the directory tree
  - training dataset hash, plus the canonical training SMILES for the
    holdout-overlap check
  - split metadata, metrics, gate result and model spec
  - parent version, `created_at`/`created_by`, and status-change actor/note
- Every transition is written to `custom_model_version_events`.
- `run_training_job` reserves the version before training. A training failure
  marks it `rejected` (`training_failed: …`). A passed gate gives `candidate`;
  a failed or missing-metric gate gives `rejected`. Runs without a registry get
  a unique run directory, so no run overwrites an earlier artifact.

**Promotion states:** pending, candidate, active, rejected, retired.
- A partial unique index enforces at most one `active` version per model.
- Promotion requires:
  - a passed gate
  - candidate or retired status
  - a named reviewer
  - a re-verified artifact hash
- On promotion the previous active version becomes `retired`.
- `rollback` re-activates a retired version (default: the most recently retired).
- `reject` records the reviewer's decision.

**Persistence and reload:**
- A fresh registry instance (simulated restart) lists versions from the DB and
  lazily loads the exact active artifact.
- The artifact is re-hashed on every load. On mismatch the registry raises
  `ArtifactIntegrityError` (HTTP 409) and refuses to serve.
- REST and Docker versions are rebuilt from their persisted spec.
- In-process Python-function wrappers cannot be rebuilt after a restart; this
  is reported explicitly.
- `get_registry(db_path)` provides one registry per DB per process.
  `api_router` and `models_inference` previously built a new registry on every
  request, so `/models/{name}/run` could never find a model registered in an
  earlier request.
- The `custom_model_registrations` summary row (used by the Models catalog)
  now carries `active_version`. Run-log rows record `model_version`.

**Comparison:** `compare_versions(v_a, v_b, holdout)` scores both
hash-verified versions on the same holdout:
- Identical metrics are computed for both: classification gives n, n_scored,
  accuracy and AUC; regression gives MAE, RMSE and R².
- It refuses a holdout that overlaps either version's training molecules,
  unless explicitly allowed (then the overlap is reported).
- The holdout hash and metrics are stored in `custom_model_comparisons`.

**API** (`/api/drug-discovery/{campaign_id}/models/{name}`):
- `GET /versions` and `GET /versions/{v}`
- `POST /versions/{v}/promote` and `POST /versions/{v}/reject`; body
  `{reviewer, note}`, and the caller identity from the audit log is recorded
  alongside the reviewer
- `POST /rollback` with body `{reviewer, to_version?}`
- `POST /compare` with body `{version_a, version_b, holdout: [{smiles, label}]}`
- `GET /comparisons`

**Also fixed in the same area:**
- `POST /models/register` passed the wrong keyword arguments to the REST and
  Docker wrappers (`input_field`, `output_field`, `timeout_s`, `command`), so
  registration returned 500 for both modes. It now maps them correctly.
  `DockerModelWrapper` gained the `command` argument.
- `trigger_retrain_now` read `proposal.items`, which doesn't exist, and the
  error was swallowed. The ADMET follow-up it tried to start targeted a
  nonexistent `/api/nextflow/run` endpoint, an unused `NEXTFLOW_EXECUTOR_PORT`
  and a nonexistent `admet_screening` workflow id, so it could never have run.
  The dead code is removed. The response now carries an explicit
  `admet_followup: {submitted: false, reason, proposed_smiles}`.
- There were two `POST /{campaign_id}/retrain` registrations. The frontend calls
  only `/retrain/trigger|status|start|stop`, and FastAPI served the first
  registration, so the shadowed `trigger_retrain_post_legacy` was removed.

## Test results (2026-10-30)

| Suite | Result |
|---|---|
| `scripts/test_sysucc_usecases.py --output /tmp/…` | **29/29 passed** (baseline before fixes: 18 passed, 11 failed). Case 3: labels respond to the new assay batch, rounds [1, 2], missing/inf AUC gates fail, 0.8 passes, 0.6 fails. |
| `drug_discovery/tests/test_model_versioning.py` | 13 passed: v1/v2 immutability, restart reload of the exact artifact, hash mismatch refused, promotion blocked on failed and missing-metric gates, reviewer required, rollback to v1, one active version enforced by the DB, compare on the same untouched holdout, overlap refused, REST version survives restart |
| `drug_discovery/tests/test_model_versions_api.py` | 5 passed (FastAPI `TestClient`) |
| `test_campaign_learning_loop.py` | 12 passed (with fastapi) |
| `test_assay_report_fidelity.py`, `test_training_worker.py`, `test_regulatory_pair_recorder.py` | all passed |
| `ml_training/tests` (all) | 158 passed, 2 skipped (Ludwig not installed) |
| `drug_discovery/tests` (whole directory) | 222 passed, 1 skipped, 8 failed. All 8 failures pre-existing and unrelated: `test_autoloop_wrapper` fakes don't accept `org_id` (`ind_autoloop.py` unmodified since June); PDF/DOCX tests need `reportlab`/`python-docx` |
| `test_phase3_autoretrain_ind.py` (script) | 76/76 |
| `backend/test_dd_modules.py` | PASS |
| `frontend/server/code-runner-output-dir.test.ts` | 9 passed, 1 skipped |
| Module imports | OK under Python 3.14 except `models_inference`, which needs the Galaxy webapp dependency `a2wsgi` (not installed locally). Under anaconda `python3.9`, every import fails inside its broken scipy (environmental); all changed files compile under 3.9. |

**Test environment:**
- API tests ran in a throwaway venv (`/tmp/biomate_api_venv`: system
  site-packages plus fastapi, httpx and python-multipart).
- Other Python tests ran under `/opt/homebrew/bin/python3` 3.14 (RDKit 2026.03,
  sklearn 1.9).
- The pre-sync checklist has not been run: no full `tsc` and no full `vitest`.

## Remaining gaps

**IND assembly and data handling:**
- **Species in the IND narrative.** Ingestion now records rat vs human, but
  the IND MRSD/PK narrative does not yet consume the extracted species when
  choosing allometric scaling or species wording.
- **Benchling column mismatch.** `BenchlingConnector` emits `assay_name`,
  `assay_value` and `created_at`. The assay validator requires `assay_type`,
  `value` and `assay_date`. LIMS-polled rows therefore do not match the CSV
  ingestion contract.
- **Censored values.** `operator` (`<`, `>`) is stored but not modelled;
  censored values are treated as exact in ranking and labels.
- **Salt forms and parents.** Identity checks compare canonical structures, so
  a salt and its parent free base are treated as different compounds, and no
  salt stripping or parent mapping is done.

**Learning loop and model platform:**
- **Ludwig split.** The `fixed`-partition scaffold split has not been run
  against real Ludwig, which isn't installed locally.
- **ADMET follow-up.** ADMET screening of proposals is not automated. It needs
  a real indexed ADMET workflow with its parameter mapping and the requesting
  user's identity for billing.
- **Candidate discrimination.** On the small fixture, both proposed candidates
  get the same predicted score (the GP reverts to its prior mean for distant
  structures). The scores respond to new data, but they don't rank one
  candidate above the other.
- **Reload limits.**
  - Python-function models cannot be reloaded after a restart.
  - Artifacts are re-hashed on every load, which is fine for small molecular
    models but would be costly for large LLM artifacts.
  - Comparison metrics are computed in-process. They are not yet linked to
    MLflow runs or shown in the UI.
- **No UI for the version lifecycle.** The frontend has no UI for promote,
  rollback or compare; only the API exists.

**API cleanup:**
- `GET /{campaign_id}/retrain` still triggers a retrain. A GET with side
  effects is kept only for backward compatibility.

**Deployment:**
- **Not synced to dev.** Before running `scripts/sync_to_dev.sh`:
  1. Run the full `docs/PRE_SYNC_CHECKLIST.md`: `tsc --noEmit`, the full
     `vitest` suite, and the Python module-load checks inside the Galaxy
     container.
  2. Commit.
  3. Sync.

  Then verify live on dev with the fixture account:
  - A `run_code` artifact is written and downloadable as the non-root sandbox
    user.
  - Assay ingest rejects negative IC50 and identity conflicts, and warns on
    incomplete compounds.
  - Retrain twice gives rounds N and N+1, the scores change after the safety
    batch, and the `training_report` lists the excluded compounds.
  - Train v1 and v2, promote v1, restart the `biomate-galaxy-dev` container,
    then `/models/{name}/run` serves v1 with a verified hash. Compare v1 vs v2
    on a held-out set, promote v2, roll back to v1.
  - Study-report upload keeps species and GLP status as stated, and prediction-only text is rejected.
  - Run `python3 scripts/test_sysucc_usecases.py --live` against the exact
    deployed build.

## Dev deployment and live verification (2026-10-30 evening)

- Committed as `400aeffb7` with only the files listed above, plus the SYSUCC docs and use-case runner.
- Unrelated uncommitted work was set aside for the sync and restored afterwards, unchanged. That work is the private-skills access change: `routes.ts`, `auth-middleware.ts`, `galaxy-assistant.ts`, `scientific-chat-tools*.ts`, `skill-access*.ts`, `optional-auth-mfa-boundary.test.ts`, `skill_manager.py`, `skill_loader.py` and `ai_assistant.py`, plus three untracked `target_id/bench_*.py` scripts. None of it was deployed.
- Pre-sync checks on the exact deploy state passed. `tsc` was clean, and `vitest` passed 1,986 tests with 0 failures. An AST scan of the changed Python files found no Python 3.9-incompatible annotations.
- `scripts/sync_to_dev.sh` deployed `b6ca37fc → 400aeffb`:
  - The frontend container was rebuilt, and the public build was verified as `400aeffb7`.
  - The backend Python was hot-patched, gunicorn restarted, and Galaxy came back healthy.
  - The database was already identical on dev, so it was not transferred.
  - Post-sync smoke tests (workflow generation, DB-search routing, connector contract) passed. Result: healthy.
- Live use-case suite against dev: **31 passed, 1 failed**, up from 19 passed and 13 failed on 2026-10-29. Report: `/tmp/sysucc_live_after_sync.json`.
  - `live_comparison_artifact` now **passes**: `candidate_comparison.csv` is written (93 bytes, correct rows, B selected).
  - `live_r_pknca_numerical_result` is still failing as expected. PKNCA is not installed in the generic R code-runner. The indexed PKNCA workflow runs in its own container and remains untested on dev.
- Not yet verified on dev:
  - the authenticated model-versioning journey (train v1 and v2, restart the container, confirm the exact active artifact reloads with hash verification, then compare, promote and roll back);
  - the campaign retrain through the public API.

  Both need the shared fixture credential (`E2E_FIXTURE_PASSWORD`), which is unset.
