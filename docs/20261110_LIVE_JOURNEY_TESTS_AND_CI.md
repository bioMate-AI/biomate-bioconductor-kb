# Live journey tests, model canary, and CI honesty (Track E)

Date: 2026-11-10 · Branch: `track/e-livetests` · Base: `integration/unmerged-20261110`

## 1. Why this exists

On 2026-11-10, 263 vitest files (2,655 tests) passed while dev was broken for
real users: the Models panel was dead (every hosted BioNeMo model returned 410),
the chat answer was trapped inside the progress box, a JSONL dataset was shown
as comma-split CSV, and "不用工作流" still forced a workflow. About half of the
vitest files stub the backend; the 118 Playwright files are not run in CI; and
the CI backend step ended in `|| echo "Some tests failed"`.

Measured while doing this work: **the CI backend step had been running zero
tests.** `tests/test_reference_http_cache.py` ran its checks at import time and
ended in a module-level `sys.exit()`, so pytest aborted the whole session with
`INTERNALERROR` (exit 3) during collection. The `|| echo` turned that into a
green check. The frontend job had the same pattern: `npm run lint` does not
exist in `package.json`, and the vitest and build failures were also swallowed.

**Standing rule for every result below:** a journey passes only if the user
outcome actually happened on the deployed stack, such as a real structure,
real numbers, or a produced file. A "completed" badge or HTTP 200 does not
count. A SKIP is not green: the runner counts it as a failure and reports it
separately with its reason. Every run records the deployed commit from
`/build-info.json`.

## 2. Live user journeys — `frontend/e2e/live-journeys.e2e.ts`

The suite runs Playwright against a deployed stack (default
`https://dev-public.biomate.ai`; override with `BIOMATE_URL`). It uses the
real backend and **no route mocking**.

- **Harness discipline (CLAUDE.md):** it logs in once as
  `lifeifei163361@163.com` and creates one project, both in `globalSetup`
  (`e2e/live-journeys.global.ts`). `globalTeardown` deletes the project. The
  harness never calls `/api/auth/register`. Each journey is an independent
  test, so one failure does not skip the others. Login and project creation
  sit in `globalSetup` because a file-level `beforeAll` would run again after
  Playwright restarts a worker following a failure.
- **Password:** taken from `E2E_FIXTURE_PASSWORD`, otherwise from
  `~/.config/biomate/e2e_fixture_password`. It is never committed.
- **Config:** `frontend/playwright.live.config.ts` uses 0 retries, one worker
  and bundled Chromium. Each retry would spend real LLM and GPU budget, and a
  journey that only passes on a retry counts as failing.
- **Fixture:** `frontend/e2e/fixtures/epar_sample.jsonl` is the first 200
  records of `data/glp_study_data/epar_study_tables.jsonl`, with keys
  `source, drug, page, headers, rows`.

| Journey | What the user does | What must actually happen (assertions) |
|---|---|---|
| **d. models** | Runs Boltz-2 and Evo2-7B | **API:** Boltz-2 returns status `completed`, a `.cif`/`.pdb` structure reference, and a pLDDT array whose length equals the sequence length (33). Evo2-7B returns status `completed` and a generated region that starts at the end of the input and has positive length. **UI:** Models → "Run a model" → Structure → runs a real Boltz-2 inference. The test captures the `/api/inference/:id/result` response the page received and requires a per-residue pLDDT; a "completed" badge alone is not enough. If the page has been restructured (another track is rebuilding it), the test falls back to requiring the live catalog to render. |
| **a. dataset** | Uploads the JSONL file and opens it in the data panel | The upload, sent as `application/octet-stream`, is stored as `application/x-ndjson` (the server derives the type from the extension). The preview shows exactly the 5 record columns. The stat grid shows 200 rows, 5 columns and `application/x-ndjson`. The preview shows more than 8 rows, and its pane scrolls to the last row. |
| **e. training** | Plans a tabular classifier from the panel | Probes `POST /api/model-training/plan`. While that route returns 404 the test SKIPs with that reason, and **the runner counts the SKIP as a failure**. Once the route ships, it must accept a real plan over the uploaded file. |
| **b+c. chat** | Attaches the dataset (`/?project=&attachFile=&draft=`) and sends "你可以直接编程统计吗 不用工作流", then reloads the page | **Hard requirements:** a `run_code` tool_event appears in the real `/api/chat/stream` SSE or a run_code block is rendered. No workflow card, chip or panel appears. The answer, read outside `[role=log]`, states the true count of 200 within 120 s. The URL gains `?session=`. After reload, the same session is open and both the question and the answer are still visible. **Soft requirements** (they still fail the run but do not stop step c): a run_code block is rendered in the chat, and the composer is empty after sending. |

