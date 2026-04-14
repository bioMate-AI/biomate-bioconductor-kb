# Parameter System Redesign — 2026-04-06

## Summary

Complete overhaul of how workflow parameters are presented and pre-filled in BioMate. Covers three layers:
1. **Schema-driven metadata** — nf-core `nextflow_schema.json` integration for typed, grouped, constrained parameters
2. **Custom workflow schemas** — hand-authored `nextflow_schema.json` for all 18 drug discovery workflows
3. **AI pre-filling** — two-tier system: DB-driven tool_knowledge hints + LLM intent inference

---

## Layer 1: nf-core JSON Schema Integration

### Backend (`ai_assistant.py`)

- `_parse_nextflow_schema(filename)` — reads `nextflow_schema.json` from the workflow directory
  - Iterates `$defs` groups, skips hidden params and infrastructure groups (generic_options, awsbatch_job_resources, etc.)
  - Maps JSON Schema types to BioMate param types:
    - `enum` → `select` (with options list)
    - `format: file-path` + `mimetype` → `file`
    - `format: directory-path` / `format: path` → `string` (NOT file — output dirs are not browsable)
    - `boolean` → `boolean`
    - `integer` / `number` → `number` (with min/max)
    - else → `string`
  - Each entry carries: name, label, description, type, default, group, required, options, minimum, maximum, pattern

- `_get_workflow_params(filename)` — tries schema first, falls back to heuristic `.nf` parser
- `_schema_type_to_param_type(name, param_def)` — the type-mapping function

### Frontend (`nextflow-workflow-viewer.tsx`)

- `buildViewerParameters()` — reads `required_params`/`optional_params` from workflow definition
  - Carries `group`, `options`, `minimum`, `maximum`, `autoFilled`, `rationale`, `value` from backend
- Groups params by `p.group` label → one collapsible `ParameterGroup` per group
- Sort within each group: required-empty → required-filled → has-default → optional
- First group opens by default; others collapsed

### Frontend (`parameter-group.tsx`)

- `Parameter` interface extended with `minimum`, `maximum`, `autoFilled`, `rationale`, `citation`
- `file` type: renders text input + **Browse** button → opens `GalaxyDatasetBrowser`
- `select` type: renders `<Select>` dropdown with enum values
- `boolean` type: renders `<Switch>`
- `number` type: renders numeric input with min/max range hint
- `KnowledgeBadge` component: info icon tooltip showing AI-recommended badge + rationale + citation
- `EditableParamRow` component: inline pencil → edit field → commit/cancel for auto-filled params

---

## Layer 2: Custom Drug Discovery Schemas

### Scope

All 18 workflows under `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/`:

| Workflow | Key Domain Knowledge Encoded |
|----------|------------------------------|
| `amber_pmemd_md` | force_field (ff19SB/ff14SB), water_model (tip3p/tip4p-ew/opc), gaff_version, temperature in K |
| `gromacs_protein_md` | force_field (amber99sb-ildn/charmm36m), water_model, ion_concentration 0.15M physiological |
| `reinvent4_lead_design` | mode (de_novo/scaffold_decoration/linker_design/scaffold_hopping), scoring_function, prior_model |
| `schrodinger_glide_docking` | docking_precision (HTVS/SP/XP) with use-case descriptions, ligprep_ph 7.4 physiological |
| `moe_covalent_docking` | warhead_type (7 types), reactive_residue format, docking_protocol |
| `aizynthfinder_retrosynthesis` | pass_max_steps (≤4 = commercially accessible), pass_min_score |
| `alphafold_db_search` | search_mode (both/foldseek/mmseqs2), evalue, coverage thresholds |
| `assay_ingestion_and_ranking` | potency_weight/safety_weight, hERG safety threshold 1.0 μM |
| `cro_submission_export` | CRO vendor, project metadata |
| `drug_moa_rnaseq` | gmt_file fallback to Hallmarks, n_replicates QC |
| `nca_pknca` | route (oral/iv/sc/im), time_unit/conc_unit labels |
| `pharmacophore_filtering` | min_features 3 = reasonable selectivity |
| `pocket_detection_druggability` | druggability ≥0.5 = tractable, pocket volume 300–1500 Å³ |
| `scaffold_hopping` | lipinski_filter Ro5 criteria |
| `structure_prediction_docking` | af3_mode (server/local), vina_exhaustiveness |
| `p0_docking_validation` | default: 7RFS (nirmatrelvir), RMSD < 2 Å standard |
| `p0_mrna_validation` | CAI > 0.9, MFE < -150 kcal/mol thresholds |
| `p0_pharmacophore_validation` | AUC > 0.75 = discriminating model |

