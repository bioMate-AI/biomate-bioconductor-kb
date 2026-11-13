# iGenomes `genome` param projection (2026-11-13)

## Symptom

`instructions-obedience.e2e.ts` part (b) failed: project rule "always use GRCh38"
appeared only in reply prose, never as a structured workflow parameter for
nf-core/rnaseq.

## Root cause

`AIAssistant._NEXTFLOW_INTERNAL_PARAMS` incorrectly listed `genome` alongside
true executor/infra params (`outdir`, `input`, `max_cpus`, …). Both shared
projection paths skipped it:

1. `_parse_nextflow_schema` — nf-core `nextflow_schema.json` declares `genome`
   (iGenomes key) but the INTERNAL skip dropped it while keeping `fasta`/`gtf`.
2. `_parse_nextflow_params` — biomni stubs (e.g. `biomni_workflows/nfcore/rnaseq/main.nf`)
   declare `params.genome = null // … GRCh38 | …` but the same skip hid it.

With no `genome` slot:

- Backend `_rule_based_param_inference` / `_extract_genome_build` never fired
  (`"genome" not in param_names`).
- Frontend `groundInlineParameters` dropped any LLM-extracted `genome` as
  schema-unknown.
- Project rules reached only the intent/response prompt (`intentRulesBlock`),
  so prose obeyed them but structured params did not.

`input` remaining INTERNAL is correct: the executor builds the samplesheet
(fetchngs / upload). It is described via `workflow_ga.data_inputs`, not as an
editable param.

## Fix

| Change | Where |
|--------|--------|
| Remove `genome` from `_NEXTFLOW_INTERNAL_PARAMS` | `backend/lib/galaxy/ai/ai_assistant.py` |
| Treat bare `genome` / `genome_build` / … as string (not file) unless `format=file-path` | `_schema_type_to_param_type`, `_INPUT_FILE_PARAM_NAMES`, `.nf` parser |
| Emit `data_inputs` for required executor `input` from the `.nf` parser too | `_parse_nextflow_params` |
| Organism vernacular → canonical iGenomes key (`human` → `GRCh38`) | `_extract_genome_build` |
| Prefer enum-compatible genome values; set `value` + `default` | `_inject_genome_into_params` |
| Thread project rules into generate + param extraction queries; fold backend-filled params into `inlineParameters` | `frontend/server/galaxy-assistant.ts` |
| E2E `allParams` reads `parameters` / `default` / `metadata.inlineParameters` | `frontend/e2e/instructions-obedience.e2e.ts` |

## Tests

- `lib/galaxy/ai/tests/test_executor_data_inputs.py` — schema projects `genome` as string
- `lib/galaxy/ai/tests/test_igenomes_genome_projection.py` — stub `.nf` + organism rules + inject

## Remaining gaps

- Live obedience e2e on `dev-public` still needs sync after this branch lands
  (dev was on `1ecb81fd` when diagnosed).
- FDR 0.01 remains soft for rnaseq (no significance param); DE workflows that
  expose `differential_max_qval` / similar can harden that assert later.
