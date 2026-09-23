# Multi-omics & systems biology

> One-line promise: take two or more molecular layers from the **same set of
> samples** — RNA + DNA-methylation, RNA + proteomics, RNA + ATAC — and find the
> **shared axes of variation** that no single layer shows on its own, then read
> those axes back as biology (a subtype, an IGHV-status axis, a survival split).
> You bring one CSV per layer; BioMate factorizes or fuses them and hands you an
> interpretable factor/cluster table plus the loadings that say *which features in
> which layer* drive each axis.
> For: **translational / systems-biology researchers** with matched multi-omic
> cohorts, and **bioinformaticians** who want MOFA2 / SNF run reproducibly on AWS
> Batch under one input contract instead of hand-wiring R. No coding required.

<!--
P1 chapter (build order 7). Every "supported" claim below is green in coverage-ledger.md
§ "Multi-omics & systems biology". HONESTY RULE for this domain: it has aspirational chains.
A method is documented as "supported" ONLY where a runnable subworkflow main.nf exists AND a
live end-to-end run is recorded. MOFA2 + SNF + omics_normalize meet that bar (live CLL Batch
runs, docs 20260811 / 20260727). The GWAS→scRNA→eQTL "target chain" does NOT (no coloc/PP4,
hardcoded scRNA demo data, not DB-registered) → it lives in "What's not covered" / Appendix E.
-->

## What this is for

This is the **"combine my omics layers and find what's shared"** path. Single-layer
analysis (bulk RNA-seq DE, a methylation array on its own) answers "what changed in
*this* layer." Multi-omics integration answers a different, harder question: **which
biological programs are visible across layers at once**, and which are private to one
layer. That cross-layer signal is often where the durable biology lives — a disease
subtype that shows up in both expression and methylation is far more credible than one
seen in expression alone.

BioMate meets you with a **universal input contract**: one matrix per modality
(features × samples, columns matched across layers), passed as a list. The same
contract feeds every integration method, so you can run more than one method on
*identical* inputs and compare — the thing that is normally painful to do fairly.

Two method families are supported today, and they answer two different questions:

1. **MOFA2 (latent-factor integration).** Learns a small set of **shared latent
   factors** across the layers (Bayesian factor analysis with automatic relevance
   determination). Each factor is an interpretable axis: you get a *factors table*
   (samples × factors) and a *weights table* (features × factors) telling you which
   genes / CpGs / proteins load on each axis, plus a variance-decomposition that
   shows **which layer each factor draws from** (shared vs layer-specific). Use it
   when you want an interpretable, continuous decomposition.
2. **SNF (Similarity Network Fusion).** Builds a per-layer patient-similarity
   network, fuses them into one network, and spectral-clusters it into **discrete
   subtypes**. Use it when your question is "how many groups, and who's in each."

The through-line is **interpretation, not a factor dump.** The worked example ends on
a biological decision (this factor separates this known clinical axis at this AUC),
not a heatmap.

