# 2026-07-26 — End-to-End Use-Case Audit: Single-cell + Multi-omics

Continuation of the comprehensive MG-tutorial-style audit (see
`docs/20260723_E2E_USECASE_AUDIT_CLINICAL_PBPK.md`). Same standard: generate →
run → audit chat/panel/outputs/findings + **biomedical soundness**, plus chat
flow fluency.

---

## Use case 4 — Multi-omics (MOFA2) ✅ routes + sound; ⚠ universal-interface regression

Query: *"matched RNA-seq, DNA methylation, proteomics from 40 tumor samples —
run a multi-omics factor analysis…"*

- **Routing: correct** → **MOFA2 Multi-Omics Factor Analysis** (single workflow,
  `bioconductor/mofa2/main.nf`; NOT the fixed chain).
- **Chat description: biomedically sound** — joint factorization across all layers.
- **Not executed** — requires 3 staged omics matrices (not available).

### Design check (per user: "universal interface to combine ANY combination of omics")
**The universal engine EXISTS ✓** — input is a generic `path(input_files,
stageAs:'?/*')` (any number of files), `create_mofa(data)` on a list, and
dynamic `views_names(model)` handling (`if length > 2`). MOFA2 genuinely
factorizes any combination.

**But two things break "any combination":**
1. **Hardcoded view labeling** (`mofa2/main.nf:152`):
   ```r
   new_views <- c("Transcriptomics", "Proteomics")
   if (length(views_names(model)) > 2) new_views <- c(new_views, paste("View", 3:length(views_names(model))))
   views_names(model) <- new_views[1:length(views_names(model))]
   ```
   `data.rds` is a NAMED list and `create_mofa(data)` already sets correct view
   names — line 152 **clobbers them**. For RNA+methylation+proteomics, methylation
   → "Proteomics", proteomics → "View 3". Scientifically misleading output.
2. **Fixed chain** (`chain_composer/proposed_chains/multi_omics_mofa_chain.json`)
   hardwires RNA (`rnaseq_deseq2_de`) + proteomics (`bioc_proteomics_de_v2`) +
   metabolomics (`lcms_metabolomics_consensus`) → not arbitrary combinations.

**Fix direction:**
- **main.nf:152** — preserve input-provided view names; only assign "View N" to
  genuinely unnamed views. Restores correct labeling for ANY combination.
- **Interface** — let the user declare their modalities (a modality-name list
  matched to the input files) so `data.rds` is built with real view names, and
  generalize the chain from fixed-3 to an arbitrary set of omics-preprocessing
  steps + one MOFA integration.

---

## Use case 5 — Single-cell (demo data) ⚠ FAILED — over-promised demo + wrong route

Query: *"single-cell RNA-seq pipeline with clustering and cell-type annotation on
demo data — I just want to see it work end to end with the built-in example
dataset."*

**Chat claimed** (`scrnaseq_standard_endtoend`):
> **Input:** Built-in demo dataset (**pbmc3k** example) with default Seurat
> pipeline parameters
> Key steps: nf-core/scrnaseq alignment (CellRanger) → Harmony batch integration
> + Leiden clustering → CellTypist automated annotation

**What actually happened** (run `a97bba63`): routed to bare **`nf-core/scrnaseq`**,
params empty (`version`/`toolParameters` only), **FASTQC exited 127** ("Essential
container in task exited") — no input data. **Run failed at the first task.**

**Root findings:**
1. **`scrnaseq_standard_endtoend` is not a wired workflow.** Zero matches in
   `backend/` or `frontend/server/`. The LLM assembled that composite name +
   promised a plumbed pbmc3k demo, but the executable behind it is just
   `nf-core/scrnaseq` (FASTQ → counts) with **no demo dataset**.
2. **Over-promise / soundness gap.** The chat asserted a "Built-in demo dataset
   (pbmc3k example)" that is not actually plumbed into the run. Violates the
   Chat Presentation Standard (no hallucinated capability). For "I just want to
   see it work," the run must either use a real wired demo or the chat must not
   claim one.
3. **Wrong route for the intent.** "Clustering + cell-type annotation on demo
   data" is a DOWNSTREAM analysis. `nf-core/scrnaseq` is UPSTREAM (alignment/
   quantification, needs FASTQ). A real pbmc3k demo **does exist** in the
   bioconductor single-cell workflows (`nebulosa/seurat_density`, etc. — they
   fetch `pbmc3k_filtered_gene_bc_matrices.tar.gz` from 10x's S3 via
   BiocFileCache; `STATUS.md` also references `pbmc3k_tiny.h5ad`). Routing should
   have picked a downstream Seurat/scanpy clustering+annotation workflow with the
   pbmc3k demo, not upstream nf-core/scrnaseq.

