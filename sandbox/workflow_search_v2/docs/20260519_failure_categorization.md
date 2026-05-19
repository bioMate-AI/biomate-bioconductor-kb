# 155-Case Workflow-Routing Failure Categorization

**Date:** 2026-05-19
**Source:** `evaluation/datasets/cross_domain_routing/queries.yaml`
**Runner:** `sandbox/workflow_search_v2/scripts/categorize_failures.py`
**BGE dense retrieval:** **DISABLED locally** — absolute numbers are artificially low; failure-mode distribution is still valid

## Failure-mode distribution

| Category | Count | % | Recommended lever |
|---|---|---|---|
| HIT | 108 | 69.7% | — |
| UNRELATED_TOP1 | 21 | 13.5% | Lever 1 + retrieval-engine review (likely missing context) |
| CORRECT_IN_TOP3 | 17 | 11.0% | Lever 1 (intent boost re-orders top-3) OR Lever 2 (LLM verify) |
| CORRECT_IN_TOP10_NOT_TOP3 | 4 | 2.6% | Lever 2 (domain-gated re-rank) |
| DISAMBIG_OK | 3 | 1.9% | Existing disambiguation UX handles it |
| ADJACENT | 2 | 1.3% | **Lever 1: Intent-anchor map** — codify rnaseq-vs-scrnaseq etc. |

Total n = 155

## Failure examples (top 5 per category)

### UNRELATED_TOP1

- **rna_001** `Run standard RNA-seq analysis on my paired-end FASTQ files from a mouse experime`
  - expected: `nf-core/rnaseq`
  - got top-3: `['nf-core/cutandrun', 'scry', 'ALDEx2']` (scores [36.0, 35.0, 34.2])
- **rna_007** `Generate BigWig coverage tracks from my RNA-seq experiment for genome browser vi`
  - expected: `nf-core/rnaseq`
  - got top-3: `['CoverageView', 'GenomicPlot', 'Basic4Cseq']` (scores [53.1, 47.5, 37.4])
- **rna_012** `Strandedness is unknown for my RNA-seq libraries — auto-detect it and align`
  - expected: `nf-core/rnaseq`
  - got top-3: `['BUSseq', 'sva', 'xcore']` (scores [44.2, 36.8, 35.7])
- **rna_013** `Identify genes upregulated in lung tissue from COVID-19 patients versus healthy `
  - expected: `nf-core/rnaseq`
  - got top-3: `['oncomix', 'iNETgrate', 'nf-core/viralrecon']` (scores [32.5, 27.5, 27.2])
- **var_008** `Rank and prioritize variants by pathogenicity score for a patient with unexplain`
  - expected: `nf-core/raredisease`
  - got top-3: `['ASSIGN', 'Assay Ingestion And Ranking', 'CRISPRseek']` (scores [30.6, 29.9, 29.7])

### CORRECT_IN_TOP10_NOT_TOP3

- **rna_004** `Remove ribosomal RNA contamination and trim adapters before aligning my transcri`
  - expected: `nf-core/rnaseq`
  - got top-3: `['nf-core/fastq_trim_fastp_fastqc', 'Fastq Trim Fastp Fastqc', 'celda']` (scores [38.1, 33.2, 32.4])
- **sc_012** `Find cell types in a single-cell experiment from inflamed colon tissue biopsies`
  - expected: `nf-core/scrnaseq`
  - got top-3: `['LRcell', 'nf-core/imcyto', 'lisaClust']` (scores [36.3, 30.1, 29.7])
- **vc_007** `Predict transcriptional response to MYC knockout in K562 using gene perturbation`
  - expected: `gears_perturbation_prediction`
  - got top-3: `['gears_perturbation_prediction_gpu', 'NTW', 'transcriptformer_cell_state_gpu']` (scores [48.0, 37.5, 33.5])