### Schema Format

Each `nextflow_schema.json` uses JSON Schema Draft 2020-12 with `$defs` groups:
- `input_output_options`: required file inputs
- `analysis_parameters`: workflow-specific settings with enums, min/max, descriptions
- `generic_options`: outdir, publish_dir_mode (hidden)

Help text embedded in `description` fields provides scientific justification (e.g., "ff19SB (Tian et al., 2020) supersedes ff14SB for most protein simulations").

---

## Layer 3: AI Parameter Pre-filling

### Source 1: DB-driven tool_knowledge hints (`_apply_parameter_hints`)

- Called after `_get_workflow_params` in `_return_nextflow_match`
- Matches `scientific_rationale.parameter_hints` by param name (case-insensitive)
- Sets `autoFilled: true` + `rationale` on matched params
- Only overrides `default` when none already exists

### Source 2: LLM intent inference (`_infer_params_from_intent_llm`)

- Haiku call (claude-haiku-4-5-20251001, max_tokens=512)
- System prompt: 10-rule scientific advisor with examples for temperature conversion, precision levels, scaffold modes, reactive residues
- Input: workflow name + param catalogue (type, enum options, description) + user query (truncated to 400 chars)
- Output: JSON array of `{name, value, rationale}` — at most 5 suggestions
- Validation: name must exist in non-file params; value must be non-empty
- Non-blocking: returns `[]` on any failure (no API key, network error, bad JSON)

### Wiring

Both applied in sequence in `_return_nextflow_match`:
```python
hints = scientific_rationale.get('parameter_hints', [])
req, opt = self._apply_parameter_hints(req, opt, hints)
llm_suggestions = self._infer_params_from_intent_llm(user_intent, match.name, req, opt)
req, opt = self._apply_llm_suggestions(req, opt, llm_suggestions)
```

### Frontend display

- `ViewerParameter` extended with `autoFilled?: boolean` and `rationale?: string`
- `buildViewerParameters()` carries these through from backend params
- `renderedParameters` memo: preserves existing `autoFilled: true` instead of overwriting to false
- `ParameterGroup` renders `KnowledgeBadge` (info icon) and `EditableParamRow` (pencil Override) for pre-filled params

---

## Bug Fixes

### `directory-path` → `string` (not `file`)

`_schema_type_to_param_type`: `format: directory-path` now correctly maps to `string`. Output directories should not open the dataset browser — they're write paths, not inputs.

### `data`/`data_collection` → `file` in `parameter-dialog.tsx`

`mapInputType()` in Galaxy tool parameter dialog now maps Galaxy's native `data` and `data_collection` types to `file`, which triggers the Browse button and GalaxyDatasetBrowser.

---

## GalaxyDatasetBrowser wiring

Both parameter contexts now have Browse buttons:
1. **Nextflow top-level params** (`nextflow-workflow-viewer.tsx`): Browse button in `ParameterGroup` via `onBrowseDataset` prop → `setBrowsingForParam` → `GalaxyDatasetBrowser` at viewer level
2. **Galaxy tool step params** (`parameter-dialog.tsx`): Browse button in `ParameterInput` → `setBrowsingForParam` → `GalaxyDatasetBrowser` at dialog level

> **Known gap**: `GalaxyDatasetBrowser` returns Galaxy dataset IDs. Nextflow workflows need file paths (local or S3). Resolution layer needed: when a dataset ID is selected for a Nextflow file param, resolve to its actual path via `GET /api/galaxy/datasets/{id}` or prompt user to use the URL tab.