> **Tip** — Multi-omics integration needs the **same samples across layers**. The
> matrices must share sample columns (matched order). MOFA2 tolerates missing values
> within a layer; SNF needs complete data (BioMate mean-imputes per feature so SNF
> gets a fair run). If your layers are on *different* samples, that is a diagonal /
> mosaic problem — not yet supported here (see What's not covered).

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Integrate my RNA + methylation (+ proteomics) and give me interpretable shared factors" | `mofa2` (**MOFA2**, id **11853**), universal `// Input: omics` list | One CSV per layer (features × samples, matched columns) | `mofa_extracted_factors.csv` (samples × factors) + `mofa_extracted_weights.csv` (loadings) + variance plots PDF | Cloud (AWS Batch) |
| "Fuse my omics layers and cluster patients into molecular subtypes" | `Snf_multiomics` (**SNF**, id **14639**), same `// Input: omics` list | Same matched CSVs | `snf_clusters.csv` (sample → cluster) | Cloud |
| "Normalize each layer the same way before I integrate, so the comparison is fair" | `omics_normalize` (per-modality log2 / asinh / quantile / z-score + QC) | Raw per-layer CSVs | `normalized_<view>.csv` per layer + `omics_qc_metrics.csv` (before/after) + QC plots | Cloud |
| "Model a smooth covariate (e.g. time) across my omics, not just discrete factors" | `mofa2_mefisto_covariate_analysis` (**MEFISTO**, id **13192**) | Matched CSVs + a continuous covariate | Covariate-aware factors + interpolation | Cloud |
| "Weighted gene co-expression modules from my expression matrix" | `multiwgcna` (**WGCNA**, id **11914**); `biocor_wgcna_integration` (id 13339) | Expression matrix (genes × samples) | Co-expression modules + preservation stats + plots | Cloud |
| "Pathway / gene-set enrichment on a ranked gene list" | `clusterprofiler_gene_set_enrichment_analysis` (**GSEA**, id **12956**); ORA `clusterprofiler` (id 11122) | Ranked gene list / DE table | GO/KEGG/Reactome/WikiPathways enrichment table + dotplot | Cloud |
| "Protein–protein interaction network + enrichment from my gene set" | `stringdb` (id **12478**) | Gene list | STRING PPI network + enrichment | Cloud |

> **Pitfall — "multi-omics" is not "run DESeq2 on each layer separately."** If you
> just want per-layer differential analysis (RNA DE *and* protein DE, reported side
> by side), those are the single-domain chapters (Transcriptomics, Proteomics). This
> chapter is for **joint** decomposition — one model over all layers at once. Say
> "integrate" / "joint" / "shared factors" / "MOFA" / "fuse" so the intent is clear.

> **Pitfall — factors (MOFA2) vs clusters (SNF) are different answers.** MOFA2 gives
> you continuous, interpretable axes you interpret post-hoc against known biology;
> SNF gives you a hard partition. On the same CLL data MOFA2 recovered the IGHV axis
> *better* and *as a single interpretable factor* (see Worked example). Pick the tool
> to your question, not by habit.

## How to ask

BioMate routes on the **combining** intent plus the **modalities named**. The single
most important disambiguation is joint integration vs per-layer analysis.

Latent-factor integration (the default for paired continuous layers):

> "I have matched RNA-seq, DNA-methylation and proteomics from 40 tumour samples —
> run a multi-omics factor analysis and tell me which factors separate my subtypes."

Subtype clustering across layers:

> "Fuse my RNA and methylation layers and cluster the patients into molecular
> subtypes."

**How the routing decides.** The `mofa2` single workflow routes through normal
workflow search on integration vocabulary and returns the MOFA2 card with the omics
matrices shown as inputs (verified live: routing correct → *MOFA2 Multi-Omics Factor
Analysis*, `docs/20260726_E2E_AUDIT_SINGLECELL_MULTIOMICS.md:15-16`). A **method-
selection layer** exists behind the scenes (`method_selector.recommend` +
`integration_planner.plan_integration`) that picks the integrator *from your data
shape* — MOFA2 for paired continuous layers, SNF when the goal is clustering/subtypes,
intNMF for all-count data, and so on (`backend/lib/galaxy/ai/multiomics/method_selector.py:275`;
mapping in `integration_planner.py:27-38`).

**Disambiguation to avoid:**

- **Joint vs per-layer.** "Run DE on my RNA and my proteomics" is two single-layer
  jobs, not integration. Use an integration verb ("integrate", "combine", "joint",
  "fuse", "shared variation", "MOFA", "SNF") when you want one model over all layers.
- **Factors vs subtypes.** Ask for "interpretable shared factors / axes of variation"
  → MOFA2; ask for "molecular subtypes / patient clusters / how many groups" → SNF.
- **Same-sample requirement.** Integration needs matched samples across layers. If
  your layers are measured on *different* individuals (unpaired / diagonal), that is a
  different (unsupported) regime — say so rather than forcing it.

> **Tip — one input contract, many methods.** MOFA2, SNF, and the other matrix
> integrators (MCIA, intNMF, iClusterPlus, JIVE) all consume the **same** `// Input:
> omics` list — a matrix per modality, view name = filename. That is what lets you run
> a second method on identical inputs and compare fairly, instead of re-plumbing your
> data for each tool (`integration_planner.py:27-38`).

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| `mofa2` (id **11853**) | MOFA2 Bayesian latent-factor integration; emits factors + weights + variance decomposition | `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/mofa2/main.nf` (process `BIOC_MOFA2_STANDARD_MOFA_ANALYSIS:23`; `// Input: omics` list `:5,32`; outputs `:219-220`); DB id 11853, domain `systems_biology` |
| `Snf_multiomics` (id **14639**) | Similarity Network Fusion → fused patient network → spectral clustering into subtypes | `.../bioconductor/snf_multiomics/main.nf` (process `BIOC_SNF_MULTIOMICS:16`; `SNF()` + `spectralClustering()` `:99`; `snf_clusters.csv`); DB id 14639 |
| `omics_normalize` | Method-agnostic per-modality normalization + before/after QC (the fairness step feeding both methods) | `.../bioconductor/omics_normalize/main.nf` (process `:31`; `normalized_*.csv` `:43,186`; `omics_qc_metrics.csv` `:44,201`) |
| `mofa2_mefisto_covariate_analysis` (id **13192**) | MEFISTO — covariate-aware (e.g. temporal) factor model | `.../bioconductor/mofa2/mefisto_covariate_analysis.nf`; DB id 13192 |
| `multiwgcna` (id **11914**) | WGCNA co-expression modules + multi-trait comparison + permutation preservation | `.../bioconductor/multiwgcna/main.nf` (process `:27`; multiWGCNA R pipeline); DB id 11914 |
| `clusterprofiler_gene_set_enrichment_analysis` (id **12956**) | GSEA over GO/KEGG/Reactome/WikiPathways (`gseGO`/`gseKEGG`/`gseWP`) | `.../bioconductor/clusterprofiler/gene_set_enrichment_analysis.nf` (process `:21`); DB id 12956 |
| `clusterprofiler` (id **11122**) | Over-representation analysis (`enrichGO`/`enrichKEGG`) + cnetplot/emapplot | `.../bioconductor/clusterprofiler/main.nf` (process `:30`); DB id 11122 |
| `stringdb` (id **12478**) | STRING protein–protein interaction network + background-corrected enrichment | `.../bioconductor/stringdb/main.nf` (process `:30`); DB id 12478 |
| Method-selection layer | Chooses integrator from data shape (modalities, overlap, goal); maps method → runnable `main.nf` | `backend/lib/galaxy/ai/multiomics/method_selector.py:275`; `integration_planner.py:27-38,53-110` |

The **step→step contract is real and deterministic**: `omics_normalize` writes
`{outdir}/normalized_<stem>.csv`, and the integrator resolves its `omics` list to
exactly those files with no runtime S3 listing — proven against real Batch output
(`docs/20260811_MULTIOMICS_PIPELINE_LIVE_RUN.md:58-69`). That is why you can chain
normalize → integrate and know the second step will find its inputs.

> **License** — MOFA2, SNFtool, WGCNA, clusterProfiler, STRINGdb are open-source
> academic packages (Bioconductor / CRAN); results are yours. STRING and the
> GO/KEGG/Reactome/WikiPathways annotations are standard public releases.

## QC gates & how to read them

Multi-omics QC is about **fairness and conformability** before it is about the biology
— if the layers weren't put on comparable scales, any "shared factor" can be an
artifact of one layer's dynamic range.

| Gate | Threshold | What a fail means | Enforced where |
|---|---|---|---|
| **Matched samples across layers** | Identical sample set/order across all matrices | Non-conformable arrays; the run errors (SNF) or silently mis-aligns (any method) | **Code-enforced by the method** — MOFA2/SNF require identical samples/order across views; SNF is explicit ("SNF requires identical samples/order across views", `snf_multiomics/main.nf:75`) |
| **Per-layer normalization applied before integration** | Each layer normalized to comparable scale (log2/asinh/quantile/z; count-heuristic default) | One high-dynamic-range layer swamps the others — factors describe scale, not biology (the exact TCGA-collapse failure mode) | **Produced + logged** by `omics_normalize` (before/after `PMAD/PCV/frac_na/skew` in `omics_qc_metrics.csv`); it is a **step you run**, not an automatic halt |
| **Missing-value handling** | MOFA2 tolerates NAs natively; SNF gets per-feature mean imputation | Unhandled NAs break SNF's distance computation | **Code-handled** — MOFA2 native; SNF mean-imputes (`snf_multiomics/main.nf`) |
| **Factor → known-biology recovery** | e.g. a factor separating a known clinical axis at high AUC | If no factor tracks any known axis, either the biology is weak or the layers weren't fairly normalized | **Interpretive / advisory** — you score factors against ground truth (the harness `scripts/multiomics_metric_harness.py` does this for benchmarking; you read it for your own data) |

**How to read each:**

- **Matched samples** — the non-negotiable precondition. If two layers don't share the
  same sample columns in the same order, fix the matrices first; nothing downstream is
  meaningful otherwise.
- **Normalization fairness** — run `omics_normalize` first and read `omics_qc_metrics.csv`:
  each view's post-normalization SD should be ~1 and skew near 0. This is the guard
  against the classic failure where an expression block (values in the thousands)
  drowns a methylation block (β in 0–1). The ranking of methods held under provably-
  identical normalization on CLL, so the head-to-head isn't a preprocessing artifact
  (`docs/20260727_MULTIOMICS_BENCHMARK_DESIGN.md:261-273`).
- **Factor recovery** — the single most informative "is this real" check. Join your
  factors to a known label (subtype, mutation status, survival) and test association;
  a factor that cleanly separates a known axis is your credibility anchor before you
  interpret the *novel* factors.

> **QC gate — normalize before you integrate.** The fairness of a multi-omics result
> lives almost entirely in the shared upstream normalization. Run `omics_normalize`
> across all layers first so every method sees provably-identical inputs; then the
> difference you see between MOFA2 and SNF is real method behaviour, not a scaling
> accident.

> **Pitfall — a factor that explains one layer only is not "integration."** MOFA2's
> variance decomposition tells you, per factor, how much variance comes from each
> layer. A factor drawing ~all its variance from one layer is a *layer-specific* axis
> (fine to report as such) — the *shared* factors (variance spread across layers) are
> the multi-omics payoff. Read the variance plot before you tell an integration story.

### What "fixing" a QC issue looks like here

Unlike ADMET (which auto-tunes a filter), multi-omics QC issues are **data-shape and
normalization** problems you correct and re-run:

- Non-matched samples → subset/reorder your matrices to the common sample set, re-run.
- One layer dominating the factors → run `omics_normalize` (or a stronger transform
  for that layer) and re-integrate. No need to re-collect data.
- No factor tracks known biology → check normalization first; then consider whether
  the layers genuinely share signal, or whether the effect is single-layer.

There is **no automatic multi-omics auto-loop** — these fixes are manual, and this
chapter says so.

## Worked example (gold standard)

**Goal.** Run the flexible normalize → integrate pipeline on a cohort where the right
answer is known, and read the top factor as a biologist would.

**Dataset.** The **Dietrich CLL cohort** (chronic lymphocytic leukaemia; Dietrich et
al., *J Clin Invest* 2018 — the canonical MOFA vignette cohort), staged at
`s3://biomate-nextflow-work/cll_test/`. Two layers used here — **mRNA** (`mrna.csv`,
12.5 MB) and **DNA-methylation** (`methylation.csv`, 14.9 MB) — over matched patients,
with **IGHV mutation status** (`ighv_labels.csv`: 104 mutated / 84 unmutated) as the
held-out ground truth. IGHV status is the dominant, clinically-load-bearing axis of CLL
biology, so it is a hard, published readout to score the pipeline against
(`docs/20260811_MULTIOMICS_PIPELINE_LIVE_RUN.md:14-18,99-113`).

**Prompt:**

> "I have matched mRNA and DNA-methylation from a CLL cohort — normalize each layer and
> run a multi-omics factor analysis."

**What comes back and how to read it:**

- **Step 0 — normalize (real Batch run `af1f0a1f`, SUCCEEDED).** `omics_normalize`
  emitted `normalized_mrna.csv`, `normalized_methylation.csv`, and
  `omics_qc_metrics.csv` directly at `{outdir}/normalized_<stem>.csv`. Interpretation:
  both layers are now on a comparable scale, so the factors that follow describe
  biology, not one layer's dynamic range. (Layout matched the `resolve_pipeline`
  contract exactly — `20260811:52-69`.)