**Fix direction (not yet applied):**
- Wire a one-click single-cell demo (pbmc3k) to a downstream clustering/annotation
  workflow so "demo data" scRNA actually runs, OR
- Make routing send "demo scRNA clustering/annotation" to the bioconductor
  Seurat/pbmc3k path, AND stop the chat from claiming a built-in demo when the
  routed workflow has none.

---

## Cross-cutting bug — generic "**workflow** is ready" prefix

Seen on BOTH MOFA2 and scrnaseq: the pre-execution summary opens with
`**workflow** is ready in the panel…` instead of the real name. Source:
`server/galaxy-assistant.ts:4647`, where
`workflowName = wf.workflow_name || wf.name || 'workflow'` — both fields are
falsy on `generatedWorkflow` for these workflows, so it falls to the literal
"workflow". The correct name IS available (it appears on the LLM's next line).
Low-severity (name shown on line 2) but violates the "never blank name"
standard. Fix: extend the fallback chain to `wf.display_name`, `wf.chain_name`,
`wf.workflow_ga?.name`.

---

## Status of prior fixes (verified this session)
- **Chain execution** (panel dispatch `90ff3aaf` + step-source `6759cdf6a`):
  deployed + verified — ADMET+PBPK chain run `b457ed05` submits with a real
  `chain_run_id` and runs (was: silent no-op → failed submission). See
  `docs/20260723_FLEXIBLE_CHAIN_EXECUTION_DESIGN.md` §6.

## Coverage so far (end-to-end, biomedical soundness)
| Use case | Route | Run | Soundness |
|---|---|---|---|
| MG (DESeq2 + enrichGO) | ✅ | ✅ ran | ✅ TNF/complement, matches output |
| Clinical trial (BOIN) | ✅ | ✅ succeeded | ✅ MTD 30mg, Liu&Yuan boundaries |
| ADMET panel | ✅ | ✅ completed | ✅ hERG/BBB/PPB/CYP correct |
| PBPK chain | ✅ | ✅ runs (fixed) | description sound |
| Multi-omics (MOFA2) | ✅ | ✅ **completed** (run `c96493d7`) | ✅ real-modality labels + injected factors recovered |
| Single-cell (demo) | ⚠ wrong route | ❌ FASTQC fail | ⚠ over-promised pbmc3k demo |

---

## Multi-omics (MOFA2) — RESOLVED + VERIFIED end-to-end (2026-07-27)
The universal-interface + labeling fixes and the dedicated `:3.20-mofa2` container
(MOFA2 + basilisk/mofapy2 baked) are all deployed and verified on dev Batch (run
`c96493d7`). Fixes along the way: install MOFA2 from explicit standard-source repos
(the auto-added `BioCcontainers` mirror 504s); `[.]` not `\\.` in R regexes
(nextflow `"""` escaping); wrap optional plots in `try()` (GGally absent).
**Verified output:** views labeled `methylation/proteomics/rna` (real modalities,
not the old `Transcriptomics/Proteomics/View 3`); MOFA2 recovers the 2 injected
shared latent factors (F1 group-split diff +2.71, F2 gradient corr +0.51; F3–6
inactive); standardized `mofa_extracted_factors.csv` / `_weights.csv` emitted.
This is Phase 0 of the multi-omics benchmark (see
`docs/20260727_MULTIOMICS_BENCHMARK_DESIGN.md`). Full container/build saga:
that doc's §6.
