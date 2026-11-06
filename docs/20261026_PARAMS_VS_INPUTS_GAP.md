# Workflow requirements gap: "parameters" vs "inputs" are not one declared contract

**Date:** 2026-10-26. **Severity:** UX / correctness (silent runtime failure). **Found via:** running the
`survival` KM/Cox workflows through the MCP for the Design UI data handoff — the runs launched with no
input and failed at runtime instead of being gated pre-run.

## TL;DR
A workflow's requirements live in **three different, unreconciled places**: declared `params.*`, declared
channel **file inputs** (`path(...)`), and **values hardcoded in the script** (e.g. `read.csv("patient_clinical_data.csv")`).
BioMate's parameter-completion stack (defaults → rule+LLM prefill → schema validation → pre-run gating)
only sees the **first** reliably. Anything a workflow needs that is *not* declared in its param schema —
most importantly **required input files** — is **invisible** to that stack: it isn't prefilled, isn't
gated, and the run **launches and crashes at runtime** with a cryptic engine error. To a user there is no
meaningful difference between "a parameter" and "an input" — both are just *things the workflow needs* —
so this split is an implementation leak that should be unified behind **one declared requirement contract**.

## What works today (declared params)
- **Optional params** are filled from schema/.nf **defaults**, then overlaid by a **hybrid rule + LLM
  prefill** that reads the user's message (rules for units/flags/negations; LLM for free-text), validated
  against the schema's `allowed_values`, with per-value provenance (`default` / `recommended` /
  `from message` / `llm_extracted` / `autoFilled`). Live example: the BOIN run auto-filled
  `design=BOIN` (`llm_extracted, autoFilled=true`); everything else fell back to defaults and the run
  proceeded.
- **Missing *declared-required* params** are gated pre-run in the UI (blocked alert → *Fix now* /
  *Confirm anyway*). Declared requirements degrade gracefully.

## What breaks (undeclared requirements, esp. file inputs)
**Concrete evidence — the `survival` (KM) workflow:**
- `search_workflow` reported `required_params: []` and `param_prefill_deferred: false` — i.e. BioMate
  believes the workflow needs **nothing**.
- But the workflow's R script hardcodes `read.csv("patient_clinical_data.csv")`
  (`.../bioconductor/survival/main.nf`). The requirement exists **only in the script**, not the schema.
- Result with no input: the run **launched on AWS Batch**, the R task failed with
  `Error in file(...) : cannot open file 'patient_clinical_data.csv': No such file or directory`,
  the output dir was **empty**, and the real error was buried in the S3 work dir `.command.err`. No
  "this workflow needs a clinical-data CSV (columns time/status/group)" prompt — just a silent post-hoc
  crash.
- A second trap on top of it: when a file *is* provided via `upload_file`, the object key is
  **UUID-prefixed** (`<uuid>-patient_clinical_data.csv`), so the staged basename no longer matches the
  name the script reads — same cryptic failure until the object is re-keyed to the exact expected name.

This is why `prereq detection` scores low in the benchmarks (~0.33 on PBPK): the prerequisite often isn't
*declared* anywhere the detector can read.

## The deeper confusion: params vs inputs is not a real user distinction
A workflow needs a file in **three** different ways, with no single rule:
1. a **param of type `file`** (e.g. `quant`, or `input` for nf-core/fetchngs) — declared, visible;
2. a **channel input** `path(input_files)` — declared in the process, but not always surfaced as a param;
3. a **hardcoded filename** the script reads directly — **undeclared**, invisible (the survival case).

To the user these are identical ("the workflow needs my data"), but each is handled by a different code
path, so prefill/gating/prereq coverage is inconsistent. The param-vs-input split is a Nextflow
implementation detail leaking into the product.

