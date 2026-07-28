# String-Param Single-Quote Robustness Fix — 2026-07-27

## Problem

Free-text string params in several Nextflow subworkflows were interpolated
directly into a **single-quoted** bash export inside the Groovy `"""` script
block:

```nextflow
export PARAM_ANALYSIS='${params.analysis}'
```

When the param value contained an apostrophe/single-quote — e.g. real disease
names `Sjögren's syndrome`, `Behçet's`, `Crohn's`, or labels like
`predictive (RAS)` — the apostrophe **closed the bash single-quote early**,
corrupting the rest of the shell line (unterminated quote, truncated value, or
a syntax error). This blocked legitimate scientific inputs.

Parens/spaces alone are safe inside single quotes; the apostrophe is the
breaking character.

## The Fix (escape pattern)

Per vulnerable line, wrap the interpolation with a Groovy `.toString().replace`
that rewrites each `'` into the standard bash single-quote-escape idiom `'\''`
(close-quote, escaped-literal-quote, reopen-quote):

```nextflow
export PARAM_X='${params.x.toString().replace("'", "'\\''")}'
```

In the Groovy `"""` string the `\\'` compiles to a literal `\'`, so the emitted
bash becomes e.g.:

```bash
export PARAM_ANALYSIS='predictive (RAS+apostrophe'\''s)'
export PARAM_DISEASE='Sjogren'\''s syndrome'
export PARAM_COHORT='Behçet'\''s & Sjögren'\''s cohort (subset)'
```

which bash parses back to the exact original string.

**Key safety property:** for a value containing **no** apostrophe,
`replace("'", …)` is the identity — the emitted export line is **byte-identical**
to before the change. So apostrophe-free runs are guaranteed regression-free.

## Scope

Only **free-text string** exports were changed. Numeric, boolean, enum
(`outcome_type` = auto|binary|continuous), `outdir`, and file-**path** params
were intentionally left untouched to avoid risk. Files
`integration_benchmark/main.nf` and `target_scorecard_ranker/main.nf` were
explicitly out of scope (owned by other agents) and were **not** touched by
this work.

## Files & Lines Changed

| File | Params fixed (line) |
|------|---------------------|
| `nextflow_nfcore/subworkflows/biostatistics/gate3_interaction_test/main.nf` | `analysis` (64), `biomarker_positive` (66), `treatment_experimental` (67), `default_treatment` (68) |
| `nextflow_nfcore/subworkflows/biostatistics/virtual_trial_gate3/main.nf` | `analysis` (75) |
| `nextflow/subworkflows/database/query_opentarget.nf` | `disease` (48), `efo_id` (49) |
| `nextflow_nfcore/subworkflows/immunology/autoantibody_isotype_stratification/main.nf` | `cohort` (69) |
| `nextflow_nfcore/subworkflows/immunology/antigen_resolution/main.nf` | `disease_genes` (91), `patient_id` (92) |
| `nextflow_nfcore/subworkflows/biostatistics/cohort_qc_triage/main.nf` | `dataset_id` (99), `required_fields` (100), `provenance_fields` (101), `batch_field` (102), `group_field` (103) |
| `nextflow_nfcore/subworkflows/biostatistics/qsp_virtual_population/main.nf` | `analysis` (95) |

(All paths relative to `/Users/kky/biomate-td-pr/backend/biomni_workflows/`.)

**Not changed:** `database/metadata_harmonizer/main.nf` — inspected; its only
string exports are file paths (`metadata_file`, `ontology_file`) plus numeric
thresholds. No free-text string param, so nothing to fix.

Params left as-is by design: `outcome_type` (enum), all `*_file` paths, all
numeric/boolean/threshold/weight/rank params, `outdir`.

## Test Results

All runs via `/opt/homebrew/bin/nextflow run <path> -profile standard`
(Nextflow 25.10.6).

### 1. gate3_interaction_test — apostrophe + parens label
- Input: `--analysis "predictive (RAS+apostrophe's)"` on `coin.csv` (1294 rows,
  `--biomarker_positive KRASwt --treatment_experimental cetux`).
- Result: **status = completed**, process `1 of 1 ✔`.
- Emitted export: `export PARAM_ANALYSIS='predictive (RAS+apostrophe'\''s)'`.
- Output `gate3_results.json` `analysis` field = `predictive (RAS+apostrophe's)`
  — apostrophe + parens intact, no truncation, `.command.err` empty.

### 2. query_opentarget — real apostrophe disease name
- Input: `--disease "Sjogren's syndrome"`.
- Result: process `1 of 1 ✔`, `.command.err` empty. No bash quoting error.
- Emitted export: `export PARAM_DISEASE='Sjogren'\''s syndrome'`.
- The value passed cleanly through to Python and the **live Open Targets API**,
  which resolved it: `Sjogren syndrome (MONDO_0010030) -> 25/2755 targets`, and
  produced full output files (`target_prioritisation.csv`, `target_evidence.csv`, …).
- EFO-id control (`--efo_id EFO_0000685`): export line
  `export PARAM_EFO='EFO_0000685'` well-formed, `.command.err` empty — the shell
  passed the id cleanly. The process itself exited 1 on a downstream **data/API**
  condition (that id returned no queryable targets), which is unrelated to
  quoting and pre-existing.

### 3. autoantibody_isotype_stratification — multi-apostrophe + non-ASCII cohort
- Input: `--cohort "Behçet's & Sjögren's cohort (subset)"` on a 5-row serology CSV.
- Result: process `1 of 1 ✔`, `.command.err` empty.
- Emitted export: `export PARAM_COHORT='Behçet'\''s & Sjögren'\''s cohort (subset)'`
  — both apostrophes escaped correctly.
- Output `cohort_summary.json` `cohort` field = `Behçet's & Sjögren's cohort (subset)`
  — two apostrophes, ç/ö, ampersand, and parens all preserved verbatim.

### 4. Regression check — apostrophe-free run unchanged
- Re-ran gate3 on `coin.csv` with the original baseline label
  `COIN_mCRC_KRAS_cetuximab_OS_events` (no apostrophe) and compared to the
  stored baseline `docs/gate3_benchmark_data/results/coin_gate3_results.json`:
  - `gate3_verdict`: **NO SIGNAL** — MATCH
  - `decisions_changed_pct`: **0.0** — MATCH
  - `interaction.p_value`: **0.912367** — MATCH
  - `analysis` label preserved verbatim.
- Emitted export line was **byte-identical** to pre-change:
  `export PARAM_ANALYSIS='COIN_mCRC_KRAS_cetuximab_OS_events'` (no escaping
  applied because there is no `'`). Confirmed the `.replace` is identity for
  apostrophe-free input.
- (The `interaction.estimate` differs only in **sign** vs the stored baseline —
  a pre-existing reference-level convention that surfaces when the
  `biomarker_positive` flag is/ isn't supplied. Magnitude, p-value, and verdict
  are identical, and this is fully independent of the quoting change.)

## Conclusion

Apostrophe-containing free-text string params (disease names, cohort labels,
analysis labels — including non-ASCII and multi-apostrophe cases) now run to
completion with the value preserved intact. Apostrophe-free runs are
byte-identical and produce unchanged output. No workaround; the root cause
(unescaped interpolation into a single-quoted bash export) is fixed at the
source line.