Screenshots and the SSE capture go to `frontend/e2e/screenshots/live-journeys/`
(gitignored). The final run's evidence is committed under
`docs/20261110_live_journeys_run/`.

### How to run

```bash
scripts/run_live_journeys.sh                      # against dev; prints a table; exit != 0 on any FAIL/SKIP/NORUN
BIOMATE_URL=https://other.host scripts/run_live_journeys.sh
scripts/run_live_journeys.sh --grep "a\. dataset"   # extra args go to playwright
```

The runner installs Chromium only if Playwright cannot find it. It prints the
deployed commit and a PASS/FAIL/SKIP/NORUN table, and writes
`frontend/e2e/reports/live-journeys-<stamp>.{json,log}`.

**Post-sync hook.** This PR does not edit `scripts/sync_to_dev.sh`, because
another PR changes it. Add this as the last line, after the health check:

```bash
"$REPO_ROOT/scripts/run_live_journeys.sh" || echo "LIVE JOURNEYS FAILED — dev is broken for users"
```

## 3. Live results on dev

LIVE_RESULTS_PLACEHOLDER

## 4. Daily model canary

- `scripts/model_canary.py` uses only the standard library. It logs in as the
  fixture user and runs a tiny real inference on **every** model returned by
  `GET /api/models`:
  - structure models get a 33-residue protein;
  - genomic models get a 27-nt DNA sequence plus 16 tokens;
  - custom/chemical models get two SMILES.
- It checks the payload, not just the status:
  - structure: a structure file plus a per-residue pLDDT;
  - genomic: a generated region;
  - custom/chemical: a non-empty result.
- It prints a table with the backend's **real error**, writes `--json` and the
  GitHub step summary, and exits 1 if any model fails.
- `.github/workflows/model-canary.yml` runs it daily at 13:17 UTC and on
  `workflow_dispatch`, with an optional `only` input. It targets dev and
  uploads `model-canary.json` as an artifact.

**Repository secrets and variables needed:**

| Name | Kind | Required | Purpose |
|---|---|---|---|
| `E2E_FIXTURE_PASSWORD` | secret | yes | password of `lifeifei163361@163.com` on dev (the job fails loudly if missing) |
| `E2E_TEST_TOKEN` | secret | no | dev rate-limit bypass (defaults to the documented dev token) |
| `BIOMATE_DEV_URL` | variable | no | target (default `https://dev-public.biomate.ai`) |

**Canary run on dev, 2026-11-10 18:45 CST (commit 2faa9a9ac2): 2/4 models OK.**

| Model | Status | Real error |
|---|---|---|
| bionemo:boltz2 | **bad_payload** | pLDDT length 1 ≠ sequence length 33. The job "completes", but the per-residue confidence is a single value. A second run got `BioNeMo boltz2 error 429: Too Many Requests`. |
| bionemo:openfold2 | **failed** | `BioNeMo openfold2 error 500 … predict-structure-from-msa-and-template: CUDA error: unspecified launch failure` (upstream NIM) |
| bionemo:evo2_7b | ok | — |
| bionemo:evo2_40b | ok | — |

Boltz-2 is intermittent. Earlier calls in the same session returned a correct
33-value pLDDT, but other calls, including the one the UI made in the final
journey run, returned a single value. The UI then renders "mean 1" with an
empty per-residue chart while showing a green "completed" badge. This is
exactly the kind of false success the founder asked about. The parsing lives
in `backend/lib/galaxy/webapps/galaxy/api/models_inference.py`
(`_bionemo_structure`: `_perres(entry.plddt)` → `_plddt_from_structure` →
`raw.plddt`). The likely cause is a response shape whose structure text
parses to a single B-factor. This is not fixed here because product code is
out of scope for Track E.