- **Step 1 — MOFA2 (real Batch run `7e8979d1`, SUCCEEDED).** Emitted
  `mofa_extracted_factors.csv` (samples × 10 factors, 89 KB) and
  `mofa_extracted_weights.csv` (feature loadings, 6.2 MB). The factors table is the
  artifact you carry forward — a filterable table, not a picture.
- **The ground-truth check.** Scoring each MOFA factor against IGHV status
  (direction-agnostic Mann–Whitney AUC, n=188):

  | Factor | \|AUC vs IGHV\| |
  |---|---|
  | **Factor 1** | **0.962** |
  | Factor 5 | 0.641 |
  | Factor 4 | 0.599 |
  | others | ≤ 0.57 |

  Interpretation: **Factor 1 separates IGHV-mutated from unmutated at AUC 0.962** —
  reproducing the canonical MOFA CLL result (Argelaguet 2018 reported ~0.968). One
  interpretable axis, learned from RNA + methylation jointly, recovers the field's
  reference clinical axis. That is your credibility anchor for reading the *other*
  factors on this cohort.
- **The method contrast (same inputs, same harness).** Run through BioMate on the same
  data, **SNF** clusters the fused network but recovers IGHV only at matched-k=3
  ARI 0.375, versus MOFA2's ARI 0.526 and its single-factor AUC 0.962 — MOFA2 recovers
  the axis better *and* exposes it as one interpretable factor. The ranking held under
  provably-identical normalization (`docs/20260727_MULTIOMICS_BENCHMARK_DESIGN.md:237-273`).