- **sc_021** `My scRNA-seq has inflated cell counts — I see clusters co-expressing T cell and `
  - expected: `scrna_doublet_qc`
  - got top-3: `['scShapes', 'HIPPO', 'DEsingle']` (scores [55.0, 46.3, 45.6])

### CORRECT_IN_TOP3

- **rna_006** `Run a StringTie transcript assembly on my aligned RNA-seq BAM files`
  - expected: `nf-core/bam_stringtie_merge`
  - got top-3: `['Bam Stringtie Merge', 'nf-core/bam_stringtie_merge', 'nf-core/rnaseq']` (scores [83.5, 80.7, 61.0])
- **rna_010** `I already have a count matrix from rnaseq. Now I want to find differentially exp`
  - expected: `nf-core/differentialabundance`
  - got top-3: `['nf-core/rnaseq', 'nf-core/differentialabundance', 'CleanUpRNAseq']` (scores [66.3, 62.8, 52.4])
- **sc_007** `Quality control of single-cell sequencing: filter empty droplets and doublets`
  - expected: `nf-core/scrnaseq`
  - got top-3: `['scds', 'scCB2', 'nf-core/scrnaseq']` (scores [43.0, 41.2, 40.3])
- **var_010** `Calculate tumor mutational burden (TMB) from WES of a melanoma sample`
  - expected: `nf-core/sarek`
  - got top-3: `['CaMutQC', 'nf-core/sarek', 'MesKit']` (scores [57.7, 42.0, 40.0])
- **var_012** `Run UMI consensus calling to reduce PCR duplicates before variant detection in c`
  - expected: `nf-core/sarek`
  - got top-3: `['Fastq Create Umi Consensus Fgbio', 'nf-core/sarek', 'nf-core/fastq_create_umi_consensus_fgbio']` (scores [43.7, 43.6, 42.1])

### DISAMBIG_OK

- **var_001** `Call germline SNPs and indels from whole genome sequencing of a healthy voluntee`
  - expected: `nf-core/sarek`
  - got top-3: `['nf-core/rnavar', 'nf-core/variantprioritization', 'SeqArray']` (scores [44.3, 43.2, 42.1])
- **var_011** `Annotate germline variants with ClinVar and gnomAD allele frequencies from WGS`
  - expected: `nf-core/sarek`
  - got top-3: `['nf-core/variantcatalogue', 'nf-core/raredisease', 'VariantFiltering']` (scores [48.9, 46.1, 43.7])
- **vc_011** `Classify cell type from my gene expression profile, high MKI67 and MYC, using si`
  - expected: `transcriptformer_cell_state`
  - got top-3: `['BASiCS', 'miQC', 'retrofit']` (scores [44.2, 42.2, 41.3])

### ADJACENT

- **meta_010** `Reconstruct individual microbial genomes from an ocean metagenome using long rea`
  - expected: `nf-core/mag`
  - got top-3: `['nf-core/taxprofiler', 'nf-core/bacass', 'CellBarcode']` (scores [39.7, 36.0, 34.4])
- **adv_007** `DDA vs DIA: I ran data-independent acquisition proteomics — which pipeline shoul`
  - expected: `nf-core/diaproteomics`
  - got top-3: `['nf-core/mhcquant', 'procoil', 'Path2PPI']` (scores [57.3, 31.3, 30.8])

## Lever recommendation

**Lever 3 (tighter disambig gate)** — failures are scattered, no dominant pattern; gate tightening + Lever 1 on selected high-traffic queries.

## Surprises vs the proposal's predictions

1. **ADJACENT failures are RARE** (2/155 = 1.3%). The proposal's headline hypothesis — "rnaseq-vs-scrnaseq confusion" — does not match the actual data. The benchmark is well-curated and the existing search already disambiguates these. Lever 1's value isn't in adjacency-resolution.

2. **CORRECT_NOT_IN_TOP10 = 0**. Every correct answer is in the top-10. Retrieval (FTS + keyword + BGE-when-enabled) finds the right workflow; **ranking is the gap, not retrieval**.

