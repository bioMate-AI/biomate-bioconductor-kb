# Transcriptomics (bulk RNA-seq)

> One-line promise: go from either a **count matrix** or **raw FASTQ** to a
> ranked list of differentially expressed genes, a volcano plot you can read at a
> glance, and the enriched pathways behind the signal — with the QC gates that
> tell you whether the numbers are trustworthy before you interpret them.
> For: **wet-lab biologists / PIs** with a treated-vs-control experiment and no
> desire to write R, and **bioinformaticians** who want the nf-core production
> chain run and reported for them. No coding required.

<!--
P1 chapter. Every "supported" claim below is green in coverage-ledger.md § "Transcriptomics (bulk RNA-seq)".
Honesty rule: a QC threshold is documented as "enforced" ONLY where it lives in pipeline code (qc_trace_monitor.py
/ qc_evidence.yaml). Thresholds that live only in the tutorial demo spec are labelled "visual / advisory" and
their real code default is stated where it differs. Anything not built is in "What's not covered".
-->

## What this is for

This is the **"which genes changed, and what do they do"** path. You have two or
more groups of samples — treated vs control, tumour vs normal, timepoint A vs B —
and you want to know which genes go up, which go down, and which biological
pathways that movement implicates.

BioMate meets you at whichever point you are already at:

1. **You already have a count matrix** (from Salmon, STAR, featureCounts, recount2,
   or a collaborator). BioMate runs the differential-expression step directly —
   this is the fast, freemium front door.
2. **You have raw FASTQ reads.** BioMate runs the full production chain:
   align + quantify (nf-core/rnaseq) → differential expression (DESeq2) →
   gene-set enrichment (clusterProfiler), and reports QC at every hand-off.

The through-line of this chapter is **interpretation, not a statistics dump.**
Every QC number below is explained as "what it means and what to do next," and the
worked example ends on a *decision* (these genes, these pathways, this confidence),
not a process tree.

> **Tip** — You do not need FASTQ to get value. If you already have a counts table,
> jump straight to differential expression — it is the cheapest, fastest lane.
> Alignment from FASTQ is the expensive step (STAR/Salmon on AWS Batch); run it
> only when you actually have raw reads to process.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "I have a count matrix — find genes up/down, treated vs control" | `nf-core/differentialabundance` (DESeq2), id **1497**; the downstream-only chain `bioc_bulk_rnaseq_de_v2` composes it with enrichment | Counts CSV (genes × samples) + sample sheet + contrast | DE table (log2FC, padj) + volcano + sample-distance heatmap | Cloud (AWS Batch) |
| "Run the whole pipeline from my FASTQ: align, DE, and pathways" | chain **`bulk_rnaseq_de_analysis`**: nf-core/rnaseq (1491) → differentialabundance (1497) → clusterProfiler GSEA (12956) | FASTQ + sample sheet + contrast | MultiQC HTML + DE table + GSEA table + volcano/heatmap | Cloud |
| "Same, but I want the Bioconductor bare-R path with an R Markdown narrative" | chain `bulk_rnaseq_consensus_de_bioc` (nf-core/rnaseq + bare-R DESeq2, swappable to edgeR/limma, + clusterProfiler ORA) | FASTQ + sample sheet + contrast | DE table + ORA table + R Markdown report + sessionInfo | Cloud |
| "Detect gene fusions in my tumour RNA-seq" | `nf-core/rnafusion` (id **12771**) | FASTQ | Fusion call table | Cloud |
| "Find differential splicing / alternative isoform usage" | `nf-core/rnasplice` (id **12772**); `dexseq` (11259); `sgseq_*` (13246/13247) | FASTQ or counts | Differential splicing table | Cloud |

> **Pitfall** — This chapter is **bulk** RNA-seq. If your data is single-cell (10x
> Chromium, Cell Ranger output, an `.h5ad`), do **not** run these workflows —
> DESeq2 run cell-by-cell inflates false positives because cells from one donor are
> not independent replicates. BioMate routes single-cell prompts to a separate
> chain; see "How to ask" and the Single-cell chapter.

## How to ask

BioMate routes on intent. The disambiguation that matters here is **what you
already have** (count matrix vs FASTQ) and **bulk vs single-cell**.

Count-matrix DE (the fast lane):

> "I have a count matrix — run differential expression, treated vs control, and
> tell me which genes are up and down."

Full pipeline from FASTQ:

> "Run nf-core rnaseq then differential expression and GSEA. FASTQ uploaded,
> conditions ctrl (samples 1–3) vs treated (samples 4–6), reference GRCh38."

**How the routing actually decides** (verified in
`backend/lib/galaxy/ai/unified_workflow_search.py:2602-2619`). The
`bulk_rnaseq_de_analysis` chain is matched when your prompt carries any of:

- **DE intent** — "differential expression", "differentially expressed", "deseq2",
  "edger", "limma", "voom", "fold change", "log2fc", "padj", "fdr", "up/downregulated".
- **You already have processed input** — "salmon output/quant", "kallisto output",
  "my count table / count matrix", "have counts".
- **Downstream analysis** — "pathway enrichment", "gsea", "go enrichment",
  "gene ontology", "pathway analysis".

**Disambiguation to avoid:**

- **Bulk vs single-cell — the documented pitfall.** Single-cell prompts must NOT
  route to the bulk differential-abundance chain. The router enforces this in code:
  a query is only allowed onto the single-cell chain if it carries single-cell
  context ("single cell", "scrnaseq", "10x genomics", "cell ranger", "seurat",
  "scanpy", "anndata", "umi counts", …), via
  `_chain_multimodal_context_compatible()`
  (`unified_workflow_search.py:2620-2657`). The in-code comment is explicit:
  *"Bulk RNA-seq queries share vocabulary with this chain but describe completely
  different assays."* If your data is single-cell, say so — that one word flips the
  route and gets you the correct pseudo-bulk statistics.
- **FASTQ vs count matrix.** "Run RNA-seq on my FASTQ to get a count matrix" should
  land on **nf-core/rnaseq alone** (alignment/quant), not the DE chain — DE needs a
  count matrix as input. If you want the whole thing end-to-end, say "…then
  differential expression and GSEA" so the full chain is selected. (Regression test
  `test_workflow_retrieval_semantic.py:356-366` guards exactly this.)
- **Microarray vs RNA-seq.** DESeq2 and edgeR model *raw integer counts* (negative
  binomial). If you have Affymetrix / continuous log₂ intensities, the correct tool
  is **limma** — applying a count model to normalised intensities is statistically
  wrong. Mention "microarray" or "Affymetrix" and BioMate routes to limma instead.