**The artifact.** A factors table (`mofa_extracted_factors.csv`) + a weights table +
the variance-decomposition plots. You end on a decision — *Factor 1 is the IGHV axis at
AUC 0.962; here are the genes and CpGs that load on it* — a gold-standard-comparable
result, not a process tree.

> **Note (verification tier).** The workflow files, IDs (11853 / 14639), the universal
> `omics` contract, and the normalize→integrate step contract are **code-verified (C)**
> by reading source (citations above). The CLL run is stronger than a spec claim: it is
> a **recorded live AWS Batch run** (normalize `af1f0a1f`, MOFA2 `7e8979d1`; plus
> benchmark runs `6517aaf4` / `c96493d7` / SNF `fc3b1719`) with the IGHV-AUC scored
> post-hoc — tier **C + live-run (L ✅ recorded)** per `docs/20260811_...` and
> `docs/20260727_MULTIOMICS_BENCHMARK_DESIGN.md`. What was **not** yet productionized at
> that time: a one-click `execute_and_wait` that drives *both* steps from a single chat
> action (the two steps were driven manually to de-risk), and the `MULTIOMICS_ROUTING`
> integration card is default-OFF (`20260811:123-129`) — see What's not covered.

## Outputs & visualization

Outputs render in the after-run panel's Outputs tab via the in-app viewer taxonomy
(`frontend/client/src/components/step-output-preview.tsx`), mapped by file extension.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| MOFA2 factor table | `mofa_extracted_factors.csv` | **Table** viewer (sortable, preview + full download) | Download to join factors to your clinical metadata and test associations |
| MOFA2 feature loadings | `mofa_extracted_weights.csv` | **Table** viewer | Sort by \|weight\| per factor to read the top drivers in each layer |
| Variance decomposition / factor plots | `mofa_analysis_plots.pdf` | **PDF iframe** viewer | Read *before* interpreting factors — tells you shared vs layer-specific |
| SNF clusters | `snf_clusters.csv` | **Table** viewer | Download to cross-tab clusters against known subtypes |
| Normalization QC | `omics_qc_metrics.csv` + `omics_qc_plots.pdf` | **Table** + **PDF** viewer | Confirm each layer's post-norm SD≈1 / skew≈0 before trusting the integration |
| Enrichment (GSEA/ORA) | `*_results.csv` / `.tsv` | **Table** viewer | Download for the pathway figure; sort by adjusted p-value |
| WGCNA modules / dotplots | `*.pdf` / `*.csv` | **PDF / Table** viewer | Export module plots; download module membership |