## 5. CI honesty — `.github/workflows/ci-tests.yml`

| Before | After |
|---|---|
| `pip install -r requirements.txt \|\| echo "requirements.txt not found"` | Must install. `rdkit==2024.3.5` is installed on top, exactly as `backend/Dockerfile` does, because the SMILES QC gates need it in-process. The test-only dependencies `openapi-spec-validator`, `anthropic` and `openai` are also installed for the offline connector-schema tests. |
| `python -m pytest tests/ -v --tb=short \|\| echo "Some tests failed"` (collection crashed, so 0 tests ran) | `python -m pytest tests/ -v --tb=short` as a **hard gate** |
| `npm run lint \|\| echo` (the script does not exist) | `npx tsc --noEmit -p .` (pre-sync checklist step 1) as a hard gate |
| `npm test -- --passWithNoTests \|\| echo` | `npx vitest run` as a hard gate (checklist step 2) |
| `npm run build \|\| echo "Build failed"` | `npm run build` as a hard gate |
| frontend job timeout 10 min | 30 min (tsc over the whole tree, plus ~260 vitest files, plus the build) |

**Local verification at HEAD:**

- `tsc --noEmit` is clean.
- `vitest run`: 2,645 passed and 3 failed in the sparse worktree. The 3
  failures come from 2 files that read `evaluation/routing_eval/runs/…` and
  `reference/claude_design/…`. Both paths are tracked in git and were simply
  absent from the sparse checkout; with them present, both files pass. The
  full checkout that CI uses has them.
- Backend: see the next section.

### Backend test fixes (stale tests fixed at the root)

| File | Root cause | Fix |
|---|---|---|
| `test_reference_http_cache.py` | Checks ran at import time, ended in a module-level `sys.exit()` (an INTERNALERROR that aborted the whole session), and left `urllib.request.urlopen` patched for every later module | Checks moved into a test function; the patch is restored in `finally`; the script entry point is kept |
| `test_accession_detection.py`, `test_nextflow_false_success.py` | They installed fake `pydantic`, `fastapi` and `galaxy.*` modules in `sys.modules` and never removed them. Every later module then failed with `cannot import name 'ConfigDict' from 'pydantic' (unknown location)` | `sys.modules` is snapshotted and restored around the private executor load. The accession stub was also stale (the executor now imports `fastapi.Request` and `galaxy.ai.runs` / `s3_utils`) |
| `test_qc_e2e_domains.py`, `test_qc_edge_cases.py`, `test_gap3_complete_integration.py` (56 tests) | Since 7668498b4a (2026-05-14) the QC monitor also emits `('chat_progress', …)` narration through the same `sse_callback`, and the tests counted it as a QC event | The capture helpers ignore `chat_progress`; narration is tested in `workflow_ops/tests/test_workflow_chat_narrator.py` |
| `test_qc_e2e_domains.py::TestMonaMetabolomics` (5 tests) | Since 04651dbd08, advisory-only items surface through `qc_warning` rather than `qc_gate_triggered`, and the sibling test already asserts that they do not block | The tests now assert on the `qc_warning` event and its `warnings` |
| `test_nextflow_version_pin.py` | The test asserted `publishDir = null`, which 0dc5a6ac39 (2026-07-20) removed on purpose because it breaks Nextflow 25.10.5 processes that declare publishDir | The test now guards that removal |
| `test_rationale_endpoint_http.py`, `test_workflow_phase_rationale.py` | `sqlite3.connect()` on a missing database path at import time either created a 0-byte database or raised "unable to open database file" and aborted collection | The file is checked before connecting; tests that need data use `requires_workflow_db` |
| `tests/conftest.py` (new) | `backend.lib.*` imports only worked when another module happened to put the repo root on `sys.path` first (order-dependent); live e2e scripts (`e2e_*_test.py`, `e2e_ui/`) were collected as unit tests | The repo root is added to `sys.path`; an explicit `collect_ignore` lists each live script with its reason |

