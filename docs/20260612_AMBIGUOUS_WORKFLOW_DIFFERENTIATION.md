# Differentiating ambiguous workflow descriptions

**Date**: 2026-06-12
**Trigger**: cross-check on `docs/20260612_BIOC_CHAINS_DESIGN.md` showed retrieval ambiguity between Bioconductor-bare workflows and nf-core pipeline equivalents.

## What the user asked

> "if they are of the same intent, why use bioconductor, aren't they the same? I want to make the fields of such ambiguous workflows or tools be more differentiating"

Right framing. They are NOT the same — same statistical *intent*, different *execution shape*. The DB descriptions didn't make the shape distinction clearly enough.

## The 4 workflows touched

| Workflow | Real role | Before | After |
|---|---|---|---|
| `deseq2` | Bare Bioc R/Markdown workflow — single-method DESeq2 | description (103 chars) was generic — didn't flag "single-method" or "for multi-method use X" | description (526 chars) now states "Bare Bioconductor R/Markdown workflow ... single method ... for one-click multi-method nf-core pipeline use nf-core/differentialabundance" |
| `nf-core/differentialabundance` | nf-core pipeline wrapping DESeq2 + limma + edgeR + GSEA + HTML | **annotation_v2 empty (0 bytes)** while deseq2 had 2.5KB — asymmetric data biased retrieval | annotation_v2 (1328 bytes) now populated with key_parameters / alternatives (pointing back at `deseq2`) / when_to_use / pitfalls |
| `clusterprofiler` | ORA on a discrete gene list | **identical** annotation_v2 to GSEA variant — copy-paste bug | description + annotation_v2 explicitly say "Over-Representation Analysis (ORA) on an unranked gene list" and alternative points at GSEA variant |
| `clusterprofiler_gene_set_enrichment_analysis` | GSEA on a ranked statistic vector | **identical** annotation_v2 to ORA variant | description + annotation_v2 explicitly say "GSEA on a RANKED list" with KS-style explanation and pointer to ORA variant |

Three structural problems were latent in the DB:

1. **Generic description on `deseq2`** — didn't say "single-method" or distinguish from the nf-core pipeline.
2. **Asymmetric annotation_v2** — `deseq2` had a rich annotation (2,539 chars); `nf-core/differentialabundance` had **none** (0 chars). Retrieval signals derived from annotation_v2 were unbalanced.
3. **Copy-paste annotation_v2** on the clusterProfiler pair — identical `when_to_use` and `alternatives` despite different statistical intent (ORA vs GSEA).

## Post-apply retrieval check

Re-ran `compose_chain` on 4 disambiguation queries:

| Query | Expected | Got | Result |
|---|---|---|---|
| "bulk RNA-seq DESeq2 differential expression with clusterProfiler pathway enrichment" | `bulk_rnaseq_consensus_de_bioc` (Bioc) | nf-core/differentialabundance chain | **still MISS** (see analysis) |
| "nf-core pipeline for differential abundance with GSEA HTML report on a count matrix" | `bulk_rnaseq_de_analysis` (nf-core) | nf-core chain ✓ | EXACT |
| "gene-list over-representation analysis with clusterProfiler for upregulated DE genes" | ORA chain | `[nf-core/rnaseq, deseq2, clusterprofiler]` ✓ | **EXACT — newly correct** |
| "GSEA pathway enrichment on a ranked log2 fold-change list from RNA-seq DE" | GSEA chain | `[nf-core/rnaseq, differentialabundance, clusterprofiler_gsea]` ✓ | EXACT |

**Score: 3/4 disambiguate correctly. The clusterProfiler pair now distinguishes ORA from GSEA based on user wording. The deseq2 / differentialabundance pair still resolves to the nf-core chain on the explicit-DESeq2 query — for the reason below, this is not a workflow-description problem.**

## Why the explicit-DESeq2 query still misses (analysis)

Both candidate chains list DESeq2 and clusterProfiler among their constituent workflow names:

- `bulk_rnaseq_consensus_de_bioc`: nf-core/rnaseq → **deseq2** → **clusterprofiler**
- `bulk_rnaseq_de_analysis`: nf-core/rnaseq → nf-core/differentialabundance (wraps **deseq2**) → clusterprofiler_gsea

When the user types "DESeq2 + clusterProfiler" with no other qualifier, both chains are textually consistent with the query. The differentiation lives at the *chain* level — "Bioconductor consensus" vs "nf-core pipeline" — not the workflow level. **Workflow-level description quality is not the bottleneck for this case.**

The improvement work above did fix:
- The clusterProfiler ORA/GSEA pair (newly disambiguates by input shape)
- The annotation_v2 asymmetry on the DESeq2 / differentialabundance pair (composer now sees structured signal on both sides)

It did not fix:
- Chain-level naming for ambiguous "DESeq2 + clusterProfiler" queries — that's the next layer.

## The next layer (chain-level differentiation, not done in this pass)

The clean fix is on the **chain** descriptions, not the workflow descriptions. Three options, listed by leverage:

1. **Add Bioconductor-distinctive tokens to `bulk_rnaseq_consensus_de_bioc.description`** in `workflow_chains` — e.g., explicit "Bioconductor consensus DE comparison: DESeq2 + edgeR/limma alternatives + IHW", so any query mentioning "Bioconductor", "consensus", or naming multiple alternative DE methods scores it higher.
2. **Have the `bioc_kb` tutorial pre-load the right framing** in the user's query string before sending it to the composer, e.g. prepend "Bioconductor consensus DE" — guarantees retrieval without changing the DB.
3. **Accept the ambiguity** as valid — `bulk_rnaseq_de_analysis` and `bulk_rnaseq_consensus_de_bioc` are both correct answers to a plain "DESeq2 + clusterProfiler" query; the handoff tutorial can use either equivalently.

Recommendation: **option 1** is the right fix because it improves retrieval for all future users, not just the tutorial. ~30-line script analogous to `differentiate_ambiguous_workflows.py` but operating on `workflow_chains.description`. Not done in this pass; recorded as next work.

## Files

- `backend/scripts/differentiate_ambiguous_workflows.py` — the script; idempotent, atomic, dry-run by default
- `backend/database/differentiate_ambiguous_backup_20260612T205708.json` — row-level backup of the 4 rows before the update
- This doc — analysis + post-apply verification
- DB backup `backend/database/galaxy_ai_tools.db.backup-20260610-141017` — full pre-session backup remains valid

## Pattern, not a one-off

The three structural problems found here are generalizable:

| Pattern | How to detect | How to fix |
|---|---|---|
| Generic description | `length(description) < 150` AND domain in {bioconductor, R, single-tool} | Add execution-shape language + cross-reference to pipeline-form alternative |
| Asymmetric annotation_v2 | Two workflows in the same intent cluster where one has annotation_v2 and the other does not | Populate the missing one |
| Copy-paste annotation_v2 | `SELECT name, count(*) GROUP BY annotation_v2` finds duplicates | Manual differentiation per pair |

If you want a sweep across the whole 2,455-workflow catalog, the same script structure scales: identify the ambiguous pairs by SQL (input/output type overlap, tools_used overlap, name-token similarity), draft updates, dry-run, apply with backup. Each pair is a few minutes of human review.