> **Tip — read the variance plot before the factors.** The MOFA variance
> decomposition tells you which factors are genuinely *shared* across layers. Interpret
> those as your multi-omics story; treat single-layer-dominated factors as
> layer-specific. This is the "is my integration real" plot, and it's cheap to read
> in-app.

## Pitfalls & tips

> **Pitfall — matched samples are mandatory.** Every layer must cover the same samples
> in the same order. SNF errors on non-conformable arrays; other methods can silently
> mis-align. Subset to the common sample set first.

> **Pitfall — normalize across layers or your factors describe scale, not biology.**
> The documented TCGA-collapse failure came from an unnormalized high-dynamic-range
> layer swamping a low-range one. Run `omics_normalize` first; confirm post-norm SD≈1.

> **Tip — run two methods on the same input and compare.** The universal `omics`
> contract lets MOFA2 and SNF (and MCIA/intNMF/…) run on identical matrices. Comparing
> a factor decomposition against a hard clustering on the same data is often more
> informative than either alone — MOFA2 won the CLL IGHV recovery, but the comparison
> is the evidence.

> **Tip — factors are hypotheses until you tie them to metadata.** A MOFA factor is
> just an axis until you associate it with a known variable (subtype, mutation,
> survival). Download the factors table, join your clinical metadata, and test — that
> association (like Factor 1 ↔ IGHV) is what turns a factor into a finding.

