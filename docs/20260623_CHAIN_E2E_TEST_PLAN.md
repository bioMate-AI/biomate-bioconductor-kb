# Chain System E2E Test Plan (Revised)
**Date:** 2026-06-23  
**Status:** Approved — implementation in `chain-system-comprehensive.e2e.ts`

---

## Design principle

**Routing must not depend on keywords.**

The routing pipeline is embedding-based (BGE cosine similarity) + LLM pairwise judge. Each chain is indexed with its description, `required_inputs` type names, and `example_queries`. A query that describes the user's _data state_ and _desired outcome_ in natural language should score correctly against the right chain embedding — no keywords injected, no regex patterns, no signal-boosting by substring match.

The previous `_COUNT_MATRIX_SIGNALS` frozenset and `_COUNT_MATRIX_PAT` regex hint were removed. If routing fails without them, the fix is: improve the chain's description and `example_queries`, not add more keywords.

**Consequence for tests:** test messages are written as a real biologist would describe their situation, not as query strings engineered to trigger routing rules.

---

## Architecture under test

```
User message
  → BGE embedding of user_intent
  → cosine similarity against chain embedding index
      (chain text = name + display_name + description + required_inputs types + example_queries)
  → LLM pairwise judge for top-N ties
  → WorkflowChainPlan card rendered in chat
  → (after run) executor fires _fire_chain_suggestions() → SSE inject → chain-suggestion-card
```

---

## Use cases

| UC | Scenario | Expected result | Routing signal (in embedding space) |
|----|----------|-----------------|--------------------------------------|
| UC-1 | RNA-seq data already quantified; want DE + pathway enrichment | `bioc_bulk_rnaseq_de_v2` chain | query describes "processed expression data", "already quantified" → close to chain description "PRE-COMPUTED COUNT MATRIX" |
| UC-2 | Raw paired-end reads; want full pipeline from alignment to DE | full rnaseq workflow or chain starting from FASTQ | query describes "raw sequencing data", "reads" → not close to bioc_bulk_rnaseq_de_v2 which requires count matrix |
| UC-3 | ChIP-seq peak files ready; want gene annotation + pathway enrichment | `bioc_chipseq_annotation_v2` chain | query describes "peak files", "annotate to genes" → matches chip-seq annotation chain embedding |
| UC-4 | cryoSPARC SPA finished; want standard post-processing refinement | `cryoem_standard_refinement` chain | query describes "completed SPA", "improve resolution" → matches refinement chain |
| UC-5 | Sample has multiple conformations; want heterogeneity analysis | `cryoem_conformational_heterogeneity` chain | query describes "conformational states", "structural populations" → matches heterogeneity chain |
| UC-6 | High-res map ready; want atomic model built and validated | `cryoem_model_building` chain | query describes "density map", "atomic model", "stereochemistry" → matches model building chain |
| UC-7 | Metagenomics assembly — no chain in system | single workflow (nf-core/mag) or disambiguation; NOT bioc/cryoem chain | no false-positive: mag/metagenomics embeddings don't match any chain |

---

## Test messages (natural language, no engineered keywords)

**UC-1:**
> "I've finished my RNA-seq run. The gene-level expression data is already quantified. I want to identify which genes are differentially expressed between my treated and control conditions, then see which biological pathways are significantly enriched."

**UC-2:**
> "I have paired-end FASTQ files from a time-course RNA-seq experiment with three biological replicates per time point. I need to go from raw sequencing reads all the way to differential expression analysis."

**UC-3:**
> "I ran ChIP-seq for a histone modification and have the called peak regions. I want to know which genes are located near these peaks and what biological processes those genes are involved in."

**UC-4:**
> "I just completed particle picking, 2D classification, and an initial 3D reconstruction in cryoSPARC. I have a clean particle set and a reference map. What are the recommended post-processing steps to improve map resolution and quality?"

**UC-5:**
> "My cryo-EM protein sample appears to adopt multiple distinct structural conformations. I need to computationally characterize the range of conformational states and understand the conformational landscape."

**UC-6:**
> "I have a refined cryo-EM density map at around 3 Angstrom resolution. I need to build an atomic model into this map and then rigorously validate the stereochemical quality of the model."

**UC-7:**
> "I'm studying microbial communities from soil samples. I need to assemble metagenomes from the sequencing reads, bin contigs into draft genomes, and classify the taxonomy of each bin."

---

## Assertions per UC

### Flow A — routing + chain card rendering (API + UI)

For each UC, the test:
1. Sends the message via chat
2. Parses the AI stream response for a workflow object
3. Asserts on the returned `workflow_type`, chain name/domain, and rendered card

| UC | `workflow_type` | Chain name constraint | Domain | Step count | Anti-assertion |
|----|-----------------|----------------------|--------|------------|----------------|
| UC-1 | `chain` | contains `bulk_rnaseq_de` OR `deseq2` | `transcriptomics` | ≥ 2 | NOT nf-core/rnaseq (needs FASTQ) |
| UC-2 | `workflow` OR `chain` | if chain: must NOT be bioc_bulk_rnaseq_de_v2 alone | any | — | required_inputs must not be count_matrix-only |
| UC-3 | `chain` | contains `chipseq` OR `annotation` | `transcriptomics` or `genomics` | ≥ 2 | — |
| UC-4 | `chain` | contains `refinement` OR `cryoem` | `cryo_em` | ≥ 3 | — |
| UC-5 | `chain` | contains `heterogeneity` OR `conformational` | `cryo_em` | ≥ 2 | — |
| UC-6 | `chain` | contains `model_building` OR `phenix` OR `model` | `cryo_em` | ≥ 2 | — |
| UC-7 | `workflow` OR `chain` | — | NOT `transcriptomics`, NOT `cryo_em` | — | No `bioc_*` or `cryoem_*` chain |

For UC-2 and UC-7, a disambiguation card (`workflow_type: "disambiguation"`) is also acceptable — the system correctly identified ambiguity.

### Flow B — SSE injection → chain-suggestion-card

| Test | Setup | Action | Assertion |
|------|-------|--------|-----------|
| B-1 | Browser opens EventSource for a test invocationId | POST /internal/sse-inject with 1 suggestion | `[data-testid="chain-suggestion-card"]` visible; item text correct |
| B-2 | Same invocationId | POST /internal/sse-inject with 2 suggestions | Two `[data-testid^="chain-suggestion-item-"]` visible |
| B-3 | Same invocationId | POST /internal/sse-inject with empty suggestions array | NO `[data-testid="chain-suggestion-card"]` |

B-1/B-2/B-3 use a synthetic invocationId via `GET /api/sse/invocation/:id` (registers a real client, no Galaxy polling). This tests the SSE → browser → React render path without requiring a live GPU run.

---

## What the test does NOT do

- Does not craft messages containing "count_matrix", "tsv", "gene_counts" as routing aids  
- Does not inject routing hint strings into the query  
- Does not assert on exact chain names (allows for semantically equivalent alternatives)  
- Does not run a GPU workflow to completion (B tests use SSE inject directly)

---

## Files

```
frontend/e2e/chain-system-comprehensive.e2e.ts   ← implementation
docs/20260623_CHAIN_E2E_TEST_PLAN.md             ← this document
```
