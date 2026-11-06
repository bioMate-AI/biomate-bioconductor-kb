# P0 requirement-scan: measured blast radius of the inputs gap

> **CORRECTION (2026-10-26, after reading the executor):** the headline "1,177 invisible" below
> **overstated** the problem. The executor (`nextflow_executor.py`) already has a robust declared-input
> system — it parses `// Input:` headers (`_BIOC_INPUT_DECL_RE`), resolves the exact read-filename
> (`_resolve_read_filename`), stages uploads under the expected name, and pre-flight-checks format. Re-split
> of the 1,177: **1,173 (99.7%) are executor-handled** (`// Input:` header or `read_input_file`); only
> **4 are truly unhandled** (no declaration at all). So **staging is not the gap.** The real, narrower gap
> is **discoverability**: the executor *knows* the declared input names (survival `patient_clinical_data.csv`,
> DESeq2 `cts`/`coldata`), but they are **not surfaced** in `search_workflow` / `required_params` /
> `input_types` — **35** executor-handled workflows declare nothing in `input_types`, and more list only
> scalar params, so a caller/user can't learn what inputs to provide and discovers them by crashing (the
> exact failures this session). **P1 is therefore the discoverability fix**, not a 1,177-row backfill:
> surface the executor's already-derived declared inputs at search/spec time. The raw scan below is kept
> for the record.


**Date:** 2026-10-26. **What:** the P0 static scanner from `docs/20261026_PARAMS_VS_INPUTS_GAP.md`, run
read-only over the whole workflow catalog (`backend/database/galaxy_ai_tools.db`, 4,223 workflows).
Scanner: `scratchpad/req_scan.py`.

## Method
For each workflow, parse its stored script (`workflow_json` — the `.nf` plus embedded R/Python) for the
input surface, and classify:
- **A — invisible literal filename:** the script reads a data file by a literal name
  (`read.csv("X.csv")`, `read.table(gzfile("X.gz"))`, `read.taqman("X")`, `readRDS("X")`, …) where `X` is
  **not** pinned by a `stageAs:` and **not** a file the workflow itself writes → the user must name their
  upload exactly `X`, with nothing telling them so. This is the `survival` failure we hit.
- **B — keyed input:** uses `read_input_file("key")` → the caller must know the opaque key. This is the
  DESeq2 `cts` + `coldata` pattern (keys discoverable only by crashing).
- **C — nothing declared:** (A or B) **and** `input_types` empty → no queryable declaration at all.

## Results
| Metric | Count | % of 4,223 |
|---|---|---|
| **A — reads an invisible literal filename** | **1,177** | **27.9%** |
| &nbsp;&nbsp;↳ **multi-file** (≥2 undeclared files) | **694** | **16.4%** |
| &nbsp;&nbsp;↳ single-file | 483 | 11.4% |
| **B — uses `read_input_file` keys** | 20 | 0.5% |
| **C — needs input but declares nothing (`input_types` empty)** | 36 | 0.9% |

**The headline: ~28% of the catalog has an undeclared input requirement, and most of those (694) are
multi-input** — exactly the "many workflows have multi input/parameters, and BioMate isn't smooth with
them" concern, now a number. A user running any of these without foreknowledge gets the survival/DESeq2
experience: launch → cryptic runtime crash → guess the filename/key → repeat.

### Most common required-but-invisible filenames (users would have to guess these)
`expression_matrix.csv` (64) · `sample_metadata.csv` (30) · `sce.rds` (23) · `spe.rds` (14) ·
`counts.tsv` (11) · `counts_matrix.csv` (11) · `metadata.csv` (11) · `phenotype_data.csv` (11) ·
`counts.csv` (9) · `expression_data.csv` (8) · `y.rds` (8) · `txdb.rds` (8).

### Representative multi-input cases
`absseq` → `counts.tsv` + `groups.csv`; `absseq_complex_design_analysis` → `counts.tsv` +
`design_metadata.csv`; `adsplit_manual_split...` → `entrez_id_mapping.rds` + `expression_matrix.csv`;
`Nca Pknca` → `validated_conc_time.csv`; DESeq2 → `cts` + `coldata`.

## Honest caveats (don't over-read the number)
- The **28% is the "input surface not surfaced in the schema"**, not a proven 28% crash rate. The
  executor's input-resolution wrapper *may* resolve some literal reads at runtime if the caller supplies
  the right key — but even when it does, the key/requirement is **still not in `required_params`** (DESeq2
  proved `cts`/`coldata` are invisible to the schema), so the interactive/caller experience is the same.
- The **Bioconductor "document-derived" subworkflow family dominates** the 1,177 (auto-generated from
  vignettes with hardcoded example filenames). That's where the fix pays off most.
- Single-file cases are lower-risk than multi-file, but still undiscoverable.

## So what
P0 is done and the gap is quantified: **1,177 workflows (694 multi-input)** need the declared-requirement
contract. The scanner that produced this is the same one P1 uses to **backfill the schema** — i.e. the
diff above is directly actionable: register these scanned requirements as declared file inputs, normalize
staged names, and gate/prompt pre-run (P1–P3 in the gap doc). One scanner, whole class closed.
