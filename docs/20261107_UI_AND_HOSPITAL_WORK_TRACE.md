# UI and hospital work trace — 2026-11-07

Read-only investigation; no deployment or feature removal performed in this trace.

## Deployment
Public dev build-info read on November 7 reports `20f159a1cb794b8222ad2f923ae192270d9ee64c`.
PR #328 (`codex/zh-en-ui-parity`) is separate and not deployed. Build identity alone does not establish runtime asset or database parity.

## Confirmed navigation reversals
- `f16903d38` placed Import workflow and Connectors under Settings.
- `e548d3805` restored top-level Workflows on October 14, explicitly treating the Settings placement as a design gap. This conflicts with the user's explicit navigation decision.
- `fc4af4823` on November 1 explicitly moved Connectors into workspace navigation and Import workflow into More tools.
- Current sidebar renders More tools and both the Settings navigation entry and footer Settings icon. This is a source-level regression, not solely a stale deployment explanation.

## Existing implementations retained
- Models: `frontend/client/src/components/models/models-panel.tsx`, routed from `/models` in App.tsx. Five tracks, real read hooks and adaptation mutations exist. Route currently supplies no explicit project prop; project/context behavior needs functional audit before concluding why users see empty content.
- Instructions: `ProjectInstructionsPage` in project-guidance-cards.tsx is mounted by project-detail.tsx. Rules, output formats, skills & experts, and memory exist. Recent output-format and instruction-count fixes are in deployed ancestry. Current visible behavior still needs browser verification.
- Workflow upload: workflow-history-dialog.tsx retains upload and imports views, `.nf/.ga/.yml/.yaml` input and `/api/workflows/upload-file` submission. Wrong entry location is distinct from missing implementation.

## nf-core and SYSUCC evidence
- November 6 nf-core compatibility commit `176dac7a5` is an ancestor of deployed HEAD.
- `evaluation/routing_eval/domain_retag/nfcore_test_profile_validation_run17_scdownstream_20261106.json` records completed run `cb7a1b63-28a0-41ea-9074-9a3f33fd64f2`, 197 output files. This is recorded evidence, not a new execution in this audit.
- `scripts/validation/validate_nfcore_test_profiles.py` searches and executes through workflow APIs, then polls runs. It does not create a demonstration chat/project. Catalog execution and user-visible demonstration readiness are separate.
- `docs/20261105_SYSUCC_SIM_MULTIOMICS_VALIDATION.md` records a synthetic cohort (not hospital patient data), direct SNF execution and model training through Batch. The document explicitly excludes routing from what those runs prove.
- Earlier SYSUCC use-case evidence (`docs/20261029_SYSUCC_USECASE_TEST_RESULTS.md`) explicitly excludes chat/UI E2E and records failures. Later fixes and newer evidence must be checked before assigning current pass/fail status.
- No SYSUCC/zhongshan-named entry found in current frontend client TS/TSX/JSON or public JSON search. This does not prove generic examples cannot cover these tasks, but no dedicated visible hospital case was established.

## Required follow-through
Trace each remembered feature and hospital case through implementation, tests, catalog identity, datasets, ownership/project/chat linkage, visible entry point and deployed runtime. Restore explicit navigation decisions without rewriting retained functional modules. Verify complete journeys with prepared synthetic/public datasets; do not represent historical API execution as UI acceptance or expose other users' test records.

## Deck-specific follow-up
The user's requirement includes complex cases shown in customer decks, not only individual workflow availability.

| Case family | Existing evidence located | Missing acceptance evidence in this audit |
| --- | --- | --- |
| Bulk RNA-seq chat → nf-core differentialabundance | `docs/20261006_REAL_USECASE_E2E_RESULTS.md`: completed run `4dbcc0cf-ce6f-4ef0-9c1f-2b98b02343ea`, explicitly chat-routed | Current account visibility, project/chat reopening and current-build repeatability |
| SYSUCC multi-omics integration → biomarkers → subtype model | November 5 synthetic-cohort report and recorded Batch runs | Deck entry → prepared project/datasets → chat routing → preserved results |
| ADMET toxicity screening | November 5 use-case validation log records completed run `a4fe422e-3e52-4ada-b11b-e78fa33e01cc` | Current chat journey and observed QC event; log explicitly excludes observed gate-fire evidence |
| Models training | Generic tabular trainer/routing fixes documented November 4; real Batch model run November 5 | Current live routing flag, UI project context and durable model registry linkage |
| Campaign/peptide loops | October 25 deck data handoff distinguishes actual generation results from illustrative measurement/campaign tables | Exact deck version and subsequent validated closed-loop evidence; illustrative tables must not become fabricated saved experiments |
| nf-core test profiles | November 5–6 JSON records; validator exercises product execution API | Per-case discoverability and authorized saved-demo linkage; do not expose fixture-account runs to unrelated users |

Correction: direct-API execution is not the explanation for every case. At least one genuine chat→workflow completion is documented. Historical evidence is retained and must be reconciled rather than dismissed or rerun indiscriminately.

## Parallel repair batch

User explicitly authorized parallel subagents on November 7. Three scoped streams implemented:

- Instructions/output formats: editable name/kind/requirements; Save/Cancel; actual template preview; idempotent example insertion; no false optimistic saved state. Focused 14 tests passed.
- Workflow/chat: checkpoint-aware recovery advice; no scientific findings or findings-analysis jobs for diagnostic-only failures; truthful Not started phase state; phase-prefix deduplication; no persisted stale Generating workflow marker. Focused 64 passed, 19 existing skipped.
- Files: bounded metadata cards, inferred JSON/YAML MIME from generic storage MIME, unknown dimensions distinct from measured empty data, useful operation-specific errors reset on file switch; inert YAML rendering test. Focused 31 tests passed.

Root integration: restored Settings imports/connectors entry and removed More tools/duplicate footer gear; model track loading/error/invalid-response handling; removed misleading watch-live link; Models-specific scroll container; file open-in launches under the same Galaxy user used for staging, resolves job-correlated interactive URL and rejects absent access URLs instead of inventing one. Added new UI translations in English and Chinese.

All are LOCAL changes until commit/push/deployment evidence is appended. No complete hospital-demo readiness claim. Still open: full Models training/registry linkage, duplicate lifecycle screenshot provenance, after-run hierarchy visual reconciliation, true Jupyter launch and scroll interaction checks, dedicated case/project preparation and deployed EN/ZH verification.

Integrated validation: 212 suites / 2,315 tests passed, 3 suites / 42 tests skipped; TypeScript and production build passed. Sync staging, 2 health tests, Bash syntax and diff whitespace passed. Commit/push/deployment status is recorded separately.