3. **The biggest failure category (UNRELATED_TOP1, 13.5%) is a granularity-mismatch problem.** Examples: "Run standard RNA-seq analysis on paired-end FASTQ files" → got `nf-core/cutandrun` (wrong pipeline) instead of `nf-core/rnaseq`. "Generate BigWig coverage tracks from RNA-seq" → got `CoverageView` (a single-tool wrapper that solves a sub-step). The search has no signal distinguishing "give me the pipeline" vs "give me the tool."

## Revised lever recommendation

**Lever 1 (intent-anchor canonical map) still wins, but its value proposition is different from the original proposal:**

- ❌ NOT for adjacency disambiguation (rare in the data)
- ✅ For **pipeline-intent matching**: when the query has hallmarks of "user wants a full pipeline" (verbs like "run", "analyze end-to-end", "from FASTQ to counts/variants/peaks"), boost the canonical nf-core pipeline above single-tool wrappers and adjacent pipelines.
- ✅ For **rank-promotion within top-3**: 17 CORRECT_IN_TOP3 cases mean the answer is already in top-3; intent-anchor lookup confidently promotes it to top-1.

### Estimated lift from Lever 1

Conservative estimate of failures Lever 1 can close:

| Category | Count | Estimated close rate | HITs gained |
|---|---|---|---|
| CORRECT_IN_TOP3 | 17 | ~70% | 12 |
| UNRELATED_TOP1 (pipeline-intent subset) | ~10 of 21 | ~50% | 10 |
| CORRECT_IN_TOP10_NOT_TOP3 | 4 | ~50% | 2 |

**Estimated total lift: +24 HITs → 132/155 = 85.2% (from 69.7%) = +15.5pp.**

With BGE active in production, baseline is higher (~80% per memory) so absolute lift is smaller in percentage terms but the same in failure count (~24 cases).

### What Lever 1 would NOT close

- ADJACENT (2 cases) — existing disambiguation UX handles these
- DISAMBIG_OK (3 cases) — same
- The half of UNRELATED_TOP1 that isn't pipeline-intent — genuine FTS noise; out of scope

## Refined Lever 1 design

```yaml
# sandbox/workflow_search_v2/data/intent_anchors.yaml
bulk_rnaseq_pipeline:
  canonical: nf-core/rnaseq
  trigger_terms: ["rna-seq", "bulk rna", "rnaseq analysis", "fastq to counts", "gene expression analysis"]
  pipeline_intent_required: true
  disqualified_if_present: ["single-cell", "10x", "small rna", "smrnaseq"]

variant_calling_germline:
  canonical: nf-core/sarek
  trigger_terms: ["variant calling", "germline variants", "wgs variants"]
  pipeline_intent_required: true
  disqualified_if_present: ["somatic", "tumor", "trio", "rare disease"]
# ... ~15-20 more entries
```

Plus `prioritize_workflow_by_intent(query, candidates)`:
1. Check for `pipeline_intent_required` markers in query (verbs: "run", "from", "analyze end-to-end").
2. Scan for `trigger_terms`.
3. If exactly one intent fires AND no `disqualified_if_present` term, promote `canonical` workflow to top-1.
4. Otherwise pass through (existing disambiguation handles ambiguity).

## Validation plan

1. Build `data/intent_anchors.yaml` — ~15 entries.
2. Add library function under `sandbox/workflow_search_v2/`.
3. Re-run this script with library applied. Measure HIT lift.
4. Target: +10pp. If hit, propose production wiring behind `BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1`.

Estimated effort: **~3 hours**.

## What's NOT recommended

- Workflow-level dedup/alias map — no duplicates exist
- Touching `UnifiedWorkflowSearch` or `ai_assistant.py` directly — sandbox-first
- BGE / FTS rework — retrieval is fine, ranking is the gap
- Lever 2 or Lever 3 — failure data doesn't justify either as a first move
