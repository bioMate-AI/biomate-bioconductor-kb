# The workflow catalog & how routing picks a workflow

> One-line promise: after this page you understand what BioMate can run (the indexed catalog), how a
> plain-language goal becomes the *right* workflow without you naming one, and where routing draws the
> line between an indexed workflow and one it builds on demand. For everyone — especially readers who
> want to know *why* they got the workflow they got.

<!--
Reference chapter (Part II). Template-adapted: keeps "What this is for / How to ask / What's not
covered" but the middle is catalog+routing mechanics, not a single use case.
Every "supported" claim is code-verified (tier C); see the ledger rows at the foot of this page.
-->

## What this is for

BioMate does not make you memorise workflow names. You describe a goal — *"differential expression,
treated vs control from my FASTQ"* — and BioMate **routes** that sentence to a validated workflow (or a
multi-step **chain**) from an indexed catalog, pre-fills its parameters, and opens it in the run panel
(see I.6). This page explains the two things behind that: **the catalog** (what's on the shelf) and
**the router** (how it chooses). Read it when you want to know why a particular workflow came back, how
to phrase a goal so it routes cleanly, or when to trust an indexed workflow versus one generated for you.

## The catalog at a glance

The catalog is a SQLite database, `backend/database/galaxy_ai_tools.db`, with two tables that matter
here:

- **`workflows`** — every runnable single workflow (one row each). Columns include `name`, `domain`,
  `description`, `tags`, `step_count`, `tools_used`, `input_types`, `output_types`, `source`, `format`,
  `nextflow_path`/`filename`, and a full `workflow_json`. Parameters and steps are attached at
  routing time (see *Under the hood* below).
- **`workflow_chains`** — curated multi-step pipelines. Each row carries `steps` (an ordered list of
  member workflows with a role and a `params_template`), `connections` (the **step→step file
  hand-off**), `required_inputs`, `expected_outputs`, and `example_queries`
  (`backend/scripts/index_all_workflows.py:845-883`).

**How big is it, really?** Queried live, the catalog holds **4,200 workflows across 42 domains, plus
70 chains**. The largest domains are transcriptomics (1,695), genomics (756), epigenomics (265),
drug_discovery (200), proteomics (184), and variant_calling (181).

> **Pitfall — the "2,455 / 34" number is stale.** `CLAUDE.md` and several tool descriptions still say
> "2,455 workflows across 34 domains" (e.g. `search_workflow`'s description in
> `backend/lib/mcp/tools_manifest.py:118`); the MCP server blurb says "4,017 / 36". The database
> itself is the source of truth — **4,200 / 42 / 70 chains** as counted directly from
> `galaxy_ai_tools.db`. Treat the round numbers in prose as approximate; the catalog grows as
> workflows are indexed.

![The catalog spans dozens of domains; a goal routes to one workflow or a chain, not a name you have to remember.](../assets/ii01-1-catalog-domains.png)
<!-- CAPTURE route=/capabilities ; state=capabilities page listing domains/workflow counts ; focus=domain grid ; note=shows breadth of catalog (captured live from dev) -->

## What a chain is (and why it matters)

A single workflow does one job (align FASTQ; call variants). A **chain** wires several together so an
output of one becomes the input of the next. The canonical example, `bulk_rnaseq_de_analysis`
(`index_all_workflows.py:473-507`):

1. **nf-core/rnaseq** — alignment + quantification (`params_template: {aligner: star_salmon, genome: GRCh38}`)
2. **nf-core/differentialabundance** — DESeq2 differential expression
3. **clusterProfiler** — GO/KEGG/Reactome enrichment

The `connections` field is the load-bearing part: it declares, for example,
`from_step 1, from_output "counts_matrix" → to_step 2, to_input "counts"` — so the count matrix flows
into DE automatically. `required_inputs` = `fastq_files`, `sample_sheet`, `contrast`;
`expected_outputs` = `multiqc_report`, `de_results`, `gsea_results`. You never assemble this by hand;
routing recognises the goal and proposes the whole chain.

## How to ask (so routing picks cleanly)

You describe the **goal and the shape of your input**, not a workflow name. The router keys off intent
and input signals.

> "Differential expression between treated and control from my count matrix."
> — routes to the count-matrix entry point (downstream-only), not a from-FASTQ run.

> "Process 30 bulk RNA-seq FASTQ samples into a counts matrix."
> — routes to nf-core/rnaseq (producing counts), **not** the DE chain.

> "Cluster my 10x single-cell data and annotate cell types."
> — routes to the single-cell chain; the word "10x"/"single-cell" is what keeps it *off* the bulk chain.

**The disambiguation to avoid:** two assays can share vocabulary. Bulk RNA-seq and single-cell both
say "cells", "clustering", "expression". Add one disambiguating signal and routing is unambiguous:

- **bulk vs single-cell** → say "single-cell", "scRNA-seq", "10x", "Cell Ranger", "Seurat" for the
  single-cell path; say "bulk", "count matrix", "DESeq2" for bulk.
- **germline vs somatic** → say "germline" or "somatic/tumour-normal" for variant calling.
- **DE-intent vs FASTQ-processing** → "differential expression / DESeq2 / upregulated" pulls the DE
  chain; "process raw reads / produce a counts matrix" pulls the aligner.

If your prompt is genuinely ambiguous (you named two methods, or the top two candidates score within a
narrow gap), BioMate returns a **disambiguation card** instead of guessing — a short list of candidate
workflows with a one-line role each; you click the one you meant (see *Disambiguation* below).

## Tools & surfaces behind this

For agent/MCP callers the catalog is exposed as three tiered tools
(`backend/lib/mcp/tools_manifest.py`):

| Tool | What it does | Backend |
|---|---|---|
| **`search_workflow`** | Natural-language search of the catalog; returns ranked cards (id, name, domain, one-line description, estimated Batch cost). Use when you want to *pick* a workflow explicitly. | `/api/workflows/search` (`tools_manifest.py:114-136`) |
| **`get_workflow_spec`** | Full spec for one workflow: required + optional params (types, allowed values), default QC profile/thresholds, expected inputs, cost/runtime, license. Call before running for explicit param control. | `/api/workflows/spec` (`tools_manifest.py:137-155`) |
| **`generate_workflow`** | Routes a goal end-to-end: returns a `workflow_ga` object — `name`, `domain`, `description`, `required_params`, `optional_params`, `steps`, `nextflow_path`, plus pre-filled `parameters`. | `/api/ai_assistant/generate_workflow` → `generate_workflow_unified()` (`backend/lib/galaxy/ai/ai_assistant.py:3404-3420`) |

In the chat product you don't call these directly — the composer's routing runs `generate_workflow`
for you and proposes the card (see I.6). Steps are normally loaded eagerly into `workflow_ga.steps`
(`ai_assistant.py:136-150`); if that list is empty/stale the frontend lazily fetches them from
`/api/nextflow/steps?nextflow_path=…` (`nextflow_executor.py:6291`).

## Under the hood — how routing actually picks

The router (`backend/lib/galaxy/ai/unified_workflow_search.py`, entry `search()` at line 825) does **not**
rely on you naming a workflow. It combines three signals, then scores:

1. **LLM catalog browse** — a fast model ranks the most relevant workflow IDs from a broad candidate set
   (`search()` "Pass 0", `unified_workflow_search.py:854-860`); returns nothing gracefully if the LLM is
   unavailable.
2. **Dense retrieval** — BGE sentence-embeddings give a cosine-similarity pre-filter over all workflows
   (`_dense_workflow_prefilter`, `:867`); degrades to FTS-only if the embedding index is missing.
3. **Full-text search (FTS)** over name/description/annotation/tags/domain/tools, augmented with any
   LLM-extracted key terms (`_build_fts_query`, `:879`).

Results are then scored (exact-name, prefix, phrase, domain bias, embedding bonus) and, for chains,
passed through a **chain-compatibility guard** before being proposed.

### The bulk-vs-single-cell guard (why "share vocabulary" isn't enough)

`_chain_multimodal_context_compatible()` (`unified_workflow_search.py:2638`) drops a chain if the query
lacks that chain's *required assay signal*, even when general vocabulary matches. The in-code comment on
the single-cell chain is explicit:

> "Bulk RNA-seq queries ('process 30 bulk RNA-seq samples', 'produce a gene counts matrix') share
> vocabulary with this chain but describe completely different assays. Required: user must mention
> single-cell sequencing technology, barcodes, or Cell Ranger."
> — `unified_workflow_search.py:2620-2634`

So the single-cell chain requires one of `{single cell, scrnaseq, 10x genomics, cellranger, seurat,
anndata, …}` (`:2627-2633`), and the bulk DE chain requires one of `{differential expression, deseq2,
edger, limma, salmon output, my count matrix, gsea, …}` (`:2609-2618`). A generic "analyse my cells"
prompt matches neither guard and won't be force-routed to the wrong assay.

### Disambiguation (when it asks instead of guessing)

Two cases produce a disambiguation card rather than a silent pick
(`ai_assistant.py:4600-4608, 4610-4613`):

- **You named multiple methods** ("compare DESeq2 vs edgeR") → the router enumerates the mentioned
  methods as candidates and asks which to run.
- **The top candidates are too close** → when ≥2 plausible results score above a floor and the gap
  between #1 and #2 is under the threshold, it returns `workflow_type: 'disambiguation'` with a
  `candidates` list. (Certain unambiguous intents, e.g. "admet", bypass this and route straight
  through.)

The card renders in chat when `workflow_type === 'disambiguation'`
(`frontend/client/src/components/workflow-disambiguation-card.tsx`); you click a candidate and it
re-submits as an explicit choice. Three near-identical bulk-RNA chains
(`bulk_rnaseq_de_analysis`, `bulk_rnaseq_consensus_de_bioc`, `bioc_bulk_rnaseq_de_v2`) carry
pre-written differentiation blurbs specifically so this step reads clearly
(`backend/scripts/differentiate_ambiguous_chains.py:31-75`).

![A disambiguation card: two or more candidate workflows, each with a one-line role, when the goal is genuinely ambiguous.](../assets/ii01-2-disambiguation.png)
<!-- CAPTURE route=/ ; state=chat after an ambiguous prompt (e.g. "compare DESeq2 vs edgeR") ; focus=disambiguation card in chat ; note=candidates with role + score (captured live from dev) -->

## Indexed vs generated-on-demand (the honest boundary)

BioMate prefers an **indexed** workflow and only **generates** one when nothing indexed fits
(`ai_assistant.py:5032-5134`):

- **Indexed (the common case):** the router found a catalog match above the confidence floor and returns
  it. This is a validated, pre-tested workflow — what you want for reproducible work.
- **Generated-on-demand (fallback):** when no indexed workflow clears the confidence bar, the
  `NextflowComposer` assembles a new DSL2 `main.nf` from the tool library (Galaxy ToolShed / nf-core
  modules / Bioconductor wrappers), writes it to a generated directory, and returns it flagged
  `source='nextflow_composed'` with `needs_user_feedback=True` (`ai_assistant.py:5045-5108`).

> **Tip — know which one you got.** A generated workflow is a *draft composition*, not a
> production-validated pipeline. Treat it as a starting point: review its steps in the run panel before
> committing a long Cloud run. Indexed workflows are the trusted path.

## What's not covered

- **Live cost/runtime before you run.** `search_workflow`/`get_workflow_spec` describe an *estimated*
  Batch cost, but the run panel intentionally shows no per-run estimate before Confirm & Run (see I.13).
  Expected timing is set by the domain chapter, not a per-run number.
- **Deep, worked coverage of every catalog workflow.** Only the documented domains (Part III) have
  end-to-end worked examples. The catalog contains many more workflows (fusion, splicing, RNA-variant,
  and others) that route and run but are not yet individually documented → Appendix E.
- **Stale catalog counts in prose/tool descriptions.** The "2,455 / 34" and "4,017 / 36" figures are
  out of date; the live count is 4,200 / 42 / 70. Documented here; a code cleanup of those strings is a
  roadmap item → Appendix E.

---
_Verification: coverage-ledger.md "## II.1 Workflow catalog & routing" — all tier C (source + live DB
read); no Batch runs fired._