> **QC gate — a factor is "shared" only if its variance spans layers.** Use the
> variance decomposition to separate shared factors (the multi-omics payoff) from
> layer-specific ones before you write the story.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in
**Appendix E (Coverage & roadmap)**:

- **The GWAS → scRNA → eQTL "target prioritization chain."** A `gwas_scrna_eqtl_target_chain`
  file exists (`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gwas_scrna_eqtl_target_chain/main.nf`,
  540 lines) and routes via a hardcoded override, but it is **not documented as
  supported** because it does not do what it claims: (1) its docstring promises
  eQTL **colocalization with PP4** (`:16`) but the code never computes PP4 — it reduces
  eQTL evidence to a **binary "any eQTL found?"** gate (`:284,372`); (2) its "Layer 3"
  scRNA cell-type profile is **hardcoded reference data** for three genes
  (CD40LG / FCGRT / CHRNA1, `:306-332`), not a live CellxGene query — the exact
  demo-data fallback the honesty rule forbids; (3) it is **not registered in the
  `workflow_chains` DB** and depends on a fragile router regex. It was "❌ Proposed /
  not built" as of `docs/20260718_CONFERENCE_BD_X_WORKFLOW_PRIORITY.md:26,52`; the
  current build runs but is capability-incomplete. **Treat coloc/PP4-based target
  prioritization as roadmap, not a supported chain.**
