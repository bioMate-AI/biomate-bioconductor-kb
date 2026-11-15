# S3 path exposure sanitization (2026-11-15)

## Goal

User-facing surfaces (UI param strip, chat reply prose, browser JSON, LLM
system-prompt examples) must not carry raw `s3://` seed-bucket URIs. Execute
time still resolves real URIs for Batch.

## What shipped

| Layer | Change |
|-------|--------|
| Cold-start / Prepared-inputs | Cryo movies seed as `fixture:empiar-10028-movies` (catalog + `cryo_inputs.json`) |
| Fixture map | `frontend/shared/demo-fixture-paths.ts` + Galaxy `_DEMO_FIXTURE_PATHS` expand tokens at launch (`routes.ts` execute + `_validate_input_paths`) |
| MG GEO routing prompts | `galaxy-assistant.ts` GSE227835 samplesheet/matrix/contrasts/gene_list use `fixture:mg-demo-*` (not work-bucket paths) |
| Param-infer few-shot | `ai_assistant.py` cryo example uses `fixture:empiar-10028-movies` |
| Browser egress | Status / output-file payloads strip `s3_uri` / work dirs; validation errors go through `redactStoragePaths` |
| Display / errors | `cleanParamValueForDisplay`, `userFacingErrorText` hide cryo/work bucket names |

## Residuals (intentional)

1. **Upload protocol `s3_uri`** in `[Uploaded datasets: …]` blocks — required so Nextflow workers can read user uploads. Hidden from UI reply text via `redactStoragePaths` / NEVER-show-storage rule; keep server-side.
2. **Server-only fixture maps** still hold real URIs — never shipped in client bundles as seed values.

## Tests

Targeted vitest: `demo-fixture-paths`, `prepared-inputs-params`, `user-facing-error`, `cold-start-demo-catalog`, `nextflow-workflow-viewer.display`, `execution-integrity` (redactStoragePaths).
