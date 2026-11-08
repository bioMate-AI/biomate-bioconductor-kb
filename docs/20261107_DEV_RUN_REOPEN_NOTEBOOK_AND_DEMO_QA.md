# Dev run reopening, notebook staging and demo readiness QA — 2026-11-07

## Live observations versus prepared repairs

Live checks against dev build `6c5a7eddd4cc5c2c6ec43e9699a7f8fa1bb7b082` confirmed:

- Run Manager inventory was retained: `/api/workflows/runs/overview` returned **100 rows, total 765**. The smoke harness incorrectly inspected `runs` instead of the actual `rows` property. Its zero-count failure was a harness error; corrected locally.
- Saved completed run `cb7a1b63-28a0-41ea-9074-9a3f33fd64f2` has `projectId=null`, no saved chat ID and a workflow definition. Showing the active QA project's name in its workflow panel was incorrect.
- Opening the owned synthetic `qa_counts.csv` in Jupyter returned HTTP 500 wrapping Galaxy HTTP 400 after 2.64 seconds. Tool availability reported Jupyter installed; this was not proof that file staging worked.
- Galaxy's current history-content API copies existing datasets and does not accept the old `{type:'file',source:'url'}` upload payload. `GalaxyAPIProxy.uploadFromUrl` still used that invalid protocol. The prepared repair uses `POST /api/tools`, `tool_id=upload1`, URL-paste inputs and the same per-user API client. Signed download URLs are no longer logged. No claim of a successful deployed notebook launch is made yet.

Prepared follow-up UI repairs use the persisted run's project identity and matching project name, omit unknown/unfiled identities, replace the selected workflow on manual run switch and collapse the Run Manager so its list cannot consume the workflow's usable height. A reopened list is bounded to 40vh with internal scrolling. “Current chat” with no saved chat ID now yields no records rather than silently querying all chats; All chats remains explicitly available and is the default when no preference exists. Pending AI-summary wording distinguishes missing summary data from workflow execution status.

## Focused validation

- Galaxy URL upload/request identity, key recovery and notebook route contract: **3 suites, 19 tests passed**. Tests bind local HTTP servers; the unprivileged sandbox's socket EPERM was retried with approved local socket access, not worked around in production code.
- Run identity/scope and AI-summary copy: **2 suites, 20 tests passed**.
- Cold-start catalog/preparation/dashboard: **3 suites, 194 tests passed** against current served assets.
- Earlier read-only After-run saved-data contract audit: **48 pass, 0 fail, 4 skip**. Skips are absent historical chat IDs, not successful chat restoration checks.

The final deployment must carry the reviewed follow-up commit before these source changes can be described as live. Full regression/type/build checks and browser verification are controlled by the parent release task.

## Every visible cold-start entry: structural coverage

The current exported dashboard/domain catalog contains **97 distinct example seeds** across all tracks and modality variants:

| Category | Count | Prepared context |
|---|---:|---|
| Catalog-mapped analysis/design/training examples | 74 | Explicit per-intent bundles; no arbitrary fallback data |
| Catalog-mapped public search examples | 9 | Named targets/series and provenance context; an experimental dataset is not required to ask a literature/database question |
| Prepared examples with attached files | 4 | MG differential expression, synthetic survival, recovered synthetic hospital integration and subtype prediction |
| Prepared examples using explicit workflow built-in defaults | 8 | Listed below; self-contained input/default requests, not invented uploaded datasets |
| Internal project examples | 2 | Create/reuse a real MG tutorial project and upload its inputs |
| **Total** | **97** | **Zero unmapped displayed seeds** |

The 83 catalog-mapped entries use 30 explicit bundles referencing **61 unique catalog assets**, plus `demo_notes.md`. Served MG and recovered hospital inputs are independently checked by the asset suite; all historical synthetic cohort CSV hashes match their provenance manifest. Four displayed examples establish dedicated project context: two Internal MG queries and two recovered hospital examples. Historical outputs are not imported as new results.

Eight built-in/default examples: human cachexia metabolomics; EBV antibody titers; flow cytometry immunophenotyping; CAR-T construct design; CTCF ChIP-seq peak calling; histology nuclei segmentation; ATAC-seq accessibility; proteomics pull-down QC. The suite asserts each explicitly requests existing built-in demo/default inputs (CAR-T is a self-contained in-silico design). This audit does **not** newly execute or establish current remote availability of all eight workflow defaults, and asset mapping is not a scientific execution pass.

No displayed entry is structurally unsupported by the source mapping. Actual workflow routing, prerequisites, external downloads and compute remain execution acceptance checks. Cryo-EM examples explicitly identify remote/staged map/movie inputs; their small manifests are provenance, not substitutes for those bytes.

## Predicted follow-up smoke results

1. Run Manager All chats retains saved records. Current chat on an unsaved chat returns zero; switching to All chats restores account history.
2. Selecting the historical unfiled run opens its actual completed workflow without the QA project label; Manager collapses and the workflow retains usable height.
3. AI summary pending is labeled unavailable/loading precisely, never as a restarted workflow.
4. Notebook staging should now reach Galaxy's upload1 endpoint and return an actual uploaded dataset ID. A subsequent notebook launch must still be verified for asynchronous dataset readiness, job dispatch and a real correlated access URL. A later failure is not to be suppressed or reported as success.
5. Cold-start hospital examples download their exact original synthetic inputs, prepare the dedicated demo project and a draft, with no automatic workflow execution. Changed existing fixture inputs stop setup instead of being overwritten.

Evidence logs and redacted counts: `/tmp/biomate-hospital-audit/probe-runs-jupyter.log`, `run-project-identity.log`, `cold-start-entry-counts.json`; local focused logs `/tmp/galaxy-url-import-tests.log`, `/tmp/run-manager-identity-tests.log`, `/tmp/cold-start-final-audit-tests.log`.
