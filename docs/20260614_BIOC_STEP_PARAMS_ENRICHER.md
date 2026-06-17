# Bioconductor per-step parameter enricher (2026-06-14)

## Problem
Workflow-level params live in `params_schema` (typed + described, 17k+), but per-step
`step_metadata` entries carried only `{step, phase, outputs, visualizations, qc}`. The UI
per-step path (`nextflow-workflow-viewer.tsx` `step.parameters`, `step-adjust-modal.tsx`)
got `{}` for every Bioconductor step → no editable per-step params.

## The exact consumed shape (traced)
- `nextflow-workflow-viewer.tsx:687`: inline preview renders
  `Object.entries(step.parameters).map(([k,v]) => \`${k}: ${v}\`)` → values must be SCALARS.
- `nextflow-workflow-viewer.tsx:1056`: `parameters: step.parameters` passed through as
  `Record<string, unknown>`.
- `step-adjust-modal.tsx:45/51`: seeds overrides with `{ ...step.parameters }` (name → value);
  infers widget type from the *value* (`typeof === boolean|number`) **and** from
  `workflowDefinition.required_params/optional_params` matched by name. It does NOT read
  type/options from a nested object.
- `parameter-group.tsx`: the rich `Parameter` interface (type ∈ string|number|boolean|select|file,
  options[], minimum/maximum) is the WORKFLOW-level GlobalParamsPanel shape, not per-step.

**Conclusion:** served `step.parameters` MUST be flat `{ name: default_value }`. Rich metadata
(type/description/options) is sourced by the modal from the workflow-level schema by name.

## What was built
`backend/scripts/enrich_bioc_step_params.py` (mirrors `enrich_bioc_step_metadata.py`:
`--dry-run`, `--no-db`, auto-backup, idempotent; `--db`/`BIOC_PARAMS_DB`, refuses canonical DB):
- Reads `params_schema.parameters[]` + `data_inputs[]` (file params).
- Splits the .nf R body into sections (`# N.`, `# STAGE N:`, `# --- x ---`).
- Aligns sections → existing `step_metadata` entries by step-name/section-header token Jaccard
  (≥0.34), positional fallback.
- Attribution: each param lands on every step whose section body references its name as a token;
  params referenced in no section (workflow-level inputs / setup-stage values) land on the first
  (input/setup) step so they stay editable. Guarantees no param is dropped.
- Writes a rich `params` LIST onto each step: `{name, type∈5-set, default, description, options[],
  required}`. Type map: allowed_values → `select`; path/file-suffix → `file`; else string/number/boolean.

## Serving alignment
`nextflow_executor._steps_from_db_metadata` previously hardcoded `"parameters": {}`. Changed to
flatten the stored `params` list → `parameters: {name: default}` (UI shape) and also forward the
rich list under `param_meta`. This is the only serving change.

## Coverage (DB copy `/tmp/params_test.db`)
- 3148 workflows processed; 2902 (92.2%) have ≥1 step carrying params.
- 11,603 steps; 7,721 (66.5%) carry params; 31,451 param attributions.
- Idempotent (identical `step_metadata` hash on re-run).
- Contract assertions pass: all defaults scalar/null, type ∈ 5-set, name/desc/options present,
  select carries options, served names ⊆ workflow-level schema names.

## Policy
Worked on `/tmp/params_test.db` (copy); canonical DB untouched and write-guarded. Committed to
`feat/bioc-step-params`.