## Proposed fix — one declared requirement contract
Collapse "parameters" and "inputs" into a single declared **requirements** list per workflow, each entry:
`{ name, kind: scalar|enum|file|dataset, required: bool, default?, allowed_values?, maps_to:
param|channel|script_path, provenance_source, validation }`. Then:
- **One** completion/gating pass reads it: defaults → rule+LLM prefill → schema validation → **pre-run
  gating for every missing required item, file or scalar alike** — with a helpful prompt ("attach a
  clinical-data CSV with columns `time, status, group`") instead of a runtime `read.csv` crash.
- **Derive it, don't hand-maintain it:** statically scan each `.nf`/R/py script for hardcoded reads
  (`read.csv("X")`, `path(...)`, `file("X")`) and register those as declared `file` requirements, so
  script-level needs can never again be invisible to the schema.
- **Normalize staged filenames:** when a file requirement declares an expected basename, the executor
  stages the uploaded object **as that name** (strip the upload UUID prefix), removing the second trap.
- Treat a missing required input as a **pre-run QC/verifiable-reward gate** (same machinery that gates
  QC thresholds), so "it will fail because input X is missing" is caught before spending a Batch run.

## Implementation scope — the requirement-scanner (the fix, concretely)

A read-only static scanner that derives each workflow's **true** requirement set from its own files, emits
a normalized manifest, and backfills the schema. Phased so value lands before the risky parts.

**What it parses** (per workflow: the `.nf` + any embedded R/Python heredoc):
| Source pattern | Requirement it implies |
|---|---|
| `params.X = <default>` | scalar param `X`, optional, default `<default>` |
| `path(v, stageAs: 'Y')` in `input:` | file input, **expected staged name `Y`** |
| `read_input_file("K")` (biomate wrapper) | **declared input key `K`** (this is the real run_workflow param key — e.g. `cts`, `coldata`) |
| `read.csv("F")` / `read.table(gzfile("F"))` / `read.taqman("F")` / `file("F")` | file input, **expected basename `F`**, required |
| `colnames(x) <- tolower(...)` + `grep("time\|status\|…")` | column-mapping hints → surface expected columns |

**Output — one manifest per workflow** (store in the DB alongside `params_schema`):
```
requirements: [
  { key, kind: scalar|enum|file, required: bool, default?, allowed_values?,
    staged_name?, expected_columns?, format_hint?, maps_to: param|channel|script|wrapper }
]
```

**Phases:**
- **P0 — scan + diff report (read-only, ship first).** Run across the catalog; for each workflow diff
  *declared* (`required_params`/`input_types`) vs *scanned* requirements. Output the set of workflows whose
  scripts need more than the schema declares (the invisible-input list) — this **quantifies the blast
  radius** and is immediately useful (e.g. "N workflows will silently fail without undeclared input X").
  Add a unit test asserting scanned ⊆ declared going forward.
- **P1 — backfill + executor stage-name normalization.** Write the scanned file requirements into the
  schema so `search_workflow`/`get_workflow_spec` report them. In the executor, when a requirement
  declares a `staged_name`/basename, **stage the uploaded object as that name** (strip the `upload_file`
  UUID prefix) — kills the filename-mismatch trap.
- **P2 — wire the interaction.** Feed the manifest to (a) **pre-run gating**: block on any missing required
  file with a helpful prompt ("attach `coldata` — columns `sample,condition`"); (b) the **chat assistant**:
  prompt the user for missing inputs instead of launching a doomed run; (c) **prefill**: nothing to fill
  for files, but surface them in the param strip as required with provenance.
- **P3 — re-measure.** The `prereq` benchmark dimension should jump from ~0.33; add a regression test that
  a known multi-input workflow (DESeq2: `cts`+`coldata`) is gated pre-run, not crashed.

**Effort shape:** P0 is a self-contained script + report (small, no risk). P1–P2 touch the schema loader,
executor staging, and the gating/assistant path; each is independently shippable. One scanner fixes the
whole class instead of patching workflows one by one.

**Guardrail:** the scanner is the source of truth derived from scripts, so it can't drift from what the
code actually reads — the root cause of this entire class of silent failures.

## Scope
Instances of undeclared/mis-declared requirements beyond `survival`: the Cox workflow
(`survival_cox_proportional_hazards_regression`, same hardcoded `patient_clinical_data.csv`), and more
generally any `bioconductor/*` "document-derived real input-consuming pipeline" that hardcodes an input
name in its script. A static scan (above) would enumerate the full set. Related: `project_e2e_virtual_workflows`,
`project_workflow_validation_gaps`, the `param_prefill` / `prereq` benchmark dimensions.