- **The curated 4-step MOFA+ chain** (`multi_omics_mofa_chain.json`:
  `rnaseq_deseq2_de` → `bioc_proteomics_de_v2` → `lcms_metabolomics_consensus` →
  `mofa_plus_integration`) is defined but is **distinct from the verified `mofa2`
  single-workflow path** that actually ran on CLL. The live-verified capability is the
  universal `mofa2` / `Snf_multiomics` workflow on matched CSVs — not this fixed
  RNA+protein+metabolite chain, which has not been live-verified end-to-end here.
- **One-click chained execution.** The CLL normalize → MOFA2 run was driven **two steps
  manually** to de-risk; the production `execute_and_wait` that drives both from a
  single chat action, and the `MULTIOMICS_ROUTING=1` integration card, were **not yet
  enabled** (`docs/20260811_MULTIOMICS_PIPELINE_LIVE_RUN.md:123-129`). Run normalize,
  then integrate, as two actions.
- **Single-cell and spatial multi-omics integration.** CITE-seq / Multiome (RNA+ATAC),
  StabMap (mosaic), GLUE (diagonal/unpaired), totalVI/MultiVI, SpatialGlue — the field's
  single-cell and spatial integration methods — are **not packaged as runnable
  workflows** (StabMap is explicitly `_NOT_YET_RUNNABLE`, `integration_planner.py:41`).
  Supported integration here is **bulk matrix, matched-sample** only.
- **Additional matrix integrators as documented workflows.** MCIA, intNMF,
  iClusterPlus, JIVE, MFA/rGCCA **exist** and share the universal contract (DB ids
  14632–14639; `integration_planner.py:27-38`), but only MOFA2 and SNF have a recorded
  gold-standard live run in this chapter. The others are available-but-undocumented
  (roadmap).
- **Deep coverage of the systems-biology catalog.** WGCNA (11914), clusterProfiler
  GSEA/ORA (12956/11122), STRINGdb (12478), MEFISTO (13192), KEGGgraph, and the ~100
  `systems_biology` catalog workflows **exist and route**, but this chapter documents
  only their entry points — end-to-end worked examples + gold-standard validation for
  them are roadmap.
- **No multi-omics auto-loop.** QC fixes (matched samples, normalization) are manual;
  there is no automatic remediation loop.
- **Interactive tools (RStudio / Jupyter) launch.** Not provisioned on dev (the
  availability probe returns `available:false`); in-app table/PDF viewers cover reading
  outputs.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Multi-omics & systems biology"** — `mofa2` id 11853 + universal `// Input: omics`
list + factor/weight outputs (C); `Snf_multiomics` id 14639 fuse+spectral-cluster (C);
`omics_normalize` per-modality norm + deterministic `normalized_<stem>.csv` step
contract (C); method-selection layer `method_selector.recommend` / `integration_planner`
(C); Dietrich CLL worked example — Factor 1 AUC 0.962 vs IGHV, MOFA2>SNF ARI, on
recorded AWS Batch runs `af1f0a1f`/`7e8979d1`/`6517aaf4`/`fc3b1719` (C + L ✅ recorded);
MOFA2 routing correct on live dev (C); systems-biology catalog existence — multiwgcna
11914, clusterProfiler 12956/11122, stringdb 12478, mefisto 13192 (C existence, 🗺️ deep
coverage); and the roadmap/gap rows — GWAS→scRNA→eQTL chain (coloc/PP4 absent, hardcoded
scRNA, not DB-registered → 🗺️/🔧), curated MOFA+ chain vs verified single workflow (🔧),
one-click execute_and_wait + MULTIOMICS_ROUTING default-OFF (🗺️), single-cell/spatial &
StabMap not runnable (🗺️), other matrix integrators undocumented (🗺️)._
