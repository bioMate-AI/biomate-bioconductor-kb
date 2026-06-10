# Type-Flow Graph — Bioc-Inclusive Scope

**Date**: 2026-06-10
**Built after**: Bioc output re-inference applied (`docs/20260610_BIOC_OUTPUT_APPLIED.md`)

## Headline: the graph just got 11× larger

| | Pre-Bioc-output-inference | Post-apply |
|---|---|---|
| Workflows in graph | 308 | **1,371** (4.5×) |
| Bioc workflows in graph | 1 | **1,064** |
| Edges | 6,388 | **73,072** (11×) |
| Bioc-involving edges | 0 | **67,001** (92% of all edges) |
| nfcore → Bioc edges | 0 | **15,975** |
| Bioc → Bioc edges | 0 | **50,108** |
| Bioc → nfcore edges | 0 | **223** |

The data substrate for the user's "connect specialties seamlessly across domains" vision now exists at scale. Every typed edge is a candidate chain step.

## Two methodological notes

1. **Bioc inputs are still freeform.** The output stub was fixed in `bioc_output_inferrer.py`; Bioc input_types remain prose like `"counts.tsv (matrix of raw integer counts)"`. To build the type-flow graph we run a regex pass to extract canonical tokens (`counts_matrix`, `expression_matrix`, `vcf`, `bam`, `singlecellexperiment`, etc.) from those descriptions. ~80% of Bioc workflows surface at least one canonical input via this.
2. **Aliases extended.** The existing `_PLANNER_ALIASES` table was complemented with cross-edges for the new Bioc output kinds (`de_table → gene_list`, `expression_matrix → counts_matrix`, etc.) so the graph picks up natural downstream consumers.

## Finding 1: Massive nf-core → Bioc hub-spoke fanout

**9 nf-core transcriptomics pipelines each feed 654 unique Bioc consumers** (only one tie of many in the 654-out-degree class):

```
nf-core/circrna, drop, lncpipe, oncoanalyser, rnadnavar, rnafusion, rnavar,
smrnaseq, tfactivity  →  ~654 Bioc consumers each
```

These pipelines all produce `counts_matrix` / `expression_matrix`; every Bioc DE caller, enrichment tool, normalization package, and visualization consumes one of those. The graph is dense because the canonical types DESCRIBE A REAL INTERCHANGE FORMAT — `counts_matrix` is what 100+ Bioc tools take.

## Finding 2: Hub-consumer Bioc workflows

**Bioc workflows with the most diverse non-Bioc upstream support:**

| Bioc workflow | Distinct producers | Domain |
|---|---|---|
| `purecn` | 71 | variant_calling |
| `damefinder_methyl_circle_visualization` | 71 | epigenomics |
| `appreci8r` | 65 | variant_calling |
| `bbcanalyzer` | 65 | genomics |
| `cnvrd2` | 65 | variant_calling |
| `ggbio` | 65 | genomics |
| `madseq` | 65 | genomics |
| `variantfiltering` | 65 | variant_calling |
| `zygositypredictor_gene_zygosity_prediction` | 65 | genomics |
| `epialleler_sequence_variant_association` | 65 | genomics |

These are natural **anchor points** for variant-analysis chains: any of the 65–71 upstream sources can feed them, so a single curated chain authored around one of these consumes a much wider real-traffic distribution.

## Finding 3: Natural 3-step chains are emergent, not curated

Sample 3-step `nf-core → Bioc → Bioc` chains now visible by following typed edges:

```
nf-core/rnaseq → absseq → gostag
nf-core/rnaseq → absseq → metaphor
nf-core/rnaseq → absseq → norce_pathway_enrichment
nf-core/rnaseq → absseq → ribosomeprofilingqc_floss
nf-core/rnaseq → aggregatebiovar → gostag
```

The first three are all the same shape: bulk RNA-seq → DE caller → pathway/network analysis. None are in `workflow_chains`. The composer's L3 free-composition can walk these without explicit curation, given the typed graph.

## Finding 4: The right action isn't "author more chains"

The combinatorial scale of the graph (15,975 cross-source edges, 50,108 within-Bioc) makes hand-authoring of each plausible 2- or 3-step chain impractical. The graph IS the chain catalog at this point.

**The right next move is to wire the typed graph into the L3 composer's prompt:**

- Given a query, retrieve top-K typed upstream candidates (Bioc + non-Bioc)
- For each, compute downstream consumers via the typed graph
- Show the LLM: *"workflow X produces counts_matrix; 487 Bioc workflows consume that; here are the top 5 by description match to your query"*

This makes the L3 path of the design doc concrete — typed retrieval instead of relying on the pattern library + name retrieval alone. No code change yet; this is a follow-on lift.

## Finding 5: Cross-source flow distribution

| Source pair | Edges |
|---|---|
| **bioconductor → bioconductor** | 50,108 |
| **nfcore → bioconductor** | 13,711 |
| **nfcore_subwf → bioconductor** | 2,264 |
| nfcore → nfcore | 1,353 |
| nfcore → nfcore_subwf | 849 |
| nextflow → nextflow | 834 |
| nfcore_subwf → nfcore | 657 |
| nextflow → nfcore | 515 |
| biomate → nextflow | 435 |
| nfcore_subwf → nfcore_subwf | 336 |
| **biomni_nextflow → bioconductor** | 313 |
| biomate → nfcore | 269 |
| biomni_nextflow → nextflow | 247 |
| **bioconductor → nfcore** | 188 |
| biomni_nextflow → nfcore | 163 |

Bioc is now the dominant participant — the long-suspected most-connected source. Cross-source feeds INTO Bioc (16,288 edges) outnumber feeds OUT of Bioc (411) by ~40×. Most real-world workflows produce data; Bioc analyzes it.

## Implications

### Confirmed
- The user's "Bioc is important to connect to other workflows" claim is now quantified: **67,001 typed edges involve Bioc, 92% of the graph**.
- The "connect specialties seamlessly" vision was blocked entirely by the output stub. Removing it unblocks the rest.
- No further $-budgeted LLM passes are needed for the structural-connectivity story; the data was always there.

### Open
- **Wire typed graph into L3 composer prompt** — biggest unrealized win from this graph. Not done in this turn.
- **Bioc → non-Bioc edges are sparse (411 total).** That's accurate: Bioc tends to be a terminal analysis stage. Real-world Bioc → downstream is via reports / publications, not further pipelines.
- **648 Bioc workflows on stub remain.** Expanding `bioc_output_inferrer._RULES` (free, deterministic) catches more without LLM spend; the no-match cases are mostly specialized analyses (APA, epimutation, vulnerability profiling).

## Reproducibility

```bash
cd /home/yzhang/biomate/.claude/worktrees/agent-aaf4e393b5ea5b614
export PYTHONPATH=$PWD/backend/lib

# The ad-hoc graph build is currently a one-off Python script (not a CLI module).
# Move into chain_composer/type_flow_graph.py if this becomes a recurring need.
```

## Status

Survey continues to validate by the data: the catalog had everything needed; the indexer's `output_types` stub was the only thing hiding it. With ~2,123 stubs removed and the graph re-built, the structural shape of Bioc connectivity is fully visible for the first time.