### Strict xfail list (each one reasoned; `strict=True`, so an unexpected pass fails CI)

| Marker / tests | Condition | Reason |
|---|---|---|
| `requires_workflow_db` (`tests/_ci_markers.py`): `test_workflow_retrieval_semantic.py` (158), `test_wired_workflow_search.py` (6), `test_chain_composer.py` (6), `test_ai_assistant_api_citations.py::TestEndToEndWorkflowGeneration` (3), 3 in `test_rationale_endpoint_http.py`, 4 in `test_workflow_phase_rationale.py` | `backend/database/galaxy_ai_tools.db` is absent or empty | The workflow catalog (~330 MB) is not in git, so CI never has it. Verified 2026-11-10: with the real database symlinked in, the chain_composer, citation, wired_search and rationale tests all pass. Note: against that local snapshot, 21 of 158 retrieval-semantic cases fail on ranking quality; that belongs to the routing owner and is visible whenever the database is present. |
| `requires_rscript`: `test_bioc_qc_harness_roundtrip.py` (4) | `Rscript` is not on PATH; the test raises `FileNotFoundError` | R and Bioconductor live in the Batch worker images, not on the CI runner |
| `test_qc_consistency.py` `_needs_threshold_table` (28 tests, including the parametrised profile-registry check where a profile is inferred) | `DEFAULT_THRESHOLDS` / `QC_NAMED_PROFILES` are not exported | The suite targets module-level tables that `qc_trace_monitor.py` never exported (`git log -S` finds no commit defining them). The owner must either export a threshold table or rewrite the suite against `_get_threshold()`. |
| `test_qc_consistency.py` `_profile_mapping_drift` (8 tests) | always | The `infer_qc_profile()` path→profile mapping changed after these expectations were written (for example, FFPE paths now map to `wgs_somatic_tumor_only` instead of `wgs_ffpe`, and metagenomics paths now map to `metagenomics_human_gut` instead of `None`). Whether to update the expectations or restore the mapping is a QC-owner decision. |
| `test_qc_evidence.py` `_compound_grade` (2 tests) | always | `admet_herg_ic50` provenance is the compound value `'GOLD-metric / SILVER-tier'`, which is outside the GOLD/SILVER/BRONZE contract that consumers expect |

BACKEND_RESULT_PLACEHOLDER

## 6. Files

- `frontend/e2e/live-journeys.e2e.ts`, `live-journeys.global.ts`,
  `live-journeys.setup.ts`, `live-journeys.teardown.ts`,
  `fixtures/epar_sample.jsonl`
- `frontend/playwright.live.config.ts`
- `scripts/run_live_journeys.sh`, `scripts/model_canary.py`
- `.github/workflows/model-canary.yml`, `.github/workflows/ci-tests.yml`
- `backend/tests/conftest.py`, `backend/tests/_ci_markers.py`, plus the test
  fixes listed above
- `docs/20261110_live_journeys_run/`: the final run's JSON report, log,
  screenshots and answer text

## 7. Open issues found (product; not fixed here, owners noted)

1. **The chat drops the run_code block on the final message** (chat UI). The
   SSE stream carries `tool_event` run_code call and result events, and the
   blocks render while streaming, then disappear when the final payload
   replaces the placeholder. `chat-interface.tsx` builds the final
   `aiMessage.metadata` (around line 1221) without `data.toolBlocks`, although
   `finalPayload.toolBlocks` is set at line 984.
2. **The composer keeps the sent question after sending** when the message
   was pre-filled through `?draft=` (chat UI).
3. **Boltz-2 pLDDT is sometimes a single value, and the UI shows a green
   "completed" with "mean 1" and an empty chart** (Models). OpenFold2 fails
   with an upstream CUDA error. NVIDIA's hosted API sometimes returns 429.
   See §4.
4. **Answer accuracy varies:** the record count (200) was right in every run,
   but one run reported "涵盖药物：25 种" when the true distinct-drug count is
   24, and another described the dataset as a single drug. Accuracy beyond the
   record count is not asserted yet; consider asserting a second, unambiguous
   statistic.
5. `POST /api/model-training/plan` is not deployed (404), so journey e cannot
   pass yet.