> **Tip — three bulk-DE chains, one intent, different entry points.** BioMate keeps
> three chains apart on purpose (`differentiate_ambiguous_chains.py`):
> `bulk_rnaseq_de_analysis` = one-click nf-core production path (HTML report, GSEA);
> `bulk_rnaseq_consensus_de_bioc` = Bioconductor bare-R path (swappable DE method, R
> Markdown); `bioc_bulk_rnaseq_de_v2` = downstream-only when you *already have a
> count matrix*. Naming what you have — FASTQ or counts — picks the right one.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| Chain `bulk_rnaseq_de_analysis` | 3-step production pipeline FASTQ→DE→GSEA | `backend/scripts/index_all_workflows.py:474-507`; DB `workflow_chains` (name pinned by `pin_bioc_chain_workflow_ids.py`) |
| `nf-core/rnaseq` (id **1491**) | Alignment + quantification; default `aligner=star_salmon`, `genome=GRCh38` | `backend/biomni_workflows/nfcore/rnaseq/main.nf:12,14`; DB id 1491 |
| `nf-core/differentialabundance` (id **1497**) | DESeq2 differential expression; accepts a `matrix` (counts) directly | `backend/biomni_workflows/nfcore/differentialabundance/main.nf:9,16` (`normalisation_method='deseq2'`); DB id 1497 |
| `clusterprofiler_gene_set_enrichment_analysis` (id **12956**) | GO / KEGG / Reactome enrichment (clusterProfiler, `org.Hs.eg.db`) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/clusterprofiler/gene_set_enrichment_analysis.nf`; DB id 12956 |
| Chain routing / disambiguation | Keyword + context gating; bulk-vs-single-cell guard | `backend/lib/galaxy/ai/unified_workflow_search.py:2602-2657` |
| QC-gate monitor | Reads STAR/Salmon metrics from run trace, applies thresholds | `backend/lib/galaxy/jobs/qc_trace_monitor.py` (STAR `4589`, Salmon `4625`); evidence `backend/config/qc_evidence.yaml:1665-1669` |
| Other bulk-RNA workflows | fusion `nf-core/rnafusion` (12771), splicing `nf-core/rnasplice` (12772) + `dexseq` (11259) + `sgseq` (13246/13247), circRNA `nf-core/circrna` (12681), RNA variant `nf-core/rnavar` (12773) | DB `workflows` |

The chain's step-to-step hand-off is real, not decorative: step 1's `counts_matrix`
output feeds step 2's `counts` input; step 2's `de_results` feeds step 3's
`gene_list` input (`index_all_workflows.py:486-489`). That is why a count matrix can
enter at step 2 — the contract is the file, not the pipeline position.

> **License** — nf-core pipelines and Bioconductor packages (DESeq2, clusterProfiler)
> are open-source academic tools; results are yours. The GRCh38 reference and
> GO/KEGG/Reactome annotations are the standard public releases.

## QC gates & how to read them

A QC gate answers one question for a biologist: **"can I trust the DE list I'm
about to interpret?"** For bulk RNA-seq the gates sit at the two hand-offs where
things silently go wrong — alignment and sample clustering.

| Gate | Threshold | What a fail means | Enforced where |
|---|---|---|---|
| **STAR uniquely-mapped %** | **≥ 70%** pass · 50–70% advisory · < 50% fail | Reads aren't landing uniquely on the genome — wrong reference, contamination, or degraded RNA. Downstream counts are unreliable. | **Code-enforced.** `qc_trace_monitor.py:4589` (default 70.0 for STAR_ALIGN); evidence `qc_evidence.yaml:1665-1669` (ENCODE-anchored, SILVER provenance) |
| **Salmon mapping rate %** | Tutorial target **≥ 70%**; **code default 50%** | Reads aren't mapping to the transcriptome — same causes as above, at the quantification step. | **Code default is 50%** (`qc_trace_monitor.py:4625`), *not* the 70% the tutorial spec quotes — see the pitfall below |
| **DESeq2 sample-distance = clear clusters** | Samples in a condition group together; groups separate | If treated and control don't separate on the sample-distance heatmap / PCA, your biological signal is weaker than your batch/technical noise — interpret the DE list with caution or check for a swapped label. | **Visual / advisory.** The heatmap is produced as a diagnostic plot (`qc_evidence.yaml:1715-1725` dispersion/QC plots); there is **no automated "2 clusters" pass check** — you read it |

**How to read each:**

- **Uniquely-mapped ≥ 70%** — for human/mouse this is routine; 80–90% is typical.
  A number in the 50–70% band is *advisory*: the run continues, but treat it as
  "check your reference genome and RNA quality." Below 50% something is wrong (wrong
  organism, heavy rRNA/adapter contamination) — don't interpret DE from it.
- **Salmon mapping rate** — read it the same way as uniquely-mapped. Be aware the
  in-app gate trips at 50%, so a 55% run will *not* be flagged even though the
  tutorial gold-standard demo expects 70% for a clean library. Use 70%+ as your own
  interpretive bar for a high-quality human/mouse library.
- **Sample-distance heatmap** — this is the single most informative "is my
  experiment real" plot. Two clean blocks (treated together, control together) means
  your contrast is well-posed. A sample sitting in the wrong block often means a
  mislabelled sample or a dominant batch effect — fix the metadata and re-run the DE
  step (you do not need to re-align).

> **Pitfall — the Salmon 70% number is a target, not a code gate.** The tutorial /
> gold-standard spec lists "Salmon mapping rate ≥ 70%," but the enforced default in
> `qc_trace_monitor.py:4625` is **50%**. The manual states the code truth: the
> automatic flag fires below 50%. Apply 70% as your own quality bar for model
> organisms; don't assume the system halted a 60%-mapping run for you.

> **QC gate — clustering before conclusions.** The sample-distance heatmap is
> advisory (you read it, the system doesn't halt on it). But it is load-bearing:
> interpret it *before* the volcano plot. If groups don't separate, no p-value
> threshold will rescue the biology.

### What "fixing" a QC fail looks like here

Unlike the ADMET auto-loop (which re-tunes a screening filter), bulk RNA-seq QC
issues are usually **metadata or reference** problems you correct and re-run:

- Wrong contrast / condition column → correct the sample sheet, re-run the **DE
  step only** (step 2). No re-alignment needed — this is why the count-matrix entry
  point matters.
- Low mapping → check you selected the right `genome` (GRCh38 vs GRCm39 etc.) and
  strandedness (`auto` is the default and usually right).
- A suspiciously huge DE list (thousands of "significant" genes) almost always means
  a mis-specified contrast, not real biology — re-check labels before believing it.

## Worked example (gold standard)

**Goal.** Run the full FASTQ→DE→GSEA chain on a benchmark where the *right answer is
known*, and read the artifact as a biologist would.

**Dataset.** `GSE49712` — the SEQC / MAQC-III consortium reference set
(*Nat Biotechnol* 32:903, 2014): 10 samples, 5× Mix A vs 5× Mix B, with **ERCC
spike-in transcripts at known fold-change ratios** (4:1, 1:1, 0.67:1, 0.5:1). The
spike-ins are the ground truth — we know exactly which "genes" should move and by
how much, so we can score the whole pipeline, not just eyeball it.
(`evaluation/tutorial_demos/gold_standards.yaml:5-15`;
`Tutorial Demo Scenarios 7-domain.md:39-96`.)

**Prompt** (the recorded tutorial T1):

> "Run nf-core rnaseq then differential expression and GSEA."

**What comes back and how to read it:**

- **Alignment QC (MultiQC).** Mean uniquely-mapped ≈ **87%** across the 10 samples —
  comfortably over the 70% gate. Interpretation: clean, well-mapped libraries; the
  counts are trustworthy. This is your sanity anchor before looking at any gene.
- **Sample-distance heatmap.** Mix A samples cluster together, Mix B together, with
  a clean split. Interpretation: the contrast is well-posed; the DE that follows
  reflects the A-vs-B design, not noise.
- **DE table.** ≈ **8,400 genes at FDR < 0.05** for the `B_vs_A` contrast, each with
  a log2 fold-change and adjusted p-value. This is the artifact you carry forward —
  a ranked, filterable list, not a picture.
- **The ground-truth check.** Joining the ERCC spike-ins to their known ratios gives
  **~92% truth recovery** (fraction of spike-ins whose fold-change sign/direction
  matches the design) and AUC-ROC ≈ 0.95 of `padj` vs ERCC class — matching the
  SEQC/MAQC-III benchmark. Interpretation: the pipeline recovers known biology at
  the published standard, so you can trust it on your unknown genes too.
- **GSEA.** Top enriched pathway: **cell cycle (KEGG), padj ≈ 1.2e-12.** Interpretation:
  the gene-level movement aggregates into a coherent biological story — this is what
  you report, not the raw gene list alone.

**The artifact.** A DE results table (`de_results.tsv`) + a volcano plot + the
enrichment table. You end on a decision — *these genes moved, this pathway is driving
it, at benchmark-grade confidence* — which is exactly the "gold-standard-comparable
artifact" the tutorial-demo plan mandates.

> **Note (verification tier).** The chain wiring, workflow IDs (1491 / 1497 / 12956),
> default params, routing, and QC gates are **code-verified (C)** by reading source
> (citations above). The numeric outputs (~8,400 DEGs, 92% ERCC recovery) come from
> the gold-standard demo spec; a **fresh live AWS Batch re-run** to reproduce those
> exact numbers is **pending (L / ⏳)** and was not fired — Batch runs cost real money
> and the plan forbids speculative execution.

## Outputs & visualization

Every output renders in the after-run panel's Outputs section via the in-app viewer
taxonomy (`frontend/client/src/components/step-output-preview.tsx`); the mapping
below is by file extension.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| MultiQC alignment/quant report | `multiqc_report.html` | **HTML iframe** viewer (sandboxed; `step-output-preview.tsx:973-976`) | Read STAR/Salmon per-sample rates inline; no export needed |
| Volcano plot | `*.png` / `*.pdf` | **Image** viewer (click-to-zoom) or **PDF iframe** (vector stays sharp) | Export PDF for the figure panel |
| Sample-distance heatmap / PCA | `*.pdf` | **PDF iframe** viewer | Read before the volcano — the "is my experiment real" plot |
| DE results table | `de_results.tsv` / `.csv` | **Table** viewer (sortable, 200-row preview + full download; `step-output-preview.tsx:209-280`) | Download CSV to filter/sort for your own SAR/target triage |
| GO / KEGG / Reactome enrichment | `enrichment_results.csv` / `.tsv` | **Table** viewer | Download for the pathway figure; sort by adjusted p-value |
| Enrichment dotplot | `*.pdf` / `*.png` | **PDF / Image** viewer | Export for the figure panel |
| R Markdown narrative (Bioc path) | `.html` | **HTML iframe** viewer | The bare-R path bundles full `sessionInfo` for reproducibility |

> **Tip — read the table in-app, don't re-plot.** The DE table renders sortable in
> the panel with a 200-row preview and a full-file download. Sort by `padj` to see
> your top hits, or by `log2FC` for effect size — you rarely need to open RStudio
> just to look. Go interactive (RStudio/Jupyter) only when you want to re-analyse,
> and only where those tools are provisioned (see What's not covered).

## Pitfalls & tips

> **Pitfall — bulk vs single-cell is a real statistical error, not a preference.**
> Running DESeq2 on individual cells inflates false positives (cells from one donor
> aren't independent). If your input is 10x / Cell Ranger / `.h5ad`, use the
> single-cell chain (pseudo-bulk aggregation by donor). Say "single-cell" in your
> prompt so the router's context guard sends you there.

> **Pitfall — count model needs counts.** DESeq2/edgeR require **raw integer
> counts**. Don't feed them TPM, FPKM, or normalised/log-transformed values, and
> don't use them on microarray intensities — say "microarray" / "Affymetrix" so
> BioMate routes to limma instead.

> **Tip — start from the matrix if you have it.** Alignment (STAR/Salmon) is the
> expensive Batch step. If a collaborator already gave you a count matrix, ask for
> "differential expression on my count matrix" — you skip straight to the fast lane.

> **Tip — a giant DE list usually means a wrong contrast.** Thousands of
> "significant" genes is more often a mislabelled condition column than dramatic
> biology. Check the sample-distance heatmap and your contrast labels first; correct
> the sample sheet and re-run the DE step only (no re-alignment).

> **QC gate — read the Salmon rate yourself.** The automatic flag trips at 50%, but
> a clean human/mouse library should map ≥ 70%. A 55–65% run passes the code gate
> yet warrants a second look at reference and RNA quality.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in
**Appendix E (Coverage & roadmap)**:

- **A bulk-RNA auto-loop / auto-remediation.** Unlike the ADMET chapter, there is no
  automatic parameter-tuning loop for RNA-seq QC fails. Low mapping or a bad contrast
  is surfaced to you to correct (metadata/reference) and re-run — the fix is manual,
  and the manual says so.
- **Automated "sample-distance = 2 clusters" gate.** The heatmap is produced as a
  diagnostic plot; the "clear clusters" criterion is a **visual judgement you make**,
  not a code-enforced pass/fail. Do not assume the system halted on poor clustering.
- **Salmon 70% enforcement.** The enforced code default is **50%**
  (`qc_trace_monitor.py:4625`); the 70% figure is a tutorial target, not the gate the
  system actually applies.
- **Deep coverage of fusion / splicing / RNA-variant workflows.** `nf-core/rnafusion`
  (12771), `nf-core/rnasplice` (12772), `dexseq` (11259), `sgseq` (13246/13247),
  `nf-core/circrna` (12681) and `nf-core/rnavar` (12773) **exist in the catalog** and
  route, but this chapter documents only that they exist and their entry point — the
  end-to-end worked examples and gold-standard validation for them are **not written
  or live-verified here** (roadmap). Treat them as available-but-undocumented until a
  dedicated section lands.
- **Interactive tools (RStudio / Jupyter) launch.** On dev these are **not
  provisioned** (the availability probe returns `available:false`); the launch
  buttons are correctly hidden. In-app table/plot/HTML viewers cover reading outputs;
  interactive re-analysis is environment-dependent.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Transcriptomics (bulk RNA-seq)"** — chain `bulk_rnaseq_de_analysis` + step IDs
1491/1497/12956 + default params (C), count-matrix entry point via
differentialabundance `matrix` (C), routing keywords + bulk-vs-single-cell context
guard (C), three-chain disambiguation (C), STAR ≥70% code-enforced gate (C), Salmon
50%-code-vs-70%-doc mismatch (C 🔧), DESeq2 sample-distance visual-only (C), viewer
taxonomy for MultiQC/volcano/heatmap/DE-table/enrichment (C), GSE49712 gold-standard
artifact + ERCC recovery (C from demo spec; live-Batch numeric re-run L / ⏳), and the
roadmap/gap rows (🗺️)._
